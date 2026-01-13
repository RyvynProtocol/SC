// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "src/logic/TokenBucketLib.sol";
import "src/interfaces/IRyBOND.sol";
import "src/interfaces/IYieldManager.sol";

contract RyvynHandler is Ownable {
    using TokenBucketLib for TokenBucketLib.UserBuckets;

    address public ryUSD;
    address public ryBOND;
    address public yieldManager;

    mapping(address => TokenBucketLib.UserBuckets) public userBuckets;

    uint256 public constant BASE_SENDER_SHARE = 70; // 70%
    uint256 public constant BASE_RECEIVER_SHARE = 30; // 30%
    uint256 public constant MAX_SHIFT_CAP = 20; // ±20%
    uint256 public constant SCALING_FACTOR = 90 days; // 3 months normalization
    uint256 public constant PERCENT_PRECISION = 100;

    event MintHandled(address indexed user, uint256 amount, uint256 reward);
    event TransferHandled(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 senderAge,
        uint256 receiverAge,
        uint256 senderReward,
        uint256 receiverReward
    );

    error InvalidAddress();

    modifier onlyRyUSD() {
        require(msg.sender == ryUSD, "Only ryUSD can call");
        _;
    }

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function setRyUSD(address _ryUSD) external onlyOwner {
        if (_ryUSD == address(0)) revert InvalidAddress();
        ryUSD = _ryUSD;
    }

    function setRyBOND(address _ryBOND) external onlyOwner {
        if (_ryBOND == address(0)) revert InvalidAddress();
        ryBOND = _ryBOND;
    }

    function setYieldManager(address _yieldManager) external onlyOwner {
        if (_yieldManager == address(0)) revert InvalidAddress();
        yieldManager = _yieldManager;
    }

    function onMint(address user, uint256 amount) external onlyRyUSD {
        if (user == address(0)) revert InvalidAddress();
        userBuckets[user].addBucket(amount);

        uint256 reward = 0;
        // Reward on mint disabled to prevent instant arbitrage
        /*
        if (ryBOND != address(0) && yieldManager != address(0)) {
            uint256 rewardRate = IYieldManager(yieldManager)
                .calculateDynamicRewardRate();
            reward = (amount * rewardRate) / 10000;

            if (reward > 0) {
                IYieldManager(yieldManager).allocateReward(user, reward);
                IRyBOND(ryBOND).creditRyBond(user, reward);
            }
        }
        */

        emit MintHandled(user, amount, reward);
    }

    function handleTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRyUSD {
        if (from == address(0) || to == address(0)) revert InvalidAddress();

        userBuckets[from].updateAllBucketStatuses();

        uint256 senderAge = userBuckets[from].consumeBucket(uint96(amount));
        uint256 receiverAge = getWeightedAge(to);

        userBuckets[to].addBucket(amount);

        if (yieldManager != address(0)) {
            IYieldManager(yieldManager).recordTransferVolume(amount);
        }

        uint256 senderReward = 0;
        uint256 receiverReward = 0;

        if (ryBOND != address(0) && yieldManager != address(0)) {
            uint256 rewardRate = IYieldManager(yieldManager)
                .calculateDynamicRewardRate();

            if (rewardRate > 0) {
                (
                    uint256 senderShare,
                    uint256 receiverShare
                ) = calculateDynamicSplit(senderAge);

                uint256 totalReward = (amount * rewardRate) / 10000;

                senderReward = (totalReward * senderShare) / PERCENT_PRECISION;
                receiverReward =
                    (totalReward * receiverShare) /
                    PERCENT_PRECISION;

                if (senderReward > 0 || receiverReward > 0) {
                    IYieldManager(yieldManager).allocateReward(
                        from,
                        senderReward + receiverReward
                    );

                    IRyBOND(ryBOND).creditTransferReward(
                        from,
                        senderReward,
                        to,
                        receiverReward
                    );
                }
            }
        }

        emit TransferHandled(
            from,
            to,
            amount,
            senderAge,
            receiverAge,
            senderReward,
            receiverReward
        );
    }

    function calculateDynamicSplit(
        uint256 weightedAge
    ) public pure returns (uint256 senderShare, uint256 receiverShare) {
        uint256 ageFactor = (weightedAge * MAX_SHIFT_CAP) / SCALING_FACTOR;

        if (ageFactor > MAX_SHIFT_CAP) {
            ageFactor = MAX_SHIFT_CAP;
        }
        senderShare = BASE_SENDER_SHARE + ageFactor;

        if (senderShare > 90) {
            senderShare = 90;
        } else if (senderShare < 50) {
            senderShare = 50;
        }

        receiverShare = PERCENT_PRECISION - senderShare;
    }

    // --- VIEW FUNCTIONS ---
    function getUserBucketInfo(
        address user
    )
        external
        view
        returns (
            uint256 activeBuckets,
            uint256 totalBalance,
            uint256 oldestBucketAge
        )
    {
        return userBuckets[user].getBucketInfo();
    }

    function getBucketBalance(address user) external view returns (uint256) {
        return userBuckets[user].getTotalBalance();
    }

    function getBucketStatusCounts(
        address user
    ) external view returns (uint256 uninvested, uint256 invested) {
        return userBuckets[user].getBucketStatusCounts();
    }

    function getWeightedAge(address user) internal view returns (uint256) {
        TokenBucketLib.UserBuckets storage self = userBuckets[user];
        uint256 totalBalance = 0;
        uint256 totalWeightedTime = 0;
        uint256 bucketsLength = self.buckets.length;
        uint32 pointer = self.pointer;

        for (
            uint256 i = pointer;
            i < bucketsLength && i < TokenBucketLib.MAX_BUCKETS_PER_CONSUME;
            i++
        ) {
            TokenBucketLib.Bucket memory bucket = self.buckets[i];
            totalWeightedTime += (bucket.amount *
                (block.timestamp - bucket.timestamp));
            totalBalance += bucket.amount;
        }

        if (totalBalance == 0) return 0;
        return totalWeightedTime / totalBalance;
    }

    // -- ADMIN FUNCTION --
    function forceUpdateBucketStatuses(address user) external onlyOwner {
        userBuckets[user].updateAllBucketStatuses();
    }

    function getUserBucketsDetailed(
        address user
    )
        external
        view
        returns (
            uint256[] memory amounts,
            uint256[] memory timestamps,
            uint256[] memory ages,
            TokenBucketLib.BucketStatus[] memory statuses
        )
    {
        TokenBucketLib.UserBuckets storage ub = userBuckets[user];
        uint256 count = ub.buckets.length - ub.pointer;

        amounts = new uint256[](count);
        timestamps = new uint256[](count);
        ages = new uint256[](count);
        statuses = new TokenBucketLib.BucketStatus[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 idx = ub.pointer + i;
            amounts[i] = ub.buckets[idx].amount;
            timestamps[i] = ub.buckets[idx].timestamp;
            ages[i] = block.timestamp - timestamps[i];
            statuses[i] = ub.buckets[idx].status;
        }
    }

    function previewTransferRewards(
        address from,
        uint256 amount
    )
        external
        view
        returns (
            uint256 senderReward,
            uint256 receiverReward,
            uint256 senderShare,
            uint256 receiverShare
        )
    {
        if (yieldManager == address(0)) return (0, 0, 0, 0);

        uint256 senderAge = getWeightedAge(from);
        uint256 rewardRate = IYieldManager(yieldManager)
            .calculateDynamicRewardRate();

        if (rewardRate == 0) return (0, 0, 0, 0);

        (senderShare, receiverShare) = calculateDynamicSplit(senderAge);

        uint256 totalReward = (amount * rewardRate) / 10000;
        senderReward = (totalReward * senderShare) / PERCENT_PRECISION;
        receiverReward = (totalReward * receiverShare) / PERCENT_PRECISION;
    }
}
