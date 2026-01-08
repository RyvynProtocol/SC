// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/mocks/token/MockUSDC.sol";
import "src/core/RyvynHandler.sol";
import "src/core/ryUSD.sol";
import "src/treasury/TreasuryManager.sol";
import "src/treasury/YieldManager.sol";
import "src/core/ryBOND.sol";

contract CompleteOnChainTest is Script {
    MockUSDC mockUSDC = MockUSDC(0xcb456899a90bc65ba19B899316623C481e3ebDCB);
    RyvynHandler handler =
        RyvynHandler(0x19600CB6458E903f2Ad335592046Bd786c214677);
    RyUSD ryUSD = RyUSD(0xF5DC8dE141b22D054621C9C413A40b95AC0d226f);
    TreasuryManager treasury =
        TreasuryManager(0x57BBcFA27123e352848a05645e3287C1058f09c0);
    YieldManager yieldManager =
        YieldManager(0x665566b12f2e9E93d55F0F2FFDeaE46553BD037D);
    ryBOND ryBond = ryBOND(0x210d2e01d0e3Ec57dD0EcCcCe8eA6f893FF12c0C);

    address public deployer;
    address public alice = 0x1111111111111111111111111111111111111111;
    address public bob = 0x2222222222222222222222222222222222222222;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Alice (Receiver):", alice);
        console.log("Bob (Receiver):", bob);

        vm.startBroadcast(deployerPrivateKey);

        _phase1_InitialSetup();
        _phase2_AliceFirstDeposit();
        _phase3_BuildYieldHistory();
        _phase4_AliceSecondDeposit();
        _phase5_BucketStatusCheck();
        _phase6_DynamicRewardDemo();
        _phase7_TransferToBob();
        _phase8_BobDeposit();
        _phase9_CrossTransfers();
        _phase10_RyBondClaiming();
        _phase11_TreasuryOperations();
        _phase12_FinalSummary();

        vm.stopBroadcast();

        console.log("\nTEST COMPLETED SUCCESSFULLY\n");
    }

    function _phase1_InitialSetup() internal {
        console.log("\nPHASE 1: INITIAL SETUP & YIELD SIMULATION\n");

        console.log("\nInjecting initial yield pool (500,000 USDC)");
        yieldManager.simulateYieldGeneration(500_000 * 1e6);

        console.log(" Building initial volume history (7 days)");
        for (uint i = 0; i < 7; i++) {
            yieldManager.addDemoVolume(80_000 * 1e6);
            yieldManager.recordDailySnapshot();
        }

        (uint256 pool, , , uint256 movingAvg, uint256 rewardRate) = yieldManager
            .getPoolStats();
        console.log("\n Yield Pool:", pool / 1e6, "USDC");
        console.log(" 7-Day Avg Volume:", movingAvg / 1e6, "USDC/day");
        console.log(" Initial Reward Rate:", rewardRate, "bps");
        console.log("   Percentage:", (rewardRate * 100) / 10000, "%");
    }

    function _phase2_AliceFirstDeposit() internal {
        console.log(" PHASE 2: ALICE'S FIRST DEPOSIT              ");

        console.log("\n Minting USDC to Alice");
        mockUSDC.mintAdmin(alice, 50_000 * 1e6);
        console.log("  Alice USDC:", mockUSDC.balanceOf(alice) / 1e6);

        console.log("\n Alice deposits 20,000 USDC");
        mockUSDC.approve(address(ryUSD), 20_000 * 1e6);
        ryUSD.deposit(20_000 * 1e6);

        console.log("  Alice ryUSD:", ryUSD.balanceOf(deployer) / 1e6);

        (uint256 buckets, uint256 balance, uint256 age) = handler
            .getUserBucketInfo(deployer);
        console.log("  Active Buckets:", buckets);
        console.log("  Total Balance:", balance / 1e6);

        (uint256 pending, uint256 credited, ) = ryBond.getUserStats(deployer);
        console.log("  ryBOND Credited:", credited, "(from mint reward)");
    }

    function _phase3_BuildYieldHistory() internal {
        console.log(" PHASE 3: BUILD YIELD & VOLUME HISTORY       ");

        console.log("\n Adding more RWA yield (200,000 USDC)");
        yieldManager.simulateYieldGeneration(200_000 * 1e6);

        console.log(" Recording additional volume days");
        for (uint i = 0; i < 3; i++) {
            yieldManager.addDemoVolume(100_000 * 1e6);
            yieldManager.recordDailySnapshot();
        }

        (, , , uint256 newAvg, uint256 newRate) = yieldManager.getPoolStats();
        console.log("\n New 7-Day Avg:", newAvg / 1e6, "USDC/day");
        console.log(" Updated Reward Rate:", newRate, "bps");
    }

    function _phase4_AliceSecondDeposit() internal {
        console.log(" PHASE 4: ALICE'S SECOND DEPOSIT (NEW BUCKET)");

        console.log("\n Alice deposits another 15,000 USDC");
        mockUSDC.approve(address(ryUSD), 15_000 * 1e6);
        ryUSD.deposit(15_000 * 1e6);

        (uint256 buckets, uint256 balance, ) = handler.getUserBucketInfo(
            deployer
        );
        console.log("  Active Buckets:", buckets);
        console.log("  Total Balance:", balance / 1e6);

        console.log("\n Checking individual buckets:");
        (
            uint256[] memory amounts,
            uint256[] memory timestamps,
            uint256[] memory ages,

        ) = handler.getUserBucketsDetailed(deployer);

        for (uint i = 0; i < amounts.length; i++) {
            console.log("  Bucket", i + 1, amounts[i] / 1e6, "USDC");
            console.log("    Age:", ages[i], "seconds");
        }
    }

    function _phase5_BucketStatusCheck() internal {
        console.log(" PHASE 5: BUCKET STATUS TRANSITIONS          ");

        (uint256 uninvested, uint256 invested) = handler.getBucketStatusCounts(
            deployer
        );
        console.log("\n Current bucket status:");
        console.log("  Uninvested:", uninvested);
        console.log("  Invested:", invested);

        console.log("\n Force updating bucket statuses");
        handler.forceUpdateBucketStatuses(deployer);

        (uninvested, invested) = handler.getBucketStatusCounts(deployer);
        console.log(
            "  After update - Uninvested:",
            uninvested,
            "| Invested:",
            invested
        );
    }

    function _phase6_DynamicRewardDemo() internal {
        console.log(" PHASE 6: DYNAMIC 70/30 REWARD SPLIT         ");

        console.log("\n Previewing transfer rewards (5,000 ryUSD):");
        (uint256 sR, uint256 rR, uint256 sS, uint256 rS) = handler
            .previewTransferRewards(deployer, 5_000 * 1e6);

        console.log("  Sender Share:", sS, "%");
        console.log("  Receiver Share:", rS, "%");
        console.log("  Sender Reward:", sR, "| Receiver Reward:", rR);
        console.log("  Total Reward:", (sR + rR));
    }

    function _phase7_TransferToBob() internal {
        console.log(" PHASE 7: TRANSFER TO BOB (WITH REWARDS)     ");

        uint256 aliceBefore = ryUSD.balanceOf(deployer);

        console.log("\n Transferring 8,000 ryUSD to Bob");
        ryUSD.transfer(bob, 8_000 * 1e6);

        console.log("  Alice ryUSD before:", aliceBefore / 1e6);
        console.log("  Alice ryUSD after:", ryUSD.balanceOf(deployer) / 1e6);
        console.log("  Bob ryUSD:", ryUSD.balanceOf(bob) / 1e6);

        (uint256 aliceP, uint256 aliceC, ) = ryBond.getUserStats(deployer);
        (uint256 bobP, uint256 bobC, ) = ryBond.getUserStats(bob);

        console.log(
            "\n  Alice ryBOND - Pending:",
            aliceP,
            "| Credited:",
            aliceC
        );
        console.log("  Bob ryBOND - Pending:", bobP, "| Credited:", bobC);

        (, uint256 aliceBuckets, ) = handler.getUserBucketInfo(deployer);
        (, uint256 bobBuckets, ) = handler.getUserBucketInfo(bob);
        console.log(
            "  Alice Buckets:",
            aliceBuckets,
            "| Bob Buckets:",
            bobBuckets
        );
    }

    function _phase8_BobDeposit() internal {
        console.log(" PHASE 8: BOB'S FRESH DEPOSIT                ");

        console.log("\n Minting USDC to Bob");
        mockUSDC.mintAdmin(bob, 30_000 * 1e6);

        console.log(" Bob deposits 12,000 USDC");
        mockUSDC.approve(address(ryUSD), 12_000 * 1e6);
        ryUSD.deposit(12_000 * 1e6);

        console.log("  Deployer ryUSD:", ryUSD.balanceOf(deployer) / 1e6);
        console.log("  Bob ryUSD:", ryUSD.balanceOf(bob) / 1e6);

        (uint256 buckets, , ) = handler.getUserBucketInfo(bob);
        console.log(
            "  Bob's Buckets:",
            buckets,
            "(1 from transfer + 1 from deposit)"
        );
    }

    function _phase9_CrossTransfers() internal {
        console.log(" PHASE 9: CROSS-USER TRANSFERS               ");

        console.log("\n Bob transfers 5,000 ryUSD back to Alice");
        ryUSD.transfer(deployer, 5_000 * 1e6);

        console.log("  Alice ryUSD:", ryUSD.balanceOf(deployer) / 1e6);
        console.log("  Bob ryUSD:", ryUSD.balanceOf(bob) / 1e6);

        (uint256 aliceP, uint256 aliceC, ) = ryBond.getUserStats(deployer);
        (uint256 bobP, uint256 bobC, ) = ryBond.getUserStats(bob);

        console.log("\n  Alice Total ryBOND:", aliceC);
        console.log("  Bob Total ryBOND:", bobC);

        yieldManager.addDemoVolume(13_000 * 1e6);
    }

    function _phase10_RyBondClaiming() internal {
        console.log(" PHASE 10: ryBOND CLAIMING & YIELD ACCRUAL   ");

        (uint256 pending, uint256 credited, uint256 claimed) = ryBond
            .getUserStats(deployer);

        console.log("\n Alice's ryBOND Status:");
        console.log("  Pending:", pending);
        console.log("  Credited:", credited);
        console.log("  Already Claimed:", claimed);
        console.log("  Total Earned:", credited + claimed);
    }

    function _phase11_TreasuryOperations() internal {
        console.log(" PHASE 11: TREASURY OPERATIONS & ALLOCATION  ");

        (uint256 totalDep, uint256 totalAlloc, uint256 hotWallet) = treasury
            .getAllocationInfo();

        console.log("\n Treasury Status:");
        console.log("  Total Deposited:", totalDep / 1e6, "USDC");
        console.log("  Total Allocated:", totalAlloc / 1e6, "USDC");
        console.log("  Hot Wallet:", hotWallet / 1e6, "USDC");
        console.log("  Allocation %:", (totalAlloc * 100) / totalDep, "%");

        (
            address usdy,
            address ousg,
            address lending,
            address reserve
        ) = treasury.getStrategies();
        console.log("\n Strategy Addresses:");
        console.log("  USDY:", usdy);
        console.log("  OUSG:", ousg);
        console.log("  Lending:", lending);
        console.log("  Reserve:", reserve);
    }

    function _phase12_FinalSummary() internal {
        console.log(" PHASE 12: FINAL PROTOCOL SUMMARY            ");

        (
            uint256 pool,
            uint256 totalDep,
            uint256 totalAlloc,
            ,
            uint256 rate
        ) = yieldManager.getPoolStats();

        console.log("\n YieldManager Final State:");
        console.log("  Remaining Pool:", pool / 1e6, "USDC");
        console.log("  Total Deposited:", totalDep / 1e6, "USDC");
        console.log("  Total Allocated:", totalAlloc / 1e6, "USDC");
        console.log("  Utilization:", (totalAlloc * 100) / totalDep, "%");
        console.log("  Current Rate:", rate, "bps");
        console.log("   Percentage:", (rate * 100) / 10000, "%");

        console.log("\n User Balances:");
        console.log("  Alice ryUSD:", ryUSD.balanceOf(deployer) / 1e6);
        console.log("  Bob ryUSD:", ryUSD.balanceOf(bob) / 1e6);

        (uint256 aliceBuckets, , ) = handler.getUserBucketInfo(deployer);
        (uint256 bobBuckets, , ) = handler.getUserBucketInfo(bob);
        console.log("  Alice Buckets:", aliceBuckets);
        console.log("  Bob Buckets:", bobBuckets);

        (, uint256 aliceC, ) = ryBond.getUserStats(deployer);
        (, uint256 bobC, ) = ryBond.getUserStats(bob);
        console.log("  Alice ryBOND:", aliceC / 1e6);
        console.log("  Bob ryBOND:", bobC / 1e6);
    }
}
