// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@interfaces/IMockVault.sol";

contract ryBOND is Ownable, ReentrancyGuard {
    // ============ Events ============
    event RyBONDCredited(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event RyBONDClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event RyBONDAccrued(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event VestingDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event TransferRewardDistributed(
        address indexed sender,
        address indexed receiver,
        uint256 senderReward,
        uint256 receiverReward,
        uint256 timestamp
    );

    // ============ Structs ============
    struct UserInfo {
        uint128 lockedBalance;
        uint128 vestedBalance;
        uint64 vestingEnd;
        uint64 lastUpdate;
    }

    // ============ State Variables ============
    mapping(address => UserInfo) public userInfo;

    address public ryvynHandler;
    IMockVault public vault;

    uint256 public vestingDuration;

    // ============ Modifiers ============

    modifier onlyHandler() {
        _onlyHandler();
        _;
    }

    function _onlyHandler() internal view {
        require(
            msg.sender == ryvynHandler,
            "ryBOND: caller is not RyvynHandler"
        );
    }

    // ============ Internal Functions ============

    function _updateVesting(address user) internal {
        if (user == address(0)) return;

        UserInfo storage info = userInfo[user];

        if (info.lastUpdate >= info.vestingEnd) {
            return;
        }

        uint256 currentTime = block.timestamp;
        if (currentTime > info.vestingEnd) {
            currentTime = info.vestingEnd;
        }

        uint256 elapsedTime = currentTime - info.lastUpdate;
        uint256 totalVestingTime = info.vestingEnd - info.lastUpdate;

        if (totalVestingTime > 0 && elapsedTime > 0) {
            uint256 vestedAmount = (uint256(info.lockedBalance) * elapsedTime) /
                totalVestingTime;

            if (vestedAmount > 0) {
                if (vestedAmount > info.lockedBalance) {
                    vestedAmount = info.lockedBalance;
                }

                info.lockedBalance -= uint128(vestedAmount);
                info.vestedBalance += uint128(vestedAmount);
                emit RyBONDAccrued(user, vestedAmount, block.timestamp);
            }
        }

        info.lastUpdate = uint64(currentTime);
    }

    // ============ Constructor ============

    constructor(address _ryvynHandler, address _vault) Ownable(msg.sender) {
        require(_ryvynHandler != address(0), "ryBOND: handler is zero address");
        require(_vault != address(0), "ryBOND: vault is zero address");

        ryvynHandler = _ryvynHandler;
        vault = IMockVault(_vault);
        vestingDuration = 7 days; // 7 days vesting
    }

    // ============ External Functions (Called by RyvynHandler) ============

    function creditRyBond(address user, uint256 amount) external onlyHandler {
        require(user != address(0), "ryBOND: user is zero address");
        require(amount > 0, "ryBOND: amount is zero");

        _updateVesting(user);

        UserInfo storage info = userInfo[user];

        info.lockedBalance += uint128(amount);

        info.lastUpdate = uint64(block.timestamp);
        info.vestingEnd = uint64(block.timestamp + vestingDuration);

        emit RyBONDCredited(user, amount, block.timestamp);
    }

    function creditTransferReward(
        address sender,
        uint256 senderReward,
        address receiver,
        uint256 receiverReward
    ) external onlyHandler {
        if (sender != address(0) && senderReward > 0) {
            _credit(sender, senderReward);
        }

        if (receiver != address(0) && receiverReward > 0) {
            _credit(receiver, receiverReward);
        }

        emit TransferRewardDistributed(
            sender,
            receiver,
            senderReward,
            receiverReward,
            block.timestamp
        );
    }

    function _credit(address user, uint256 amount) internal {
        _updateVesting(user);
        UserInfo storage info = userInfo[user];
        info.lockedBalance += uint128(amount);
        info.lastUpdate = uint64(block.timestamp);
        info.vestingEnd = uint64(block.timestamp + vestingDuration);
    }

    // ============ User Functions ============

    function claim() external nonReentrant {
        _updateVesting(msg.sender);

        UserInfo storage info = userInfo[msg.sender];
        uint256 amount = info.vestedBalance;
        require(amount > 0, "ryBOND: nothing to claim");

        info.vestedBalance = 0;

        vault.distributeYield(msg.sender, amount);

        emit RyBONDClaimed(msg.sender, amount, block.timestamp);
    }

    // ============ View Functions ============

    function pendingRyBond(address user) external view returns (uint256) {
        UserInfo storage info = userInfo[user];

        uint256 vested = info.vestedBalance;
        uint256 locked = info.lockedBalance;

        if (locked == 0 || block.timestamp < info.lastUpdate) {
            return vested;
        }

        uint256 currentTime = block.timestamp;
        if (currentTime > info.vestingEnd) {
            currentTime = info.vestingEnd;
        }

        uint256 elapsedTime = currentTime - info.lastUpdate;
        uint256 totalVestingTime = info.vestingEnd - info.lastUpdate;

        if (totalVestingTime > 0) {
            uint256 newVested = (uint256(locked) * elapsedTime) /
                totalVestingTime;
            vested += newVested;
        }

        return vested;
    }

    function getFlowRate(address user) external view returns (uint256) {
        UserInfo storage info = userInfo[user];
        if (info.lockedBalance == 0 || block.timestamp >= info.vestingEnd) {
            return 0;
        }

        uint256 remainingTime = info.vestingEnd - block.timestamp;
        if (remainingTime == 0) return 0;

        // Return amount per second
        return (uint256(info.lockedBalance) * 1e18) / remainingTime; // Scaled by 1e18 for precision
    }

    // ============ Admin Functions ============

    function setRyvynHandler(address _ryvynHandler) external onlyOwner {
        require(_ryvynHandler != address(0), "ryBOND: handler is zero address");
        ryvynHandler = _ryvynHandler;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "ryBOND: vault is zero address");
        vault = IMockVault(_vault);
    }

    function setVestingDuration(uint256 newDuration) external onlyOwner {
        uint256 oldDuration = vestingDuration;
        vestingDuration = newDuration;
        emit VestingDurationUpdated(oldDuration, newDuration);
    }
}
