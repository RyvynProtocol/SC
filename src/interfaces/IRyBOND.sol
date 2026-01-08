// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRyBOND {
    function creditRyBond(address user, uint256 amount) external;

    function creditTransferReward(
        address sender,
        uint256 senderReward,
        address receiver,
        uint256 receiverReward
    ) external;
}
