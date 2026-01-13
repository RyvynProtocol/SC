// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/core/RyvynHandler.sol";
import "src/core/ryUSD.sol";
import "src/treasury/YieldManager.sol";
import "src/core/ryBOND.sol";

contract UpgradeHandlerScript is Script {
    address constant RYUSD_ADDR = 0xF5DC8dE141b22D054621C9C413A40b95AC0d226f;
    address constant YIELD_MANAGER_ADDR =
        0x06dE2bF7F830D5dAFa5F62B949fc3ABf301F2746;
    address constant RYBOND_ADDR = 0x210d2e01d0e3Ec57dD0EcCcCe8eA6f893FF12c0C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Upgrading RyvynHandler with deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        RyvynHandler newHandler = new RyvynHandler(deployer);
        console.log("NEW RyvynHandler deployed at:", address(newHandler));

        newHandler.setRyUSD(RYUSD_ADDR);
        newHandler.setRyBOND(RYBOND_ADDR);
        newHandler.setYieldManager(YIELD_MANAGER_ADDR);
        console.log("Configured NEW Handler dependencies");

        RyUSD(RYUSD_ADDR).setHandler(address(newHandler));
        console.log("Updated ryUSD handler");

        YieldManager(YIELD_MANAGER_ADDR).setRyvynHandler(address(newHandler));
        console.log("Updated YieldManager handler");

        ryBOND(RYBOND_ADDR).setRyvynHandler(address(newHandler));
        console.log("Updated ryBOND handler");

        vm.stopBroadcast();

        console.log("\n=== UPGRADE COMPLETE ===");
        console.log("Please update your Frontend config:");
        console.log("ryvynHandler:", address(newHandler));
    }
}
