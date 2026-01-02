// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "src/logic/TokenBucketLib.sol";

contract RyvynHandler is Ownable {
    using TokenBucketLib for TokenBucketLib.UserBuckets;

    address public ryUSD;

    mapping(address => TokenBucketLib.UserBuckets) public userBuckets;

    event MintHandled(address indexed user, uint256 amount);
    event TransferHandled(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 senderAge,
        uint256 receiverAge
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

    function onMint(address user, uint256 amount) external onlyRyUSD {
        if (user == address(0)) revert InvalidAddress();
        userBuckets[user].addBucket(amount);
        emit MintHandled(user, amount);
    }

    function handleTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRyUSD {
        if (from == address(0) || to == address(0)) revert InvalidAddress();
        uint256 senderAge = userBuckets[from].consumeBucket(uint96(amount));
        uint256 receiverAge = getWeightedAge(to);
        userBuckets[to].addBucket(amount);

        emit TransferHandled(from, to, amount, senderAge, receiverAge);
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

    function getWeightedAge(address user) internal view returns(uint256) {
        TokenBucketLib.UserBuckets storage self = userBuckets[user];
        uint256 totalBalance = 0;
        uint256 totalWeightedTime = 0;
        uint256 bucketsLength = self.buckets.length;
        uint32 pointer = self.pointer;

        for(uint256 i = pointer; i < bucketsLength && i < TokenBucketLib.MAX_BUCKETS_PER_CONSUME; i++) {
            TokenBucketLib.Bucket memory bucket = self.buckets[i]; 
            totalWeightedTime+= (bucket.amount * (block.timestamp - bucket.timestamp));
            totalBalance += bucket.amount;
        }

        if(totalBalance == 0) return 0;
        return totalWeightedTime / totalBalance;
    }
}
