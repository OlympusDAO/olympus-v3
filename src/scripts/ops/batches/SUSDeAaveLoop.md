# sUSDe Aave Loop Strategy

## Overview

`SUSDeAaveLoop` is a batch script for the Olympus Yield MS that supports:

- `executeLoop`: open/increase a leveraged sUSDe/USDe loop position on Aave.
- `executeRebalanceWallet`: rebalance collateral split toward 1:1 with wallet-funded actions only.
- `executeUnwindLoop`: run one max-safe unwind iteration that repays USDT debt and releases collateral while preserving a minimum health factor.

The script builds all swap routes and amounts before adding operations to the batch.

## Cache + Replay Workflow

`SUSDeAaveLoop` persists planning inputs in per-flow TOML cache files via `StdConfig`:

- loop path: `./cache/SUSDeAaveLoop-loop.toml`
- unwind path: `./cache/SUSDeAaveLoop-unwind.toml`

The cache is used only for multisig replay determinism:

- `--signonly` writes cache entries from live planning reads.
- `--signature` replays from cache and does not re-quote or re-read planning inputs that were cached.

The script validates replay safety before planning continues:

- cache file exists,
- `createdAt` is fresh (TTL: 300 seconds),
- `chainId` matches current chain,
- `owner` matches current Safe owner,
- `version` and `function` match expected values,
- args fingerprint matches the effective function args.

If validation fails, the script reverts with a recovery hint:

- rerun `--signonly` and reuse the produced signature, or
- clear the cache files in `./cache`.

Cached planning data includes:

- Aave account and reserve snapshots used for sizing,
- Kyber route build outputs per swap leg (`router`, calldata, quoted `amountOut`),
- critical ERC4626 conversions (`convertToAssets`, `convertToShares`) with input/output checks,
- reporting baseline snapshots used in post-step reporting.

Implementation details that matter for idempotency:

- Cache keys are normalized from dotted names (for example `swaps.loop.swap1.router`) to TOML-safe keys (`swaps__loop__swap1__router`) so `StdConfig` does not parse them as nested objects.
- Numeric cache values are stored and read back as fixed-width encoded integers (`abi.encode(uint256)`), not TOML decimals, to avoid precision loss on large 18-decimal values.

## Key Mainnet Addresses

| Component                            | Address                                      |
| ------------------------------------ | -------------------------------------------- |
| Yield MS Safe                        | `0x2075e3b46470cfcE124Daaf52b46Dcf965727Dd1` |
| Aave V3 Pool                         | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| Aave Data Provider                   | `0x41393e5e337606dc3821075Af65AeE84D7688CBD` |
| KyberSwap Router (quoted at runtime) | hardcoded route API + build API              |
| sUSDe                                | `0x9D39A5DE30e57443BfF2A8307A4256c8797A3497` |
| USDe                                 | `0x4c9EDD5852cd905f086C759E8383e09bff1E68B3` |
| USDT                                 | `0xdAC17F958D2ee523a2206206994597C13D831ec7` |

## Functions

### `executeLoop`

Opens or extends the loop in a single batch:

