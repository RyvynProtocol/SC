// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract YieldManager is Ownable {
    using SafeERC20 for IERC20;

    // --- STATE VARIABLES ---
    IERC20 public immutable usdc;

    uint256 public unallocatedYieldPool;
    uint256 public targetUtilization = 8000;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_REWARD_RATE = 1000; // Cap at 10%

    uint256 public constant SNAPSHOT_PERIOD = 1 days;
    uint256 public constant MOVING_AVERAGE_DAYS = 7;

    struct DailySnapshot {
        uint256 volume;
        uint256 timestamp;
    }

    DailySnapshot[] public dailySnapshots;
    uint256 public currentDayVolume;
    uint256 public lastSnapshotTime;

    uint256 public totalYieldDeposited;
    uint256 public totalYieldAllocated;

    address public ryvynHandler;

    // --- EVENTS ---
    event YieldDeposited(uint256 amount, uint256 timestamp);
    event RewardAllocated(address indexed user, uint256 amount);
    event DailySnapshotRecorded(uint256 volume, uint256 timestamp);
    event TargetUtilizationUpdated(uint256 oldValue, uint256 newValue);
    event TransferVolumeRecorded(uint256 amount);

    // --- ERRORS ---
    error Unauthorized();
    error InvalidAmount();
    error InvalidUtilization();

    // --- MODIFIERS ---
    modifier onlyAuthorized() {
        if (msg.sender != ryvynHandler && msg.sender != owner()) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _usdc, address _initialOwner) Ownable(_initialOwner) {
        require(_usdc != address(0), "Invalid USDC address");
        usdc = IERC20(_usdc);
        lastSnapshotTime = block.timestamp;
    }

    // --- ADMIN FUNCTIONS ---
    function setRyvynHandler(address _handler) external onlyOwner {
        require(_handler != address(0), "Invalid address");
        ryvynHandler = _handler;
    }

    function setTargetUtilization(uint256 _utilization) external onlyOwner {
        if (_utilization == 0 || _utilization > BASIS_POINTS) {
            revert InvalidUtilization();
        }
        emit TargetUtilizationUpdated(targetUtilization, _utilization);
        targetUtilization = _utilization;
    }

    // --- ADMIN FUNCTIONS ---
    function simulateYieldGeneration(uint256 amount) external onlyOwner {
        unallocatedYieldPool += amount;
        totalYieldDeposited += amount;
        emit YieldDeposited(amount, block.timestamp);
    }

    function addDemoVolume(uint256 volume) external onlyOwner {
        currentDayVolume += volume;
        emit TransferVolumeRecorded(volume);
    }

    function resetSnapshots() external onlyOwner {
        delete dailySnapshots;
        currentDayVolume = 0;
        lastSnapshotTime = block.timestamp;
    }

    // --- CORE FUNCTIONS ---
    function depositYield(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        unallocatedYieldPool += amount;
        totalYieldDeposited += amount;

        emit YieldDeposited(amount, block.timestamp);
    }

    function recordTransferVolume(uint256 amount) external onlyAuthorized {
        currentDayVolume += amount;
        emit TransferVolumeRecorded(amount);

        if (block.timestamp >= lastSnapshotTime + SNAPSHOT_PERIOD) {
            _recordDailySnapshot();
        }
    }

    function allocateReward(
        address user,
        uint256 amount
    ) external onlyAuthorized {
        if (amount == 0) return;
        if (amount > unallocatedYieldPool) {
            amount = unallocatedYieldPool;
        }

        if (amount > 0) {
            unallocatedYieldPool -= amount;
            totalYieldAllocated += amount;
            emit RewardAllocated(user, amount);
        }
    }

    function recordDailySnapshot() external {
        _recordDailySnapshot();
    }

    function _recordDailySnapshot() internal {
        dailySnapshots.push(
            DailySnapshot({
                volume: currentDayVolume,
                timestamp: block.timestamp
            })
        );

        emit DailySnapshotRecorded(currentDayVolume, block.timestamp);

        currentDayVolume = 0;
        lastSnapshotTime = block.timestamp;

        if (dailySnapshots.length > MOVING_AVERAGE_DAYS) {
            for (uint256 i = 0; i < dailySnapshots.length - 1; i++) {
                dailySnapshots[i] = dailySnapshots[i + 1];
            }
            dailySnapshots.pop();
        }
    }

    // --- VIEW FUNCTIONS ---
    function getMovingAverageVolume() public view returns (uint256) {
        if (dailySnapshots.length == 0) {
            return currentDayVolume > 0 ? currentDayVolume : 1e18;
        }

        uint256 totalVolume = currentDayVolume;
        for (uint256 i = 0; i < dailySnapshots.length; i++) {
            totalVolume += dailySnapshots[i].volume;
        }

        uint256 numDays = dailySnapshots.length + 1;
        return totalVolume / numDays;
    }

    function calculateDynamicRewardRate()
        public
        view
        returns (uint256 rewardRate)
    {
        uint256 movingAvg = getMovingAverageVolume();

        if (movingAvg == 0 || unallocatedYieldPool == 0) {
            return 0;
        }

        uint256 utilizableYield = (unallocatedYieldPool * targetUtilization) /
            BASIS_POINTS;
        rewardRate = (utilizableYield * BASIS_POINTS) / movingAvg;

        if (rewardRate > MAX_REWARD_RATE) {
            rewardRate = MAX_REWARD_RATE;
        }
    }

    function getPoolStats()
        external
        view
        returns (
            uint256 _unallocatedPool,
            uint256 _totalDeposited,
            uint256 _totalAllocated,
            uint256 _movingAverage,
            uint256 _rewardRate
        )
    {
        return (
            unallocatedYieldPool,
            totalYieldDeposited,
            totalYieldAllocated,
            getMovingAverageVolume(),
            calculateDynamicRewardRate()
        );
    }

    function getSnapshotsCount() external view returns (uint256) {
        return dailySnapshots.length;
    }

    function getSnapshot(
        uint256 index
    ) external view returns (uint256 volume, uint256 timestamp) {
        require(index < dailySnapshots.length, "Invalid index");
        DailySnapshot memory snapshot = dailySnapshots[index];
        return (snapshot.volume, snapshot.timestamp);
    }
}
