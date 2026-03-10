# Update Emergency Config

This skill updates `documentation/emergency/emergency-config.json` by analyzing contract source code.

## Two Invocation Modes

```text
/update-emergency-config                              → scan mode
/update-emergency-config src/policies/NewThing.sol    → contract mode
/update-emergency-config src/periphery/Bridge.sol     → contract mode
```

**Mode detection:**

- No argument → **scan mode**
- Argument is a `.sol` file under `src/policies/` or `src/periphery/` → **contract mode**
- Argument is a `.sol` file outside those directories → **error** (contract keys can only be resolved for policies and periphery contracts)

## Instructions for Claude

### Mode A: Scan Mode (no argument)

#### A1: Discover uncovered contracts

1. **Find all .sol files** in `src/policies/` and `src/periphery/`

2. **Enumerate concrete contract declarations** in each file:
   - Use `Grep` with pattern `^contract\s+\w+` to find contract declarations
   - For each match, read the file and check if the contract declaration has the `abstract` keyword
   - Skip only contracts that are explicitly declared as `abstract contract`
   - Build a list of concrete contract names with their file paths

3. **Walk inheritance chain** (up to 3 levels) for each concrete contract:
   - Start with the concrete contract's `is` inheritance list
   - For each parent contract in the inheritance list:
     - Check if it matches `PolicyEnabler`, `PeripheryEnabler`, or `IEnabler` (direct match or pattern match)
     - If not a known enabler, read the parent contract's file and extract its inheritance list
     - Repeat up to 3 levels deep from the original contract
   - Track which enabler (if any) was found and at what level

4. **Filter contracts** that have `PolicyEnabler`, `PeripheryEnabler`, or `IEnabler` in their inheritance chain

5. Read `documentation/emergency/emergency-config.json` and extract `contractRegistry` array

6. Cross-reference: for each discovered contract, check if the contract name is already in `contractRegistry`

7. Present the list of uncovered contracts to the user, showing:
   - Contract name
   - File path
   - Detected enabler (PolicyEnabler / PeripheryEnabler / IEnabler)
   - Inheritance level where detected (direct or indirect)

8. Use AskUserQuestion to let the user select which contracts to add

9. For each selected contract, run the **Detection Hierarchy** (see below), then proceed to **Resolve Addresses**, **Ask Metadata**, **Update Config**, and **Validate** (Steps B3–B7)

### Mode B: Contract Mode (argument is a `.sol` file under `src/policies/` or `src/periphery/`)

#### B1: Validate Path and Read the Contract Source

1. **Validate the path**: Check that the `.sol` file is under `src/policies/` or `src/periphery/`. If the file is outside these directories, return an error explaining that contract keys can only be resolved for policies and periphery contracts, and suggest the user either:
   - Move the contract to the appropriate directory if it's a policy or periphery contract, or
   - Use scan mode (`/update-emergency-config` without arguments) to discover valid contracts

2. **Read the contract source**: Read the specified `.sol` file.

#### B2: Run the Detection Hierarchy

Analyze the contract source in this order. Stop at the first match:

##### Level 1 — PolicyEnabler

- Grep for `is PolicyEnabler` or `is.*PolicyEnabler` in the inheritance declaration
- Check for indirect inheritance: if the contract inherits from a base contract, read that base contract to see if *it* inherits PolicyEnabler. For example, `ConvertibleDepositFacility` inherits `BaseDepositFacility` which inherits `PolicyEnabler` — this counts as Level 1.
- Result:
    - Function: `disable` / Signature: `disable(bytes)` / Args: `[{"name": "disableData_", "type": "bytes", "value": ""}]`
    - ABI: `periphery_enabler`
    - Owner: `emergency` (PolicyEnabler grants `onlyEmergencyOrAdminRole` on disable)

##### Level 2 — PeripheryEnabler

- Grep for `is PeripheryEnabler` or `is.*PeripheryEnabler`
- Result:
    - Function: `disable` / Signature: `disable(bytes)` / Args: `[{"name": "disableData_", "type": "bytes", "value": ""}]`
    - ABI: `periphery_enabler`
    - Owner: `dao` (PeripheryEnabler uses `_onlyOwner()`, typically DAO multisig)

