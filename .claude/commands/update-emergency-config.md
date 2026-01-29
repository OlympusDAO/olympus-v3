# Update Emergency Config

This skill updates `emergency-config.json` based on an existing Solidity emergency script and `env.json`.

## Prerequisites

Before using this skill, ensure:
1. The Solidity batch script exists in `src/scripts/emergency/`
2. Contract addresses are deployed and present in `src/scripts/env.json`

## Workflow

```
[Solidity script exists] + [Contract deployed in env.json]
                    ↓
         Run this skill with script path
                    ↓
         Parses script → extracts calls, owner
                    ↓
         Reads env.json → gets addresses per chain
                    ↓
         Generates component for emergency-config.json
                    ↓
         Asks for metadata (severity, category, etc.)
                    ↓
         Updates emergency-config.json
                    ↓
         Runs validation
```

## Usage

```
/update-emergency-config src/scripts/emergency/YourComponent.sol
```

## Instructions for Claude

When this skill is invoked:

### Step 1: Parse the Solidity Script

Read the provided Solidity file and extract:

1. **Owner (multisig type)**:
   - `setUpEmergency(...)` → `"owner": "emergency"`
   - `setUp(true, ...)` → `"owner": "dao"`

2. **Contract keys and function calls** from `addToBatch()` calls:
   ```solidity
   address addr = _envAddressNotZero("olympus.policies.ContractName");
   addToBatch(addr, abi.encodeWithSelector(IInterface.functionName.selector, args));
   ```
   Extract:
   - `contractKey`: e.g., `"olympus.policies.ContractName"`
   - `function`: e.g., `"functionName"`
   - `signature`: e.g., `"functionName(bool)"` (derive from selector/interface)
   - `args`: extract argument values if present

3. **Component ID**: derive from contract name in kebab-case (e.g., `YieldRepurchaseFacility.sol` → `yield-repurchase-facility`)

### Step 2: Read env.json for Addresses

Read `src/scripts/env.json` and for each chain, resolve the contractKey to get addresses.

For example, if contractKey is `"olympus.policies.OlympusHeart"`:
- Check `env.json.current.mainnet.olympus.policies.OlympusHeart`
- Check `env.json.current.sepolia.olympus.policies.OlympusHeart`
- etc.

Build `availableOn` array from chains where address exists and is not zero address.

### Step 3: Determine ABI Key

Match the function signature to existing ABIs in `emergency-abis.json`:

| Function Pattern | ABI Key |
|------------------|---------|
| `disable(bytes)` | `periphery_enabler` |
| `enable(bytes)` | `periphery_enabler` |
| `shutdownWithdrawals()`, `shutdownMinting()`, `shutdown()`, `restart()` | `emergency` |
| `setBorrowPaused(bool)`, `setLiquidationsPaused(bool)` | `cooler_v2` |
| `setBridgeStatus(bool)` | `cross_chain_bridge` |
| `deactivate()`, `activate()` | `reserve_migrator` |
| `shutdown(address[])` | `yield_repurchase_facility` |
| `withdrawLiquidity(uint256)` | `ccip_lock_release_pool` |
| `emergencyShutdownFixedExpiryMarket(uint256)` | `bond_manager` |

If no match found, ask user if a new ABI entry is needed.

### Step 4: Ask User for Metadata

Use AskUserQuestion to gather:

1. **Category** (required):
   - `treasury` - TRSRY, MINTR related
   - `lending` - Cooler, loans
   - `bridge` - Cross-chain bridges
   - `emissions` - EmissionManager, bonds
   - `core` - Heart, fundamental operations
   - `reserve` - Reserve management

2. **Severity** (required):
   - `critical` - Immediate shutdown, funds at risk
   - `high` - Urgent, significant vulnerability
   - `medium` - Important but not urgent
   - `low` - Monitor, precautionary

3. **Description** (required): What this shutdown does (1-2 sentences)

4. **Shutdown Criteria** (optional): When to trigger (list of conditions)

5. **Post-Shutdown Steps** (optional): Steps after shutdown (list)

6. **Dependencies** (optional): Other component IDs to shutdown together

### Step 5: Update emergency-config.json

1. Read current `documentation/emergency/emergency-config.json`

2. Add contract to `contractRegistry` if not present (extract contract name from contractKey, e.g., `olympus.policies.OlympusHeart` → `OlympusHeart`)

3. Add/update contract addresses in `chains.*.contracts` for each chain where the contract exists

4. Add new component to `components` array:
```json
{
  "id": "<kebab-case-id>",
  "name": "<Human Readable Name>",
  "description": "<from user>",
  "category": "<from user>",
  "severity": "<from user>",
  "owner": "<emergency|dao>",
  "shutdownCriteria": ["<from user>"],
  "calls": [
    {
      "contractKey": "<from script>",
      "function": "<from script>",
      "signature": "<from script>",
      "args": [<from script>],
      "abi": "<matched abi key>"
    }
  ],
  "availableOn": ["<chains from env.json>"],
  "postShutdownSteps": ["<from user>"],
  "batchScript": "<path to solidity script>"
}
```

5. Update `version` (bump patch version)

6. Update `lastUpdated` to current ISO 8601 timestamp

7. Update `updatedBy` to `"claude-code"`

### Step 6: Validate

Run validation:
```bash
node shell/validate-emergency-config.js
```

If validation fails, fix the issues and re-run.

### Step 7: Summary

Report to user:
- Component ID added
- Chains where available
- Owner (emergency/dao MS)
- Reminder to test with `./shell/shutdown.sh <component-id> --list`

## Example

For `src/scripts/emergency/Heart.sol`:

**Parsed from script:**
- Owner: `emergency` (uses `setUpEmergency`)
- ContractKey: `olympus.policies.OlympusHeart`
- Function: `disable(bytes)` with empty bytes arg
- ABI: `periphery_enabler`

**From env.json:**
- mainnet: `0x5824850D8A6E46a473445a5AF214C7EbD46c5ECB`
- sepolia: `0x1dc2c4E15189a7aa61Eff2b3DD3D5EAe8fA03377`

**Generated component:**
```json
{
  "id": "heart",
  "name": "Olympus Heart",
  "description": "Disables the Heart policy that triggers periodic protocol operations",
  "category": "core",
  "severity": "medium",
  "owner": "emergency",
  "calls": [{
    "contractKey": "olympus.policies.OlympusHeart",
    "function": "disable",
    "signature": "disable(bytes)",
    "args": [{"name": "disableData_", "type": "bytes", "value": ""}],
    "abi": "periphery_enabler"
  }],
  "availableOn": ["mainnet", "sepolia"],
  "batchScript": "src/scripts/emergency/Heart.sol"
}
```

## Notes

- Most new contracts implement `IEnabler` interface and use `periphery_enabler` ABI
- Only add new ABI entries if the function signature is truly unique
- Dynamic args (like `withdrawLiquidity(uint256)`) should use `"value": "dynamic"` with `"envKey"` for resolution
- Keep component IDs kebab-case and descriptive
