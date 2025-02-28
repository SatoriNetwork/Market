// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount) external returns (bool);
}

/**
 * Multi-Seller / Multi-Offering Payment (Locked Subscription Rate)
 *
 * - Each Seller can create/update an offering with a 'currentRate'.
 * - Each subscription stores its own 'subRate' that is locked in at creation time
 *   (or last forced-lower).
 * - If the Seller raises the offering's currentRate, it does not affect existing subs.
 * - If the Seller lowers the offering's rate, we forcibly finalize any subs above that rate,
 *   then set subRate = newRate for them going forward.
 * - Buyer deposits tokens to that subscription at subRate; they can withdraw leftover tokens
 *   if not yet earned by the Seller. The Seller can claim tokens that have accrued.
 *
 */
contract MultiSellerOfferingsLockedRate {
    event OfferingCreatedOrUpdated(
        address indexed seller,
        string offeringId,
        uint256 oldRate,
        uint256 newRate
    );
    event Subscribed(
        address indexed seller,
        string offeringId,
        address indexed buyer,
        uint256 depositChange,
        uint256 finalDeposit,
        uint256 lockedRate
    );
    event SellerClaimed(address indexed seller, string offeringId, uint256 totalClaimed);
    event BuyerWithdrawn(address indexed seller, string offeringId, address indexed buyer, uint256 amount);

    IERC20 public immutable token;

    // Each Offering has a 'currentRate', but each subscription uses 'subRate' locked in at creation (unless forcibly lowered).
    struct Offering {
        uint256 currentRate;
        bool exists;
        address[] subscriberList;
        mapping(address => Subscription) subs; // buyer => Subscription
    }

    struct Subscription {
        uint256 deposit;           // tokens the buyer has locked
        uint256 owedToSeller;      // accrued to seller but not claimed
        uint256 lastAccrualTime;   // last time we finalized
        uint256 subRate;           // the locked rate for this subscription
    }

    // (seller => (offeringKey => Offering))
    mapping(address => mapping(bytes32 => Offering)) private offerings;

    constructor(address _token) {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    // ---------------------------------------------------------
    //        CREATE / UPDATE OFFERING (SELLER-ONLY)
    // ---------------------------------------------------------
    /**
     * The seller can create or update an offering's currentRate.
     * - If the offering doesn't exist, we create it with newRate.
     * - If it does exist:
     *   -- If newRate < oldRate, forcibly finalize & lower the subRate of any sub above newRate.
     *   -- If newRate > oldRate, existing subRates are unaffected, only new subscriptions are higher.
     */
    function createOrUpdateOffering(string calldata offeringId, uint256 newRate) external {
        bytes32 offKey = keccak256(abi.encodePacked(offeringId));
        Offering storage off = offerings[msg.sender][offKey];

        uint256 oldRate = off.currentRate;
        if (!off.exists) {
            // brand new
            off.exists = true;
            off.currentRate = newRate;
            emit OfferingCreatedOrUpdated(msg.sender, offeringId, 0, newRate);
            return;
        }

        // If new rate is the same, do nothing
        if (newRate == oldRate) {
            return;
        }

        // If lowering, forcibly finalize & lower existing subRates that are above the new rate
        if (newRate < oldRate) {
            address[] storage subs = off.subscriberList;
            for (uint256 i = 0; i < subs.length; i++) {
                address buyer = subs[i];
                Subscription storage srec = off.subs[buyer];
                if (srec.subRate > newRate && srec.lastAccrualTime > 0) {
                    // finalize at old subRate
                    _finalizeAccrual(srec, srec.subRate);
                    // now forcibly lower
                    srec.subRate = newRate;
                }
            }
        }
        // if newRate > oldRate, we do nothing to existing subRates
        // future subscriptions will use newRate

        off.currentRate = newRate;
        emit OfferingCreatedOrUpdated(msg.sender, offeringId, oldRate, newRate);
    }

    // ---------------------------------------------------------
    //             BUYER SUBSCRIBE / DEPOSIT
    // ---------------------------------------------------------
    /**
     * Buyer deposits tokens into a subscription. If it doesn't exist, we create a new one,
     * locking in the seller's 'currentRate' at the time of creation. If it does exist, we finalize
     * at the old subRate, then add deposit.
     */
    function subscribe(address seller, string calldata offeringId, uint256 depositAmount) external {
        require(depositAmount > 0, "Deposit=0? Use withdraw or do nothing");
        bytes32 offKey = keccak256(abi.encodePacked(offeringId));
        Offering storage off = offerings[seller][offKey];
        require(off.exists, "Offering not exist");

        bool ok = token.transferFrom(msg.sender, address(this), depositAmount);
        require(ok, "TransferFrom failed");

        Subscription storage srec = off.subs[msg.sender];
        if (srec.lastAccrualTime == 0) {
            // brand new sub
            srec.lastAccrualTime = block.timestamp;
            srec.subRate = off.currentRate; // lock in
            off.subscriberList.push(msg.sender);
        } else {
            // existing sub
            _finalizeAccrual(srec, srec.subRate);
        }

        srec.deposit += depositAmount;
        emit Subscribed(seller, offeringId, msg.sender, depositAmount, srec.deposit, srec.subRate);
    }

    // ---------------------------------------------------------
    //            BUYER WITHDRAW (UNEARNED TOKENS)
    // ---------------------------------------------------------
    function buyerWithdraw(address seller, string calldata offeringId, uint256 amount) external {
        bytes32 offKey = keccak256(abi.encodePacked(offeringId));
        Offering storage off = offerings[seller][offKey];
        require(off.exists, "No such offering");

        Subscription storage srec = off.subs[msg.sender];
        require(srec.lastAccrualTime > 0, "No subscription");

        _finalizeAccrual(srec, srec.subRate);

        require(srec.deposit >= srec.owedToSeller + amount, "Not enough leftover");
        srec.deposit -= amount;

        bool ok = token.transfer(msg.sender, amount);
        require(ok, "Withdraw failed");

        emit BuyerWithdrawn(seller, offeringId, msg.sender, amount);
    }

    // ---------------------------------------------------------
    //                 SELLER CLAIM
    // ---------------------------------------------------------
    /**
     * The seller can claim from all subscriptions in one shot.
     * For large subscription counts, you may want partial claims or advanced indexing.
     */
    function sellerClaim(address offeringSeller, string calldata offeringId) external {
        require(msg.sender == offeringSeller, "Not your offering");
        bytes32 offKey = keccak256(abi.encodePacked(offeringId));
        Offering storage off = offerings[offeringSeller][offKey];
        require(off.exists, "No such offering");

        address[] storage subs = off.subscriberList;
        uint256 totalClaimed = 0;

        for (uint256 i = 0; i < subs.length; i++) {
            address buyer = subs[i];
            Subscription storage srec = off.subs[buyer];
            if (srec.lastAccrualTime == 0) continue; // skip
            _finalizeAccrual(srec, srec.subRate);

            uint256 owed = srec.owedToSeller;
            if (owed == 0) continue;

            // if deposit < owed, pay what's left
            if (owed > srec.deposit) {
                owed = srec.deposit;
            }
            srec.deposit -= owed;
            srec.owedToSeller = 0;

            totalClaimed += owed;
        }

        if (totalClaimed > 0) {
            bool ok = token.transfer(offeringSeller, totalClaimed);
            require(ok, "Seller claim transfer failed");
        }

        emit SellerClaimed(offeringSeller, offeringId, totalClaimed);
    }

    // ---------------------------------------------------------
    //                 INTERNAL ACCRUAL LOGIC
    // ---------------------------------------------------------
    /**
     * Lock in the subRate. This function finalizes at that subRate.
     */
    function _finalizeAccrual(Subscription storage srec, uint256 rate) internal {
        uint256 nowTime = block.timestamp;
        uint256 last = srec.lastAccrualTime;
        if (nowTime <= last) return;

        if (rate == 0) {
            srec.lastAccrualTime = nowTime;
            return;
        }

        uint256 delta = nowTime - last;
        uint256 newlyAccrued = (rate * delta) / 3600;
        srec.owedToSeller += newlyAccrued;
        srec.lastAccrualTime = nowTime;
    }

    // ---------------------------------------------------------
    //               VIEW / HELPER FUNCTIONS
    // ---------------------------------------------------------
    function getOfferingRate(address seller, string calldata offeringId) external view returns (uint256) {
        return offerings[seller][keccak256(abi.encodePacked(offeringId))].currentRate;
    }

    function getSubscription(address seller, string calldata offeringId, address buyer)
        external
        view
        returns (
            uint256 deposit,
            uint256 owedToSeller,
            uint256 lastAccrualTime,
            uint256 subRate
        )
    {
        Subscription storage srec = offerings[seller][keccak256(abi.encodePacked(offeringId))].subs[buyer];
        return (srec.deposit, srec.owedToSeller, srec.lastAccrualTime, srec.subRate);
    }
}
