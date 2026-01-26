---
description: Guide for addressing linter notes in the Olympus V3 codebase. Run this after every coding task.
---

# Linter Note Resolution Guide

This guide covers how to address forge-lint notes in the Olympus V3 codebase.

## Important: Run After Every Coding Task

After completing any code changes (writing new code, refactoring, fixing bugs), ALWAYS run linting and address any notes before considering the task complete.

```bash
# Check for linting issues
pnpm run lint:check

# Or run full lint which will auto-fix some issues
pnpm run lint
```

## Scope: Focus on Current Work

When analyzing linting output:

1. **Only address notes in files you're actively working on** - Don't modify files outside your current task scope unless explicitly asked
2. **Explicitly list out-of-scope files** - When providing analysis, clearly categorize files as:
   - **In scope** - Files being modified in the current task
   - **Deployed/Out of scope** - Files that should be suppressed but not touched

### Reporting Format

When providing linting analysis, organize findings as:

```
## In-Scope Files (Fix Required)
- src/path/File.sol: Fix the issue directly

## Deployed/Out-of-Scope Files (Ignored - Would Require Suppression)
- src/external/Contract.sol: Deployed - suppress with justification
- src/modules/Deployed.sol: Deployed - suppress with justification
```

This makes it explicit what was skipped and why.

## Two-Tier Approach

The approach to fixing linter notes depends on whether the contract is deployed to production:

| Contract Status | Approach |
|-----------------|----------|
| **IN DEVELOPMENT** (current branch/PR) | Fix linter notes by refactoring code |
| **DEPLOYED** to production | Suppress with justification comment |

### Determining Deployment Status

1. **Check if the contract is deployed:**
   - Search the contract name in `src/scripts/deploy/savedDeployments/`
   - Check `src/scripts/env.json` for deployed addresses
   - Ask the user if unsure

2. **In-development contracts:**
   - New contracts being written for the first time
   - Contracts undergoing significant refactoring
   - Contracts not yet deployed to any chain

3. **Deployed contracts:**
   - Contracts with live deployments on mainnet/testnet
   - Contracts where changing code would require a governance proposal

## In-Development Contracts: Fix the Code

For contracts still in development, **always fix the linter note** by refactoring the code rather than suppressing it.

### Common Fixes

**Shadowing variable names:**
```solidity
// BAD - Shadowing
uint256 amount = 100;
{
    uint256 amount = 200; // Linter note: shadowing
}

// GOOD - Use distinct names
uint256 amount = 100;
{
    uint256 newAmount = 200;
}
```

**Unnecessary variables:**
```solidity
// BAD - Unused variable
uint256 calculatedValue = _calculate();
return true;

// GOOD - Remove or use
uint256 calculatedValue = _calculate();
return calculatedValue > 0;
```

**Explicit conversions:**
```solidity
// BAD - Unsafe typecast
address contractAddress = address(uint160(tokenContract));

// GOOD - Use safe conversion pattern
address contractAddress = address(tokenContract);
```

**Modifier logic:**
```solidity
// BAD - Unwrapped modifier logic
modifier onlyAdmin() {
    require(msg.sender == admin, "Unauthorized");
    _;
    _doSomething(); // Linter note: logic after modifier body
}

// GOOD - Wrap in function
modifier onlyAdmin() {
    _;
}

function doSomething() onlyAdmin external {
    _doSomething();
}
```

## Deployed Contracts: Suppress with Justification

For deployed contracts, suppression is acceptable since changing the code would require a governance proposal.

### Suppression Template

```solidity
/// forge-lint: disable-next-line(rule-name)
/// Reason: Deployed contract - changing would require governance proposal
```

### Examples

```solidity
// Example 1: Shadowing in deployed contract
/// forge-lint: disable-next-line(var-name-mixedcase)
/// Reason: Deployed contract - variable naming matches existing interface
uint256 depositAmount = _getDeposit();

// Example 2: External constraint
/// forge-lint: disable-next-line(avoid-low-level-calls)
/// Reason: Required for compatibility with external contract interface
_callExternalTarget(target, data);

// Example 3: Legitimate exception
/// forge-lint: disable-next-line(no-empty-blocks)
/// Reason: Empty block intentionally left for future upgrade path
function upgradeV2() external { }
```

## Internal State Variable Naming

**Internal state variables MUST use underscore prefix:**

```solidity
// GOOD - Internal state with underscore
uint256 internal _counter;
mapping(address => uint256) internal _balances;

// BAD - Missing underscore
uint256 internal counter;
mapping(address => uint256) internal balances;
```

This convention distinguishes internal state from:
- Public state variables (no underscore): `uint256 public totalSupply;`
- Local variables (no underscore): `uint256 amount = 100;`
- Function parameters (no underscore): `function mint(uint256 amount)`

## Running Linting

### Quick Check (No Auto-Fix)

```bash
pnpm run lint:check
```

This runs:
- `prettier:check` - Check formatting
- `solhint:check` - Check Solidity linting
- `markdownlint` - Check Markdown files

### Full Lint (With Auto-Fix)

```bash
pnpm run lint
```

This runs:
- `prettier` - Auto-formats code
- `solhint` - Auto-fixes some Solidity issues
- `markdownlint` - Auto-fixes Markdown issues

### Individual Tools

```bash
# Format code only (fastest)
pnpm run prettier

# Check Solidity linting only
pnpm run solhint:check

# Fix Solidity linting where possible
pnpm run solhint
```

## Common Forge-Lint Rules

| Rule | Description | Fix Strategy |
|------|-------------|--------------|
| `var-name-mixedcase` | Variable uses mixedCase | Rename to snakeCase or suppress if deployed |
| `func-name-mixedcase` | Function uses mixedCase | Rename or suppress if external interface |
| `const-name-snakecase` | Constant uses snakeCase | Rename to mixedCase or suppress |
| `avoid-low-level-calls` | Uses `call`/`delegatecall` | Refactor or suppress if required |
| `no-empty-blocks` | Empty code block | Remove or add comment |
| `unwrapped-modifier-logic` | Logic after `_;` in modifier | Move logic to function |
| `unsafe-typecast` | Direct address typecast | Use safe conversion or suppress |
| `screaming-snake-case-immutable` | Immutable uses UPPER_CASE | Suppress (acceptable pattern) |
| `reason-string` | Revert uses string message | Use custom error instead |
| `no-global-import` | Global import used | Use specific imports |
| `func-visibility` | Function lacks visibility | Add `public`/`external`/`internal` |
| `max-line-length` | Line exceeds 80 chars | Break line or suppress |

## Auto-Fixable Issues

Many linting issues can be auto-fixed by running:

```bash
pnpm run prettier  # Auto-formats code
pnpm run solhint   # Auto-fixes some Solidity issues
```

Always run these first before manual fixes.

## Workflow Summary

1. **Complete code changes** - Write or modify code
2. **Run linting** - `pnpm run lint:check`
3. **Address notes for in-development contracts** - Refactor code to fix
4. **Suppress notes for deployed contracts** - Add justification comments
5. **Re-run linting** - Verify all issues resolved
6. **Mark task complete** - Only when linting passes

## Quick Reference

| Goal | Command |
|------|---------|
| Check linting | `pnpm run lint:check` |
| Auto-fix and format | `pnpm run lint` |
| Format only | `pnpm run prettier` |
| Check Solidity only | `pnpm run solhint:check` |
| Fix specific file | `pnpm run prettier -- src/Contract.sol` |
