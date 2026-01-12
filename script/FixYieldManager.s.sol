// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "src/treasury/YieldManager.sol";
import "src/core/RyvynHandler.sol";

contract FixYieldManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ryUSD = vm.envAddress("RYUSD_ADDRESS");
        address usdcAddress = 0xcb456899a90bc65ba19B899316623C481e3ebDCB;
        address ryvynHandlerVal = 0x19600CB6458E903f2Ad335592046Bd786c214677;

        vm.startBroadcast(deployerPrivateKey);

        YieldManager newYieldManager = new YieldManager(
            usdcAddress,
            vm.addr(deployerPrivateKey)
        );
        console.log("New Yield Manager deployed at:", address(newYieldManager));

        newYieldManager.setRyvynHandler(ryvynHandlerVal);
        console.log("New YieldManager handler set");

        RyvynHandler handler = RyvynHandler(ryvynHandlerVal);
        handler.setYieldManager(address(newYieldManager));
        console.log("RyvynHandler updated with new YieldManager");

        vm.stopBroadcast();
    }
}
