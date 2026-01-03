// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITreasuryManager {
    function onMint(uint256 amount) external;
    function onRedeem(address to, uint256 amount) external;
}
