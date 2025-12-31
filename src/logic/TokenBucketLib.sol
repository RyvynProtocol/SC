// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TokenBucketLib {
    // --- STRUCTS ---
    struct Bucket {
        uint96 amount;
        uint32 timestamp;
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

    // -- FUNCTIONS ---
    function addBucket(UserBuckets storage self, uint256 amount) internal {
        if (amount <= 0) revert InvalidAmount();
        require(amount <= type(uint96).max, "TokenBucket: amount too large");

        self.buckets.push(
            Bucket({amount: uint96(amount), timestamp: uint32(block.timestamp)})
        );

        emit BucketAdded(msg.sender, amount, block.timestamp);
    }

    // function consumeBucket() {
    // TODO: consume from oldest buckets (FIFO)
    // }

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
}
