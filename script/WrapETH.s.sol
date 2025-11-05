// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

interface IWETH {
    function deposit() external payable;
    function balanceOf(address) external view returns (uint256);
}

contract WrapETH is Script {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);
        
        console.log("User:", user);
        console.log("ETH balance:", user.balance);
        
        vm.startBroadcast(privateKey);
        
        // Wrap 0.0003 ETH (keep rest for gas)
        IWETH(WETH).deposit{value: 0.0003 ether}();
        
        uint256 wethBalance = IWETH(WETH).balanceOf(user);
        console.log("WETH balance after wrap:", wethBalance);
        
        vm.stopBroadcast();
    }
}