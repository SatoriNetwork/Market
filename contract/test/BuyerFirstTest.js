const MockSATORI = artifacts.require("MockSATORI");
const BuyerFirst = artifacts.require("BuyerFirst");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const { time } = require("@openzeppelin/test-helpers/");
const { assert } = require("chai");
const { BN } = web3.utils;

contract("BuyerFirst", accounts => {
  const [buyer, seller] = accounts;
  let satori;
  let market;
  const initialSATORI = web3.utils.toWei('90000000', 'ether');

  beforeEach(async () => {
    satori = await MockSATORI.new(initialSATORI);
    market = await BuyerFirst.new(satori.address);
  });

  // Test for supplySatori function
  it("it should let anyone make a deal as a buyer", async () => {
    try {
      await market.createDeal(
        '_serviceURL',
        60*60, //_cadenceInSeconds,
        10,  //_initialDeposit,
        { from: newOwner });
    } catch (error) {
      assert.include(error.message, "Only owner can call this function", "Only owner can call this function");
    }
  });
});
