// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/mocks/token/MockUSDC.sol";
import "src/core/ryUSD.sol";
import "src/core/RyvynHandler.sol";
import "src/treasury/TreasuryManager.sol";
import "src/mocks/vaults/MockVault.sol";

contract TransferFlowTest is Test {
    MockUSDC public usdc;
    RyUSD public ryUSD;
    RyvynHandler public handler;
    TreasuryManager public treasury;
    MockVault public vaultUSDY;
    MockVault public vaultOUSG;
    MockVault public vaultLending;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public reserveWallet = address(0x999);

    uint256 constant MINT_AMOUNT = 1000e6; // 1,000 USDC

    function setUp() public {
        usdc = new MockUSDC(owner);
        ryUSD = new RyUSD(address(usdc), owner);
        handler = new RyvynHandler(owner);
        handler.setRyUSD(address(ryUSD));

        vaultUSDY = new MockVault(address(usdc), "USDY Vault", owner);
        vaultOUSG = new MockVault(address(usdc), "OUSG Vault", owner);
        vaultLending = new MockVault(address(usdc), "Lending Vault", owner);

        treasury = new TreasuryManager(
            address(usdc),
            address(vaultUSDY),
            address(vaultOUSG),
            address(vaultLending),
            reserveWallet,
            owner
        );

        ryUSD.setHandler(address(handler));
        ryUSD.setTreasury(address(treasury));
        treasury.setRyUSD(address(ryUSD));

        // Give Alice initial USDC
        usdc.mintAdmin(alice, 10000e6);
    }

    // ==================== TRANSFER TESTS ====================

    function test_TransferSimple() public {
        // Alice mints 1000 ryUSD
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        // Time travel 30 days
        vm.warp(block.timestamp + 30 days);

        // Alice transfers to Bob
        vm.prank(alice);
        ryUSD.transfer(bob, MINT_AMOUNT);

        // Verify balances
        assertEq(ryUSD.balanceOf(alice), 0, "Alice should have 0");
        assertEq(ryUSD.balanceOf(bob), MINT_AMOUNT, "Bob should have 1000");

        // Verify Bob's bucket
        (
            uint256 activeBuckets,
            uint256 totalBalance,
            uint256 oldestAge
        ) = handler.getUserBucketInfo(bob);
        assertEq(activeBuckets, 1, "Bob should have 1 bucket");
        assertEq(totalBalance, MINT_AMOUNT, "Balance should match");
        assertEq(oldestAge, 0, "Bob's bucket should be fresh");
    }

    function test_TransferPartialAmount() public {
        // Alice mints 1000 ryUSD
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        // Alice transfers 600 to Bob (partial)
        uint256 transferAmount = 600e6;
        vm.prank(alice);
        ryUSD.transfer(bob, transferAmount);

        // Verify balances
        assertEq(ryUSD.balanceOf(alice), 400e6, "Alice should have 400");
        assertEq(ryUSD.balanceOf(bob), transferAmount, "Bob should have 600");

        // Verify Alice still has bucket with remaining
        (uint256 aliceBuckets, uint256 aliceBalance, ) = handler
            .getUserBucketInfo(alice);
        assertEq(aliceBuckets, 1, "Alice should still have 1 bucket");
        assertEq(aliceBalance, 400e6, "Alice bucket balance should be 400");
    }

    function test_TransferFromMultipleBuckets() public {
        // Alice mints 600 at day 0
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(600e6);
        vm.stopPrank();

        
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(alice);
        ryUSD.deposit(400e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 20 days);

        (uint256 aliceBucketsBeforeTransfer, , ) = handler.getUserBucketInfo(
            alice
        );
        assertEq(
            aliceBucketsBeforeTransfer,
            2,
            "Alice should have 2 buckets before transfer"
        );

        vm.prank(alice);
        ryUSD.transfer(bob, 700e6);

        (, uint256 aliceBalanceAfter, ) = handler.getUserBucketInfo(alice);
        assertEq(aliceBalanceAfter, 300e6, "Alice should have 300 remaining");

        assertEq(ryUSD.balanceOf(bob), 700e6, "Bob should have 700");
    }

    function test_TransferToReceiverWithExistingHoldings() public {
        // Bob mints 500 
        usdc.mintAdmin(bob, 1000e6);
        vm.startPrank(bob);
        usdc.approve(address(ryUSD), 500e6);
        ryUSD.deposit(500e6);
        vm.stopPrank();

        // Bob has held 20 days
        vm.warp(block.timestamp + 20 days);

        // Alice mints 1000
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        // Alice has held 10 days, Bob 30 days
        vm.warp(block.timestamp + 10 days);

        // Verify Bob's weighted age before transfer (should be ~30 days)
        (, , uint256 bobOldestAge) = handler.getUserBucketInfo(bob);
        assertEq(bobOldestAge, 30 days, "Bob oldest bucket should be 30 days");

        // Alice transfers 1000 to Bob
        vm.prank(alice);
        ryUSD.transfer(bob, MINT_AMOUNT);

        // Verify Bob now has 2 buckets
        (uint256 bobBuckets, uint256 bobBalance, ) = handler.getUserBucketInfo(
            bob
        );
        assertEq(bobBuckets, 2, "Bob should have 2 buckets");
        assertEq(bobBalance, 1500e6, "Bob should have 1500 total");
        assertEq(
            ryUSD.balanceOf(bob),
            1500e6,
            "Bob ryUSD balance should match"
        );
    }

    function test_TransferSequential() public {
        // Chain: Alice -> Bob -> Charlie

        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        // Alice -> Bob
        vm.prank(alice);
        ryUSD.transfer(bob, MINT_AMOUNT);

        // Verify Bob received
        assertEq(ryUSD.balanceOf(bob), MINT_AMOUNT, "Bob should have 1000");

        // Bob holds for 15 days
        vm.warp(block.timestamp + 15 days);

        // Bob -> Charlie
        vm.prank(bob);
        ryUSD.transfer(charlie, MINT_AMOUNT);

        // Verify final state
        assertEq(ryUSD.balanceOf(alice), 0, "Alice should have 0");
        assertEq(ryUSD.balanceOf(bob), 0, "Bob should have 0");
        assertEq(
            ryUSD.balanceOf(charlie),
            MINT_AMOUNT,
            "Charlie should have 1000"
        );

        // Verify Charlie's bucket is fresh
        (uint256 charlieBuckets, , uint256 charlieAge) = handler
            .getUserBucketInfo(charlie);
        assertEq(charlieBuckets, 1, "Charlie should have 1 bucket");
        assertEq(charlieAge, 0, "Charlie bucket should be fresh");
    }

    function test_TransferToNewAddress() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        (uint256 bobBucketsInit, , ) = handler.getUserBucketInfo(bob);
        assertEq(bobBucketsInit, 0, "Bob should have 0 buckets initially");

        vm.warp(block.timestamp + 10 days);
        vm.prank(alice);
        ryUSD.transfer(bob, 500e6);

        (uint256 bobBucketsAfter, uint256 bobBalance, uint256 bobAge) = handler
            .getUserBucketInfo(bob);
        assertEq(bobBucketsAfter, 1, "Bob should have 1 bucket");
        assertEq(bobBalance, 500e6, "Bob balance should be 500");
        assertEq(bobAge, 0, "Bob bucket should be fresh");
    }

    function test_TransferEmitsEvent() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, MINT_AMOUNT);

        // Transfer
        vm.prank(alice);
        ryUSD.transfer(bob, MINT_AMOUNT);
    }

    // Define Transfer event for expectEmit
    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_CannotTransferMoreThanBalance() public {
        // Alice mints
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        // Try to transfer more than balance - should revert
        vm.prank(alice);
        vm.expectRevert();
        ryUSD.transfer(bob, MINT_AMOUNT * 2);
    }
}
