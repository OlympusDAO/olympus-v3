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

- Verify PriceConfigv2 is enabled
- Verify `price_admin` role granted to DAO MS
- Identify all assets required for OHM pricing
- Prepare price feed and strategy configurations
- Deploy submodules (feeds, strategies)

### 2. Deployment (DAO MS - Same Batch)

```solidity
// Action 1: Upgrade PRICE module
kernel.executeActions(
    Actions.UpgradeModule,
    address(priceV1_2)
);

// Action 2-N: Install submodules
priceConfig.installSubmodule(feedSubmodule1);
priceConfig.installSubmodule(feedSubmodule2);

// Action N+M: Add assets
priceConfig.addAsset(
    ohm,
    storeMovingAverage,
    useMovingAverage,
    movingAverageDuration,
    lastObservationTime,
    initialObservations,
    strategy,
    feeds
);
// ... repeat for other assets
```

### 3. Verification

- Call `price.getCurrentPrice()` — should return valid OHM price
- Call `price.getAssets()` — verify all expected assets configured
- Monitor moving averages for accuracy

## Ongoing Operations

DAO MS can use PriceConfigv2 to:

- Add/remove assets as needed
- Update price feeds and strategies
- Configure moving average settings
- Install/upgrade submodules

No OCG approval required for these operations.
