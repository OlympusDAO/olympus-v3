# Update Emergency Config

This skill helps you update the emergency shutdown configuration when adding or modifying emergency components.

## File Structure Overview

| File | Purpose | Change Frequency |
|------|---------|------------------|
| `documentation/emergency/emergency-config.schema.json` | Validation rules | Rarely (only when adding new fields) |
| `documentation/emergency/emergency-config.json` | Components, addresses, chains | On every new contract |
| `documentation/emergency/emergency-abis.json` | ABI definitions for shutdown functions | Only when new function pattern |
| `shell/validate-emergency-config.js` | Validation script | Rarely |

## Available ABI Patterns

Most new contracts use existing ABI patterns. Check this table before adding new ABIs:

| ABI Key | Functions | Used By |
|---------|-----------|---------|
| `emergency` | `shutdownWithdrawals()`, `shutdownMinting()`, `shutdown()`, `restart()` | Emergency policy |
| `periphery_enabler` | `disable(bytes)`, `enable(bytes)` | Heart, ConvertibleDeposits, CCIPBridge, CCIPTokenPool, ReserveWrapper, and most new contracts |
| `cooler_v2` | `setBorrowPaused(bool)`, `setLiquidationsPaused(bool)` | CoolerV2 |
| `cross_chain_bridge` | `setBridgeStatus(bool)` | CrossChainBridge (LayerZero) |
| `reserve_migrator` | `activate()`, `deactivate()` | ReserveMigrator |
| `yield_repurchase_facility` | `shutdown(address[])` | YieldRepurchaseFacility |
| `emission_manager` | `shutdown()`, `restart()` | EmissionManager |
| `ccip_lock_release_pool` | `withdrawLiquidity(uint256)` | CCIPLockReleaseTokenPool (mainnet) |
| `bond_manager` | `emergencyShutdownFixedExpiryMarket(uint256)` | BondManager (manual only) |

**Note:** Most new contracts implement `IEnabler` interface and use `periphery_enabler` ABI. You typically don't need to add new ABIs.

## Adding a New Emergency Component

### Step 1: Create the Solidity Batch Script

Create a new file in `src/scripts/emergency/YourComponent.sol`:

```solidity
// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {IEmergencyBatch} from "src/scripts/emergency/IEmergencyBatch.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

contract YourComponent is BatchScriptV2, IEmergencyBatch {
    function run(
        bool signOnly_,
        string memory argsFilePath_,
        string memory ledgerDerivationPath_,
        bytes memory signature_
    )
        external
        override
        setUpEmergency(signOnly_, argsFilePath_, ledgerDerivationPath_, signature_)
        // OR use setUp(true, ...) for DAO MS controlled contracts
    {
        _validateArgsFileEmpty(argsFilePath_);

        address contractAddress = _envAddressNotZero("olympus.policies.YourContract");
        addToBatch(contractAddress, abi.encodeWithSelector(IEnabler.disable.selector, ""));

        proposeBatch();
    }
}
```

**Multisig Selection:**
- `setUpEmergency(...)` - Uses Emergency MS (faster, for critical issues)
- `setUp(true, ...)` - Uses DAO MS (requires governance)

### Step 2: Add Contract Address to env.json

Add the contract address to `src/scripts/env.json` under the appropriate chain:

```json
{
  "current": {
    "mainnet": {
      "olympus": {
        "policies": {
          "YourContract": "0x..."
        }
      }
    }
  }
}
```

### Step 3: Update emergency-config.json

**3.1** Add to `contractRegistry`:
```json
"contractRegistry": [
  "Emergency",
  "CoolerV2",
  "YourContract"
]
```

**3.2** Add contract address to `chains.mainnet.contracts` (and other chains):
```json
"chains": {
  "mainnet": {
    "contracts": {
      "YourContract": "0x..."
    }
  }
}
```

