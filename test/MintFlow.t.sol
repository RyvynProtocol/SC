// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/mocks/token/MockUSDC.sol";
import "src/core/ryUSD.sol";
import "src/core/RyvynHandler.sol";
import "src/treasury/TreasuryManager.sol";
import "src/mocks/vaults/MockVault.sol";

contract MintFlowTest is Test {
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

        usdc.mintAdmin(alice, 10000e6); // 10,000 USDC
    }

    // ==================== BASIC TESTS ====================
    function test_SetupCorrect() public view {
        assertEq(address(ryUSD.underlyingToken()), address(usdc));
        assertEq(ryUSD.ryvynHandler(), address(handler));
        assertEq(ryUSD.treasuryManager(), address(treasury));
        assertEq(handler.ryUSD(), address(ryUSD));
        assertEq(treasury.ryUSD(), address(ryUSD));
    }

    function test_AliceHasUSDC() public view {
        assertEq(usdc.balanceOf(alice), 10000e6);
    }

    // ==================== MINT FLOW TESTS ====================
    function test_MintRyUSD() public {
        vm.startPrank(alice);

        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);

        vm.stopPrank();

        assertEq(
            ryUSD.balanceOf(alice),
            MINT_AMOUNT,
            "Alice should have ryUSD"
        );
        assertEq(usdc.balanceOf(alice), 9000e6, "Alice USDC should decrease");
    }

    function test_MintCreatesHistory() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        assertEq(ryUSD.getMintHistoryLength(), 1, "Should have 1 mint record");
        assertEq(ryUSD.getUserMintCount(alice), 1, "Alice should have 1 mint");

        RyUSD.MintRecord memory record = ryUSD.getMintRecord(0);
        assertEq(record.user, alice, "User should be Alice");
        assertEq(record.amount, MINT_AMOUNT, "Amount should match");
        assertEq(record.timestamp, block.timestamp, "Timestamp should match");
    }

    function test_MintCreatesBucket() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        (
            uint256 activeBuckets,
            uint256 totalBalance,
            uint256 oldestAge
        ) = handler.getUserBucketInfo(alice);

        assertEq(activeBuckets, 1, "Should have 1 active bucket");
        assertEq(totalBalance, MINT_AMOUNT, "Bucket balance should match");
        assertEq(oldestAge, 0, "Bucket should be brand new");
    }

    function test_TreasuryReceivesUSDC() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();
        (
            uint256 totalDeposited,
            uint256 totalAllocated,
            uint256 hotWallet
        ) = treasury.getAllocationInfo();
        assertEq(totalDeposited, MINT_AMOUNT, "Treasury should receive USDC");

        assertEq(hotWallet, 50e6, "Hot wallet should keep 5% threshold");
        assertEq(totalAllocated, 950e6, "Should allocate 95% to vaults");
    }

    function test_MultipleMints() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT * 3);

        ryUSD.deposit(MINT_AMOUNT);
        vm.warp(block.timestamp + 1 days);
        ryUSD.deposit(MINT_AMOUNT);
        vm.warp(block.timestamp + 2 days);
        ryUSD.deposit(MINT_AMOUNT);

        vm.stopPrank();

        assertEq(ryUSD.balanceOf(alice), MINT_AMOUNT * 3);
        assertEq(
            ryUSD.getUserMintCount(alice),
            3,
            "Should have 3 mint records"
        );

        (
            uint256 activeBuckets,
            uint256 totalBalance,
            uint256 oldestAge
        ) = handler.getUserBucketInfo(alice);

        assertEq(activeBuckets, 3, "Should have 3 buckets");
        assertEq(totalBalance, MINT_AMOUNT * 3, "Total balance should match");
        assertEq(oldestAge, 3 days, "Oldest bucket should be 3 days old");
    }

    // ==================== TREASURY ALLOCATION TESTS ====================
    function test_TreasuryAllocatesAboveThreshold() public {
        uint256 largeAmount = 100_000e6; // 100,000 USDC

        usdc.mintAdmin(alice, largeAmount);

        vm.startPrank(alice);
        usdc.approve(address(ryUSD), largeAmount);
        ryUSD.deposit(largeAmount);
        vm.stopPrank();

        (, uint256 totalAllocated, uint256 hotWallet) = treasury
            .getAllocationInfo();

        assertTrue(totalAllocated > 0, "Should have allocated to vaults");
        assertTrue(
            hotWallet < largeAmount,
            "Hot wallet should be less than total"
        );

        assertTrue(vaultUSDY.totalDeposits() > 0, "USDY vault should receive");
        assertTrue(vaultOUSG.totalDeposits() > 0, "OUSG vault should receive");
        assertTrue(
            vaultLending.totalDeposits() > 0,
            "Lending vault should receive"
        );
    }

    // ==================== WITHDRAW TESTS ====================
    function test_WithdrawRyUSD() public {
        ryUSD.setTreasury(address(0));

        uint256 depositAmount = 100e6;

        vm.startPrank(alice);
        usdc.approve(address(ryUSD), depositAmount);
        ryUSD.deposit(depositAmount);

        uint256 withdrawAmount = depositAmount / 2;
        ryUSD.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(
            ryUSD.balanceOf(alice),
            depositAmount - withdrawAmount,
            "ryUSD balance incorrect"
        );
        assertEq(
            usdc.balanceOf(alice),
            10000e6 - depositAmount + withdrawAmount,
            "USDC balance incorrect"
        );

        ryUSD.setTreasury(address(treasury));
    }

    function test_WithdrawLargeAmountNeedsRefill() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);

        vm.expectRevert(TreasuryManager.InsufficientLiquidity.selector);
        ryUSD.withdraw(500e6);
        vm.stopPrank();
    }
    function test_CannotWithdrawMoreThanBalance() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);

        vm.expectRevert("Insufficient balance");
        ryUSD.withdraw(MINT_AMOUNT * 2);
        vm.stopPrank();
    }

    // ==================== STATS TESTS ====================
    function test_GetStats() public {
        vm.startPrank(alice);
        usdc.approve(address(ryUSD), MINT_AMOUNT * 2);
        ryUSD.deposit(MINT_AMOUNT);
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();

        (
            uint256 totalMinted,
            uint256 totalBurned,
            uint256 totalSupply,
            uint256 mintCount
        ) = ryUSD.getStats();

        assertEq(totalMinted, MINT_AMOUNT * 2, "Total minted should match");
        assertEq(totalBurned, 0, "No burns yet");
        assertEq(totalSupply, MINT_AMOUNT * 2, "Total supply should match");
        assertEq(mintCount, 2, "Should have 2 mints");
    }

    // ==================== EDGE CASES ====================
    function test_CannotMintZero() public {
        vm.startPrank(alice);
        vm.expectRevert("Zero amount");
        ryUSD.deposit(0);
        vm.stopPrank();
    }

    function test_CannotMintWithoutApproval() public {
        vm.startPrank(alice);
        vm.expectRevert();
        ryUSD.deposit(MINT_AMOUNT);
        vm.stopPrank();
    }
}
