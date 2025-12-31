// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRyvynHandler {
    function handleTransfer(address from, address to, uint256 amount) external;
     function onMint(address user, uint256 amount) external;
}
