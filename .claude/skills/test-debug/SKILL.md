---
description: Guide for debugging tests in the Olympus V3 codebase
---

# Test Debugging Guide

This guide covers how to run and debug unit tests, fork tests, and proposal tests in the Olympus V3 codebase.

## Overview

Different test types require different approaches:

| Test Type | Purpose | Command Pattern |
|-----------|---------|-----------------|
| Unit tests | Isolated contract testing | `forge test -vvv --match-contract <Contract>` |
| Fork tests | Mainnet state interaction | `forge test -vvv --match-contract <Contract>Fork --fork-url mainnet` |
| Proposal tests | Governance simulation | `forge test -vvv --match-contract <Contract> --match-path 'src/test/proposals/*.t.sol' --fork-url mainnet` |

## Verbosity Levels

Foundry's verbosity flags control output detail:

| Flag | Output | Use Case |
|------|--------|----------|
| `-v` | Test pass/fail | Quick check |
| `-vv` | Test logs | Basic debugging |
| `-vvv` | Test logs + traces | Standard unit test debugging |
| `-vvvv` | Full traces with setup | **Use for `setUp()` issues only** |

**Important:** If a test fails in `setUp()`, you MUST use `-vvvv` to see the trace. Lower verbosity levels won't show where the failure occurs.

## Unit Tests

Unit tests run in isolation without external chain state.

### Running All Unit Tests

**Quick check** (runs all unit tests):
```bash
pnpm run test:unit
```
**Warning:** This will run all unit tests and may take several minutes.

### Running a Specific Test Contract

```bash
forge test -vvv --match-contract DepositTest
```

### Running a Specific Test Function

```bash
forge test -vvv --match-test testGivenAmountIsZero
```

### Debugging a Failing Unit Test

1. **First run** - See the failure:
   ```bash
   forge test -vvv --match-contract DepositTest
   ```

2. **If failure is in `setUp()`** - Use maximum verbosity:
   ```bash
   forge test -vvvv --match-contract DepositTest
   ```

3. **Narrow to specific test** - Once you know which test fails:
   ```bash
   forge test -vvvv --match-test testGivenAmountIsZero_whenDeposit_reverts
   ```

### Reading Unit Test Traces

When a test fails with `-vvv` or `-vvvv`, Foundry outputs a trace showing:
- Contract calls (depth indicates call stack)
- State changes
- Revert reasons
- Line numbers

**Example trace output:**
```
[Fork] Cheats.sol (0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)
[5592] SimpleVault::deposit(1000000000000000000, 0x...)
    ├─ [5592] ERC20::approve()
    │   └─ ← [Return] 119
    ├─ [5554] SimpleVault::mint()
    │   ├─ [5554] VM::asset()
    │   │   └─ ← [Return] 0x...
    │   └─ ← [Revert] VAULT_CapacityExceeded()
    └─ ← [Revert] VAULT_CapacityExceeded()
```

The trace shows the call stack and where the revert occurred.

## Fork Tests

Fork tests run against a forked mainnet/testnet state. They require an RPC URL.

### Environment Setup

Set `ALCHEMY_API_KEY` in your `.env` file:

```bash
ALCHEMY_API_KEY=your_key_here
```

### Running All Fork Tests

**Quick check** (runs all fork tests):
```bash
pnpm run test:fork
```
**Warning:** This will run all fork tests and may take several minutes.

### Running a Specific Fork Test Contract

```bash
forge test -vvv --match-contract OperatorFork --fork-url mainnet
```

**Note:** Use `-vvvv` only if debugging a `setUp()` failure in a fork test.

### Running Against Testnet

```bash
forge test -vvvv --match-contract ProposalFork --fork-url baseSepolia
```

### Common Fork Test Issues

**Issue:** `Fork not found` error
```bash
# Solution: Ensure RPC URL is correct and Alchemy key is set
forge test -vvvv --match-contract MyTest --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY
```

**Issue:** Test passes locally but fails in CI
```bash
# Solution: Fork at a specific block to match CI environment
forge test -vvvv --match-contract MyTest --fork-url mainnet --fork-block-number 21000000
```

**Issue:** `setUp()` failure with no trace
```bash
# Solution: Use -vvvv to see setup trace
forge test -vvvv --match-contract MyForkTest --fork-url mainnet
```

### Fork Test Debugging Tips

1. **Use `-vvv` for standard debugging** - Sufficient for most fork test failures
2. **Use `-vvvv` for `setUp()` failures** - Only when the test fails during setup
3. **Check for state changes** - The forked state may have changed since the test was written
4. **Use specific block numbers** - Pinning a block ensures reproducible tests
5. **Deal tokens to test accounts** - Fork tests start with mainnet state, use `deal()` to fund accounts

