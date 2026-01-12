// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/treasury/YieldManager.sol";
import "src/mocks/token/MockUSDC.sol";

contract FundYieldManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Addresses
        address usdcAddress = 0xcb456899a90bc65ba19B899316623C481e3ebDCB;
        address yieldManagerAddress = 0x06dE2bF7F830D5dAFa5F62B949fc3ABf301F2746;

        vm.startBroadcast(deployerPrivateKey);

        MockUSDC usdc = MockUSDC(usdcAddress);
        YieldManager yieldManager = YieldManager(yieldManagerAddress);

        // 1. Mint 50,000 USDC to deployer if needed (or assume deployer has it)
        // Just making sure we have enough
        usdc.mintAdmin(deployer, 50000 * 1e6);
        console.log("Minted 50k USDC to deployer");

        // 2. Approve YieldManager
        uint256 amountToFund = 10000 * 1e6; // $10,000
        usdc.approve(yieldManagerAddress, amountToFund);
        console.log("Approved YieldManager to spend 10k USDC");

        // 3. Deposit Yield
        yieldManager.depositYield(amountToFund);
        console.log("Deposited 10k USDC to YieldManager");

        // 4. Add Demo Volume to kickstart APY
        // Otherwise MovingAverage is 1e18 (too high) and APY is 0
        yieldManager.addDemoVolume(1000 * 1e6); // $1000 volume
        console.log("Added $1000 demo volume");

        vm.stopBroadcast();
    }
}
