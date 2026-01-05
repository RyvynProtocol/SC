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
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);
    event TransferRewardDistributed(
        address indexed sender,
        address indexed receiver,
        uint256 senderReward,
        uint256 receiverReward,
        uint256 timestamp
    );

    // ============ Structs ============
    struct UserInfo {
        uint128 pendingBalance;
        uint128 totalCredited;
        uint128 totalClaimed;
        uint64 lastUpdate;
    }

    // ============ State Variables ============
    mapping(address => UserInfo) public userInfo;

    address public ryvynHandler;
    IMockVault public vault;

    // Yield rate: growth rate per second SESUAIKAN SAMA FE BE nya ye
    // Example: 1e14 = 0.0001 ryBOND per second per ryBOND held (≈ 0.36 per hour)
    uint256 public yieldRatePerSecond;

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

    function _accrue(address user) internal {
        if (user == address(0)) return;

        UserInfo storage info = userInfo[user];
        uint64 lastTime = info.lastUpdate;
        if (lastTime == 0) {
            info.lastUpdate = uint64(block.timestamp);
            return;
        }

        uint256 elapsed = block.timestamp - lastTime;
        if (elapsed == 0) return;

        uint256 balance = info.pendingBalance;

        if (yieldRatePerSecond > 0 && balance > 0) {
            uint256 yieldAmount = (balance * yieldRatePerSecond * elapsed) /
                1e18;
            if (yieldAmount > 0) {
                info.pendingBalance = uint128(balance + yieldAmount);
                info.totalCredited += uint128(yieldAmount);
                emit RyBONDAccrued(user, yieldAmount, block.timestamp);
            }
        }

        info.lastUpdate = uint64(block.timestamp);
    }

    // ============ Constructor ============

    constructor(address _ryvynHandler, address _vault) Ownable(msg.sender) {
        require(_ryvynHandler != address(0), "ryBOND: handler is zero address");
        require(_vault != address(0), "ryBOND: vault is zero address");

        ryvynHandler = _ryvynHandler;
        vault = IMockVault(_vault);
    }

    // ============ External Functions (Called by RyvynHandler) ============

    function creditRyBond(address user, uint256 amount) external onlyHandler {
        require(user != address(0), "ryBOND: user is zero address");
        require(amount > 0, "ryBOND: amount is zero");

        _accrue(user);

        UserInfo storage info = userInfo[user];
        info.pendingBalance += uint128(amount);
        info.totalCredited += uint128(amount);

        emit RyBONDCredited(user, amount, block.timestamp);
    }

    function creditTransferReward(
        address sender,
        uint256 senderReward,
        address receiver,
        uint256 receiverReward
    ) external onlyHandler {
        _accrue(sender);
        _accrue(receiver);

        if (sender != address(0) && senderReward > 0) {
            UserInfo storage senderInfo = userInfo[sender];
            senderInfo.pendingBalance += uint128(senderReward);
            senderInfo.totalCredited += uint128(senderReward);
        }

        if (receiver != address(0) && receiverReward > 0) {
            UserInfo storage receiverInfo = userInfo[receiver];
            receiverInfo.pendingBalance += uint128(receiverReward);
            receiverInfo.totalCredited += uint128(receiverReward);
        }

        emit TransferRewardDistributed(
            sender,
            receiver,
            senderReward,
            receiverReward,
            block.timestamp
        );
    }

    // ============ User Functions ============

    function claim() external nonReentrant {
        _accrue(msg.sender);

        UserInfo storage info = userInfo[msg.sender];
        uint256 amount = info.pendingBalance;
        require(amount > 0, "ryBOND: nothing to claim");

        info.pendingBalance = 0;
        info.totalClaimed += uint128(amount);

        vault.distributeYield(msg.sender, amount);

        emit RyBONDClaimed(msg.sender, amount, block.timestamp);
    }

    function claimAmount(uint256 amount) external nonReentrant {
        require(amount > 0, "ryBOND: amount is zero");

        _accrue(msg.sender);

        UserInfo storage info = userInfo[msg.sender];
        require(info.pendingBalance >= amount, "ryBOND: insufficient balance");

        info.pendingBalance -= uint128(amount);
        info.totalClaimed += uint128(amount);

        vault.distributeYield(msg.sender, amount);

        emit RyBONDClaimed(msg.sender, amount, block.timestamp);
    }

    // ============ View Functions ============

    function pendingRyBond(address user) external view returns (uint256) {
        UserInfo storage info = userInfo[user];
        uint256 balance = info.pendingBalance;

        uint64 lastTime = info.lastUpdate;
        if (lastTime == 0 || yieldRatePerSecond == 0 || balance == 0) {
            return balance;
        }

        uint256 elapsed = block.timestamp - lastTime;
        uint256 simulatedYield = (balance * yieldRatePerSecond * elapsed) /
            1e18;

        return balance + simulatedYield;
    }

    function storedBalance(address user) external view returns (uint256) {
        return userInfo[user].pendingBalance;
    }

    function getUserStats(
        address user
    )
        external
        view
        returns (uint256 pending, uint256 credited, uint256 claimed)
    {
        UserInfo storage info = userInfo[user];
        return (info.pendingBalance, info.totalCredited, info.totalClaimed);
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

    function setYieldRate(uint256 newRate) external onlyOwner {
        uint256 oldRate = yieldRatePerSecond;
        yieldRatePerSecond = newRate;
        emit YieldRateUpdated(oldRate, newRate);
    }

    function accrue(address user) external {
        _accrue(user);
    }
}
