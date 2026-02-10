# Update Emergency Config

This skill updates `documentation/emergency/emergency-config.json` by analyzing contract source code or existing batch scripts.

## Three Invocation Modes

```
/update-emergency-config                              → scan mode
/update-emergency-config src/policies/NewThing.sol    → contract mode
/update-emergency-config src/scripts/emergency/X.sol  → script mode (legacy)
```

**Mode detection:**
- No argument → **scan mode**
- Argument contains `src/scripts/emergency/` → **script mode**
- Argument is any other `.sol` file → **contract mode**

## Instructions for Claude

### Mode A: Scan Mode (no argument)

#### A1: Discover uncovered contracts

1. Grep `src/policies/` and `src/periphery/` for concrete contracts that inherit `PolicyEnabler`, `PeripheryEnabler`, or `IEnabler`:
   - Use `Grep` with patterns like `is PolicyEnabler`, `is PeripheryEnabler`, `is IEnabler`
   - Search for `is.*PolicyEnabler`, `is.*PeripheryEnabler`, `is.*IEnabler` to catch multi-inheritance
2. Skip abstract contracts — grep each matched file for `abstract contract`; if found, skip it
3. Read `documentation/emergency/emergency-config.json` and extract `contractRegistry` array
4. Cross-reference: for each discovered contract, check if the contract name is already in `contractRegistry`
5. Present the list of uncovered contracts to the user, showing:
   - Contract name
   - File path
   - Detected pattern (PolicyEnabler / PeripheryEnabler / IEnabler)
6. Use AskUserQuestion to let the user select which contracts to add
7. For each selected contract, run the **Detection Hierarchy** (see below), then proceed to **Resolve Addresses**, **Ask Metadata**, **Update Config**, and **Validate** (Steps C3–C7)

### Mode B: Script Mode (argument is `src/scripts/emergency/*.sol`)

This is the legacy flow — unchanged from before.

#### B1: Parse the Solidity Script

Read the provided Solidity file and extract:

1. **Owner (multisig type)**:
   - Look for the `setUpEmergency` modifier (on the `run` function) → `"owner": "emergency"`
   - Look for the `setUp` modifier (on the `run` function) with `true` as the first argument → `"owner": "dao"`

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

3. **Component ID**: derive from the script filename (without `.sol`) in kebab-case (e.g., `YieldRepurchaseFacility.sol` → `yield-repurchase-facility`)

#### B2: Determine ABI Key

Match the function signature to existing ABIs in `documentation/emergency/emergency-abis.json` using the **ABI Lookup Table** below.

#### B3–B7: Continue with Resolve Addresses, Ask Metadata, Update Config, Validate, Summary

Same as Steps C3–C7 below, but include `"batchScript": "<path to solidity script>"` in the generated component.

### Mode C: Contract Mode (argument is any other `.sol` file)

#### C1: Read the Contract Source

Read the specified `.sol` file.

#### C2: Run the Detection Hierarchy

Analyze the contract source in this order. Stop at the first match:

**Level 1 — PolicyEnabler**
- Grep for `is PolicyEnabler` or `is.*PolicyEnabler` in the inheritance declaration
- Check for indirect inheritance: if the contract inherits from a base contract, read that base contract to see if *it* inherits PolicyEnabler. For example, `ConvertibleDepositFacility` inherits `BaseDepositFacility` which inherits `PolicyEnabler` — this counts as Level 1.
- Result:
  - Function: `disable` / Signature: `disable(bytes)` / Args: `[{"name": "disableData_", "type": "bytes", "value": ""}]`
  - ABI: `periphery_enabler`
  - Owner: `emergency` (PolicyEnabler grants `onlyEmergencyOrAdminRole` on disable)
  - `batchScript`: omit

**Level 2 — PeripheryEnabler**
- Grep for `is PeripheryEnabler` or `is.*PeripheryEnabler`
- Result:
  - Function: `disable` / Signature: `disable(bytes)` / Args: `[{"name": "disableData_", "type": "bytes", "value": ""}]`
  - ABI: `periphery_enabler`
  - Owner: `dao` (PeripheryEnabler uses `_onlyOwner()`, typically DAO multisig)
  - `batchScript`: omit

**Level 3 — Direct IEnabler**
- Grep for `is IEnabler` or `IEnabler` in inheritance, but only if NOT already matched by Level 1 or 2
- Result:
  - Function: `disable` / Signature: `disable(bytes)` / Args: `[{"name": "disableData_", "type": "bytes", "value": ""}]`
  - ABI: `periphery_enabler`
  - Owner: **ask user** (use AskUserQuestion with options `emergency` and `dao`)
  - `batchScript`: omit

