// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/mocks/vaults/MockVault.sol";
import "src/core/ryBOND.sol";

// TODO: REDEPLOY ONLY - DELETE LATER

contract UpgradeYieldVaultScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Existing contract addresses (UPDATE THESE!)
        address ryUSDAddress = vm.envAddress("RYUSD_ADDRESS");
        address ryBondAddress = vm.envAddress("RYBOND_ADDRESS");

        console.log("Deploying with address:", deployer);
        console.log("ryUSD address:", ryUSDAddress);
        console.log("ryBOND address:", ryBondAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new yield vault with ryUSD as asset
        MockVault newYieldVault = new MockVault(
            ryUSDAddress,
            "ryBOND Yield Vault (ryUSD)",
            deployer
        );
        console.log("New Yield Vault deployed at:", address(newYieldVault));

        // 2. Update ryBOND to use new vault
        ryBOND ryBond = ryBOND(ryBondAddress);
        ryBond.setVault(address(newYieldVault));
        console.log("ryBOND.setVault updated to new vault");

        vm.stopBroadcast();

        console.log("\n=== UPGRADE COMPLETE ===");
        console.log("New Yield Vault:", address(newYieldVault));
        console.log("ryBOND now uses ryUSD for claim distribution!");
    }
}
