// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/BaseSwapper.sol";

contract DeployScript is Script {
    function run() external {
        // Base mainnet addresses
        address UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
        address POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        BaseSwapper swapper = new BaseSwapper(
            UNIVERSAL_ROUTER, 
            POOL_MANAGER,
            PERMIT2
        );
        
        console.log("BaseSwapper deployed at:", address(swapper));
        
        vm.stopBroadcast();
    }
}