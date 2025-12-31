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
        uint256 senderAge
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

    // TODO: Transfer logic
    // function handleTransfer(
    //     address from,
    //     address to,
    //     uint256 amount
    // ) external onlyRyUSD {
    //     // if (from == address(0) || to == address(0)) revert InvalidAddress();
    //     // TODO: Calculate reward split based on holding period
    //     // uint256 senderAge = userBuckets[from].consumeBuckets(amount);

    //     // userBuckets[to].addBucket(amount);

    //     // emit TransferHandled(from, to, amount, senderAge);
    // }

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
}