**Level 4 — Known emergency functions**
- Scan the source for known emergency function definitions: `shutdown`, `deactivate`, `setBorrowPaused`, `setLiquidationsPaused`, `setBridgeStatus`, `emergencyShutdown*`
- Extract full function signatures from the source
- Match to ABI keys using the **ABI Lookup Table** below
- Owner: **ask user**
- For each arg: determine if a static value can be inferred from context
  - If any arg is dynamic (can't determine a static value from the source), check for a matching script in `src/scripts/emergency/` that references this contract
  - If a matching script exists, parse it for arg values and link `batchScript`
  - If no matching script exists, flag to user and ask how to resolve

**Level 5 — Matching batch script exists**
- Check `src/scripts/emergency/` for a script that references this contract (grep for the contract name)
- If found, fall back to **Script Mode** flow (B1–B2) to parse the script
- Include `batchScript` in the generated component

**Level 6 — None of the above**
- Use AskUserQuestion to ask the user what the emergency action should be for this contract
- Ask for: function name, signature, args, ABI key, owner

#### C3: Resolve Addresses from env.json

Use `jq` to read `src/scripts/env.json` and resolve the contract's env key to get addresses per chain. Do NOT try to parse env.json manually — always use `jq`.

The contract key follows the pattern `olympus.policies.ContractName` or `olympus.periphery.ContractName` — determine the correct path based on the file location.

For example, if the contract is at `src/policies/Heart.sol` and the contract name is `OlympusHeart`:
```bash
jq -r '.current.mainnet.olympus.policies.OlympusHeart // empty' src/scripts/env.json
jq -r '.current.sepolia.olympus.policies.OlympusHeart // empty' src/scripts/env.json
```

For a periphery contract like `CCIPCrossChainBridge`:
```bash
jq -r '.current.mainnet.olympus.periphery.CCIPCrossChainBridge // empty' src/scripts/env.json
jq -r '.current.sepolia.olympus.periphery.CCIPCrossChainBridge // empty' src/scripts/env.json
```

Build `availableOn` array from chains where address exists and is not the zero address.

**Important:** The contract name in env.json may differ from the filename. Look at the `contract` declaration in the `.sol` file to get the actual name, then search env.json for that name. If the exact contract name is not found in env.json for expected chains, also search for partial matches or check existing emergency scripts' `_envAddressNotZero` calls for the actual env key used (e.g., source says `contract CoolerComposites` but mainnet env.json uses `CoolerV2Composites`).

#### C4: Ask User for Metadata

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

#### C4.5: Derive Component ID

Suggest a short, descriptive kebab-case component ID for the contract and confirm with the user via AskUserQuestion. Do NOT simply kebab-case the Solidity contract name — many contracts have prefixes like `Olympus` that should be dropped (e.g., `OlympusHeart` → `heart`, not `olympus-heart`). Look at existing component IDs in the config for style guidance.

#### C5: Update emergency-config.json

**Important:** Use `jq` for ALL reads and writes to `emergency-config.json`. Do NOT try to manually edit or write JSON — this will corrupt the file.

1. Check if a component with the same ID or same `contractKey` already exists in the `components` array. If so, use AskUserQuestion to ask the user whether to update the existing entry or create a new component.

2. Read current `documentation/emergency/emergency-config.json`

3. Add contract to `contractRegistry` if not present (extract contract name from env key or source, e.g., `olympus.policies.OlympusHeart` → `OlympusHeart`):
   ```bash
   jq '.contractRegistry += ["OlympusHeart"] | .contractRegistry |= unique' documentation/emergency/emergency-config.json > emergency-config.tmp.json && mv emergency-config.tmp.json documentation/emergency/emergency-config.json
   ```

4. Add/update contract addresses in `chains.*.contracts` for each chain where the contract exists

5. Add new component to `components` array (build the component JSON and use `jq` to append):
```json
{
  "id": "<kebab-case-id>",
  "name": "<Human Readable Name>",
  "description": "<from user>",
  "category": "<from user>",
  "severity": "<from user>",
  "owner": "<emergency|dao>",
  "shutdownCriteria": ["<from user, if provided>"],
  "calls": [
    {
      "contractKey": "<resolved env key>",
      "function": "<function name>",
      "signature": "<full signature>",
      "args": [{"name": "<arg name>", "type": "<arg type>", "value": "<arg value>"}],
      "abi": "<matched abi key>"
    }
  ],
  "availableOn": ["<chains from env.json>"],
  "postShutdownSteps": ["<from user, if provided>"],
  "dependencies": ["<from user, if provided>"],
  "batchScript": "<only if script mode or Level 4/5 detection>"
}
```

   - Omit `batchScript` entirely when the contract was detected via Level 1–3 (IEnabler patterns)
   - Omit `shutdownCriteria`, `postShutdownSteps`, `dependencies` if not provided by user

6. Update `version` (bump patch version), `lastUpdated`, and `updatedBy` using `jq`:
   ```bash
   jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.version |= (split(".") | .[2] = (.[2] | tonumber + 1 | tostring) | join(".")) |
      .lastUpdated = $ts |
      .updatedBy = "claude-code"' \
     documentation/emergency/emergency-config.json > emergency-config.tmp.json && mv emergency-config.tmp.json documentation/emergency/emergency-config.json
   ```

#### C6: Validate

Run validation:
```bash
node shell/validate-emergency-config.js
```

If validation fails, fix the issues and re-run.

#### C7: Summary

Report to user:
- Component ID added
- Detection method used (e.g., "Detected PolicyEnabler — using disable(bytes)")
- Chains where available
- Owner (emergency/dao MS)
- Whether batchScript was linked or omitted
- Reminder to test with `./shell/shutdown.sh <component-id> --list`

## ABI Lookup Table

Match function signatures to ABI keys in `documentation/emergency/emergency-abis.json`:

| Function Pattern | ABI Key |
|------------------|---------|
| `disable(bytes)` | `periphery_enabler` |
| `enable(bytes)` | `periphery_enabler` |
| `shutdownWithdrawals()`, `shutdownMinting()`, `shutdown()`, `restart()` | `emergency` |
| `shutdown()`, `restart()` (EmissionManager) | `emission_manager` |
| `setBorrowPaused(bool)`, `setLiquidationsPaused(bool)` | `cooler_v2` |
| `setBridgeStatus(bool)` | `cross_chain_bridge` |
| `deactivate()`, `activate()` (Heart) | `heart` |
| `deactivate()`, `activate()` (ReserveMigrator) | `reserve_migrator` |
| `shutdown(address[])` | `yield_repurchase_facility` |
| `withdrawLiquidity(uint256)` | `ccip_lock_release_pool` |
| `emergencyShutdownFixedExpiryMarket(uint256)` | `bond_manager` |

**Disambiguation:** If a function signature matches multiple ABI keys (e.g., `shutdown()` maps to both `emergency` and `emission_manager`; `deactivate()` maps to both `heart` and `reserve_migrator`), determine the correct key by checking which ABI contains the full set of functions used by the contract. If still ambiguous, ask the user.

If no match is found, ask the user if a new ABI entry is needed in `emergency-abis.json`.

## Detection Hierarchy Summary

```
Contract source file
    │
    ├─ Level 1: inherits PolicyEnabler?
    │   → disable(bytes), owner=emergency, no batchScript
    │
    ├─ Level 2: inherits PeripheryEnabler?
    │   → disable(bytes), owner=dao, no batchScript
    │
    ├─ Level 3: inherits IEnabler directly?
    │   → disable(bytes), owner=ask user, no batchScript
    │
    ├─ Level 4: has known emergency functions?
    │   → extract signatures, match ABI, owner=ask user
    │   → if dynamic args: check for matching script
    │
    ├─ Level 5: matching batch script in src/scripts/emergency/?
    │   → parse script (legacy flow), link batchScript
    │
    └─ Level 6: none detected
        → ask user for everything
```

## Examples

### Example 1: PolicyEnabler contract (contract mode)

For `src/policies/Heart.sol` which has `contract OlympusHeart is PolicyEnabler`:

**Detected:** Level 1 — PolicyEnabler
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
  "availableOn": ["mainnet", "sepolia"]
}
```
Note: no `batchScript` field. A legacy batch script exists at `src/scripts/emergency/Heart.sol`, but since `OlympusHeart` inherits `PolicyEnabler` (Level 1), the config is derived directly from the contract source and `batchScript` is omitted.

### Example 2: Script with dynamic args (script mode)

For `src/scripts/emergency/CCIPTokenPoolMainnet.sol`:

**Detected:** Script mode (legacy)
**Generated component includes:**
```json
{
  "batchScript": "src/scripts/emergency/CCIPTokenPoolMainnet.sol"
}
```

## Notes

- Most new contracts implement `IEnabler` via `PolicyEnabler` or `PeripheryEnabler` — the skill can derive config directly from the contract source without needing a batch script
- Batch scripts are only needed for edge cases with dynamic/on-chain args (e.g., `CCIPTokenPoolMainnet`)
- Only add new ABI entries if the function signature is truly unique
- Dynamic args (like `withdrawLiquidity(uint256)`) should use `"value": "dynamic"` with `"envKey"` for resolution
- Keep component IDs kebab-case and descriptive
