// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMockVault {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getBalance() external view returns (uint256);
    function distributeYield(address to, uint256 amount) external;
    function getAvailableYield() external view returns (uint256);
}
