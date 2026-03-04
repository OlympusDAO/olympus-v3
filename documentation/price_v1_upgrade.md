# PRICE v1 → v1.2 Upgrade Rollout

## Problem Statement

Upgrading PRICE v1 → v1.2 requires configuring new assets (OHM + underlying reserve assets) for the module to function. Without configuration, all price calls revert with `PRICE_AssetNotApproved`, breaking protocol operations.

## Constraints

- **Zero downtime required** — PRICE is critical for Heart and other systems

## Approaches Considered

### 1. Constructor Arguments (Not Feasible)

Pass asset configurations through the constructor.

**Why it fails:** Triggers "stack too deep" compiler error in v1_2:

```text
Compiler error (/solidity/libyul/backends/evm/AsmCodeGen.cpp:68): Stack too deep
```

This is **not** the EVM stack limit — it's a Yul assembler internal limit during code generation. The issue occurs specifically in v1_2 because:

- v1_2 inherits from v2 (multi-asset pricing system)
- v1_2 implements PRICEv1 compatibility interface (single-asset OHM functions)
- Complex nested array ABI decoding through multiple inheritance layers exceeds Yul's internal stack

v2 alone handles these constructor parameters fine. The problem is unique to v1_2's inheritance structure.

### 2. Immutable Initializer Pattern (Works, but unnecessary complexity)

Add an `initialize()` function gated to an immutable `initializer` address. Deploy → initialize → install.

**Why we rejected it:** Adds unnecessary contract complexity and code size. PriceConfigv2 enabled by default achieves the same goal more simply.

### 3. Same-Batch Configuration with PriceConfigv2 (Chosen)

Modify PriceConfigv2 to be enabled by default, and DAO MS has `price_admin` role. Configure assets in the same transaction batch as the module upgrade.

**Why it works:**

- All actions in same transaction → no Heart heartbeat between operations
- PriceConfigv2 already has `price_admin` permissions
- No additional contract complexity or code size pressure

## Rollout Steps

### 1. Pre-Deployment

- Verify `price_admin` role granted to DAO MS
- Identify all assets required for OHM pricing
- Prepare price feed addresses and configuration parameters

**Required Contracts:**

- `OlympusPricev1_2` - PRICE v1.2 module
- `ChainlinkPriceFeeds` - Chainlink price feed submodule
- `PythPriceFeeds` - Pyth price feed submodule
- `UniswapV3Price` - Uniswap V3 price submodule
- `ERC4626Price` - ERC4626 price submodule
- `SimplePriceFeedStrategy` - Price strategy submodule
- `PriceConfigv2` - Configuration policy (auto-enabled on installation)

### 2. Deployment

**Deployment sequence file:** `src/scripts/deploy/savedDeployments/price_v1_2_deploy.json`

**Deployment script:** `src/scripts/deploy/DeployV3.s.sol`

```bash
./shell/deployV3.sh \
  --account <wallet> \
  --sequence src/scripts/deploy/savedDeployments/price_v1_2_deploy.json \
  --chain mainnet \
  --broadcast true \
  --verify true
```

This deploys:

1. PRICE v1.2 module (`OlympusPricev1_2`)
2. 5 submodules (ChainlinkPriceFeeds, PythPriceFeeds, UniswapV3Price, ERC4626Price, SimplePriceFeedStrategy)
3. PriceConfigv2 policy (auto-enabled on installation)

### 3. MS Batch Script for PRICE Configuration

**Batch script:** `src/scripts/ops/batches/ConfigurePriceV1_2.sol`

This batch installs all 5 submodules and configures 4 assets (USDS, sUSDS, wETH, OHM) in a single transaction.

Create an args file with price feed addresses (JSON format with `.functions[].name` and `.functions[].args` structure).

```bash
./shell/safeBatchV2.sh \
  --contract ConfigurePriceV1_2 \
  --function configurePriceV1_2 \
  --chain mainnet \
  --multisig true \
  --broadcast true \
  --args <args-file.json>
```

**Batch actions:**

1. Install 5 submodules via `PriceConfigv2.installSubmodule()`
2. Configure USDS (Chainlink + RedStone + Pyth feeds, deviation-based strategy)
3. Configure sUSDS (ERC4626 wrapper, uses USDS price)
4. Configure wETH (Chainlink + RedStone + Pyth feeds, deviation-based strategy)
5. Configure OHM (2x Uniswap V3 feeds, average strategy, 7-day moving average)

**Automatic validation:** The batch script simulates a full 24-hour Heart cycle (3 beats) to validate PRICE configuration before proposing the batch.

### 4. Oracle Factories (If Needed)

If oracle factory policies are required for external protocol integrations (Chainlink, Morpho, ERC7726), see **[Oracle Factories and Policies](oracle_factories.md)** for the complete deployment flow.

**Note:** Oracle factories require PRICE v1.2+ (already satisfied by this upgrade).

### 5. Verification

Verification happens automatically as part of the batch script execution (full Heart cycle simulation).

Manual verification (optional):

- Call `price.getCurrentPrice()` — should return valid OHM price
- Call `price.getAssets()` — verify all expected assets configured
- Check moving averages are accurate

## Ongoing Operations

DAO MS can use **PriceConfigv2** (`src/policies/price/PriceConfig.v2.sol`) to:

- Add/remove assets via `addAssetPrice()` / `removeAssetPrice()`
- Update feeds and strategies via `updateAsset()`
- Install/upgrade submodules via `installSubmodule()` / `upgradeSubmodule()`

No OCG approval required — only `price_admin` role.

## File Reference

| File                                                         | Purpose                                             |
| ------------------------------------------------------------ | --------------------------------------------------- |
| `shell/deployV3.sh`                                          | Deployment shell script                             |
| `src/scripts/deploy/DeployV3.s.sol`                          | Deployment script                                   |
| `src/scripts/deploy/savedDeployments/price_v1_2_deploy.json` | Deployment sequence                                 |
| `shell/safeBatchV2.sh`                                       | Batch execution shell script                        |
| `src/scripts/ops/batches/ConfigurePriceV1_2.sol`             | PRICE configuration batch                           |
| `src/policies/price/PriceConfig.v2.sol`                      | Configuration policy (auto-enabled on installation) |
| `src/modules/PRICE/OlympusPrice.v1_2.sol`                    | PRICE v1.2 module                                   |

For oracle-related files, see **[Oracle Factories and Policies](oracle_factories.md)**.
