---
name: test-write
description: Write or review Olympus V3 Solidity tests, including external-function coverage matrices, authorization, enabled-state, numeric boundaries, state transitions, accounting, preview/write consistency, fuzzing, invariants, file structure, naming, and error handling.
---

# Test Writing Guide

This guide covers the standards for writing test files in the Olympus V3 codebase.

## File Organization

### Organize Around External Actions

Give each external state-changing action a dedicated test file. Test internal functions indirectly
through their external callers. Co-locate a directly corresponding preview or getter with the action
when it predicts or exposes the state established by that action and coverage is preserved. Keep a
standalone file when a read function has independent behavior that is not naturally established by
one action.

**Examples:**

- `src/test/modules/DEPOS/mint.t.sol` - Tests for the `mint()` function
- `src/test/modules/DEPOS/burn.t.sol` - Tests for the `burn()` function
- `src/test/modules/MINTR/periodicTasks.t.sol` - Tests for periodic task functions

**File naming:**

- Use lowercase, descriptive names: `mint.t.sol`, `addPeriodicTask.t.sol`
- Use `.t.sol` extension for test files
- Match the primary external action being tested

**Base test contracts:**

- Create a parent test contract for each contract (e.g., `DEPOSTest.sol`)
- Parent contract contains setup functions, common assertions, helper functions, and state modifiers
- Individual test files inherit from the parent
- Parent contract is marked `abstract` since it's never instantiated directly

```solidity
// src/test/modules/DEPOS/DEPOSTest.sol - Parent contract
abstract contract DEPOSTest {
    // =======================================================================
    // State Variables (accessible to all child tests)
    // =======================================================================

    IDepositPositionManager public DEPOS;
    address public godmode;
    address public admin;
    address public user;

    // =======================================================================
    // setUp() - Contract deployment and initial configuration
    // =======================================================================

    function setUp() public virtual {
        // Deploy contracts
        godmode = address(this);
        admin = makeAddr("admin");
        user = makeAddr("user");

        vm.startPrank(godmode);
        DEPOS = IDepositPositionManager(address(new DepositPositionManager()));
        vm.stopPrank();
    }

    // =======================================================================
    // Helper Functions - Common operations used across tests
    // =======================================================================

    function _createPosition(
        address owner_,
        uint256 amount_,
        uint256 conversionPrice_
    ) internal returns (uint256 positionId_) {
        vm.prank(owner_);
        positionId_ = DEPOS.mint(amount_, conversionPrice_);
        return positionId_;
    }

    function _dealTokens(address to_, uint256 amount_) internal {
        deal(address(TOKEN), to_, amount_);
    }

    function _warp(uint256 timestamp_) internal {
        vm.warp(timestamp_);
    }

    // =======================================================================
    // Assertion Helpers - Common state checks
    // =======================================================================

    function _assertPosition(
        uint256 positionId_,
        address expectedOwner_,
        uint256 expectedRemaining_
    ) internal view {
        (address owner,, uint256 remaining,,,) = DEPOS.positions(positionId_);
        assertEq(owner, expectedOwner_, "position owner mismatch");
        assertEq(remaining, expectedRemaining_, "position remaining mismatch");
    }

    // =======================================================================
    // State Modifiers - Establish commonly-used test states
    // =======================================================================

    modifier givenPositionExists(uint256 positionId_) {
        _createPosition(user, 100e18, 1e9);
        _;
    }

    modifier givenContractIsEnabled() {
        vm.prank(admin);
        DEPOS.setEnabled(true);
        _;
    }
}

// src/test/modules/DEPOS/mint.t.sol - Inherits from parent
contract MintTest is DEPOSTest {
    function test_whenAmountIsZero_reverts() public {
        // Can use DEPOS, godmode, admin, user directly
        // Can call _createPosition(), _dealTokens(), etc.
        // Can apply modifiers like givenPositionExists
    }
}
```

