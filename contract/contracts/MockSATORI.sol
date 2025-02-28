// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockSATORI is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mock SATORI", "SATORI") {
        _mint(msg.sender, initialSupply);
    }
}
