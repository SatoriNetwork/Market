const { web3 } = require("@openzeppelin/test-helpers/src/setup");
require('dotenv').config();
const SellerFirst = artifacts.require("SellerFirst");

module.exports = async function (deployer, network) {  // Ensure we're on mainnet

    if (network !== 'base_mainnet') {
        console.log('This deployment script is intended for base_mainnet only');
        return;
    }

    // Verify required environment variables
    if (!process.env.USDC_ADDRESS || !process.env.SATORI_ADDRESS) {
        throw new Error('Missing required environment variables: USDC_ADDRESS or SATORI_ADDRESS');
    }

    const satoriAddress = process.env.SATORI_ADDRESS;

    await deployer.deploy(SellerFirst, satoriAddress);
    const market = await SellerFirst.deployed();

    console.log(`SellerFirst contract deployed at: ${market.address}`);
};