**Parent contract structure:**

1. **State variables** - Shared contract addresses, test accounts
2. **setUp()** - Deploy contracts, set initial state
3. **Helper functions** - `_createPosition()`, `_dealTokens()`, `_warp()`
4. **Assertion helpers** - `_assertPosition()`, `_assertBalance()`
5. **State modifiers** - `givenPositionExists()`, `givenContractIsEnabled()`

This keeps child test files focused on the specific function being tested, while all common setup and utilities live in the parent.

## Test Modifiers for State Setup

State modifiers are defined in the parent test contract and used by child tests to establish commonly-used states.

### Naming Convention

Two modifier prefixes with distinct purposes:

| Prefix   | Purpose                                                      | Example                                         |
| -------- | ------------------------------------------------------------ | ----------------------------------------------- |
| `given*` | Establish existing state (objects, contracts, configuration) | `givenPositionExists`, `givenContractIsEnabled` |
| `when*`  | Denote parameter has a specific value or property            | `whenAmountIsZero`, `whenCallerIsNotAdmin`      |

**`given*` modifiers** - Set up state before the test:

```solidity
// Creates a position before test runs
modifier givenPositionExists(uint256 positionId_) {
    _createPosition(user, 100e18, 1e9);
    _;
}

// Enables the contract before test runs
modifier givenContractIsEnabled() {
    vm.prank(admin);
    DEPOS.setEnabled(true);
    _;
}
```

**`when*` modifiers** - Describe parameter conditions (less common, but useful for clarity):

```solidity
// Indicates the test uses zero amount
modifier whenAmountIsZero() {
    _; // Just a marker, actual zero passed in test
}

// Indicates the caller is not admin
modifier whenCallerIsNotAdmin() {
    _; // Just a marker, actual caller set in test
}

// Usage example
function test_givenPositionExists_whenAmountIsZero_reverts() public
    givenPositionExists(1)
    whenAmountIsZero
{
    // Position exists (given*)
    // Amount is zero (when*)
    vm.expectRevert(abi.encodeWithSelector(IContract.CONTRACT_InvalidAmount.selector));
    DEPOS.burn(1, 0);
}
```

**Common modifier patterns:**

```solidity
// GOOD - Clear state setup via modifier
modifier givenPositionExists(uint256 positionId_) {
    _createPosition(positionId_);
    _;
}

modifier givenContractIsEnabled() {
    vm.prank(admin);
    contract.setEnabled(true);
    _;
}

modifier givenUserHasAllowance(address owner_, uint256 amount_) {
    vm.prank(owner_);
    token.approve(spender, amount_);
    _;
}
```

### Usage in Tests

```solidity
function test_givenPositionExists_whenAmountIsZero_reverts() public givenPositionExists(1) {
    // Test logic here - position already exists
}
```

### Anti-Patterns to Avoid

```solidity
// BAD - Setting state in each test
function test_something() public {
    vm.prank(admin);
    contract.setEnabled(true);
    // ... test logic
}

function test_anotherThing() public {
    vm.prank(admin);
    contract.setEnabled(true);
    // ... test logic
}

// GOOD - Use modifier instead
function test_something() public givenContractIsEnabled {
    // ... test logic
}

function test_anotherThing() public givenContractIsEnabled {
    // ... test logic
}
```

## External Function Coverage Matrix

Before implementation, classify every changed external function against each category below. Add
focused tests for every applicable matrix cell. Record why a category is not applicable instead of
silently omitting it.

### Caller Authorization

- Cover every permitted caller class separately.
- Fuzz unauthorized callers. Exclude every authorized identity and any address with distinct
    semantics, such as `address(0)`, with `vm.assume()`.
- Fuzz the caller for permissionless functions to prove execution does not depend on one fixed
    address.
- Cover direct and delegated authorization, expiry, cancellation, and self-authorization when the
    contract supports them.

