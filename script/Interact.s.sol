// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/BaseSwapper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InteractScript is Script {
    function run() external {
        address swapperAddress = vm.envAddress("SWAPPER_ADDRESS");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        
        BaseSwapper swapper = BaseSwapper(swapperAddress);
        address user = vm.addr(privateKey);
        
        console.log("=== Swap WETH for USDC ===");
        console.log("User:", user);
        console.log("Swapper:", swapperAddress);
        
        vm.startBroadcast(privateKey);
        
        // Check balances before
        uint256 wethBefore = IERC20(swapper.WETH()).balanceOf(user);
        uint256 usdcBefore = IERC20(swapper.USDC()).balanceOf(user);
        
        console.log("");
        console.log("WETH before:", wethBefore);
        console.log("USDC before:", usdcBefore);
        
        // Approve WETH
        console.log("");
        console.log("Approving WETH...");
        IERC20(swapper.WETH()).approve(address(swapper), type(uint256).max);
        swapper.approveToken(swapper.WETH());
        
        // Swap 0.0001 WETH for USDC
        console.log("");
        console.log("Swapping 0.0001 WETH for USDC...");
        
        uint256 amountOut = swapper.swapWETHForUSDC(
            0.0001 ether,
            0 // No slippage protection for testing
        );
        
        // Check balances after
        uint256 wethAfter = IERC20(swapper.WETH()).balanceOf(user);
        uint256 usdcAfter = IERC20(swapper.USDC()).balanceOf(user);
        
        console.log("");
        console.log("=== Swap Complete ===");
        console.log("WETH after:", wethAfter);
        console.log("USDC after:", usdcAfter);
        console.log("WETH spent:", wethBefore - wethAfter);
        console.log("USDC received:", usdcAfter - usdcBefore);
        console.log("Amount out:", amountOut);
        
        vm.stopBroadcast();
    }
}