1. Supply sUSDe as collateral.
2. Borrow USDT.
3. Swap USDT -> USDe.
4. Supply parity-capped USDe to Aave (may be zero).
5. Sweep 100% of planned leftover USDe from swap #1 into wallet sUSDe via `IERC4626.deposit` (not supplied to Aave in the same run).
6. Borrow USDT again (sized from the capped USDe supply amount).
7. Swap USDT -> sUSDe (skipped if borrow #2 is zero).

Loop sizing now enforces 1:1 collateral parity protection:

- `susdeSupplyAmount` is never parity-capped (requested amount is honored, or full wallet if arg is `0`).
- USDe supply to Aave is capped from post-sUSDe collateral imbalance:
  - if post-sUSDe is sUSDe-overweight, USDe supply cap = that excess,
  - if post-sUSDe is USDe-overweight, USDe supply cap = `0`.
- actual USDe supplied to Aave = `min(conservativeSwap1USDe, usdeSupplyCapTarget)`.
- post-batch validation reverts if imbalance worsens materially, and also verifies projected vs actual imbalance coherence within drift tolerance.

Optional args (all read from the `executeLoop` function entry in args JSON):

- `susdeSupplyAmount` (default `0`): if `0`, uses full owner sUSDe balance.
- `borrowPercentage` (default `10000`): bps of available borrow capacity, max `10000`.
- `slippageBps` (default `5`): max `100`.
- `minSwap1ValueRatioBps` (default `9990`): minimum value ratio for swap 1.
- `minSwap2ValueRatioBps` (default `9990`): minimum value ratio for swap 2.
- `kyberExcludedSources` (default empty): comma-separated Kyber source IDs to exclude (for example `ekubo-v3`).

Loop still assumes a 1:1 target ratio (`targetSusdeToUsdeRatioWad = 1e18`) and only supports that target.

### `executeRebalanceWallet`

Runs one wallet-funded rebalance iteration without withdrawing Aave collateral:

1. Measure current Aave collateral split (sUSDe value vs USDe value).
2. Compute required shift toward 1:1.
3. If sUSDe is overweight: use wallet USDe first, then optionally swap wallet sUSDe -> USDe, then supply USDe.
4. If USDe is overweight: use wallet sUSDe first, then optionally deposit wallet USDe into sUSDe, then supply sUSDe.

Optional args (all read from the `executeRebalanceWallet` function entry in args JSON):

- `targetSusdeToUsdeRatioWad` (default `1000000000000000000`): currently only `1e18` is supported.
- `ratioToleranceBps` (default `100`): imbalance tolerance in bps of total sUSDe+USDe collateral value.
- `maxRebalanceValueUsde` (default `0`): max USDe value to shift in one run. `0` means no cap.
- `slippageBps` (default `5`): max `100`.
- `kyberExcludedSources` (default empty): comma-separated Kyber source IDs to exclude.

Post-batch validation requires improvement when starting outside tolerance. If a full close is not possible, output explicitly reports partial reduction and the reason.

Backward compatibility aliases for the loop value checks are still accepted:

- `minSwap1QuoteRatioBps`
- `minSwap2QuoteRatioBps`

### `executeUnwindLoop`

Runs one partial unwind iteration with max-safe sizing (no percentage throttle):

1. Swap wallet sUSDe -> USDT and repay USDT debt (wallet-first repay leg).
2. Withdraw safe USDe collateral.
3. Swap withdrawn USDe -> USDT and repay USDT debt.
4. Withdraw safe sUSDe collateral back to wallet.

Unwind stops after Step 4 for this iteration.

Optional args (all read from the `executeUnwindLoop` function entry in args JSON):

- `slippageBps` (default `50`): max `100`.
- `minHealthFactor` (default `1020000000000000000`, i.e. `1.02e18`): must be `>= 1e18`.
- `minSwap1ValueRatioBps` (default `9990`): minimum value ratio for USDe -> USDT swap.
- `kyberExcludedSources` (default empty): comma-separated Kyber source IDs to exclude (for example `ekubo-v3`).

Post-batch validation enforces:

- resulting health factor >= configured minimum,
- debt reduction meets conservative expectation,
- resulting sUSDe wallet balance is not below the conservative floor (after subtracting any wallet sUSDe used in repay leg).

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

## Idempotency Runbook (`--signonly` vs `--signature`)

Recommended operator flow for each function (`executeLoop` or `executeUnwindLoop`):

1. Run `safeBatchV2.sh` with `--signonly` using final args.
2. Submit replay with `--signature` using the same args and signature payload.
3. If replay reverts with cache validation failure, regenerate with a fresh `--signonly` run.

Expected behavior when replaying successfully:

- planning values match the sign-only run,
- quoted swap outputs and calldata are reused from cache,
- replay does not depend on new Kyber route responses or new 4626 planning conversions.

Practical verification signal:

- Compare `Safe tx hash (idempotency key)` and `Multisend calldata hash` across `--signonly` and `--signature --broadcast false`; both should match when replay is fully idempotent.
