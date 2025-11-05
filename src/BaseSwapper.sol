// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UniversalRouter } from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
/// @title BaseSwapper - Uniswap V4 Swapper for Base
/// @notice Swap WETH/USDC and USDC/DAI on Base using Uniswap V4
contract BaseSwapper {
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

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _router,
        address _poolManager,
        address _permit2
    ) {
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
        uint24 lpFee
    ) {
        // Use StateLibrary to get pool info (uses extsload)
        // Note: This will revert if extsload is not supported on the network
        PoolId id = key.toId();
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(poolManager, id);
        exists = sqrtPriceX96 != 0;
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
        
        // Transfer tokens from user to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Determine swap direction
        bool zeroForOne = Currency.unwrap(key.currency0) == tokenIn;

        // Encode the Universal Router command
        // Note: On Base mainnet, 0x10 is V4_SWAP (even though Commands library shows SEAPORT_V1_5)
        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
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
        
        // Second parameter: SETTLE_ALL - specify input currency and max amount (uint256)
        // Use exact amountIn to match documentation example
        params[1] = abi.encode(
            zeroForOne ? key.currency0 : key.currency1,
            uint256(amountIn)
        );
        
        // Third parameter: TAKE_ALL - specify output currency and minimum amount (uint256)
        params[2] = abi.encode(
            zeroForOne ? key.currency1 : key.currency0,
            uint256(minAmountOut) // Convert to uint256 as expected by TAKE_ALL
        );

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 deadline = block.timestamp + 300;
        router.execute(commands, inputs, deadline);

        // Verify and return the output amount
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        amountOut = outputCurrency.balanceOf(address(this));
        
        require(amountOut >= minAmountOut, "Insufficient output amount");

        // Transfer output tokens to user
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
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
}