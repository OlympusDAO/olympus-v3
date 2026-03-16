---
description: Check contract bytecode sizes and find optimal optimizer runs
---

# Contract Size Checker

Check contract bytecode sizes against EIP limits and find optimal optimizer settings.

## Quick Commands

**Check single contract size:**

```bash
forge build --sizes --contracts src/path/to/Contract.sol
```

**Check with specific optimizer runs:**

```bash
forge build --sizes --optimizer-runs <N> --contracts src/path/to/Contract.sol
```

**Check all contracts (existing script):**

```bash
pnpm run size
```

## Understanding Output

| Column              | Description         | Limit              |
| ------------------- | ------------------- | ------------------ |
| Runtime Size (B)    | Deployed bytecode   | 24,576 (EIP-170)   |
| Initcode Size (B)   | Deployment bytecode | 49,152 (EIP-3860)  |
| Runtime Margin (B)  | Bytes remaining     | Negative = exceeds |
| Initcode Margin (B) | Bytes remaining     | Negative = exceeds |

**Key metric:** Runtime Size must stay under 24,576 bytes.

## When Contract Exceeds Limit

### Step 1: Check Minimum Viable

First verify the contract can fit at all:

```bash
forge build --sizes --optimizer-runs 2 --contracts src/path/to/Contract.sol
```

If it still exceeds at runs=2, the contract needs refactoring (not optimizer tuning).

### Step 2: Binary Search for Optimal Runs

Find the **highest** optimizer runs that keeps bytecode under 24,576 bytes. Higher runs = better runtime gas efficiency.

**Search sequence:** 2 → 10 → 50 → 100 → 500 → 1000 → 5000 → 10000

```bash
# Try progressively higher runs
forge build --sizes --optimizer-runs 10 --contracts src/path/to/Contract.sol
forge build --sizes --optimizer-runs 50 --contracts src/path/to/Contract.sol
# ... continue until it exceeds, then binary search between last two values
```

**Example binary search:**

- runs=10 ✅ (24,561 bytes)
- runs=50 ❌ (24,583 bytes)
- runs=20 ❌ (24,580 bytes)
- runs=15 ✅ (24,565 bytes) ← **optimal**

### Step 3: Update Configuration

Once optimal runs found, offer to update:

**foundry.toml** (contract-specific profile):

```toml
[profile.default]
optimizer_runs = 10000 # default

# Add specific profile for large contract
additional_compiler_profiles = [{ name = "operator", optimizer_runs = 15 }]

[profile.operator]
via_ir = true
```

**package.json** (add to size script if needed):

```json
{
    "scripts": {
        "size": "forge build --sizes && forge build --sizes --optimizer-runs 10 --contracts src/policies/Operator.sol"
    }
}
```

## EIP Limits Reference

| EIP      | Limit        | Description               |
| -------- | ------------ | ------------------------- |
| EIP-170  | 24,576 bytes | Max deployed bytecode     |
| EIP-3860 | 49,152 bytes | Max initcode (deployment) |

Both limits are hard constraints on mainnet.

## Optimizer Runs Trade-off

| Runs              | Bytecode Size | Runtime Gas | Best For                    |
| ----------------- | ------------- | ----------- | --------------------------- |
| Low (1-10)        | Smaller       | Higher      | Large contracts near limit  |
| Medium (100-1000) | Medium        | Medium      | Balanced                    |
| High (10000)      | Larger        | Lower       | Frequently called functions |

**Goal:** Use the highest runs that keeps bytecode under 24,576 bytes.

## Example: Operator.sol

| Runs | Runtime Size | Under Limit?     |
| ---- | ------------ | ---------------- |
| 1    | 24,597       | ❌ (anomaly)     |
| 2-4  | 24,540       | ✅               |
| 10   | 24,561       | ✅               |
| 15   | 24,565       | ✅ **(optimal)** |
| 20+  | 24,583+      | ❌               |

The repository default is `optimizer_runs = 10000`; `Operator.sol` is a bytecode-size exception compiled with `optimizer_runs = 10` via the `ten-runs` profile in `foundry.toml`.

## Workflow Summary

1. Run `forge build --sizes --contracts <path>` to check current size
2. If exceeds limit, try `--optimizer-runs 2` to verify it can fit
3. Binary search: 2 → 10 → 50 → 100 → 500 → 1000 → 5000 → 10000
4. Find highest runs under 24,576 bytes
5. Offer to update `foundry.toml` with optimal setting

## Agent Instructions

When a contract exceeds the bytecode limit, you MUST:

1. **Immediately start binary search** - Don't just report the issue, solve it
2. **Run commands to find optimal runs** - Start with runs=2, then work up
3. **Report findings in a table** showing each run value and result
4. **Offer to update foundry.toml** once optimal runs found

**Example interaction:**

```text
User: Check src/modules/PRICE/OlympusPrice.v2.sol

Agent: Running size check...

Contract exceeds 24,576 byte limit. Finding optimal optimizer runs...

| Runs | Runtime Size | Margin | Under Limit? |
|------|-------------|--------|--------------|
| 2    | 24,540      | +36    | ✅ |
| 10   | 24,561      | +15    | ✅ |
| 50   | 24,583      | -7     | ❌ |
| 20   | 24,580      | -4     | ❌ |
| 15   | 24,565      | +11    | ✅ |

**Optimal: 15 runs** (highest value under limit with safety margin)

Would you like me to update foundry.toml with a compiler profile for this contract?
```

**Important:** Always run the binary search commands when a contract exceeds the limit. Do not just suggest "try lower optimizer runs" - actually run the commands and find the optimal value.
