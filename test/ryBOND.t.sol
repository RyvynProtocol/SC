// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/ryBOND.sol";

// ini pakek mockvault sm mockryvynhandler krn ku gkpunya .sol nya
contract MockVault {
    mapping(address => uint256) public distributions;

    function distributeYield(
        address user,
        uint256 amount
    ) external returns (bool) {
        distributions[user] += amount;
        return true;
    }

    function getDistribution(address user) external view returns (uint256) {
        return distributions[user];
    }
}

contract MockRyvynHandler {
    ryBOND public ryBondContract;

    function setRyBond(address _ryBond) external {
        ryBondContract = ryBOND(_ryBond);
    }

    function simulateTransferHook(
        address sender,
        uint256 senderReward,
        address receiver,
        uint256 receiverReward
    ) external {
        ryBondContract.creditTransferReward(
            sender,
            senderReward,
            receiver,
            receiverReward
        );
    }

    function simulateCreditUser(address user, uint256 amount) external {
        ryBondContract.creditRyBond(user, amount);
    }
}

contract ryBONDTest is Test {
    ryBOND public ryBondContract;
    MockVault public vault;
    MockRyvynHandler public handler;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    event RyBONDCredited(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event RyBONDClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event RyBONDAccrued(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);
    event TransferRewardDistributed(
        address indexed sender,
        address indexed receiver,
        uint256 senderReward,
        uint256 receiverReward,
        uint256 timestamp
    );

    function setUp() public {
        vault = new MockVault();
        handler = new MockRyvynHandler();

        ryBondContract = new ryBOND(address(handler), address(vault));

        handler.setRyBond(address(ryBondContract));
    }

    // ============ Constructor Tests ============

    function test_ConstructorSetsCorrectAddresses() public view {
        assertEq(ryBondContract.ryvynHandler(), address(handler));
        assertEq(address(ryBondContract.vault()), address(vault));
        assertEq(ryBondContract.owner(), owner);
    }

    function test_ConstructorRevertsOnZeroHandler() public {
        vm.expectRevert("ryBOND: handler is zero address");
        new ryBOND(address(0), address(vault));
    }

    function test_ConstructorRevertsOnZeroVault() public {
        vm.expectRevert("ryBOND: vault is zero address");
        new ryBOND(address(handler), address(0));
    }

    // ============ creditTransferReward Tests ============

    function test_CreditTransferReward_UpdatesBothBalances() public {
        uint256 senderReward = 100e18;
        uint256 receiverReward = 50e18;

        handler.simulateTransferHook(
            user1,
            senderReward,
            user2,
            receiverReward
        );

        assertEq(ryBondContract.storedBalance(user1), senderReward);
        assertEq(ryBondContract.storedBalance(user2), receiverReward);
        (, uint256 creditedUser1, ) = ryBondContract.getUserStats(user1);
        (, uint256 creditedUser2, ) = ryBondContract.getUserStats(user2);
        assertEq(creditedUser1, senderReward);
        assertEq(creditedUser2, receiverReward);
    }

    function test_CreditTransferReward_EmitsEvent() public {
        uint256 senderReward = 85e18;
        uint256 receiverReward = 15e18;

        vm.expectEmit(true, true, false, true);
        emit TransferRewardDistributed(
            user1,
            user2,
            senderReward,
            receiverReward,
            block.timestamp
        );

        handler.simulateTransferHook(
            user1,
            senderReward,
            user2,
            receiverReward
        );
    }

    function test_CreditTransferReward_AccumulatesRewards() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        handler.simulateTransferHook(user1, 200e18, user2, 100e18);

        assertEq(ryBondContract.storedBalance(user1), 300e18);
        assertEq(ryBondContract.storedBalance(user2), 150e18);
    }

    function test_CreditTransferReward_DynamicSplit() public {
        handler.simulateTransferHook(user1, 85e18, user2, 15e18);
        assertEq(ryBondContract.storedBalance(user1), 85e18);
        assertEq(ryBondContract.storedBalance(user2), 15e18);

        handler.simulateTransferHook(user3, 70e18, user2, 30e18);
        assertEq(ryBondContract.storedBalance(user3), 70e18);
        assertEq(ryBondContract.storedBalance(user2), 45e18);
    }

    function test_CreditTransferReward_OnlyHandler() public {
        vm.prank(user1);
        vm.expectRevert("ryBOND: caller is not RyvynHandler");
        ryBondContract.creditTransferReward(user1, 100e18, user2, 50e18);
    }

    function test_CreditTransferReward_ZeroSenderAddress() public {
        handler.simulateTransferHook(address(0), 100e18, user2, 50e18);

        assertEq(ryBondContract.storedBalance(address(0)), 0);
        assertEq(ryBondContract.storedBalance(user2), 50e18);
    }

    // ============ creditRyBond Tests ============

    function test_CreditRyBond_UpdatesBalance() public {
        uint256 amount = 100e18;

        handler.simulateCreditUser(user1, amount);

        assertEq(ryBondContract.storedBalance(user1), amount);
        (, uint256 credited, ) = ryBondContract.getUserStats(user1);
        assertEq(credited, amount);
    }

    function test_CreditRyBond_EmitsEvent() public {
        uint256 amount = 100e18;

        vm.expectEmit(true, false, false, true);
        emit RyBONDCredited(user1, amount, block.timestamp);

        handler.simulateCreditUser(user1, amount);
    }

    function test_CreditRyBond_RevertsOnZeroUser() public {
        vm.prank(address(handler));
        vm.expectRevert("ryBOND: user is zero address");
        ryBondContract.creditRyBond(address(0), 100e18);
    }

    function test_CreditRyBond_RevertsOnZeroAmount() public {
        vm.prank(address(handler));
        vm.expectRevert("ryBOND: amount is zero");
        ryBondContract.creditRyBond(user1, 0);
    }

    // ============ Claim Tests ============

    function test_Claim_TransfersToVaultAndResetsBalance() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        vm.prank(user1);
        ryBondContract.claim();

        assertEq(ryBondContract.storedBalance(user1), 0);
        (, , uint256 claimed) = ryBondContract.getUserStats(user1);
        assertEq(claimed, 100e18);
        assertEq(vault.getDistribution(user1), 100e18);
    }

    function test_Claim_EmitsEvent() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit RyBONDClaimed(user1, 100e18, block.timestamp);

        ryBondContract.claim();
    }

    function test_Claim_RevertsOnZeroBalance() public {
        vm.prank(user1);
        vm.expectRevert("ryBOND: nothing to claim");
        ryBondContract.claim();
    }

    function test_ClaimAmount_PartialClaim() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        vm.prank(user1);
        ryBondContract.claimAmount(60e18);

        assertEq(ryBondContract.storedBalance(user1), 40e18);
        (, , uint256 claimed) = ryBondContract.getUserStats(user1);
        assertEq(claimed, 60e18);
        assertEq(vault.getDistribution(user1), 60e18);
    }

    function test_ClaimAmount_RevertsOnInsufficientBalance() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        vm.prank(user1);
        vm.expectRevert("ryBOND: insufficient balance");
        ryBondContract.claimAmount(200e18);
    }

    // ============ View Function Tests ============

    function test_PendingRyBond_ReturnsCorrectBalance() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        assertEq(ryBondContract.pendingRyBond(user1), 100e18);
        assertEq(ryBondContract.pendingRyBond(user2), 50e18);
    }

    function test_GetUserStats_ReturnsAllStats() public {
        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        vm.prank(user1);
        ryBondContract.claimAmount(30e18);

        (uint256 pending, uint256 credited, uint256 claimed) = ryBondContract
            .getUserStats(user1);

        assertEq(pending, 70e18);
        assertEq(credited, 100e18);
        assertEq(claimed, 30e18);
    }

    // ============ Admin Function Tests ============

    function test_SetRyvynHandler_UpdatesHandler() public {
        address newHandler = address(0x999);

        ryBondContract.setRyvynHandler(newHandler);
        assertEq(ryBondContract.ryvynHandler(), newHandler);
    }

    function test_SetRyvynHandler_RevertsOnZeroAddress() public {
        vm.expectRevert("ryBOND: handler is zero address");
        ryBondContract.setRyvynHandler(address(0));
    }

    function test_SetRyvynHandler_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        ryBondContract.setRyvynHandler(address(0x999));
    }

    function test_SetVault_UpdatesVault() public {
        address newVault = address(0x888);

        ryBondContract.setVault(newVault);
        assertEq(address(ryBondContract.vault()), newVault);
    }

    // ============ Lazy Accrual Tests ============

    function test_SetYieldRate_UpdatesRate() public {
        uint256 newRate = 1e14;

        vm.expectEmit(false, false, false, true);
        emit YieldRateUpdated(0, newRate);

        ryBondContract.setYieldRate(newRate);
        assertEq(ryBondContract.yieldRatePerSecond(), newRate);
    }

    function test_LazyAccrual_BalanceGrowsOverTime() public {
        uint256 yieldRate = 1e14;
        ryBondContract.setYieldRate(yieldRate);

        handler.simulateCreditUser(user1, 100e18);

        assertEq(ryBondContract.storedBalance(user1), 100e18);

        vm.warp(block.timestamp + 10 hours);

        uint256 expectedBalance = 100e18 +
            ((100e18 * yieldRate * 36000) / 1e18);

        assertEq(ryBondContract.pendingRyBond(user1), expectedBalance);

        assertEq(ryBondContract.storedBalance(user1), 100e18);
    }

    function test_LazyAccrual_AccruesOnInteraction() public {
        uint256 yieldRate = 1e14;
        ryBondContract.setYieldRate(yieldRate);

        handler.simulateCreditUser(user1, 100e18);

        vm.warp(block.timestamp + 1 hours);

        handler.simulateCreditUser(user1, 50e18);

        uint256 expectedStored = 100e18 + 36e18 + 50e18;

        assertEq(ryBondContract.storedBalance(user1), expectedStored);
    }

    function test_LazyAccrual_ClaimIncludesAccruedYield() public {
        uint256 yieldRate = 1e14;
        ryBondContract.setYieldRate(yieldRate);

        handler.simulateCreditUser(user1, 100e18);

        vm.warp(block.timestamp + 10 hours);

        uint256 expectedYield = (100e18 * yieldRate * 36000) / 1e18;
        uint256 expectedTotal = 100e18 + expectedYield;

        vm.prank(user1);
        ryBondContract.claim();

        assertEq(vault.getDistribution(user1), expectedTotal);
        (, , uint256 claimed) = ryBondContract.getUserStats(user1);
        assertEq(claimed, expectedTotal);
    }

    function test_LazyAccrual_ManualAccrueFunction() public {
        uint256 yieldRate = 1e14;
        ryBondContract.setYieldRate(yieldRate);

        handler.simulateCreditUser(user1, 100e18);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(user2);
        ryBondContract.accrue(user1);

        uint256 expectedYield = (100e18 * yieldRate * 3600) / 1e18;
        assertEq(ryBondContract.storedBalance(user1), 100e18 + expectedYield);
    }

    function test_LazyAccrual_NoYieldWithZeroRate() public {
        assertEq(ryBondContract.yieldRatePerSecond(), 0);

        handler.simulateCreditUser(user1, 100e18);

        vm.warp(block.timestamp + 100 hours);

        assertEq(ryBondContract.pendingRyBond(user1), 100e18);
        assertEq(ryBondContract.storedBalance(user1), 100e18);
    }

    function test_LazyAccrual_CompoundingOverMultipleInteractions() public {
        uint256 yieldRate = 1e14;
        ryBondContract.setYieldRate(yieldRate);

        handler.simulateCreditUser(user1, 100e18);
        handler.simulateCreditUser(user1, 100e18);

        vm.warp(block.timestamp + 1 hours);
        handler.simulateCreditUser(user1, 50e18);

        assertEq(ryBondContract.storedBalance(user1), 322e18);

        vm.warp(block.timestamp + 1 hours);

        uint256 secondYield = (322e18 * yieldRate * 3600) / 1e18;

        vm.prank(user1);
        ryBondContract.claim();

        assertEq(vault.getDistribution(user1), 322e18 + secondYield);
    }

    // ============ Integration Test: Full Flow ============

    function test_FullFlow_TransferToClaimCycle() public {
        handler.simulateTransferHook(user1, 85e18, user2, 15e18); // Long-term holder
        handler.simulateTransferHook(user2, 70e18, user3, 30e18); // Normal split
        handler.simulateTransferHook(user3, 75e18, user1, 25e18); // Mixed

        assertEq(ryBondContract.pendingRyBond(user1), 110e18); // 85 + 25
        assertEq(ryBondContract.pendingRyBond(user2), 85e18); // 15 + 70
        assertEq(ryBondContract.pendingRyBond(user3), 105e18); // 30 + 75

        vm.prank(user1);
        ryBondContract.claim();
        assertEq(ryBondContract.pendingRyBond(user1), 0);
        assertEq(vault.getDistribution(user1), 110e18);

        vm.prank(user2);
        ryBondContract.claimAmount(50e18);
        assertEq(ryBondContract.pendingRyBond(user2), 35e18);
        assertEq(vault.getDistribution(user2), 50e18);

        handler.simulateTransferHook(user1, 100e18, user2, 50e18);
        assertEq(ryBondContract.pendingRyBond(user1), 100e18);
        assertEq(ryBondContract.pendingRyBond(user2), 85e18);

        (, uint256 creditedUser1, ) = ryBondContract.getUserStats(user1);
        assertEq(creditedUser1, 210e18);
    }

    function test_FullFlow_WithLazyAccrual() public {
        uint256 yieldRate = 1e14;
        ryBondContract.setYieldRate(yieldRate);

        handler.simulateTransferHook(user1, 100e18, user2, 50e18);

        vm.warp(block.timestamp + 10 hours);

        uint256 expectedUser1 = 100e18 + ((100e18 * yieldRate * 36000) / 1e18);
        assertEq(ryBondContract.pendingRyBond(user1), expectedUser1);

        uint256 expectedUser2 = 50e18 + ((50e18 * yieldRate * 36000) / 1e18);
        assertEq(ryBondContract.pendingRyBond(user2), expectedUser2);

        vm.prank(user1);
        ryBondContract.claim();

        assertEq(vault.getDistribution(user1), expectedUser1);
        assertEq(ryBondContract.pendingRyBond(user1), 0);
    }
}
