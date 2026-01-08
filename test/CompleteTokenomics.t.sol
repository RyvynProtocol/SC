// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/mocks/token/MockUSDC.sol";
import "src/mocks/vaults/MockVault.sol";
import "src/core/RyvynHandler.sol";
import "src/core/ryUSD.sol";
import "src/treasury/TreasuryManager.sol";
import "src/core/ryBOND.sol";
import "src/treasury/YieldManager.sol";

/**
 * @title Complete Tokenomics Flow Test
 * @notice Tests the entire tokenomics system with dynamic rewards, bucket status, and yield management
 */
contract CompleteTokenomicsTest is Test {
    MockUSDC public mockUSDC;
    MockVault public vaultUSDY;
    MockVault public vaultOUSG;
    MockVault public vaultLending;
    MockVault public ryBondVault;

    RyvynHandler public handler;
    RyUSD public ryUSD;
    TreasuryManager public treasury;
    ryBOND public ryBond;
    YieldManager public yieldManager;

    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy contracts
        mockUSDC = new MockUSDC(owner);

        vaultUSDY = new MockVault(address(mockUSDC), "USDY Vault", owner);
        vaultOUSG = new MockVault(address(mockUSDC), "OUSG Vault", owner);
        vaultLending = new MockVault(address(mockUSDC), "Lending Vault", owner);
        ryBondVault = new MockVault(address(mockUSDC), "ryBOND Vault", owner);

        handler = new RyvynHandler(owner);
        ryUSD = new RyUSD(address(mockUSDC), owner);
        treasury = new TreasuryManager(
            address(mockUSDC),
            address(vaultUSDY),
            address(vaultOUSG),
            address(vaultLending),
            owner, // reserve wallet
            owner
        );
        ryBond = new ryBOND(address(handler), address(ryBondVault));
        yieldManager = new YieldManager(address(mockUSDC), owner);

        // Wire contracts together
        handler.setRyUSD(address(ryUSD));
        handler.setRyBOND(address(ryBond));
        handler.setYieldManager(address(yieldManager));

        ryUSD.setHandler(address(handler));
        ryUSD.setTreasury(address(treasury));

        treasury.setRyUSD(address(ryUSD));

        yieldManager.setRyvynHandler(address(handler));

        ryBond.setYieldRate(1e14);

        mockUSDC.mintAdmin(alice, 1_000_000 * 1e6);
        mockUSDC.mintAdmin(bob, 1_000_000 * 1e6);
    }

    function test_CompleteFlow_YieldGeneration() public {
        console.log("\n=== TEST 1: YIELD GENERATION ===");

        // Simulate RWA yield generation
        uint256 yieldAmount = 100_000 * 1e6; // 100k USDC
        yieldManager.simulateYieldGeneration(yieldAmount);

        (uint256 pool, , , , uint256 rewardRate) = yieldManager.getPoolStats();

        console.log("Yield Pool:", pool / 1e6, "USDC");
        console.log("Initial Reward Rate:", rewardRate, "bps");

        assertEq(pool, yieldAmount, "Yield pool should match");
    }

    function test_CompleteFlow_MovingAverageVolume() public {
        console.log("\n=== TEST 2: MOVING AVERAGE VOLUME ===");

        // Simulate 7 days of volume
        for (uint i = 0; i < 7; i++) {
            yieldManager.addDemoVolume(50_000 * 1e6); // 50k per day
            yieldManager.recordDailySnapshot();
        }

        uint256 movingAvg = yieldManager.getMovingAverageVolume();
        console.log("7-Day Moving Average:", movingAvg / 1e6, "USDC");

        assertGt(movingAvg, 0, "Moving average should be > 0");
    }

    function test_CompleteFlow_DynamicRewardRate() public {
        console.log("\n=== TEST 3: DYNAMIC REWARD RATE ===");

        // Setup: Add yield and volume
        yieldManager.simulateYieldGeneration(100_000 * 1e6);
        yieldManager.addDemoVolume(50_000 * 1e6);
        yieldManager.recordDailySnapshot();

        uint256 rewardRate = yieldManager.calculateDynamicRewardRate();
        console.log("Dynamic Reward Rate:", rewardRate, "bps");
        console.log("Percentage:", (rewardRate * 100) / 10000, "%");

        assertGt(rewardRate, 0, "Reward rate should be > 0");
    }

    function test_CompleteFlow_MintWithRewards() public {
        console.log("\n=== TEST 4: MINT WITH REWARDS ===");

        // Setup yield
        yieldManager.simulateYieldGeneration(100_000 * 1e6);
        yieldManager.addDemoVolume(50_000 * 1e6);
        yieldManager.recordDailySnapshot();

        // Alice mints ryUSD
        vm.startPrank(alice);
        uint256 mintAmount = 10_000 * 1e6;
        mockUSDC.approve(address(ryUSD), mintAmount);
        ryUSD.deposit(mintAmount);
        vm.stopPrank();

        // Check ryBOND rewards
        (uint256 pending, uint256 credited, ) = ryBond.getUserStats(alice);
        console.log("Alice ryBOND Pending:", pending);
        console.log("Alice ryBOND Credited:", credited);

        assertGt(credited, 0, "Should receive ryBOND rewards");
    }

    function test_CompleteFlow_BucketStatus() public {
        console.log("\n=== TEST 5: BUCKET STATUS ===");

        // Alice mints
        vm.startPrank(alice);
        mockUSDC.approve(address(ryUSD), 10_000 * 1e6);
        ryUSD.deposit(10_000 * 1e6);
        vm.stopPrank();

        // Check initial status
        (uint256 uninvested, uint256 invested) = handler.getBucketStatusCounts(
            alice
        );
        console.log("Uninvested buckets:", uninvested);
        console.log("Invested buckets:", invested);

        assertEq(uninvested, 1, "Should have 1 uninvested bucket");
        assertEq(invested, 0, "Should have 0 invested buckets");

        // Fast-forward time (simulate 30+ days)
        vm.warp(block.timestamp + 31 days);

        // Force update bucket status
        handler.forceUpdateBucketStatuses(alice);

        // Check after 30 days
        (uninvested, invested) = handler.getBucketStatusCounts(alice);
        console.log("After 30 days:");
        console.log("  Uninvested buckets:", uninvested);
        console.log("  Invested buckets:", invested);

        assertEq(uninvested, 0, "Should have 0 uninvested buckets");
        assertEq(invested, 1, "Should have 1 invested bucket");
    }

    function test_CompleteFlow_Dynamic7030Split() public {
        console.log("\n=== TEST 6: DYNAMIC 70/30 SPLIT ===");

        // Setup yield
        yieldManager.simulateYieldGeneration(100_000 * 1e6);
        yieldManager.addDemoVolume(50_000 * 1e6);
        yieldManager.recordDailySnapshot();

        // Alice mints and waits
        vm.startPrank(alice);
        mockUSDC.approve(address(ryUSD), 10_000 * 1e6);
        ryUSD.deposit(10_000 * 1e6);
        vm.stopPrank();

        console.log("\n--- SCENARIO 1: NEW HOLDER (0 days) ---");

        // Preview transfer rewards (new holder)
        (uint256 sR1, uint256 rR1, uint256 sS1, uint256 rS1) = handler
            .previewTransferRewards(alice, 1000 * 1e6);

        console.log("Sender Share:", sS1, "%");
        console.log("Receiver Share:", rS1, "%");
        console.log("Sender Reward:", sR1);
        console.log("Receiver Reward:", rR1);

        assertEq(sS1, 70, "New holder should have base 70% share");

        console.log("\n--- SCENARIO 2: MEDIUM HOLDER (45 days) ---");

        // Fast-forward 45 days
        vm.warp(block.timestamp + 45 days);

        (uint256 sR2, uint256 rR2, uint256 sS2, uint256 rS2) = handler
            .previewTransferRewards(alice, 1000 * 1e6);

        console.log("Sender Share:", sS2, "%");
        console.log("Receiver Share:", rS2, "%");
        console.log("Sender Reward:", sR2);
        console.log("Receiver Reward:", rR2);

        assertGt(sS2, 70, "Medium holder should have > 70% share");

        console.log("\n--- SCENARIO 3: LONG-TERM HOLDER (90+ days) ---");

        // Fast-forward to 91 days total
        vm.warp(block.timestamp + 46 days);

        (uint256 sR3, uint256 rR3, uint256 sS3, uint256 rS3) = handler
            .previewTransferRewards(alice, 1000 * 1e6);

        console.log("Sender Share:", sS3, "%");
        console.log("Receiver Share:", rS3, "%");
        console.log("Sender Reward:", sR3);
        console.log("Receiver Reward:", rR3);

        assertEq(sS3, 90, "Long-term holder should have max 90% share");
    }

    function test_CompleteFlow_TransferWithRewards() public {
        console.log("\n=== TEST 7: TRANSFER WITH REWARDS ===");

        // Setup yield and volume
        yieldManager.simulateYieldGeneration(100_000 * 1e6);
        yieldManager.addDemoVolume(50_000 * 1e6);
        yieldManager.recordDailySnapshot();

        // Alice mints
        vm.startPrank(alice);
        mockUSDC.approve(address(ryUSD), 10_000 * 1e6);
        ryUSD.deposit(10_000 * 1e6);
        vm.stopPrank();

        // Wait 60 days
        vm.warp(block.timestamp + 60 days);

        // Alice transfers to Bob
        vm.prank(alice);
        ryUSD.transfer(bob, 5_000 * 1e6);

        // Check rewards
        (uint256 alicePending, uint256 aliceCredited, ) = ryBond.getUserStats(
            alice
        );
        (uint256 bobPending, uint256 bobCredited, ) = ryBond.getUserStats(bob);

        console.log(
            "Alice ryBOND - Pending:",
            alicePending,
            "| Credited:",
            aliceCredited
        );
        console.log(
            "Bob ryBOND - Pending:",
            bobPending,
            "| Credited:",
            bobCredited
        );

        assertGt(aliceCredited, bobCredited, "Sender should get more rewards");
    }

    function test_CompleteFlow_EndToEnd() public {
        console.log("\n=== TEST 8: COMPLETE END-TO-END FLOW ===");

        console.log("\n--- STEP 1: Simulate RWA Yield ---");
        yieldManager.simulateYieldGeneration(500_000 * 1e6);
        (, , , , uint256 rate1) = yieldManager.getPoolStats();
        console.log("Yield Pool: 500,000 USDC");
        console.log("Initial Rate:", rate1, "bps");

        console.log("\n--- STEP 2: Build Volume History ---");
        for (uint i = 0; i < 7; i++) {
            yieldManager.addDemoVolume(100_000 * 1e6);
            yieldManager.recordDailySnapshot();
        }
        uint256 movingAvg = yieldManager.getMovingAverageVolume();
        console.log("7-Day Avg Volume:", movingAvg / 1e6, "USDC/day");

        console.log("\n--- STEP 3: Alice Mints ryUSD ---");
        vm.startPrank(alice);
        mockUSDC.approve(address(ryUSD), 50_000 * 1e6);
        ryUSD.deposit(50_000 * 1e6);
        vm.stopPrank();

        console.log("Alice ryUSD Balance:", ryUSD.balanceOf(alice) / 1e6);
        (uint256 aliceBuckets1, , ) = handler.getUserBucketInfo(alice);
        console.log("Alice Buckets:", aliceBuckets1);

        console.log("\n--- STEP 4: Wait 60 Days ---");
        vm.warp(block.timestamp + 60 days);
        handler.forceUpdateBucketStatuses(alice);

        (uint256 uninv, uint256 inv) = handler.getBucketStatusCounts(alice);
        console.log("Bucket Status - Uninvested:", uninv, "| Invested:", inv);

        console.log("\n--- STEP 5: Alice Transfers to Bob ---");
        vm.prank(alice);
        ryUSD.transfer(bob, 20_000 * 1e6);

        console.log("Alice ryUSD:", ryUSD.balanceOf(alice) / 1e6);
        console.log("Bob ryUSD:", ryUSD.balanceOf(bob) / 1e6);

        console.log("\n--- STEP 6: Check Final Rewards ---");
        (uint256 aliceP, uint256 aliceC, ) = ryBond.getUserStats(alice);
        (uint256 bobP, uint256 bobC, ) = ryBond.getUserStats(bob);

        console.log("Alice ryBOND - Pending:", aliceP, "| Credited:", aliceC);
        console.log("Bob ryBOND - Pending:", bobP, "| Credited:", bobC);

        console.log("\n--- STEP 7: Check Yield Pool ---");
        (uint256 pool, , uint256 allocated, , ) = yieldManager.getPoolStats();
        console.log("Remaining Pool:", pool / 1e6, "USDC");
        console.log("Total Allocated:", allocated / 1e6, "USDC");

        // Assertions
        assertEq(
            ryUSD.balanceOf(alice),
            30_000 * 1e6,
            "Alice should have 30k ryUSD"
        );
        assertEq(
            ryUSD.balanceOf(bob),
            20_000 * 1e6,
            "Bob should have 20k ryUSD"
        );
        assertGt(aliceC, bobC, "Alice should have more rewards");
        assertGt(allocated, 0, "Should have allocated rewards");
        assertLt(pool, 500_000 * 1e6, "Pool should be depleted");

        console.log("\n === COMPLETE FLOW SUCCESSFUL ===");
    }
}
