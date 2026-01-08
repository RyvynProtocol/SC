// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TokenBucketLib {
    enum BucketStatus {
        Uninvested,
        Invested
    }

    struct Bucket {
        uint96 amount;
        uint32 timestamp;
        BucketStatus status;
    }

    struct UserBuckets {
        Bucket[] buckets;
        uint32 pointer;
    }

    // --- EVENTS ---
    event BucketAdded(address indexed user, uint256 amount, uint256 timestamp);
    event BucketConsumed(
        address indexed user,
        uint256 amount,
        uint256 weightedAge
    );

    // --- ERROS ---
    error InvalidAmount();
    error InsufficientBalance();
    error AmountTooLarge();

    uint256 internal constant MAX_BUCKETS_PER_CONSUME = 50;
    uint256 internal constant HOLDING_THRESHOLD = 30 days;

    // -- FUNCTIONS ---
    function addBucket(UserBuckets storage self, uint256 amount) internal {
        if (amount <= 0) revert InvalidAmount();
        if (amount > type(uint96).max) revert AmountTooLarge();

        self.buckets.push(
            Bucket({
                amount: uint96(amount),
                timestamp: uint32(block.timestamp),
                status: BucketStatus.Uninvested
            })
        );

        emit BucketAdded(msg.sender, amount, block.timestamp);
    }

    function consumeBucket(
        UserBuckets storage self,
        uint96 amount
    ) internal returns (uint256 weightedAge) {
        if (amount <= 0) revert InvalidAmount();

        uint256 originalAmount = amount;
        uint256 totalWeightedTime = 0;

        uint32 pointer = self.pointer;
        uint256 bucketsLength = self.buckets.length;

        for (
            uint256 i = pointer;
            i < bucketsLength && i < MAX_BUCKETS_PER_CONSUME;
            i++
        ) {
            Bucket storage bucket = self.buckets[i];
            uint256 timeDiff = block.timestamp - bucket.timestamp;

            if (amount <= bucket.amount) {
                totalWeightedTime += timeDiff * amount;
                bucket.amount -= amount;
                amount = 0;

                if (bucket.amount == 0) {
                    pointer++;
                }
                break;
            } else {
                totalWeightedTime += timeDiff * bucket.amount;
                amount -= bucket.amount;
                bucket.amount = 0;
                pointer++;
            }
        }
        if (amount != 0) revert InsufficientBalance();
        self.pointer = pointer;
        weightedAge = totalWeightedTime / originalAmount;
        emit BucketConsumed(msg.sender, originalAmount, weightedAge);
        return weightedAge;
    }

    // --- VIEW FUNCTIONS ---
    function getTotalBalance(
        UserBuckets storage self
    ) internal view returns (uint256 total) {
        for (uint256 i = self.pointer; i < self.buckets.length; i++) {
            total += self.buckets[i].amount;
        }
    }

    function getBucketInfo(
        UserBuckets storage self
    )
        internal
        view
        returns (
            uint256 activeBuckets,
            uint256 totalBalance,
            uint256 oldestBucketAge
        )
    {
        activeBuckets = self.buckets.length - self.pointer;
        totalBalance = getTotalBalance(self);

        if (self.pointer < self.buckets.length) {
            oldestBucketAge =
                block.timestamp -
                self.buckets[self.pointer].timestamp;
        }
    }

    function updateBucketStatus(
        UserBuckets storage self,
        uint256 bucketIndex
    ) internal {
        if (bucketIndex >= self.buckets.length) return;

        Bucket storage bucket = self.buckets[bucketIndex];
        uint256 age = block.timestamp - bucket.timestamp;

        if (
            age >= HOLDING_THRESHOLD && bucket.status == BucketStatus.Uninvested
        ) {
            bucket.status = BucketStatus.Invested;
        }
    }

    function updateAllBucketStatuses(UserBuckets storage self) internal {
        for (uint256 i = self.pointer; i < self.buckets.length; i++) {
            updateBucketStatus(self, i);
        }
    }

    function getBucketStatusCounts(
        UserBuckets storage self
    ) internal view returns (uint256 uninvested, uint256 invested) {
        for (uint256 i = self.pointer; i < self.buckets.length; i++) {
            if (self.buckets[i].status == BucketStatus.Uninvested) {
                uninvested++;
            } else {
                invested++;
            }
        }
    }
}
