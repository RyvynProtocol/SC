// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYieldManager {
    function recordTransferVolume(uint256 amount) external;

    function allocateReward(address user, uint256 amount) external;

    function calculateDynamicRewardRate() external view returns (uint256);

    function getMovingAverageVolume() external view returns (uint256);

    function unallocatedYieldPool() external view returns (uint256);
}
