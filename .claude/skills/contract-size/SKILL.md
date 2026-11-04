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

> **Measuring a contract that is already restricted.** If the contract has an entry in
> `compilation_restrictions`, `--optimizer-runs` does not reach it: the restriction rejects the
> default profile, Forge falls back to a profile from `additional_compiler_profiles`, and every
> value reports the same size. Remove the restriction entry for the duration of the measurement and
> put it back afterwards. Confirm the setting that was actually used by reading
> `.metadata.settings.optimizer.runs` from the artifact.

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

Size does not always grow monotonically with runs, so measure every candidate instead of
interpolating between two of them.

**Example binary search** (`Operator.sol`, solc 0.8.36):

- runs=10 ✅ (24,001 bytes)
- runs=100 ✅ (24,067 bytes)
- runs=400 ✅ (24,179 bytes)
- runs=10000 ❌ (28,863 bytes) ← narrow between 400 and 10000 from here

### Step 3: Update Configuration

Once optimal runs found, offer to update:

**foundry.toml** (restriction plus the profile that satisfies it):

```toml
[profile.default]
optimizer_runs = 10000

# A restriction selects a profile, it does not carry settings on its own. Forge uses the default
# profile when that satisfies the restriction, otherwise the alphabetically first entry here that
# does. With no satisfying entry the build fails: "Missing profile satisfying settings
# restrictions".
additional_compiler_profiles = [{ name = "ten-runs", optimizer_runs = 10 }]
compilation_restrictions = [{ paths = "src/policies/Operator.sol", optimizer_runs = 10 }]
```

Two properties decide whether a new restriction is safe to add:

- `optimizer_runs` matches exactly. Use `min_optimizer_runs` or `max_optimizer_runs` for a range.
- A restriction applies to the whole connected import graph, not just the file it names. Every
  contract a script or test reaches through that file compiles with the same settings. Two files
  restricted to different exact values in one graph fail the build with "Found incompatible
  settings restrictions", which is why deployment scripts avoid importing restricted contracts.

`package.json` needs no change: `pnpm run size` reads the settings from `foundry.toml`.

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

## Operator.sol

The repository default is `optimizer_runs = 10000`, and `Operator.sol` does not fit at that setting. `foundry.toml` restricts it to `optimizer_runs = 10` and declares the `ten-runs` profile that satisfies the restriction. Measured sizes are in the binary search example above.

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
