# sUSDe Aave Loop Strategy

## Overview

`SUSDeAaveLoop` is a batch script for the Olympus Yield MS that supports:

-   `executeLoop`: open/increase a leveraged sUSDe/USDe loop position on Aave.
-   `executeUnwindLoop`: run one max-safe unwind iteration that repays USDT debt and releases collateral while preserving a minimum health factor.

The script builds all swap routes and amounts before adding operations to the batch.

## Key Mainnet Addresses

| Component                            | Address                                      |
| ------------------------------------ | -------------------------------------------- |
| Yield MS Safe                        | `0x2075e3b46470cfcE124Daaf52b46Dcf965727Dd1` |
| Aave V3 Pool                         | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| Aave Data Provider                   | `0x41393e5e337606dc3821075Af65AeE84D7688CBD` |
| KyberSwap Router (quoted at runtime) | hardcoded route API + build API              |
| sUSDe                                | `0x9D39A5DE30E57443BfF2A8307A4256c8797A3497` |
| USDe                                 | `0x4c9EDD5852cd905f086C759E8383e09bff1E68B3` |
| USDT                                 | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |

## Functions

### `executeLoop`

Opens or extends the loop in a single batch:

1. Supply sUSDe as collateral.
2. Borrow USDT.
3. Swap USDT -> USDe.
4. Supply USDe as collateral.
5. Borrow USDT again.
6. Swap USDT -> sUSDe.

Optional args (all read from the `executeLoop` function entry in args JSON):

-   `susdeSupplyAmount` (default `0`): if `0`, uses full owner sUSDe balance.
-   `borrowPercentage` (default `10000`): bps of available borrow capacity, max `10000`.
-   `slippageBps` (default `5`): max `100`.
-   `minSwap1ValueRatioBps` (default `9990`): minimum value ratio for swap 1.
-   `minSwap2ValueRatioBps` (default `9990`): minimum value ratio for swap 2.
-   `kyberExcludedSources` (default empty): comma-separated Kyber source IDs to exclude (for example `ekubo-v3`).

Backward compatibility aliases for the loop value checks are still accepted:

-   `minSwap1QuoteRatioBps`
-   `minSwap2QuoteRatioBps`

### `executeUnwindLoop`

Runs one partial unwind iteration with max-safe sizing (no percentage throttle):

1. Swap wallet sUSDe -> USDT and repay USDT debt (wallet-first repay leg).
2. Withdraw safe USDe collateral.
3. Swap withdrawn USDe -> USDT and repay USDT debt.
4. Withdraw safe sUSDe collateral back to wallet.

Unwind stops after Step 4 for this iteration.

Optional args (all read from the `executeUnwindLoop` function entry in args JSON):

-   `slippageBps` (default `50`): max `100`.
-   `minHealthFactor` (default `1020000000000000000`, i.e. `1.02e18`): must be `>= 1e18`.
-   `minSwap1ValueRatioBps` (default `9990`): minimum value ratio for USDe -> USDT swap.
-   `kyberExcludedSources` (default empty): comma-separated Kyber source IDs to exclude (for example `ekubo-v3`).

Post-batch validation enforces:

-   resulting health factor >= configured minimum,
-   debt reduction meets conservative expectation,
-   resulting sUSDe wallet balance is not below the conservative floor (after subtracting any wallet sUSDe used in repay leg).

## Args File Format

`SUSDeAaveLoop` reads args by function name, not by function index.

Example: `src/scripts/ops/batches/args/SUSDeAaveLoop.json`

```json
{
    "functions": [
        {
            "args": {
                "borrowPercentage": "9000",
                "kyberExcludedSources": "ekubo-v3",
                "slippageBps": "50"
            },
            "name": "executeLoop"
        },
        {
            "args": {
                "kyberExcludedSources": "ekubo-v3",
                "minHealthFactor": "1020000000000000000",
                "minSwap1ValueRatioBps": "9990",
                "slippageBps": "50"
            },
            "name": "executeUnwindLoop"
        }
    ]
}
```

Args support either numeric JSON values or quoted numeric strings.

## Build

```bash
forge build --contracts src/scripts/ops/batches/SUSDeAaveLoop.sol
```

## Run via `safeBatchV2.sh`

Loop:

```bash
./shell/safeBatchV2.sh \
    --contract SUSDeAaveLoop \
    --function executeLoop \
    --account [account] \
    --multisig true \
    --broadcast true \
    --args src/scripts/ops/batches/args/SUSDeAaveLoop.json \
    --chain mainnet
```

Unwind iteration:

```bash
./shell/safeBatchV2.sh \
    --contract SUSDeAaveLoop \
    --function executeUnwindLoop \
    --account [account] \
    --multisig true \
    --broadcast true \
    --args src/scripts/ops/batches/args/SUSDeAaveLoop.json \
    --chain mainnet
```