```solidity
function test_whenCallerIsNotAuthorized_reverts(address caller_) public {
    vm.assume(caller_ != owner);
    vm.assume(caller_ != operator);
    vm.assume(caller_ != address(0));

    vm.expectRevert(abi.encodeWithSelector(IContract.NotAuthorized.selector));
    vm.prank(caller_);
    target.restrictedAction();
}

function test_givenActionIsReady(address caller_) public {
    vm.prank(caller_);
    target.permissionlessAction();

    assertTrue(target.actionExecuted(), "action should be executed");
}
```

### Contract State

Classify each function as enabled-only, intentionally callable while disabled, independent of the
enabled state, or dependent on re-enable validation. Test enabled and disabled behavior explicitly.
Test the re-enabled state separately when re-enablement can refresh dependencies or assumptions.

### Input Boundaries

- Cover zero, one, the semantic minimum and maximum, and representable values immediately below
    and above each limit. For every numeric input, explicitly test its maximum representable value,
    such as `type(uint256).max`, whether it should succeed or revert.
- For a cap `L`, normally prove that the exact cap succeeds and `L + 1` reverts.
- Cover zero/non-zero addresses, empty/single-item/maximum-size collections, duplicate entries,
    malformed encodings, and enum or selector boundaries when relevant.
- Cover rounding thresholds and decimal-scale combinations when arithmetic behavior can change.
- Choose each fuzzed numeric range from the behavior being proved, including valid and invalid
    intervals. One interior fuzz case does not prove boundary behavior.
- Use `bound()` to map numeric inputs into that exact target interval. Never map an invalid-input
    test into the valid interval, and keep explicit boundary tests alongside range fuzzing.

### State Transitions

Cover applicable pairs such as absent/existing, uninitialized/initialized, inactive/active,
current/stale, before/at/after a transition, and first/subsequent execution. Assert the resulting
state; proving that an operation was queued or previewed is not proof that the transition succeeds.

### Accounting And External Interactions

- Assert authoritative balance, custody, or share deltas rather than nominal input amounts.
- Assert affected per-user and aggregate accounting together.
- Document and verify rounding direction.
- Verify complete rollback when an external interaction fails.
- Exercise callback or token reentrancy where the function crosses an untrusted boundary.

### Read/Write Consistency

For previews and getters that correspond to a state-changing action, verify both successful output
and equivalent failure conditions beside the action tests. Do not remove unique read-path coverage
when consolidating files.

### Invariant Tests

Add stateful invariant tests when correctness depends on relationships that must survive arbitrary
call sequences. Strong candidates include aggregate accounting equaling the sum of positions,
custody covering liabilities, lifecycle transitions preserving reachability, authorization never
expanding unexpectedly, and enabled-state transitions preserving safety. Exercise realistic handler
actions and actors. Keep explicit unit tests for individual boundaries and revert paths; invariant
tests complement rather than replace them.

## Branching Tree Test Naming

Use the branching tree pattern to organize tests by conditions and behaviors. Use `given` only for
pre-existing state and `when` only for function parameters or other inputs to the operation:

```solidity
// given <condition>
//   when <parameter>
//     [X] it <expected result>

function test_given<Condition>_when<Parameter>() {
    // test code with multiple assertions
}
```

**Nested conditions** - Document the branching structure in comments:

```solidity
// given vault is below capacity
//   when amount exceeds remaining capacity
//     [X] it reverts
//   when amount equals remaining capacity
//     [X] it mints shares
//     [X] it emits Deposit event

function test_givenVaultBelowCapacity_whenAmountExceedsRemainingCapacity_reverts() public {
    // test code
}

function test_givenVaultBelowCapacity_whenAmountEqualsRemainingCapacity() public {
    // test code
}
```

**Multiple conditions in function name:** A test can have multiple `given*` and/or `when*` segments.
Repeat the prefix for every condition, including multiple parameter conditions such as
`whenCondition1_whenCondition2`:

