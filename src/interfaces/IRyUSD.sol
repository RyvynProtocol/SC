// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRyUSD {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;

    function totalMinted() external view returns (uint256);
    function totalBurned() external view returns (uint256);
    function getMintHistoryLength() external view returns (uint256);
}
