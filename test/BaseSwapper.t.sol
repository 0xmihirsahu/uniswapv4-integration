// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/BaseSwapper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

contract BaseSwapperTest is Test {
    BaseSwapper public swapper;
    
    // Base contract addresses - UPDATE THESE WITH CORRECT ADDRESSES
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    
    // Tokens
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    
    // Test user
    address user = address(0x1234);
    
    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("base");
        
        // Deploy swapper with this contract as owner
        swapper = new BaseSwapper(
            UNIVERSAL_ROUTER,
            POOL_MANAGER,
            PERMIT2,
            address(this) // Set test contract as owner
        );
        
        // Give user some tokens for testing
        deal(WETH, user, 10 ether);
        deal(USDC, user, 10000e6); // USDC has 6 decimals
        deal(DAI, user, 10000 ether);
    }
    
    function testCheckWETHUSDCPoolExists() public view {
        PoolKey memory key = swapper.createPoolKey(
            WETH,
            USDC,
            3000, // 0.3%
            60
        );
        
        bool exists = swapper.poolExists(key);
        console.log("WETH/USDC 0.3% pool exists:", exists);
        
        if (exists) {
            (
                ,
                uint160 sqrtPriceX96,
                int24 tick,
                uint24 protocolFee,
                uint24 lpFee,
                uint128 liquidity
            ) = swapper.getPoolInfo(key);
            
            console.log("  sqrtPriceX96:", sqrtPriceX96);
            console.log("  tick:", uint256(int256(tick)));
            console.log("  protocolFee:", protocolFee);
            console.log("  lpFee:", lpFee);
            console.log("  liquidity:", uint256(uint128(liquidity)));
        }
    }
    
    function testCheckUSDCDAIPoolExists() public view {
        PoolKey memory key = swapper.createPoolKey(
            USDC,
            DAI,
            100, // 0.01%
            1
        );
        
        bool exists = swapper.poolExists(key);
        console.log("USDC/DAI 0.01% pool exists:", exists);
        
        if (exists) {
            (
                ,
                uint160 sqrtPriceX96,
                int24 tick,
                ,
                ,
                uint128 liquidity
            ) = swapper.getPoolInfo(key);
            
            console.log("  sqrtPriceX96:", sqrtPriceX96);
            console.log("  tick:", uint256(int256(tick)));
            console.log("  liquidity:", uint256(uint128(liquidity)));
        }
    }
    
    function testApproveTokens() public {
        vm.startPrank(user);
        
        // Approve USDC
        IERC20(USDC).approve(address(swapper), type(uint256).max);
        swapper.approveToken(USDC);
        
        vm.stopPrank();
        
        console.log("Tokens approved successfully");
    }
    
    function testCheckMultiplePools() public view {
        console.log("=== Checking Multiple WETH/USDC Pools ===");
        
        uint24[] memory fees = new uint24[](3);
        int24[] memory tickSpacings = new int24[](3);
        
        fees[0] = 500;   // 0.05%
        tickSpacings[0] = 10;
        
        fees[1] = 3000;  // 0.3%
        tickSpacings[1] = 60;
        
        fees[2] = 10000; // 1%
        tickSpacings[2] = 200;
        
        (bool[] memory exist, uint128[] memory liquidities, uint160[] memory sqrtPriceX96s) = 
            swapper.checkMultiplePools(WETH, USDC, fees, tickSpacings);
        
        for (uint256 i = 0; i < fees.length; i++) {
            console.log("");
            console.log("Pool:", i);
            console.log("  Fee:", fees[i]);
            console.log("  TickSpacing:", uint256(uint24(tickSpacings[i])));
            console.log("  Exists:", exist[i]);
            console.log("  Liquidity:", uint256(uint128(liquidities[i])));
            if (exist[i]) {
                console.log("  sqrtPriceX96:", sqrtPriceX96s[i]);
            }
        }
    }
    
    function testSwapWETHForUSDC() public {
        vm.startPrank(user);
        
        // Check multiple pools to find one with liquidity
        uint24[] memory fees = new uint24[](3);
        int24[] memory tickSpacings = new int24[](3);
        
        fees[0] = 500;
        tickSpacings[0] = 10;
        fees[1] = 3000;
        tickSpacings[1] = 60;
        fees[2] = 10000;
        tickSpacings[2] = 200;
        
        (bool[] memory exist, uint128[] memory liquidities, ) = 
            swapper.checkMultiplePools(WETH, USDC, fees, tickSpacings);
        
        // Find pool with liquidity
        uint24 selectedFee;
        int24 selectedTickSpacing;
        bool foundLiquidPool = false;
        
        for (uint256 i = 0; i < fees.length; i++) {
            if (exist[i] && liquidities[i] > 0 && !foundLiquidPool) {
                selectedFee = fees[i];
                selectedTickSpacing = tickSpacings[i];
                foundLiquidPool = true;
                console.log("Found pool with liquidity: Fee", selectedFee, "TickSpacing", uint256(uint24(selectedTickSpacing)));
                break;
            }
        }
        
        // Skip test if no pools have liquidity
        if (!foundLiquidPool) {
            console.log("No pools with liquidity found. Skipping swap test.");
            vm.stopPrank();
            return;
        }
        
        // Approve tokens
        IERC20(WETH).approve(address(swapper), type(uint256).max);
        swapper.approveToken(WETH);
        
        // Get initial balances
        uint256 wethBefore = IERC20(WETH).balanceOf(user);
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        
        console.log("WETH before:", wethBefore);
        console.log("USDC before:", usdcBefore);
        
        // Swap using the pool with liquidity
        uint256 amountOut = swapper.swap(
            WETH,
            USDC,
            selectedFee,
            selectedTickSpacing,
            0.1 ether,
            0 // Set minAmountOut to 0 for testing
        );
        
        // Get final balances
        uint256 wethAfter = IERC20(WETH).balanceOf(user);
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        
        console.log("WETH after:", wethAfter);
        console.log("USDC after:", usdcAfter);
        console.log("USDC received:", amountOut);
        
        vm.stopPrank();
        
        // Assertions
        assertEq(wethBefore - wethAfter, 0.1 ether, "WETH not spent");
        assertGt(usdcAfter, usdcBefore, "USDC not received");
    }
    
    function testSwapUSDCForDAI() public {
        vm.startPrank(user);
        
        // Check multiple pools to find one with liquidity
        // Try different fee/tickSpacing combinations for USDC/DAI
        uint24[] memory fees = new uint24[](3);
        int24[] memory tickSpacings = new int24[](3);
        
        fees[0] = 100;   // 0.01%
        tickSpacings[0] = 1;
        fees[1] = 500;   // 0.05%
        tickSpacings[1] = 10;
        fees[2] = 3000;  // 0.3%
        tickSpacings[2] = 60;
        
        (bool[] memory exist, uint128[] memory liquidities, ) = 
            swapper.checkMultiplePools(USDC, DAI, fees, tickSpacings);
        
        // Find pool with liquidity
        uint24 selectedFee;
        int24 selectedTickSpacing;
        bool foundLiquidPool = false;
        
        for (uint256 i = 0; i < fees.length; i++) {
            if (exist[i] && liquidities[i] > 0 && !foundLiquidPool) {
                selectedFee = fees[i];
                selectedTickSpacing = tickSpacings[i];
                foundLiquidPool = true;
                console.log("Found pool with liquidity: Fee", selectedFee, "TickSpacing", uint256(uint24(selectedTickSpacing)));
                break;
            }
        }
        
        // Skip test if no pools have liquidity
        if (!foundLiquidPool) {
            console.log("No pools with liquidity found. Skipping swap test.");
            vm.stopPrank();
            return;
        }
        
        // Approve tokens
        IERC20(USDC).approve(address(swapper), type(uint256).max);
        swapper.approveToken(USDC);
        
        // Get initial balances
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 daiBefore = IERC20(DAI).balanceOf(user);
        
        console.log("USDC before:", usdcBefore);
        console.log("DAI before:", daiBefore);
        
        // Swap using the pool with liquidity
        uint256 amountOut = swapper.swap(
            USDC,
            DAI,
            selectedFee,
            selectedTickSpacing,
            100e6, // 100 USDC (6 decimals)
            0
        );
        
        // Get final balances
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 daiAfter = IERC20(DAI).balanceOf(user);
        
        console.log("USDC after:", usdcAfter);
        console.log("DAI after:", daiAfter);
        console.log("DAI received:", amountOut);
        
        vm.stopPrank();
        
        // Assertions
        assertEq(usdcBefore - usdcAfter, 100e6, "USDC not spent");
        assertGt(daiAfter, daiBefore, "DAI not received");
    }
    
    function testSwapUSDCForWETH() public {
        vm.startPrank(user);
        
        // Check multiple pools to find one with liquidity
        uint24[] memory fees = new uint24[](3);
        int24[] memory tickSpacings = new int24[](3);
        
        fees[0] = 500;
        tickSpacings[0] = 10;
        fees[1] = 3000;
        tickSpacings[1] = 60;
        fees[2] = 10000;
        tickSpacings[2] = 200;
        
        (bool[] memory exist, uint128[] memory liquidities, ) = 
            swapper.checkMultiplePools(USDC, WETH, fees, tickSpacings);
        
        // Find pool with liquidity
        uint24 selectedFee;
        int24 selectedTickSpacing;
        bool foundLiquidPool = false;
        
        for (uint256 i = 0; i < fees.length; i++) {
            if (exist[i] && liquidities[i] > 0 && !foundLiquidPool) {
                selectedFee = fees[i];
                selectedTickSpacing = tickSpacings[i];
                foundLiquidPool = true;
                console.log("Found pool with liquidity: Fee", selectedFee, "TickSpacing", uint256(uint24(selectedTickSpacing)));
                break;
            }
        }
        
        // Skip test if no pools have liquidity
        if (!foundLiquidPool) {
            console.log("No pools with liquidity found. Skipping swap test.");
            vm.stopPrank();
            return;
        }
        
        // Approve tokens
        IERC20(USDC).approve(address(swapper), type(uint256).max);
        swapper.approveToken(USDC);
        
        // Get initial balances
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 wethBefore = IERC20(WETH).balanceOf(user);
        
        console.log("USDC before:", usdcBefore);
        console.log("WETH before:", wethBefore);
        
        // Swap using the pool with liquidity
        uint256 amountOut = swapper.swap(
            USDC,
            WETH,
            selectedFee,
            selectedTickSpacing,
            100e6, // 100 USDC (6 decimals)
            0
        );
        
        // Get final balances
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 wethAfter = IERC20(WETH).balanceOf(user);
        
        console.log("USDC after:", usdcAfter);
        console.log("WETH after:", wethAfter);
        console.log("WETH received:", amountOut);
        
        vm.stopPrank();
        
        // Assertions
        assertEq(usdcBefore - usdcAfter, 100e6, "USDC not spent");
        assertGt(wethAfter, wethBefore, "WETH not received");
    }
}