```solidity
// Multiple given* conditions:
function test_givenPositionExists_givenContractIsEnabled() public {
    // Position exists AND contract is enabled
}

// Multiple when* conditions:
function test_whenAmountIsZero_whenCallerIsNotOwner() public {
    // Amount and caller are both function inputs
}

// Both given* and when* conditions:
function test_givenPositionExists_givenContractIsEnabled_whenAmountExceedsRemaining() public {
    // Position exists, contract enabled, amount exceeds remaining
}
```

### Parameterized Tests (first condition is `when`)

Tests that primarily vary input data parameters use `when` as the first condition. The key distinction:

| Prefix   | Meaning                                         | Example                                                 |
| -------- | ----------------------------------------------- | ------------------------------------------------------- |
| `given*` | Pre-existing state                              | `givenPositionExists`, `givenContractIsEnabled`         |
| `when*`  | Function parameters or other operation inputs   | `whenThreePrices`, `whenAmountIsZero`, `whenStrictMode` |

```solidity
// when input has 3 prices
//   when zero deviate from median
//     [X] it returns average of all prices

function test_whenThreePrices_whenZeroDeviate() public {
    // 3 prices = input parameter, not pre-existing state
    uint256[] memory prices = new uint256[](3);
    prices[0] = 1000e18;
    prices[1] = 1050e18;
    prices[2] = 1200e18;
    // test logic...
}

// when strict mode is enabled
//   when only one price remains
//     [X] it reverts

function test_whenStrictMode_whenOneRemains_reverts() public {
    // Configuration parameter test
    bytes memory params = encodeDeviationParams(1000, true); // strict mode
    // test logic...
}
```

**Note:** Don't include the expected result in the function name. A single test often has multiple
assertions/checks. The `_reverts` suffix is the sole permitted outcome suffix.

**Ordering:** Write error/revert tests first, then success tests. This makes failures easier to spot.

### Fuzz Test Naming

Foundry identifies fuzz tests from their parameters. Name the behavior being proven; do not add a
`testFuzz_` prefix or `_fuzz` suffix.

**Pattern:** `test_given<Condition>(...)` or `test_when<Parameter>(...)`

```solidity
// GOOD - the name describes the property; the parameter makes it a fuzz test
function test_whenInputArrayLengthIsLessThanThree(uint8 length) public {
    uint8 boundedLength = uint8(bound(length, 0, 2));
    // boundedLength is now in range [0, 2]
    // test logic
}

function test_whenThreePrices_whenDeviationIsValid(
    uint64 price1,
    uint64 price2,
    uint64 price3,
    uint16 deviationBps
) public view {
    uint64 boundedPrice1 = uint64(bound(price1, 1e9, 1e19));
    // boundedPrice1 is now in range [1e9, 1e19]
    // test logic
}

// BAD - fuzzing mechanism encoded in the name
function testFuzz_whenInputArrayLengthIsLessThanThree(uint8 length) public {
    // ...
}

function test_whenInputArrayLengthIsLessThanThree_fuzz(uint8 length) public {
    // ...
}
```

**Fuzz test naming guidelines:**

- Use the standard branching-tree name without `testFuzz_` or `_fuzz`
- Follow the same branching tree pattern as unit tests
- Choose the numeric target range from the behavior the test proves
- Use `bound()` to map numeric inputs into that exact valid or invalid interval
- Use `vm.assume()` for non-numeric or complex constraints
- Document the target interval and why it matches the tested behavior

**Use `bound()` to target the numeric interval under test:**

Foundry has a limit on the number of discarded fuzz inputs. Using `vm.assume()` to constrain a
numeric input can exhaust this limit when most generated values fall outside the target interval.
Derive that interval from the behavior being proved, then use `bound()` to map inputs into it. The
target may be a valid interval for a success test or an invalid interval for a revert test.

