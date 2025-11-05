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
        
        console.log("=== Swap USDC for WETH ===");
        console.log("User:", user);
        console.log("Swapper:", swapperAddress);
        
        vm.startBroadcast(privateKey);
        
        // Check balances before
        uint256 wethBefore = IERC20(swapper.WETH()).balanceOf(user);
        uint256 usdcBefore = IERC20(swapper.USDC()).balanceOf(user);
        
        console.log("");
        console.log("WETH before:", wethBefore);
        console.log("USDC before:", usdcBefore);
        
        // Approve USDC
        console.log("");
        console.log("Approving USDC...");
        IERC20(swapper.USDC()).approve(address(swapper), type(uint256).max);
        swapper.approveToken(swapper.USDC());
        
        // Swap 1 USDC for WETH (1 USDC = 1e6)
        console.log("");
        console.log("Swapping 1 USDC for WETH...");
        
        uint256 amountOut = swapper.swapUSDCForWETH(
            1e6, // 1 USDC
            0 // No slippage protection for testing
        );
        
        // Check balances after
        uint256 wethAfter = IERC20(swapper.WETH()).balanceOf(user);
        uint256 usdcAfter = IERC20(swapper.USDC()).balanceOf(user);
        
        console.log("");
        console.log("=== Swap Complete ===");
        console.log("WETH after:", wethAfter);
        console.log("USDC after:", usdcAfter);
        console.log("USDC spent:", usdcBefore - usdcAfter);
        console.log("WETH received:", wethAfter - wethBefore);
        console.log("Amount out:", amountOut);
        
        vm.stopBroadcast();
    }
}