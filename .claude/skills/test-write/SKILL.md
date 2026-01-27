---
description: Guide for writing test files following Olympus V3 testing standards
---

# Test Writing Guide

This guide covers the standards for writing test files in the Olympus V3 codebase.

## File Organization

### One Function Per File

Each contract function should have its own dedicated test file. This keeps tests focused and makes navigation easier.

**Examples:**

- `src/test/modules/DEPOS/mint.t.sol` - Tests for the `mint()` function
- `src/test/modules/DEPOS/burn.t.sol` - Tests for the `burn()` function
- `src/test/modules/MINTR/periodicTasks.t.sol` - Tests for periodic task functions

**File naming:**

- Use lowercase, descriptive names: `mint.t.sol`, `addPeriodicTask.t.sol`
- Use `.t.sol` extension for test files
- Match the function name being tested

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
    function test_givenAmountZero_mint() public {
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

| Prefix | Purpose | Example |
|--------|---------|---------|
| `given*` | Establish existing state (objects, contracts, configuration) | `givenPositionExists`, `givenContractIsEnabled` |
| `when*` | Denote parameter has a specific value or property | `whenAmountIsZero`, `whenCallerIsNotAdmin` |

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
function test_givenPositionExists_whenAmountIsZero() public
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
function test_givenPositionExists_whenBurn_reverts() public givenPositionExists(1) {
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

## Branching Tree Test Naming

Use the branching tree pattern to organize tests by conditions and behaviors:

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
//   when the deposit causes the vault to hit or exceed capacity
//     [X] it reverts
//   when the deposit does not cause the vault to hit capacity
//     [X] it mints shares
//     [X] it emits Deposit event

function test_givenVaultBelowCapacity_whenDepositExceeds_reverts() public {
    // test code
}

function test_givenVaultBelowCapacity_whenDepositWithinCapacity() public {
    // test code
}
```

**Multiple conditions in function name:** A test can have multiple `given*` and/or `when*` prefixes:

```solidity
// Multiple given* conditions:
function test_givenPositionExists_givenContractIsEnabled() public {
    // Position exists AND contract is enabled
}

// Multiple when* conditions:
function test_givenPositionExists_whenAmountIsZero_whenCallerIsNotOwner() public {
    // Position exists, amount is zero, caller is not owner
}

// Both given* and when* conditions:
function test_givenPositionExists_givenContractIsEnabled_whenAmountExceedsRemaining() public {
    // Position exists, contract enabled, amount exceeds remaining
}
```

### Parameterized Tests (first condition is `when`)

Tests that primarily vary input data parameters use `when` as the first condition. The key distinction:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `given*` | State (pre-existing conditions) | `givenPositionExists`, `givenContractIsEnabled` |
| `when*` | Parameters (input/config being tested) | `whenThreePrices`, `whenAmountIsZero`, `whenStrictMode` |

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

**Note:** Don't include the expected result in the function name. A single test often has multiple assertions/checks.

**Ordering:** Write error/revert tests first, then success tests. This makes failures easier to spot.

### Fuzz Test Naming

Fuzz tests use Foundry's property-based testing to verify behavior with random inputs. Use the `_fuzz` suffix to distinguish fuzz tests from unit tests.

**Pattern:** `test_given<Condition>_fuzz(...)` or `test_when<Parameter>_fuzz(...)`

**DO NOT use:** `testFuzz_` prefix (this is an anti-pattern)

```solidity
// GOOD - _fuzz suffix
function test_givenInputArrayLengthLessThanThree_fuzz(uint8 length) public {
    vm.assume(length < 3);
    // test logic
}

function test_givenThreePricesWithValidDeviation_fuzz(
    uint64 price1,
    uint64 price2,
    uint64 price3,
    uint16 deviationBps
) public view {
    vm.assume(price1 >= 1e9 && price1 <= 1e19);
    // test logic
}

// BAD - testFuzz_ prefix (anti-pattern)
function testFuzz_givenInputArrayLessThanThree(uint8 length) public {
    // ...
}
```

**Fuzz test naming guidelines:**

- Always use `_fuzz` suffix, never `testFuzz_` prefix
- Follow the same branching tree pattern as unit tests
- Use `bound()` for constraining numeric values (preferred over `vm.assume()`)
- Use `vm.assume()` only for non-numeric constraints or when `bound()` is not feasible
- Document the bounds being tested in comments

**Use `bound()` instead of `vm.assume()` for numeric values:**

Foundry has a limit on the number of discarded fuzz inputs. Using `vm.assume()` to constrain a large range to a small range will exhaust this limit and cause the fuzz test to fail.

```solidity
// BAD - vm.assume() discards too many values
function test_givenLargeAmount_fuzz(uint256 amount) public {
    // This discards nearly all uint256 values except 0-1000
    vm.assume(amount <= 1000);
    // Test will fail with "Fuzz testing ran out of inputs"
}

// GOOD - use bound() to constrain the input
function test_givenLargeAmount_fuzz(uint256 amount) public {
    uint256 boundedAmount = bound(amount, 0, 1000);
    // boundedAmount is now in range [0, 1000]
}

// GOOD - vm.assume() for non-numeric or complex constraints
function test_givenAddressNotZero_fuzz(address addr) public {
    vm.assume(addr != address(0));
    // Only discards 1 out of 2^160 values - acceptable
}

// GOOD - vm.assume() for tight numeric ranges
function test_givenSmallArray_fuzz(uint8 length) public {
    vm.assume(length > 0 && length <= 10);
    // Only discards 246 out of 256 values - acceptable
}
```

**When to use `bound()` vs `vm.assume()`:**

| Scenario | Use | Example |
|----------|-----|---------|
| Constrain large numeric range | `bound()` | `bound(value, 0, 1000)` for `uint256 value` |
| Constrain small numeric range | Either | `vm.assume(len < 10)` for `uint8 len` (only ~46 values discarded) |
| Non-numeric constraints | `vm.assume()` | `vm.assume(addr != address(0))` |
| Complex multi-variable | `vm.assume()` | `vm.assume(x > y)` |
| Address is not zero | `vm.assume()` | `vm.assume(addr != address(0))` |

**Why `bound()` is better for large ranges:**

When a fuzzer generates a random `uint256`, nearly all values will be outside a small target range. For example, targeting `0 <= x <= 1000` discards 99.9999% of inputs. The `bound()` function wraps the input using modulo arithmetic to keep it in range without discarding:

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

// given the caller is not admin
//   when mint is called
//     [X] it reverts

function test_givenCallerNotAdmin() public {
    vm.expectRevert(abi.encodeWithSelector(ROLES.ROLES_RequireRole.selector));
    DEPOS.mint(100e18, 1e9);
}

// given the amount is zero
//   when burn is called
//     [X] it reverts

function test_givenAmountIsZero() public {
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_InvalidAmount.selector));
    DEPOS.burn(positionId, 0);
}

// given position exists
//   when amount exceeds remaining
//     [X] it reverts with InsufficientRemaining error

function test_givenPositionExists_whenAmountExceedsRemaining() public {
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.expectRevert(abi.encodeWithSelector(IDepositPositionManager.DEPOS_InsufficientRemaining.selector));
    DEPOS.burn(positionId, 200e18);
}

// === NESTED CONDITIONS ===

// given position exists
//   given position is expired
//     when burn is called
//       [X] it reverts

function test_givenPositionExists_givenPositionExpired() public {
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
//   given user has allowance
//     when third party burns
//       [X] it decreases remaining
//       [X] it updates owner
//       [X] it emits Transfer event

function test_givenPositionExists_givenUserHasAllowance_whenThirdPartyBurns() public {
    address thirdParty = makeAddr("thirdParty");
    uint256 positionId = _createPosition(user, 100e18, 1e9);

    vm.prank(user);
    DEPOS.setApprovalForAll(thirdParty, true);

    vm.expectEmit(true, true, true, true);
    emit IERC20.Transfer(user, thirdParty, 50e18);

    vm.prank(thirdParty);
    DEPOS.burn(positionId, 50e18);

    (, , uint256 remaining, , , ) = DEPOS.positions(positionId);
    assertEq(remaining, 50e18, "remaining should be 50");
}
```

## Error Handling in Tests

### Always Use Error Selectors

**GOOD - Error selector:**

```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        IDepositPositionManager.DEPOS_InsufficientRemaining.selector
    )
);
```

**BAD - String message:**

```solidity
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
function test_givenCallerNotAdmin_reverts() public {
    _expectRevertNotAdmin();
    contract.restrictedFunction();
}
```

### Custom Errors vs Require Messages

- **Custom errors** (in contracts): Define in the contract's interface
- **Custom errors** (in tests): Use selectors from the interface
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

| Pattern | Avoid | Use Instead |
|---------|-------|-------------|
| State setup | Inline in each test | `given*` modifiers |
| Test naming | `test_somethingBad` | `test_givenCondition_whenParameter` (success) or `test_givenCondition_whenParameter_reverts` (revert) |
| Fuzz test naming | `testFuzz_*` | `test_givenCondition_fuzz` or `test_whenParameter_fuzz` |
| Constraining large numeric ranges in fuzz | `vm.assume(value <= 1000)` for `uint256 value` | `bound(value, 0, 1000)` |
| Error testing | `vm.expectRevert("message")` | `abi.encodeWithSelector(Error.selector)` |
| Assertions | `assertEq(a, b)` | `assertEq(a, b, "description")` |
| File organization | Multiple functions per file | One function per file |

## Checklist for New Test Files

- [ ] File named after the function being tested
- [ ] Inherits from appropriate parent test contract
- [ ] Uses `given*` modifiers for state setup
- [ ] Follows branching tree naming convention
- [ ] Fuzz tests use `_fuzz` suffix, not `testFuzz_` prefix
- [ ] Fuzz tests use `bound()` for large numeric ranges, `vm.assume()` for small ranges/non-numeric
- [ ] Uses error selectors, not string messages
- [ ] All assertions have descriptive messages
- [ ] Mathematical reasoning documented in comments
- [ ] Tests cover edge cases (min, max, zero, boundary values)