```solidity
// BAD - vm.assume() discards too many values
function test_whenAmountIsAtMostOneThousand(uint256 amount) public {
    // This discards nearly all uint256 values except 0-1000
    vm.assume(amount <= 1000);
    // Test will fail with "Fuzz testing ran out of inputs"
}

// GOOD - the success behavior targets the exact valid interval [0, 1000]
function test_whenAmountIsAtMostOneThousand(uint256 amount) public {
    uint256 boundedAmount = bound(amount, 0, 1000);
    // boundedAmount is in the valid interval this test proves
}

// GOOD - the revert behavior targets the exact invalid interval [1001, type(uint256).max]
function test_whenAmountExceedsOneThousand_reverts(uint256 amount) public {
    uint256 boundedAmount = bound(amount, 1001, type(uint256).max);
    // boundedAmount remains invalid; it is never mapped into the valid interval
}

// GOOD - vm.assume() for non-numeric or complex constraints
function test_whenAddressIsNotZero(address addr) public {
    vm.assume(addr != address(0));
    // Only discards 1 out of 2^160 values - acceptable
}

// GOOD - use bound() even for a narrow numeric target interval
function test_whenArrayLengthIsBetweenOneAndTen(uint8 length) public {
    uint8 boundedLength = uint8(bound(length, 1, 10));
    // boundedLength is in the exact interval this behavior requires
}
```

**When to use `bound()` vs `vm.assume()`:**

| Scenario                       | Use           | Example                                                    |
| ------------------------------ | ------------- | ---------------------------------------------------------- |
| Exact valid numeric interval   | `bound()`     | `uint8(bound(len, 1, 10))` when `[1, 10]` should succeed   |
| Exact invalid numeric interval | `bound()`     | `bound(amount, 1001, type(uint256).max)` for a revert test |
| Non-numeric constraints        | `vm.assume()` | `vm.assume(addr != address(0))`                            |
| Complex multi-variable         | `vm.assume()` | `vm.assume(x > y)`                                         |
| Address is not zero            | `vm.assume()` | `vm.assume(addr != address(0))`                            |

**Why `bound()` is better for numeric ranges:**

When a fuzzer generates a random `uint256`, nearly all values may be outside a small target range.
For example, targeting `0 <= x <= 1000` discards 99.9999% of inputs. The `bound()` function wraps
the input using modulo arithmetic to keep it in the chosen valid or invalid interval without
discarding:

```solidity
// bound() implementation (simplified)
function bound(uint256 x, uint256 min, uint256 max) pure returns (uint256) {
    return min + (x % (max - min + 1));
}

// This never discards - the fuzzer's random value is transformed into range
```

### Examples

