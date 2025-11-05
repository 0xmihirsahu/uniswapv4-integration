# Uniswap V4 Swapper for Base

A simple Uniswap V4 swapping contract for WETH/USDC and USDC/DAI on Base mainnet using the Universal Router.

## Setup

1. Install dependencies:
```bash
forge install
```

2. Set environment variables:
```bash
export PRIVATE_KEY=your_private_key
export SWAPPER_ADDRESS=your_deployed_swapper_address  # Set after deployment
```

## Commands

### Build
```bash
forge build
```

### Test
```bash
# Test on Base mainnet fork
forge test --rpc-url base

# Test specific function
forge test --match-test testCheckMultiplePools --rpc-url base
```

### Deploy
```bash
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
```

### Interact
```bash
# Swap USDC for WETH (automatically finds pool with liquidity)
forge script script/Interact.s.sol --rpc-url base --broadcast
```


## Contract Addresses (Base Mainnet)
- **BaseSwapper**: `0xb7BF1cF19Df884dFC1715467d09c6F0c76D9Dc06`

- **Universal Router**: `0x6fF5693b99212Da76ad316178A184AB56D299b43`
- **PoolManager**: `0x498581fF718922c3f8e6A244956aF099B2652b2b`
- **Permit2**: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
