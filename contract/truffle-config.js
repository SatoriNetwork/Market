/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * https://trufflesuite.com/docs/truffle/reference/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

require('dotenv').config();
const mnemonic = process.env["MNEMONIC"];
const privateKey = process.env["PRIVATE_KEY"];
const rpcUrl = process.env["RPC_URL"];
// const infuraProjectId = process.env["INFURA_PROJECT_ID"];

const HDWalletProvider = require('@truffle/hdwallet-provider');

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  networks: {
    // Useful for testing. The `development` name is special - truffle uses it by default
    // if it's defined here and no other network is specified at the command line.
    // You should run a client (like ganache, geth, or parity) in a separate terminal
    // tab if you use this network and you must also set the `host`, `port` and `network_id`
    // options below to some value.
    //
    development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
    },
    basemainnet: {
      provider: () => new HDWalletProvider(privateKey, rpcUrl),
      network_id: 8453,
      chain_id: 8453,
      gas: 5000000,
    },
    sepolia: {
      provider: () => new HDWalletProvider(privateKey, rpcUrl),
      network_id: 11155111,
      chain_id: 11155111,
      gas: 5000000,
    },
    base_mainnet: {
      provider: () => new HDWalletProvider(
        privateKey,
        rpcUrl
      ),
      network_id: 8453,  // Base mainnet network ID
      gas: 8000000,      // Adjust based on your contract needs
      gasPrice: 1000000000,  // 1 gwei, adjust based on current gas prices
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: false
    }
    //
    // goerli: {
    //   provider: () => new HDWalletProvider(privKey, `https://goerli.infura.io/v3/${infuraProjectId}`),
    //   network_id: 5,       // Goerli's id
    //   chain_id: 5
    // }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.25",      // Fetch exact version from solc-bin
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
        evmVersion: "london"
      }
    }
  },
  plugins: ["@openzeppelin/truffle-upgrades"],
};