```solidity
// === ERROR CONDITIONS (write these first) ===

// when caller is not admin
//   [X] it reverts

function test_whenCallerIsNotAdmin_reverts() public {
    address nonAdmin = makeAddr("nonAdmin");
    vm.expectRevert(abi.encodeWithSelector(ROLES.ROLES_RequireRole.selector));
    vm.prank(nonAdmin);
    DEPOS.mint(100e18, 1e9);
}

// given position exists
//   when amount is zero
//     [X] it reverts

function test_givenPositionExists_whenAmountIsZero_reverts() public {
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidAmount.selector));
    DEPOS.burn(positionId, 0);
}

// given position exists
//   when amount exceeds remaining
//     [X] it reverts with InsufficientRemaining error

function test_givenPositionExists_whenAmountExceedsRemaining_reverts() public {
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_InsufficientRemaining.selector));
    DEPOS.burn(positionId, 200e18);
}

// === NESTED CONDITIONS ===

// given position exists
//   given position is expired
//     [X] it reverts

function test_givenPositionExists_givenPositionExpired_reverts() public {
    uint256 positionId = _createPosition(user, 100e18, 1e9);
    _warp(block.timestamp + 31 days);

    vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_PositionExpired.selector));
    DEPOS.burn(positionId, 50e18);
}

// === SUCCESS CONDITIONS WITH MULTIPLE ASSERTIONS ===

// given position exists
//   when amount equals remaining
//     [X] it closes the position
//     [X] it emits PositionClosed event
//     [X] it returns zero

function test_givenPositionExists_whenAmountEqualsRemaining() public {
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.expectEmit(true, true, true, true);
    emit IDepositPositionManager.PositionClosed(positionId, user);

    DEPOS.burn(positionId, 100e18);

    // Verify position is closed
    (, , uint256 remaining, , , ) = DEPOS.positions(positionId);
    assertEq(remaining, 0, "position should be empty");
}

// given position exists
//   given position is wrapped
//     given transfer caller is approved
//       when transfer caller transfers the position
//         [X] approval preserves the owner
//         [X] transfer updates the owner
//         [X] transfer preserves the remaining deposit

function test_givenPositionExists_givenPositionIsWrapped_givenTransferCallerIsApproved_whenTransferCallerTransfersPosition()
    public
{
    address transferCaller = makeAddr("transferCaller");
    address recipient = makeAddr("recipient");
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.prank(user);
    DEPOS.wrap(positionId);

    vm.prank(user);
    DEPOS.approve(transferCaller, positionId);

    IDepositPositionManager.Position memory positionBefore = DEPOS.getPosition(positionId);
    assertEq(positionBefore.owner, user, "approval should not change the position owner");

    vm.prank(transferCaller);
    DEPOS.transferFrom(user, recipient, positionId);

    IDepositPositionManager.Position memory positionAfter = DEPOS.getPosition(positionId);
    assertEq(positionAfter.owner, recipient, "transfer should update the position owner");
    assertEq(
        positionAfter.remainingDeposit,
        positionBefore.remainingDeposit,
        "transfer should preserve the remaining deposit"
    );
}
```

## Error Handling in Tests

### Match Specific Revert Data

Match the failure path being tested, not merely the fact that some call reverted. Use the custom
error selector, and include the encoded arguments when their values are part of the behavior being
proved.

Do not use zero-argument `vm.expectRevert()` by default. It accepts any revert and can pass when the
call fails for the wrong reason. Use it only when an opaque external dependency provides no stable
revert data, and document why a stronger match is impossible.

**GOOD - Error selector:**

```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        IDepositPositionManager.DEPOS_InsufficientRemaining.selector
    )
);
```

**BAD - Any revert or string message:**

```solidity
vm.expectRevert();
vm.expectRevert("Insufficient remaining");
vm.expectRevert("UNAUTHORIZED");
```

### Helper Functions for Common Reverts

Create helper functions for frequently-used revert checks:

```solidity
function _expectRevertNotAdmin() internal {
    vm.expectRevert(
        abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("admin"))
    );
}

function _expectRevertInvalidParams(string memory param) internal {
    vm.expectRevert(
        abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidParams.selector, param)
    );
}

// Usage
function test_whenCallerIsNotAdmin_reverts() public {
    address nonAdmin = makeAddr("nonAdmin");
    _expectRevertNotAdmin();
    vm.prank(nonAdmin);
    contract.restrictedFunction();
}
```

### Custom Errors vs Require Messages

- **Custom errors** (in contracts): Define in the contract's interface
- **Custom errors** (in tests): Use selectors from the interface
- **Empty revert matching**: Use only for an opaque dependency with no stable revert data, and
  document the reason
- **Never** use string revert messages

## Assertion Best Practices

### Informative Messages

Always include a message explaining what's being asserted:

```solidity
// GOOD
assertEq(position.owner, user, "position.owner should equal user");
assertEq(amount, 0, "amount should be zero after burn");

// BAD
assertEq(position.owner, user);
assertEq(amount, 0);
```

### Helper Functions for Assertions

Create assertion helpers for complex state checks:

