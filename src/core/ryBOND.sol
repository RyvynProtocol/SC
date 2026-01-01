// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

    // ============ State Variables ============
    mapping(address => uint256) public pendingBalance;
    mapping(address => uint256) public totalCredited;
    mapping(address => uint256) public totalClaimed;
    mapping(address => uint256) public lastUpdate;

    address public ryvynHandler;
    address public vault;

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

        uint256 lastTime = lastUpdate[user];

        if (lastTime == 0) {
            lastUpdate[user] = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastTime;
        if (elapsed == 0) return;

        if (yieldRatePerSecond > 0 && pendingBalance[user] > 0) {
            uint256 yieldAmount = (pendingBalance[user] *
                yieldRatePerSecond *
                elapsed) / 1e18;
            if (yieldAmount > 0) {
                pendingBalance[user] += yieldAmount;
                totalCredited[user] += yieldAmount;
                emit RyBONDAccrued(user, yieldAmount, block.timestamp);
            }
        }

        lastUpdate[user] = block.timestamp;
    }

    // ============ Constructor ============

    constructor(address _ryvynHandler, address _vault) Ownable(msg.sender) {
        require(_ryvynHandler != address(0), "ryBOND: handler is zero address");
        require(_vault != address(0), "ryBOND: vault is zero address");

        ryvynHandler = _ryvynHandler;
        vault = _vault;
    }

    // ============ External Functions (Called by RyvynHandler) ============

    function creditRyBond(address user, uint256 amount) external onlyHandler {
        require(user != address(0), "ryBOND: user is zero address");
        require(amount > 0, "ryBOND: amount is zero");

        _accrue(user);

        pendingBalance[user] += amount;
        totalCredited[user] += amount;

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
            pendingBalance[sender] += senderReward;
            totalCredited[sender] += senderReward;
        }

        if (receiver != address(0) && receiverReward > 0) {
            pendingBalance[receiver] += receiverReward;
            totalCredited[receiver] += receiverReward;
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

        uint256 amount = pendingBalance[msg.sender];
        require(amount > 0, "ryBOND: nothing to claim");

        pendingBalance[msg.sender] = 0;
        totalClaimed[msg.sender] += amount;

        (bool success, ) = vault.call(
            abi.encodeWithSignature(
                "distributeYield(address,uint256)",
                msg.sender,
                amount
            )
        );
        require(success, "ryBOND: vault distribution failed");

        emit RyBONDClaimed(msg.sender, amount, block.timestamp);
    }

    function claimAmount(uint256 amount) external nonReentrant {
        require(amount > 0, "ryBOND: amount is zero");

        _accrue(msg.sender);

        require(
            pendingBalance[msg.sender] >= amount,
            "ryBOND: insufficient balance"
        );

        pendingBalance[msg.sender] -= amount;
        totalClaimed[msg.sender] += amount;

        (bool success, ) = vault.call(
            abi.encodeWithSignature(
                "distributeYield(address,uint256)",
                msg.sender,
                amount
            )
        );
        require(success, "ryBOND: vault distribution failed");

        emit RyBONDClaimed(msg.sender, amount, block.timestamp);
    }

    // ============ View Functions ============

    function pendingRyBond(address user) external view returns (uint256) {
        uint256 balance = pendingBalance[user];

        uint256 lastTime = lastUpdate[user];
        if (lastTime == 0 || yieldRatePerSecond == 0 || balance == 0) {
            return balance;
        }

        uint256 elapsed = block.timestamp - lastTime;
        uint256 simulatedYield = (balance * yieldRatePerSecond * elapsed) /
            1e18;

        return balance + simulatedYield;
    }

    function storedBalance(address user) external view returns (uint256) {
        return pendingBalance[user];
    }

    function getUserStats(
        address user
    )
        external
        view
        returns (uint256 pending, uint256 credited, uint256 claimed)
    {
        return (pendingBalance[user], totalCredited[user], totalClaimed[user]);
    }

    // ============ Admin Functions ============

    function setRyvynHandler(address _ryvynHandler) external onlyOwner {
        require(_ryvynHandler != address(0), "ryBOND: handler is zero address");
        ryvynHandler = _ryvynHandler;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "ryBOND: vault is zero address");
        vault = _vault;
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
