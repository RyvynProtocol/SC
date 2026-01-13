// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/core/ryBOND.sol";
import "src/core/RyvynHandler.sol";
import "src/mocks/vaults/MockVault.sol";

contract UpgradeRyBONDScript is Script {
    address constant OLD_RYBOND_ADDR =
        0x210d2e01d0e3Ec57dD0EcCcCe8eA6f893FF12c0C;
    address constant RYVYN_HANDLER_ADDR =
        0x5B37613C76eafe45630AF5Ee5877D2f444c20a0A;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Upgrading ryBOND with deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        MockVault newYieldVault = new MockVault(
            0xF5DC8dE141b22D054621C9C413A40b95AC0d226f,
            "ryBOND Yield Vault V2",
            deployer
        );
        console.log("New Yield Vault deployed at:", address(newYieldVault));

        ryBOND newBond = new ryBOND(RYVYN_HANDLER_ADDR, address(newYieldVault));
        console.log("NEW ryBOND deployed at:", address(newBond));

        RyvynHandler(RYVYN_HANDLER_ADDR).setRyBOND(address(newBond));
        console.log("Updated RyvynHandler with new ryBOND");

        vm.stopBroadcast();

        console.log("\n=== UPGRADE COMPLETE ===");
        console.log("Please update your Frontend config:");
        console.log("ryBOND:", address(newBond));
    }
}