##### Level 3 — Direct IEnabler

- Grep for `is IEnabler` or `IEnabler` in inheritance, but only if NOT already matched by Level 1 or 2
- Result:
    - Function: `disable` / Signature: `disable(bytes)` / Args: `[{"name": "disableData_", "type": "bytes", "value": ""}]`
    - ABI: `periphery_enabler`
    - Owner: **ask user** (use AskUserQuestion with options `emergency` and `dao`)

##### Level 4 — Known emergency functions

- Scan the source for known emergency function definitions: `shutdown`, `deactivate`, `setBorrowPaused`, `setLiquidationsPaused`, `setBridgeStatus`, `emergencyShutdown*`
- Extract full function signatures from the source
- Match to ABI keys using the **ABI Lookup Table** below
- Owner: **ask user**
- For each arg: determine if a static value can be inferred from context
    - If any arg is dynamic (can't determine a static value from the source), flag to user and ask how to resolve

##### Level 5 — None of the above

- Use AskUserQuestion to ask the user what the emergency action should be for this contract
- Ask for: function name, signature, args, ABI key, owner

#### B3: Resolve Addresses from env.json

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

Discard any chain where the address is empty or the zero address (`0x0000000000000000000000000000000000000000`). Build the `availableOn` array from the remaining chains only. Do NOT write zero addresses into the config for any purpose (contracts, multisigs, or otherwise).

**Important:** The contract name in env.json may differ from the filename. Look at the `contract` declaration in the `.sol` file to get the actual name, then search env.json for that name. If the exact contract name is not found in env.json for expected chains, also search for partial matches.

#### B4: Generate and Confirm Metadata

Before asking the user, **generate suggested values** for all metadata fields by analyzing:

- The contract source code (what it does, what it interacts with)
- The detection level (PolicyEnabler → emergency-owned, PeripheryEnabler → dao-owned, etc.)
- Similar existing components in `emergency-config.json` (read the config, find components with the same category or related contracts, and use their patterns as a reference)
- The contract name, its imports, and any inherited contracts

**Step 1: Generate suggestions for all fields:**

1. **Category** — infer from contract path, name, and imports:
   - `treasury` - TRSRY, MINTR, Treasury related
   - `lending` - Cooler, loans, borrower
   - `bridge` - Cross-chain bridges, CCIP, LayerZero
   - `emissions` - EmissionManager, bonds
   - `core` - Heart, fundamental operations
   - `reserve` - Reserve management, migrator, wrapper

2. **Severity** — infer from owner and contract role:
   - `critical` - Emergency-owned + handles funds directly (treasury, lending core)
   - `high` - Emergency-owned + important but not direct fund custody
   - `medium` - DAO-owned or supporting contracts
   - `low` - Periphery helpers, non-critical paths

3. **Description** — generate a 1-2 sentence description of what the shutdown does, based on the contract's purpose and the function being called (e.g., "Disables the X policy that manages Y")

4. **Shutdown Criteria** (recommended — all existing components include this) — generate 2-4 conditions based on:
   - What could go wrong with this contract (exploit, manipulation, compromise)
   - What dependencies might trigger this shutdown (e.g., "Core Cooler V2 paused and this is still active")
   - Reference similar components' criteria for style

5. **Post-Shutdown Steps** (recommended — all existing components include this) — generate 2-4 steps based on:
   - How to verify the shutdown worked (e.g., "Verify policy is disabled via isActive()")
   - What dependent systems to check
   - What monitoring to do post-shutdown
   - Reference similar components' steps for style

6. **Dependencies** (optional): Other component IDs that should be shutdown together — check if any existing components reference related contracts

**Step 2: Present all suggestions to the user for confirmation:**

Use AskUserQuestion to present the generated values. Format the suggestions clearly so the user can approve, modify, or skip each one. For example:

> I've generated the following metadata based on the contract analysis:
>
> - **Category:** lending
> - **Severity:** critical
> - **Description:** "Disables the CoolerTreasuryBorrower policy that manages borrowing from the treasury for Cooler V2 loans"
> - **Shutdown Criteria:**
>   1. "Treasury borrowing exploit detected"
>   2. "Unauthorized loan origination"
>   3. "Cooler V2 core paused and treasury borrower still active"
> - **Post-Shutdown Steps:**
>   1. "Verify policy is disabled via isActive()"
>   2. "Check no pending treasury borrows in flight"
>   3. "Consider pausing dependent Cooler V2 core if not already paused"
>
> Accept these suggestions or provide modifications?

If the user accepts, use the suggested values. If the user wants to modify, apply their changes. If the user explicitly skips shutdownCriteria or postShutdownSteps, omit them — but always generate and present suggestions first.

#### B4.5: Derive Component ID

Suggest a short, descriptive kebab-case component ID for the contract and confirm with the user via AskUserQuestion. Do NOT simply kebab-case the Solidity contract name — many contracts have prefixes like `Olympus` that should be dropped (e.g., `OlympusHeart` → `heart`, not `olympus-heart`). Look at existing component IDs in the config for style guidance.

#### B5: Update emergency-config.json

**Important:** Use `jq` for ALL reads and writes to `emergency-config.json`. Do NOT try to manually edit or write JSON — this will corrupt the file.

1. Check if a component with the same ID or same `contractKey` already exists in the `components` array. If so, use AskUserQuestion to ask the user whether to update the existing entry or create a new component.

1. Read current `documentation/emergency/emergency-config.json`

1. Add contract to `contractRegistry` if not present (extract contract name from env key or source, e.g., `olympus.policies.OlympusHeart` → `OlympusHeart`):

   ```bash
   jq '.contractRegistry += ["OlympusHeart"] | .contractRegistry |= unique' documentation/emergency/emergency-config.json > emergency-config.tmp.json && mv emergency-config.tmp.json documentation/emergency/emergency-config.json
   ```

1. Add/update contract addresses in `chains.*.contracts` only for chains in the `availableOn` array (i.e., skip chains with zero or missing addresses)

1. Add new component to `components` array (build the component JSON and use `jq` to append):

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
  "dependencies": ["<from user, if provided>"]
}
```

- Omit `shutdownCriteria`, `postShutdownSteps`, `dependencies` only if the user explicitly chose to skip them (the skill should always suggest values first)

1. Update `version` (bump patch version), `lastUpdated`, and `updatedBy` using `jq`:

   ```bash
   jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.version |= (split(".") | .[2] = (.[2] | tonumber + 1 | tostring) | join(".")) |
      .lastUpdated = $ts |
      .updatedBy = "claude-code"' \
     documentation/emergency/emergency-config.json > emergency-config.tmp.json && mv emergency-config.tmp.json documentation/emergency/emergency-config.json
   ```

#### B6: Validate

Run validation:

```bash
node shell/validate-emergency-config.js
```

If validation fails, fix the issues and re-run.

#### B7: Summary

Report to user:

- Component ID added
- Detection method used (e.g., "Detected PolicyEnabler — using disable(bytes)")
- Chains where available
- Owner (emergency/dao MS)
- Reminder to validate the updated config with `node shell/validate-emergency-config.js`

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

```text
Contract source file
    │
    ├─ Level 1: inherits PolicyEnabler?
    │   → disable(bytes), owner=emergency
    │
    ├─ Level 2: inherits PeripheryEnabler?
    │   → disable(bytes), owner=dao
    │
    ├─ Level 3: inherits IEnabler directly?
    │   → disable(bytes), owner=ask user
    │
    ├─ Level 4: has known emergency functions?
    │   → extract signatures, match ABI, owner=ask user
    │   → if dynamic args: flag to user for resolution
    │
    └─ Level 5: none detected
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

## Notes

- Most new contracts implement `IEnabler` via `PolicyEnabler` or `PeripheryEnabler` — the skill can derive config directly from the contract source
- The emergency frontend handles encoding transactions directly using the ABI data in `documentation/emergency/emergency-abis.json`
- Only add new ABI entries if the function signature is truly unique
- Dynamic args (like `withdrawLiquidity(uint256)`) should use `"value": "dynamic"` with `"envKey"` for resolution
- Keep component IDs kebab-case and descriptive
