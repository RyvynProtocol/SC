// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract RyvynHandler is Ownable {
    address public ryUSD;

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function setRyUSD(address _ryUSD) external onlyOwner {
        ryUSD = _ryUSD;
    }

    function handleTransfer(address from, address to, uint256 amount) external {
        require(msg.sender == ryUSD, "Only RyUSD can call this");
    }
}
