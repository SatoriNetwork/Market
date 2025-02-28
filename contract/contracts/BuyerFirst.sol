// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * OPTIONAL:
 * import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
 * import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
 *
 * contract SatoriPayment is ReentrancyGuard { // if you want re-entrancy guard
 *     using SafeERC20 for IERC20; // if you want safeERC20
 *     ...
 * }
 */

/**
 * Minimal ERC20 interface for the Satori token.
 */
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

/**
 * Satori Payment Contract (Simplified)
 *
 * Changes:
 *  - URL and cadence are now immutable (set at creation, cannot be changed).
 *  - A deal can be created with zero initial deposit.
 *  - moveDeposit(...) lets a Buyer transfer leftover deposit from one deal to another.
 *  - Now, the Buyer can set a seller rate for an unregistered address, automatically registering them.
 *
 * If you want re-entrancy guard or SafeERC20, see the commented code.
 */
contract SatoriPayment {
    // ---------------------------------
    // OPTIONAL:
    // import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
    // import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    // using SafeERC20 for IERC20;
    // etc.
    // ---------------------------------

    // ============ EVENTS ============ //

    /**
     * Emitted when a new deal is created.
     */
    event DealCreated(
        uint256 indexed dealId,
        address indexed buyer,
        uint256 initialDeposit,
        uint256 cadence,
        string serviceURL
    );

    /**
     * Emitted when a seller registers on a deal.
     */
    event SellerRegistered(uint256 indexed dealId, address indexed seller);

    /**
     * Emitted when the buyer sets a seller's rate.
     */
    event SellerRateSet(uint256 indexed dealId, address indexed seller, uint256 oldRate, uint256 newRate);

    /**
     * Emitted when a seller claims tokens.
     */
    event SellerClaimed(uint256 indexed dealId, address indexed seller, uint256 claimedAmount);

    /**
     * Emitted when the buyer deposits more tokens.
     */
    event BuyerDeposited(uint256 indexed dealId, uint256 amount);

    /**
     * Emitted when the buyer withdraws leftover tokens.
     */
    event BuyerWithdrew(uint256 indexed dealId, uint256 amount);

    /**
     * Emitted when the buyer moves deposit from one deal to another.
     */
    event BuyerMovedDeposit(uint256 indexed fromDealId, uint256 indexed toDealId, uint256 amount);


    IERC20 public immutable satori;

    // Incrementing ID to track each deal
    uint256 public dealCounter;

    // Default cadence is 1 hour (3600 seconds) if user sets 0.
    uint256 public constant DEFAULT_CADENCE = 3600;

    struct SellerInfo {
        // Rate in tokens per "cadence"
        uint256 ratePerCadence;
        // Last time we accounted for accrual
        uint256 lastClaimTime;
        // Accrued tokens that haven't been claimed
        uint256 accrued;
    }

    struct Deal {
        address buyer;
        string serviceURL;   // immutable after creation
        uint256 deposit;     // Satori tokens in the deal
        uint256 cadence;     // immutable after creation

        address[] sellerList;
        mapping(address => SellerInfo) sellers;
    }

    mapping(uint256 => Deal) private deals;

    constructor(address _satoriToken) {
        satori = IERC20(_satoriToken);
    }

    // ---------------------------------------------------------
    //                  DEAL CREATION
    // ---------------------------------------------------------

    /**
     * Buyer creates a new deal with optional initial deposit.
     *  - If _initialDeposit == 0, the deal starts with no deposit.
     *  - If _cadenceInSeconds == 0, we default to 1 hour.
     */
    function createDeal(
        string calldata _serviceURL,
        uint256 _cadenceInSeconds,
        uint256 _initialDeposit
    ) external returns (uint256 dealId) {
        dealCounter++;
        dealId = dealCounter;

        Deal storage d = deals[dealId];
        d.buyer = msg.sender;
        d.serviceURL = _serviceURL;
        d.cadence = (_cadenceInSeconds == 0) ? DEFAULT_CADENCE : _cadenceInSeconds;

        // If they specified an initial deposit, attempt transferFrom.
        if (_initialDeposit > 0) {
            require(
                satori.transferFrom(msg.sender, address(this), _initialDeposit),
                "Satori transfer failed"
            );
            d.deposit = _initialDeposit;
        }

        emit DealCreated(dealId, msg.sender, _initialDeposit, d.cadence, _serviceURL);
    }

    // ---------------------------------------------------------
    //             SELLER REGISTRATION / RATE
    // ---------------------------------------------------------

    /**
     * Seller calls this to register themselves on a deal (rate=0 by default).
     * The Buyer can then set or update the rate.
     */
    function registerAsSeller(uint256 dealId) external {
        Deal storage d = deals[dealId];
        require(d.buyer != address(0), "Invalid deal");

        SellerInfo storage si = d.sellers[msg.sender];
        if (si.lastClaimTime == 0) {
            si.lastClaimTime = block.timestamp;
            d.sellerList.push(msg.sender);
            emit SellerRegistered(dealId, msg.sender);
        }
    }

    /**
     * Buyer sets or updates the Seller's tokens-per-cadence rate.
     * If the "seller" is not yet registered, we'll auto-register them.
     * Then finalize any accrual up to now under the old rate.
     */
    function setSellerRate(
        uint256 dealId,
        address seller,
        uint256 newRate
    ) external onlyDealBuyer(dealId) {
        Deal storage d = deals[dealId];
        SellerInfo storage si = d.sellers[seller];

        // Auto-register if needed
        if (si.lastClaimTime == 0) {
            si.lastClaimTime = block.timestamp;
            d.sellerList.push(seller);
            emit SellerRegistered(dealId, seller);
        }

        // Finalize accrual at the old rate
        _finalizeAccrual(d, si, block.timestamp);

        uint256 oldRate = si.ratePerCadence;
        si.ratePerCadence = newRate;

        emit SellerRateSet(dealId, seller, oldRate, newRate);
    }

    // ---------------------------------------------------------
    //               SELLER CLAIM LOGIC
    // ---------------------------------------------------------

    /**
     * Seller claims all accrued tokens for a given deal.
     * Accrual is calculated from lastClaimTime to now.
     */
    function claim(uint256 dealId) external {
        Deal storage d = deals[dealId];
        SellerInfo storage si = d.sellers[msg.sender];
        require(si.lastClaimTime > 0, "Not a seller here");

        uint256 newlyAccrued = _finalizeAccrual(d, si, block.timestamp);
        uint256 totalOwed = si.accrued + newlyAccrued;
        if (totalOwed == 0) {
            return; // nothing to pay
        }

        // If deposit is insufficient, pay what's left
        uint256 payout = totalOwed > d.deposit ? d.deposit : totalOwed;
        d.deposit -= payout;
        si.accrued = 0;

        require(satori.transfer(msg.sender, payout), "Satori transfer failed");

        si.lastClaimTime = block.timestamp;

        emit SellerClaimed(dealId, msg.sender, payout);
    }

    /**
     * Internal helper for continuous accrual.
     * tokens = ratePerCadence * (delta / deal.cadence).
     * partial intervals yield partial tokens.
     */
    function _finalizeAccrual(
        Deal storage d,
        SellerInfo storage si,
        uint256 toTime
    ) internal returns (uint256 newlyAccrued) {
        uint256 last = si.lastClaimTime;
        if (toTime <= last) {
            return 0;
        }
        if (si.ratePerCadence == 0) {
            // no rate => no accrual
            si.lastClaimTime = toTime;
            return 0;
        }

        uint256 c = d.cadence;
        if (c == 0) {
            c = DEFAULT_CADENCE;
        }

        uint256 delta = toTime - last;
        newlyAccrued = (si.ratePerCadence * delta) / c;

        si.lastClaimTime = toTime;
        si.accrued += newlyAccrued;
        return newlyAccrued;
    }

    // ---------------------------------------------------------
    //           BUYER DEPOSITS / WITHDRAWALS
    // ---------------------------------------------------------

    /**
     * Buyer can deposit additional tokens into the deal.
     */
    function depositTokens(uint256 dealId, uint256 amount) external onlyDealBuyer(dealId) {
        Deal storage d = deals[dealId];
        require(
            satori.transferFrom(msg.sender, address(this), amount),
            "Satori transfer failed"
        );
        d.deposit += amount;

        emit BuyerDeposited(dealId, amount);
    }

    /**
     * Buyer withdraws leftover deposit. They cannot withdraw tokens that Sellers have accrued.
     */
    function buyerWithdraw(uint256 dealId, uint256 amount) external onlyDealBuyer(dealId) {
        Deal storage d = deals[dealId];

        // 1) Finalize accrual for all sellers so we know how much is owed.
        _finalizeAccrualAllSellers(d);

        // 2) Sum total accrued across all sellers.
        uint256 totalAccrued = _sumAccrued(d);

        require(
            d.deposit >= totalAccrued + amount,
            "Cannot withdraw: would dip into seller accrual"
        );

        d.deposit -= amount;
        require(satori.transfer(msg.sender, amount), "Satori transfer failed");

        emit BuyerWithdrew(dealId, amount);
    }

    /**
     * Move leftover deposit from one deal to another (both must be owned by the same buyer).
     * This avoids withdrawing to the buyer's wallet and re-depositing.
     */
    function moveDeposit(uint256 fromDealId, uint256 toDealId, uint256 amount) external {
        Deal storage src = deals[fromDealId];
        Deal storage dst = deals[toDealId];

        // Ensure same buyer for both deals
        require(src.buyer == msg.sender, "Not buyer of source deal");
        require(dst.buyer == msg.sender, "Not buyer of target deal");

        // Finalize accrual on the source deal so we know how much is leftover.
        _finalizeAccrualAllSellers(src);
        uint256 totalAccrued = _sumAccrued(src);
        require(
            src.deposit >= totalAccrued + amount,
            "Cannot move deposit: insufficient leftover"
        );

        // Move the deposit from src to dst
        src.deposit -= amount;
        dst.deposit += amount;

        emit BuyerMovedDeposit(fromDealId, toDealId, amount);
    }

    /**
     * Finalize accrual for each seller in the deal.
     */
    function _finalizeAccrualAllSellers(Deal storage d) internal {
        uint256 len = d.sellerList.length;
        uint256 nowTime = block.timestamp;

        for (uint256 i = 0; i < len; i++) {
            SellerInfo storage si = d.sellers[d.sellerList[i]];
            if (si.ratePerCadence > 0) {
                _finalizeAccrual(d, si, nowTime);
            } else if (si.lastClaimTime < nowTime) {
                si.lastClaimTime = nowTime;
            }
        }
    }

    function _sumAccrued(Deal storage d) internal view returns (uint256 total) {
        uint256 len = d.sellerList.length;
        for (uint256 i = 0; i < len; i++) {
            total += d.sellers[d.sellerList[i]].accrued;
        }
    }

    // ---------------------------------------------------------
    //                       MODIFIERS
    // ---------------------------------------------------------

    modifier onlyDealBuyer(uint256 dealId) {
        require(deals[dealId].buyer == msg.sender, "Not the buyer");
        _;
    }

    // ---------------------------------------------------------
    //            VIEW FUNCTIONS (OPTIONAL HELPERS)
    // ---------------------------------------------------------

    /**
     * Return basic info about a deal.
     */
    function getDeal(uint256 dealId)
        external
        view
        returns (
            address buyer,
            string memory serviceURL,
            uint256 deposit,
            uint256 cadence,
            address[] memory sellers
        )
    {
        Deal storage d = deals[dealId];
        buyer = d.buyer;
        serviceURL = d.serviceURL;
        deposit = d.deposit;
        cadence = d.cadence;
        sellers = d.sellerList;
    }

    /**
     * Get details about a specific seller in a given deal.
     */
    function getSellerInfo(uint256 dealId, address seller)
        external
        view
        returns (
            uint256 ratePerCadence,
            uint256 lastClaimTime,
            uint256 accrued
        )
    {
        SellerInfo storage si = deals[dealId].sellers[seller];
        ratePerCadence = si.ratePerCadence;
        lastClaimTime = si.lastClaimTime;
        accrued = si.accrued;
    }
}
