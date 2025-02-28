const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const MockSATORI = artifacts.require("MockSATORI");
const SellerFirst = artifacts.require("SellerFirst");

module.exports = async function (deployer, accounts) {

  // Deploy the mock Satori token
  await deployer.deploy(MockSATORI, web3.utils.toWei('5000000', 'ether'));
  const satori = await MockSATORI.deployed();

  // Deploy the SellerFirst contract with the necessary parameters
  await deployer.deploy(SellerFirst, satori.address);
  const market = await SellerFirst.deployed();

  // test functions of sellers and buyers
  //await market.changeLockPeriod(1, { from: owner });
  //await market.addAllowedAddresses([accounts[4]], { from: owner });
  //await market.updatePrice(web3.utils.toWei('16.09', 'ether'), { from: oracle });
  //await satori.approve(market.address, web3.utils.toWei('1000000', 'ether'), { from: owner });
  //await market.supplySatori(web3.utils.toWei('1000000', 'ether'), { from: owner });

  console.log(`Satori token deployed at: ${satori.address}`);
  console.log(`SellerFirst contract deployed at: ${market.address}`);
};