**3.3** Add new component to `components` array:
```json
{
  "id": "your-component",
  "name": "Your Component Name",
  "description": "What this shutdown does",
  "category": "lending|treasury|bridge|emissions|core|reserve",
  "severity": "critical|high|medium|low",
  "owner": "emergency|dao",
  "shutdownCriteria": [
    "When to trigger this shutdown"
  ],
  "calls": [
    {
      "contractKey": "olympus.policies.YourContract",
      "function": "disable",
      "signature": "disable(bytes)",
      "args": [
        { "name": "disableData_", "type": "bytes", "value": "" }
      ],
      "abi": "periphery_enabler"
    }
  ],
  "availableOn": ["mainnet", "sepolia"],
  "postShutdownSteps": [
    "Steps to take after shutdown"
  ],
  "batchScript": "src/scripts/emergency/YourComponent.sol"
}
```

### Step 4: Add ABI (only if new function pattern)

**Skip this step** if your contract uses `disable(bytes)` - it's already in `periphery_enabler`.

Only add new ABI if your contract has a unique shutdown function:

```json
{
  "your_new_abi": [
    {
      "inputs": [{ "internalType": "uint256", "name": "param_", "type": "uint256" }],
      "name": "customShutdown",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    }
  ]
}
```

### Step 5: Update version and timestamp

In `emergency-config.json`:
```json
{
  "version": "1.1.0",
  "lastUpdated": "2025-01-28T00:00:00Z"
}
```

### Step 6: Validate

```bash
node shell/validate-emergency-config.js
```

## Quick Reference: Component Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique kebab-case identifier |
| `name` | Yes | Human-readable name |
| `description` | Yes | What the shutdown does |
| `category` | Yes | `treasury`, `lending`, `bridge`, `emissions`, `core`, `reserve` |
| `severity` | Yes | `critical`, `high`, `medium`, `low` |
| `owner` | Yes | `emergency` (Emergency MS) or `dao` (DAO MS) |
| `calls` | Yes | Array of function calls |
| `availableOn` | Yes | Array of chain names |
| `shutdownCriteria` | No | When to trigger shutdown |
| `postShutdownSteps` | No | Steps after shutdown |
| `dependencies` | No | Other component IDs to shutdown together |
| `batchScript` | No | Path to Solidity script |

## Modifying an Existing Component

1. Find the component in `emergency-config.json` by its `id`
2. Update the relevant fields
3. Bump `version` (patch for fixes, minor for new features)
4. Update `lastUpdated`
5. Run validation
6. Update the Solidity script if function calls changed

## Adding a New Chain

1. Add chain config to `chains` in emergency-config.json:

```json
{
  "chains": {
    "newchain": {
      "chainId": 12345,
      "multisigs": {
        "emergency": "0x...",
        "dao": "0x..."
      },
      "contracts": {
        "Emergency": "0x...",
        "CrossChainBridge": "0x..."
      }
    }
  }
}
```

2. Update `availableOn` for relevant components
3. Add addresses to `src/scripts/env.json`
4. Run validation

## Validation Checklist

Before committing changes:

- [ ] Run `node shell/validate-emergency-config.js`
- [ ] All new contracts are in `contractRegistry`
- [ ] All ABI keys exist in `emergency-abis.json`
- [ ] All chains in `availableOn` exist in `chains`
- [ ] Contract addresses added to relevant chains
- [ ] `lastUpdated` and `version` fields updated
- [ ] Solidity script tested with `--dry-run`

## Common Issues

### "Unknown ABI reference"
Check the ABI patterns table above. Most contracts use `periphery_enabler`. Only add new ABI if truly unique function.

### "Unknown chain in availableOn"
Add the chain to `chains` object or remove from `availableOn`.

### "Duplicate component ID"
Each component must have a unique kebab-case `id`.

### "Invalid address format"
Addresses must be 42 characters: `0x` + 40 hex characters.

### "Contract in registry has no component"
Either add a component for the contract or remove it from `contractRegistry`.
