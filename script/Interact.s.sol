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
        console.log("Note: WETH->USDC swap fails because pool is at minimum price limit");
        console.log("Swapping USDC->WETH instead (should work)");
        console.log("User:", user);
        console.log("Swapper:", swapperAddress);
        
        vm.startBroadcast(privateKey);
        
        // Check balances before
        uint256 wethBefore = IERC20(swapper.WETH()).balanceOf(user);
        uint256 usdcBefore = IERC20(swapper.USDC()).balanceOf(user);
        
        console.log("");
        console.log("WETH before:", wethBefore);
        console.log("USDC before:", usdcBefore);
        
        // Approve USDC to BaseSwapper (required for transferFrom)
        console.log("");
        console.log("Approving USDC...");
        IERC20(swapper.USDC()).approve(address(swapper), type(uint256).max);
        // REQUIRED: approveToken sets up Permit2 for SETTLE_ALL to pull tokens from BaseSwapper
        // SETTLE_ALL uses Permit2 to pull tokens, so this approval is mandatory
        swapper.approveToken(swapper.USDC());
        
        // Check multiple pools with different fee/tickSpacing combinations
        // Common Uniswap fee tiers: 500 (0.05%), 3000 (0.3%), 10000 (1%)
        console.log("");
        console.log("=== Checking Multiple Pools ===");
        uint24[] memory fees = new uint24[](3);
        int24[] memory tickSpacings = new int24[](3);
        
        fees[0] = 500;   // 0.05%
        tickSpacings[0] = 10;
        
        fees[1] = 3000;  // 0.3%
        tickSpacings[1] = 60;
        
        fees[2] = 10000; // 1%
        tickSpacings[2] = 200;
        
        (bool[] memory exist, uint128[] memory liquidities, uint160[] memory sqrtPriceX96s) = 
            swapper.checkMultiplePools(swapper.USDC(), swapper.WETH(), fees, tickSpacings);
        
        // Find pool with liquidity
        uint24 selectedFee;
        int24 selectedTickSpacing;
        bool foundLiquidPool = false;
        
        for (uint256 i = 0; i < fees.length; i++) {
            console.log("");
            console.log("Pool:", i);
            console.log("  Fee:", fees[i]);
            console.log("  TickSpacing:", uint256(uint24(tickSpacings[i])));
            console.log("  Exists:", exist[i]);
            console.log("  Liquidity:", uint256(uint128(liquidities[i])));
            
            if (exist[i] && liquidities[i] > 0 && !foundLiquidPool) {
                selectedFee = fees[i];
                selectedTickSpacing = tickSpacings[i];
                foundLiquidPool = true;
                console.log("  >>> SELECTED (has liquidity!)");
            }
        }
        
        if (!foundLiquidPool) {
            revert("No pools found with liquidity. Cannot execute swap.");
        }
        
        console.log("");
        console.log("=== Using Pool with Liquidity ===");
        console.log("Fee:", selectedFee);
        console.log("TickSpacing:", uint256(uint24(selectedTickSpacing)));
        
        // Swap 1 USDC for WETH using the pool with liquidity
        // Note: Output tokens are sent directly to user (msg.sender) via TAKE action
        console.log("");
        console.log("Swapping 1 USDC for WETH...");
        
        uint256 amountOut = swapper.swap(
            swapper.USDC(),
            swapper.WETH(),
            selectedFee,
            selectedTickSpacing,
            1e5, // 0.1 USDC (6 decimals)
            0 // No slippage protection for testing (use proper minAmountOut in production!)
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