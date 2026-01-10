// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/mocks/token/MockUSDC.sol";
import "src/mocks/vaults/MockVault.sol";
import "src/core/RyvynHandler.sol";
import "src/core/ryUSD.sol";
import "src/treasury/TreasuryManager.sol";
import "src/treasury/YieldManager.sol";
import "src/core/ryBOND.sol";

contract DeployScript is Script {
    MockUSDC public mockUSDC;
    MockVault public mockVaultUSDY;
    MockVault public mockVaultOUSG;
    MockVault public mockVaultLending;
    RyvynHandler public ryvynHandler;
    RyUSD public ryUSD;
    TreasuryManager public treasuryManager;
    YieldManager public yieldManager;
    ryBOND public ryBond;

    address public deployer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with address:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n=== Deploying MockUSDC ===");
        mockUSDC = new MockUSDC(deployer);
        console.log("MockUSDC deployed at:", address(mockUSDC));

        console.log("\n=== Deploying Mock Vaults ===");
        mockVaultUSDY = new MockVault(
            address(mockUSDC),
            "Mock USDY Vault",
            deployer
        );
        console.log("MockVault USDY deployed at:", address(mockVaultUSDY));

        mockVaultOUSG = new MockVault(
            address(mockUSDC),
            "Mock OUSG Vault",
            deployer
        );
        console.log("MockVault OUSG deployed at:", address(mockVaultOUSG));

        mockVaultLending = new MockVault(
            address(mockUSDC),
            "Mock Lending Vault",
            deployer
        );
        console.log(
            "MockVault Lending deployed at:",
            address(mockVaultLending)
        );

        console.log("\n=== Deploying Core Contracts ===");

        ryvynHandler = new RyvynHandler(deployer);
        console.log("RyvynHandler deployed at:", address(ryvynHandler));

        ryUSD = new RyUSD(address(mockUSDC), deployer);
        console.log("RyUSD deployed at:", address(ryUSD));

        treasuryManager = new TreasuryManager(
            address(mockUSDC),
            address(mockVaultUSDY),
            address(mockVaultOUSG),
            address(mockVaultLending),
            deployer,
            deployer
        );
        console.log("TreasuryManager deployed at:", address(treasuryManager));

        yieldManager = new YieldManager(address(mockUSDC), deployer);
        console.log("YieldManager deployed at:", address(yieldManager));

        MockVault yieldVault = new MockVault(
            address(ryUSD),
            "ryBOND Yield Vault",
            deployer
        );
        console.log("ryBOND Yield Vault deployed at:", address(yieldVault));

        ryBond = new ryBOND(address(ryvynHandler), address(yieldVault));
        console.log("ryBOND deployed at:", address(ryBond));

        console.log("\n=== Configuring Contracts ===");

        ryvynHandler.setRyUSD(address(ryUSD));
        console.log("RyvynHandler.setRyUSD");

        ryvynHandler.setRyBOND(address(ryBond));
        console.log("RyvynHandler.setRyBOND");

        ryvynHandler.setYieldManager(address(yieldManager));
        console.log("RyvynHandler.setYieldManager");

        ryUSD.setHandler(address(ryvynHandler));
        console.log("RyUSD.setHandler");

        ryUSD.setTreasury(address(treasuryManager));
        console.log("RyUSD.setTreasury");

        treasuryManager.setRyUSD(address(ryUSD));
        console.log("TreasuryManager.setRyUSD");

        yieldManager.setRyvynHandler(address(ryvynHandler));
        console.log("YieldManager.setRyvynHandler");

        ryBond.setYieldRate(1e14);
        console.log("ryBOND.setYieldRate to 1e14");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("MockUSDC:           ", address(mockUSDC));
        console.log("MockVault USDY:     ", address(mockVaultUSDY));
        console.log("MockVault OUSG:     ", address(mockVaultOUSG));
        console.log("MockVault Lending:  ", address(mockVaultLending));
        console.log("RyvynHandler:       ", address(ryvynHandler));
        console.log("RyUSD:              ", address(ryUSD));
        console.log("TreasuryManager:    ", address(treasuryManager));
        console.log("YieldManager:       ", address(yieldManager));
        console.log("ryBOND:             ", address(ryBond));
        console.log("ryBOND Yield Vault: ", address(yieldVault));
        console.log("\nAll contracts deployed and configured successfully!");
    }
}
