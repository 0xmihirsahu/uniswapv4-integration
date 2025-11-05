// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UniversalRouter } from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { ActionConstants } from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
/// @title BaseSwapper - Uniswap V4 Swapper for Base
/// @notice Swap WETH/USDC and USDC/DAI on Base using Uniswap V4
contract BaseSwapper is Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    // V4_SWAP is now available in Commands library (0x10)

    /*//////////////////////////////////////////////////////////////
                                IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    UniversalRouter public immutable router;
    IPoolManager public immutable poolManager;
    IPermit2 public immutable permit2;
    
    /*//////////////////////////////////////////////////////////////
                            TOKEN ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed user
    );

    event TokensWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    event ETHWithdrawn(
        address indexed to,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _router,
        address _poolManager,
        address _permit2,
        address _owner
    ) Ownable(_owner) {
        router = UniversalRouter(payable(_router));
        poolManager = IPoolManager(_poolManager);
        permit2 = IPermit2(_permit2);
    }

    /*//////////////////////////////////////////////////////////////
                            POOL UTILITIES
    //////////////////////////////////////////////////////////////*/

    function createPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing
    ) public pure returns (PoolKey memory key) {
        (Currency curr0, Currency curr1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));

        key = PoolKey({
            currency0: curr0,
            currency1: curr1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });
    }

    function poolExists(PoolKey memory key) public view returns (bool exists) {
        // Use StateLibrary to check if pool exists (uses extsload)
        // Note: This will revert if extsload is not supported on the network
        PoolId id = key.toId();
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(poolManager, id);
        exists = sqrtPriceX96 != 0;
    }

    function getPoolInfo(PoolKey memory key) public view returns (
        bool exists,
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee,
        uint128 liquidity
    ) {
        // Use StateLibrary to get pool info (uses extsload)
        // Note: This will revert if extsload is not supported on the network
        PoolId id = key.toId();
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(poolManager, id);
        exists = sqrtPriceX96 != 0;
        if (exists) {
            liquidity = StateLibrary.getLiquidity(poolManager, id);
        }
    }

    /// @notice Check multiple pools with different fee/tickSpacing combinations
    /// @dev Useful for finding which pools have liquidity on Base mainnet
    function checkMultiplePools(
        address tokenA,
        address tokenB,
        uint24[] memory fees,
        int24[] memory tickSpacings
    ) public view returns (
        bool[] memory exist,
        uint128[] memory liquidities,
        uint160[] memory sqrtPriceX96s
    ) {
        require(fees.length == tickSpacings.length, "Array length mismatch");
        
        exist = new bool[](fees.length);
        liquidities = new uint128[](fees.length);
        sqrtPriceX96s = new uint160[](fees.length);
        
        for (uint256 i = 0; i < fees.length; i++) {
            PoolKey memory key = createPoolKey(tokenA, tokenB, fees[i], tickSpacings[i]);
            (bool poolExists, uint160 sqrtPriceX96, , , , uint128 liquidity) = getPoolInfo(key);
            exist[i] = poolExists;
            liquidities[i] = liquidity;
            sqrtPriceX96s[i] = sqrtPriceX96;
        }
    }

    /*//////////////////////////////////////////////////////////////
                              APPROVALS
    //////////////////////////////////////////////////////////////*/

    function approveToken(address token) external {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(
            token,
            address(router),
            type(uint160).max,
            uint48(block.timestamp + 365 days)
        );
    }

    function approveAllTokens() external {
        address[3] memory tokens = [WETH, USDC, DAI];
        
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(address(permit2), type(uint256).max);
            permit2.approve(
                tokens[i],
                address(router),
                type(uint160).max,
                uint48(block.timestamp + 365 days)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CORE SWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    function swap(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        uint128 amountIn,
        uint128 minAmountOut
    ) public returns (uint256 amountOut) {
        PoolKey memory key = createPoolKey(tokenIn, tokenOut, fee, tickSpacing);
        
        // Check if pool exists and get current price
        // Note: This will revert if pool doesn't exist
        PoolId id = key.toId();
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(poolManager, id);
        
        // Check if pool has liquidity
        uint128 liquidity = StateLibrary.getLiquidity(poolManager, id);
        if (liquidity == 0) {
            revert("Pool exists but has no liquidity. Cannot execute swap.");
        }
        
        // Determine swap direction
        bool zeroForOne = Currency.unwrap(key.currency0) == tokenIn;
        
        // Check if pool is at price limit (MIN_SQRT_PRICE + 1 for zeroForOne, MAX_SQRT_PRICE - 1 for oneForZero)
        // If so, the swap will fail with PriceLimitAlreadyExceeded
        uint160 minPrice = TickMath.MIN_SQRT_PRICE + 1;
        uint160 maxPrice = TickMath.MAX_SQRT_PRICE - 1;
        
        if (zeroForOne && sqrtPriceX96 <= minPrice) {
            revert("Pool is at minimum price limit. Cannot swap in this direction. Try swapping in opposite direction.");
        }
        if (!zeroForOne && sqrtPriceX96 >= maxPrice) {
            revert("Pool is at maximum price limit. Cannot swap in this direction. Try swapping in opposite direction.");
        }
        
        // Transfer tokens from user to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Record balances before swap (after receiving tokens from user)
        uint256 balanceBeforeIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 userBalanceBeforeOut = IERC20(tokenOut).balanceOf(msg.sender);
        
        // Ensure Permit2 is approved to pull tokens from BaseSwapper
        // SETTLE_ALL will pull tokens from msgSender() (BaseSwapper) via Permit2
        // If tokens aren't approved, the swap will fail
        // Note: approveToken should be called before swap, or we can approve here
        // For now, we'll ensure Permit2 has approval (caller should call approveToken first)
        
        // Encode the Universal Router command
        // Note: On Base mainnet, 0x10 is V4_SWAP (even though Commands library shows SEAPORT_V1_5)
        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        // Use SETTLE_ALL which pulls tokens from msgSender() (BaseSwapper) via Permit2
        // This ensures tokens stay in BaseSwapper if swap fails (no liquidity)
        // Following the official Uniswap V4 documentation pattern
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE) // Use TAKE to specify recipient explicitly
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        
        // First parameter: swap configuration using ExactInputSingleParams struct
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        
        // Second parameter: SETTLE_ALL - specify input currency and max amount
        // SETTLE_ALL will pull tokens from msgSender() (BaseSwapper) via Permit2
        // It only settles the actual debt created by the swap
        // If swap produces 0 output (no liquidity), debt is 0, so it won't pull any tokens
        params[1] = abi.encode(
            zeroForOne ? key.currency0 : key.currency1,
            uint256(amountIn) // Max amount to settle (should match or exceed amountIn)
        );
        
        // Third parameter: TAKE - specify output currency, recipient (user), and amount
        // Use OPEN_DELTA (0) to take all available credit
        // Send tokens directly to the user (msg.sender)
        params[2] = abi.encode(
            zeroForOne ? key.currency1 : key.currency0,
            msg.sender, // Send tokens directly to the user
            uint256(0) // OPEN_DELTA - take all available credit
        );

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 deadline = block.timestamp + 300;
        router.execute(commands, inputs, deadline);

        // Verify output amount by checking user's balance
        // Note: Tokens are sent directly to user via TAKE action
        uint256 userBalanceAfter = IERC20(tokenOut).balanceOf(msg.sender);
        amountOut = userBalanceAfter > userBalanceBeforeOut ? userBalanceAfter - userBalanceBeforeOut : 0;
        
        // Check if swap produced zero output (no liquidity)
        if (amountOut == 0) {
            // With SETTLE_ALL, if swap produces 0 output (no debt), no tokens are pulled
            // Tokens remain in BaseSwapper and should be refunded to the user
            uint256 balanceAfterIn = IERC20(tokenIn).balanceOf(address(this));
            
            // If tokens are still in BaseSwapper, refund them to the user
            if (balanceAfterIn >= amountIn) {
                // Refund tokens to user since swap failed
                IERC20(tokenIn).transfer(msg.sender, amountIn);
                revert("Swap produced zero output - pool has no liquidity. Tokens refunded.");
            }
            
            // If tokens were consumed but no output, the swap failed
            revert("Swap produced zero output - pool has no liquidity available for this swap");
        }
        
        // Verify minimum output amount
        require(amountOut >= minAmountOut, "Insufficient output amount");
        
        // Check that input tokens were consumed (pulled by SETTLE_ALL)
        uint256 balanceAfterIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 consumed = balanceBeforeIn > balanceAfterIn ? balanceBeforeIn - balanceAfterIn : 0;
        require(consumed == amountIn, "Input tokens not consumed");
        
        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, msg.sender);
        
        return amountOut;
    }

    /*//////////////////////////////////////////////////////////////
                        CONVENIENCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function swapWETHForUSDC(
        uint128 amountIn,
        uint128 minAmountOut
    ) external returns (uint256) {
        return swap(WETH, USDC, 3000, 60, amountIn, minAmountOut);
    }

    function swapUSDCForWETH(
        uint128 amountIn,
        uint128 minAmountOut
    ) external returns (uint256) {
        return swap(USDC, WETH, 3000, 60, amountIn, minAmountOut);
    }

    function swapUSDCForDAI(
        uint128 amountIn,
        uint128 minAmountOut
    ) external returns (uint256) {
        return swap(USDC, DAI, 100, 1, amountIn, minAmountOut);
    }

    function swapDAIForUSDC(
        uint128 amountIn,
        uint128 minAmountOut
    ) external returns (uint256) {
        return swap(DAI, USDC, 100, 1, amountIn, minAmountOut);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraw ERC20 tokens from the contract (owner only)
    /// @param token The address of the ERC20 token to withdraw
    /// @param to The address to send the tokens to
    /// @param amount The amount of tokens to withdraw (use 0 to withdraw all)
    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        
        require(withdrawAmount > 0, "No tokens to withdraw");
        require(withdrawAmount <= balance, "Insufficient balance");
        
        IERC20(token).transfer(to, withdrawAmount);
        
        emit TokensWithdrawn(token, to, withdrawAmount);
    }

    /// @notice Withdraw ETH from the contract (owner only)
    /// @param to The address to send the ETH to
    /// @param amount The amount of ETH to withdraw (use 0 to withdraw all)
    function withdrawETH(
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        
        uint256 balance = address(this).balance;
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        
        require(withdrawAmount > 0, "No ETH to withdraw");
        require(withdrawAmount <= balance, "Insufficient balance");
        
        (bool success, ) = to.call{value: withdrawAmount}("");
        require(success, "ETH transfer failed");
        
        emit ETHWithdrawn(to, withdrawAmount);
    }
}