```solidity
function setUp() public {
    vm.createSelectFork("mainnet", 21000000);
    deal(address(usdc), user, 1_000_000e6);
}
```

## Proposal Tests

Proposal tests simulate governance proposals on a forked chain.

### Running All Proposal Tests

**Quick check** (runs all proposal tests):
```bash
pnpm run test:proposal
```
**Warning:** This will run all proposal tests and may take several minutes.

### Running a Specific Proposal

```bash
forge test -vvv --match-contract ProposalExample --match-path 'src/test/proposals/*.t.sol' --fork-url mainnet
```

### Proposal Test Structure

Proposal tests typically follow this pattern:

1. **Fork mainnet** at a specific block
2. **Execute proposal** actions
3. **Assert final state**

```solidity
function test_proposal() public {
    // Fork at block before proposal execution
    vm.createSelectFork("mainnet", 21000000);

    // Execute proposal
    proposal.execute();

    // Verify results
    assertEq(address(newContract).code.length > 0, true);
}
```

### Debugging Proposal Failures

**Step 1:** Run with verbosity
```bash
forge test -vvv --match-contract ProposalExample --match-path 'src/test/proposals/*.t.sol' --fork-url mainnet
```

**Step 1a:** If failure is in `setUp()`, use maximum verbosity
```bash
forge test -vvvv --match-contract ProposalExample --match-path 'src/test/proposals/*.t.sol' --fork-url mainnet
```

**Step 2:** Check the proposal ID and state
```solidity
function setUp() public {
    vm.createSelectFork("mainnet", 21000000);
    proposal = ProposalExample(proposalAddress);

    // Log proposal state for debugging
    console.log("Proposal state:", proposal.state());
    console.log("Proposal start block:", proposal.startBlock());
    console.log("Current block:", block.number);
}
```

**Step 3:** Verify caller has voting power
```solidity
function test_proposal() public {
    address proposer = makeAddr("proposer");

    // Deal OHM for voting power if needed
    deal(address(ohm), proposer, 1_000_000e18);

    vm.startPrank(proposer);
    ohm.delegate(proposer);
    vm.roll(block.number + 1); // Checkpoint for voting

    // Execute proposal
    proposal.execute();
    vm.stopPrank();
}
```

## Common Debugging Patterns

### Checking State in Tests

Use `console.log` for quick debugging:

```solidity
import {console} from "forge-std/console.sol";

function test_something() public {
    uint256 balance = token.balanceOf(user);
    console.log("User balance:", balance);
    console.log("Expected balance:", 100e18);
}
```

### Debugging Reverts

When a test reverts, the trace shows the revert location. For custom errors:

```solidity
vm.expectRevert(abi.encodeWithSelector(IContract.CONTRACT_InvalidAmount.selector));
contract.doSomething(0); // Will revert
```

If the revert doesn't match, Foundry will show:
```
Error: Expected revert "CONTRACT_InvalidAmount" but got "CONTRACT_Unauthorized"
```

### Debugging Storage Issues

Read contract storage directly to debug state:

```solidity
function test_storageIssue() public {
    // Read storage slot directly
    bytes32 slotValue = vm.load(address(contract), bytes32(uint256(0)));
    console.logBytes32(slotValue);
}
```

### Time-Based Debugging

For tests that depend on timestamps:

```solidity
function test_timeBased() public {
    console.log("Current timestamp:", block.timestamp);
    console.log("Expiry timestamp:", expiry);

    vm.warp(expiry + 1); // Move time forward
    console.log("Warped timestamp:", block.timestamp);
}
```

## Quick Reference

| Goal | Command |
|------|---------|
| Run unit tests | `pnpm run test:unit` |
| Run fork tests | `pnpm run test:fork` |
| Run proposal tests | `pnpm run test:proposal` |
| Debug specific unit test | `forge test -vvv --match-contract ContractTest` |
| Debug specific fork test | `forge test -vvv --match-contract ContractFork --fork-url mainnet` |
| Debug specific proposal test | `forge test -vvv --match-contract Proposal --match-path 'src/test/proposals/*.t.sol' --fork-url mainnet` |
| Debug setUp() failure | `forge test -vvvv --match-contract ContractTest` |
| Run single test function | `forge test -vvv --match-test testName` |
| Fork at specific block | `--fork-block-number 21000000` |

## Workflow Summary

1. **Start with the test script** - Use `pnpm run test:*` commands first
2. **Narrow to the failing test** - Use `--match-contract` or `--match-test`
3. **Increase verbosity** - Use `-vvv` for standard debugging, `-vvvv` for `setUp()` issues
4. **Read the trace** - Follow the call stack to find the failure point
5. **Add console.log** - For additional insight into state
6. **Fix and re-run** - Use the same command to verify the fix
