# Satori Prediction Marketplace

## 📌 Overview
The **Satori Prediction Marketplace** allows users to buy or sell forecasts over time.

---

## 🛠 Tech Stack
- **Solidity 0.8.25** (Smart contract development)
- **Truffle Framework** (Testing & deployment)
- **Ganache / Hardhat** (Local blockchain for testing)
- **OpenZeppelin Contracts** (Security & upgradeability)
- **Web3.js** (Interaction with smart contract in tests)

---

## 📁 Project Structure
```
├── contracts
│   ├── BuyerFirst.sol     # contract for buyers to initiate relationships
│   ├── SellerFirst.sol    # contract for sellers to initiate relationships
│   ├── MockSATORI.sol     # Mock SATORI token (for testing)
│
├── migrations
│   ├── 1_deploy_contracts.js  # Deployment script for BuyerFirst contract
│
├── test
│   ├── BuyerFirstTest.js        # Test script for BuyerFirst smart contract
│
├── truffle-config.js      # Truffle network & compiler configuration
├── package.json           # Project dependencies
├── README.md              # Project documentation
```

---

## ⚙️ Installation & Setup
### **1️⃣ Install Dependencies**
Run the following command in the project directory:
```sh
npm install
```
This installs all required dependencies, including:
- `@openzeppelin/contracts`
- `@openzeppelin/test-helpers`
- `@openzeppelin/truffle-upgrades`
- `chai`
- `web3`

### **2️⃣ Start a Local Blockchain (Ganache CLI)**
```sh
ganache-cli -p 9545
```
Or, if using **Truffle Develop**, start the Truffle built-in blockchain:
```sh
truffle develop
```

### **3️⃣ Configure Truffle (Optional)**
Check `truffle-config.js` and ensure the `development` network is set correctly:
```js
networks: {
  development: {
    host: "127.0.0.1",
    port: 9545,
    network_id: "*",
  },
},
```

---

## 🚀 Deployment
### **1️⃣ Deploy Contracts to Local Blockchain**
```sh
truffle migrate --reset --network development
```
This will deploy **BuyerFirst.sol**, **MockUSDC.sol**, and **MockSATORI.sol** to your local blockchain.

### **2️⃣ Deploy Contracts to Live Network**
To deploy the contracts to a live network, you need to configure your `.env` file with the appropriate credentials and network settings.

1. **Configure Environment Variables**: Create a `.env` file in the root of your project (or use the provided `.env.example` as a template) and set the following variables:
   ```plaintext
   MNEMONIC=your_mnemonic_phrase_here
   PRIVATE_KEY=your_priv_key
   RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
   ```

2. **Update Truffle Configuration**: Ensure your `truffle-config.js` is set up to use the live network. For example:
   ```js
   networks: {
     live: {
       provider: () => new HDWalletProvider(
        process.env.MNEMONIC, // or PRIVATE_KEY
        process.env.RPC_URL),
       network_id: 1, // Mainnet ID
       gas: 5500000,  // Gas limit
       gasPrice: 20000000000, // 20 Gwei
     },
   },
   ```

3. **Deploy**: Run the following command to deploy to the live network:
   ```sh
   truffle migrate --network live
   ```

---

## 🧪 Running Tests
### **1️⃣ Run Tests with Truffle**
```sh
truffle test --network development
```
This will execute the `BuyerFirstTest.js` script, which includes:
- **Depositing USDC**
- **Simulating time delays**
- **Claiming SATORI after lock period**
- **Verifying balances & state changes**

If using `truffle develop`, run tests inside the console:
```sh
test
```

---

## 📜 Smart Contract Overview
### **BuyerFirst.sol** (Main Contract)
- **Admin Functions**
  - `changeOwner(address newOwner)`: Change contract owner
  - `updatePrice(uint256 newPrice)`: Update SATORI price (only oracle)
  - `changeLockPeriod(uint256 newPeriod)`: Modify lock period

- **User Functions**
  - `depositUsdc(uint256 amount)`: Deposit USDC into the contract
  - `claimSatori()`: Claim SATORI rewards after the lock period
  - `calculateClaimSatoriAmount(address user)`: Calculate claimable SATORI

- **Events**
  - `UsdcDeposited(address user, uint256 amount)`
  - `SatoriSupplied(address from, uint256 amount)`
  - `Claimed(address user, uint256 amount)`

### **MockUSDC.sol & MockSATORI.sol**
- **Mock ERC-20 tokens** for testing **USDC** and **SATORI** interactions.
- Implement `mint()` function to provide test tokens.

---

## ⚡ Example Usage
```js
// Deploy contract
await fund.supplySatori(web3.utils.toWei("5000000", "ether"), { from: owner });

// Deposit USDC
await fund.depositUsdc(web3.utils.toWei("1000000", "ether"), { from: user });

// Simulate lock period
await time.increase(7200);

// Claim SATORI
await fund.claimSatori({ from: user });
```

---

## 📝 License
This project is licensed under the **MIT License** - see the LICENSE file for details..

---

## 🎯 Future Improvements
- ✅ Integrate with **Chainlink price feeds** for dynamic SATORI pricing.
- ✅ Add **withdrawal functions** for emergency fund recovery.
- ✅ Implement **frontend UI** for user interactions.

For any questions or contributions, feel free to open an issue or PR! 🚀