```solidity
function _assertPosition(
    uint256 positionId_,
    address owner_,
    uint256 remainingDeposit_,
    uint256 conversionPrice_,
    uint48 conversionExpiry_,
    bool wrap_
) internal view {
    IDepositPositionManager.Position memory position = DEPOS.getPosition(positionId_);
    assertEq(position.operator, godmode, "position.operator");
    assertEq(position.owner, owner_, "position.owner");
    assertEq(position.remainingDeposit, remainingDeposit_, "position.remainingDeposit");
    assertEq(position.conversionPrice, conversionPrice_, "position.conversionPrice");
    assertEq(position.conversionExpiry, conversionExpiry_, "position.conversionExpiry");
    assertEq(position.wrap, wrap_, "position.wrap");
}
```

## Mathematical Reasoning in Tests

Document the decimal arithmetic step-by-step:

```solidity
// deposit = 5e18 (18 decimals)
// ohmScale = 1e9 (9 decimals)
// price = 2e18 (18 decimals)
// Expected: (5e18 * 1e9) / 2e18 = 5e27 / 2e18 = 2.5e9 (9 decimals)
// Rounds down to 2e9
assertEq(convertibleAmount, 2e9, "Convertible amount does not equal 2e9");
```

## Anti-Patterns Summary

| Pattern                                   | Avoid                                          | Use Instead                                                                                           |
| ----------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| State setup                               | Inline in each test                            | `given*` modifiers                                                                                    |
| Test naming                               | `test_somethingBad`                            | `test_givenCondition_whenParameter` (success) or `test_givenCondition_whenParameter_reverts` (revert) |
| Fuzz test naming                          | `testFuzz_*` or `test_*_fuzz`                  | Standard branching-tree name; parameters identify fuzzing                                             |
| Constraining numeric ranges in fuzz       | `bound()` into a range unrelated to the named behavior | Choose the exact valid or invalid interval first, then use `bound()`                                   |
| Error testing                             | Empty or string-based `vm.expectRevert`         | Match the selector or fully encoded custom error                                                       |
| Assertions                                | `assertEq(a, b)`                               | `assertEq(a, b, "description")`                                                                       |
| File organization                         | Multiple external actions per file             | One external state-changing action per file; co-locate corresponding preview/getter assertions        |

## Checklist for New Test Files

- [ ] File is organized around the external action being tested
- [ ] Inherits from appropriate parent test contract
- [ ] Uses `given*` modifiers for state setup
- [ ] Uses `given` for pre-existing state and `when` for function parameters or operation inputs
- [ ] Repeats `given` and `when` segments when the test has multiple conditions
- [ ] Fuzz test names do not use a `testFuzz_` prefix or `_fuzz` suffix
- [ ] Each numeric fuzz target is the exact valid or invalid interval for the behavior being proved;
      `bound()` maps into that interval, while `vm.assume()` handles non-numeric or complex constraints
- [ ] Caller matrix covers every authorized class, fuzzed unauthorized callers, and fuzzed callers
        for permissionless functions
- [ ] Enabled, disabled, and re-enabled behavior is covered where applicable
- [ ] Numeric tests cover valid and invalid ranges, exact semantic boundaries, adjacent values, and
        the type's maximum representable value with explicit boundary tests
- [ ] State-transition tests assert the resulting state, not only queue or preview behavior
- [ ] Accounting tests use authoritative deltas and cover rollback and reentrancy where applicable
- [ ] Corresponding preview/getter and write behavior agree without losing unique read-path coverage
- [ ] Stateful invariant tests cover applicable accounting, custody, lifecycle, authorization, and
        enabled-state properties
- [ ] Revert tests match specific error data; any empty `vm.expectRevert()` documents why stronger
      matching is impossible
- [ ] All assertions have descriptive messages
- [ ] Mathematical reasoning documented in comments
- [ ] Tests cover applicable state and input edge cases
