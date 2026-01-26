# Sample Test File

This is a reference example demonstrating the Olympus V3 testing standards.

## Parent Test Contract: `SimpleVaultTest.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {SimpleVault} from "src/SimpleVault.sol";
import {ISimpleVault} from "src/interfaces/ISimpleVault.sol";

/// @title Parent test contract for SimpleVault
/// @notice Contains shared setup, helpers, assertions, and state modifiers
abstract contract SimpleVaultTest is Test {
    // =======================================================================
    // State Variables (accessible to all child tests)
    // =======================================================================

    ISimpleVault public vault;
    address public godmode;
    address public admin;
    address public user;
    address public other;

    // =======================================================================
    // setUp() - Contract deployment and initial configuration
    // =======================================================================

    function setUp() public virtual {
        godmode = address(this);
        admin = makeAddr("admin");
        user = makeAddr("user");
        other = makeAddr("other");

        vm.startPrank(godmode);
        vault = ISimpleVault(address(new SimpleVault()));
        vault.setAdmin(admin);
        vm.stopPrank();
    }

    // =======================================================================
    // Helper Functions - Common operations used across tests
    // =======================================================================

    /// @notice Deposit tokens into the vault
    function _deposit(address caller_, uint256 amount_) internal {
        deal(address(vault.asset()), caller_, amount_);
        vm.prank(caller_);
        vault.asset().approve(address(vault), amount_);
        vm.prank(caller_);
        vault.deposit(amount_, caller_);
    }

    /// @notice Create a deposit for a user
    function _createDeposit(address user_, uint256 amount_) internal returns (uint256 shares_) {
        deal(address(vault.asset()), user_, amount_);
        vm.startPrank(user_);
        vault.asset().approve(address(vault), amount_);
        shares_ = vault.deposit(amount_, user_);
        vm.stopPrank();
        return shares_;
    }

    /// @notice Warp time forward
    function _warp(uint256 timestamp_) internal {
        vm.warp(timestamp_);
    }

    // =======================================================================
    // Assertion Helpers - Common state checks
    // =======================================================================

    /// @notice Assert vault has expected balance
    function _assertVaultBalance(uint256 expected_) internal view {
        assertEq(
            vault.asset().balanceOf(address(vault)),
            expected_,
            "vault balance mismatch"
        );
    }

    /// @notice assert user has expected shares
    function _assertUserShares(address user_, uint256 expectedShares_) internal view {
        assertEq(
            vault.balanceOf(user_),
            expectedShares_,
            "user shares mismatch"
        );
    }

    /// @notice Assert total supply matches expected
    function _assertTotalSupply(uint256 expected_) internal view {
        assertEq(
            vault.totalSupply(),
            expected_,
            "total supply mismatch"
        );
    }

    // =======================================================================
    // State Modifiers - Establish commonly-used test states
    // =======================================================================

    /// @notice Vault is paused
    modifier givenVaultPaused() {
        vm.prank(admin);
        vault.pause();
        _;
    }

    /// @notice User has a deposit
    modifier givenUserHasDeposit() {
        _createDeposit(user, 100e18);
        _;
    }

    /// @notice Vault has max capacity reached
    modifier givenVaultAtCapacity() {
        _createDeposit(user, vault.MAX_CAPACITY());
        _;
    }

    /// @notice Emergency withdrawal is enabled
    modifier givenEmergencyEnabled() {
        vm.prank(admin);
        vault.setEmergency(true);
        _;
    }
}
```

## Function-Specific Test File: `deposit.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {SimpleVaultTest} from "./SimpleVaultTest.sol";
import {ISimpleVault} from "src/interfaces/ISimpleVault.sol";

/// @title Tests for deposit() function
/// @notice Test file follows branching tree pattern with error conditions first
contract DepositTest is SimpleVaultTest {
    event Deposit(address indexed caller, uint256 amount, uint256 shares);

    // =======================================================================
    // ERROR CONDITIONS (write these first)
    // =======================================================================

    // given the vault is paused
    //   when deposit is called
    //     [X] it reverts

    function test_givenVaultPaused_whenDeposit_reverts() public givenVaultPaused {
        deal(address(vault.asset()), user, 100e18);
        vm.startPrank(user);
        vault.asset().approve(address(vault), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ISimpleVault.VAULT_Paused.selector));
        vault.deposit(100e18, user);

        vm.stopPrank();
    }

    // given the amount is zero
    //   when deposit is called
    //     [X] it reverts

    function test_givenAmountIsZero_whenDeposit_reverts() public {
        deal(address(vault.asset()), user, 100e18);
        vm.startPrank(user);
        vault.asset().approve(address(vault), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ISimpleVault.VAULT_InvalidAmount.selector));
        vault.deposit(0, user);

        vm.stopPrank();
    }

    // given vault is at capacity
    //   when deposit is called
    //     [X] it reverts

    function test_givenVaultAtCapacity_whenDeposit_reverts() public givenVaultAtCapacity {
        deal(address(vault.asset()), user, 1e18);
        vm.startPrank(user);
        vault.asset().approve(address(vault), 1e18);

        vm.expectRevert(abi.encodeWithSelector(ISimpleVault.VAULT_CapacityExceeded.selector));
        vault.deposit(1e18, user);

        vm.stopPrank();
    }

    // given user has no allowance
    //   when deposit is called
    //     [X] it reverts

    function test_givenUserHasNoAllowance_whenDeposit_reverts() public {
        deal(address(vault.asset()), user, 100e18);
        vm.prank(user);

        vm.expectRevert();
        vault.deposit(100e18, user);
    }

    // =======================================================================
    // SUCCESS CONDITIONS WITH MULTIPLE ASSERTIONS
    // =======================================================================

    // given valid parameters
    //   when deposit is called
    //     [X] it mints shares to receiver
    //     [X] it transfers tokens from caller
    //     [X] it emits Deposit event
    //     [X] it updates total supply

    function test_givenValidParams_whenDeposit_mintsShares() public {
        // Arrange
        uint256 depositAmount = 100e18;
        deal(address(vault.asset()), user, depositAmount);
        vm.startPrank(user);
        vault.asset().approve(address(vault), depositAmount);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, depositAmount, depositAmount);

        // Act
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Assert - shares minted
        assertEq(shares, depositAmount, "shares should equal deposit amount");
        _assertUserShares(user, depositAmount);

        // Assert - tokens transferred
        assertEq(vault.asset().balanceOf(user), 0, "user should have 0 tokens");
        _assertVaultBalance(depositAmount);

        // Assert - total supply updated
        _assertTotalSupply(depositAmount);
    }

    // given user has existing deposit
    //   when deposit is called again
    //     [X] it adds to existing shares
    //     [X] it emits Deposit event

    function test_givenUserHasDeposit_whenDeposit_addsToExistingShares() public
        givenUserHasDeposit
    {
        // Arrange
        uint256 additionalAmount = 50e18;
        deal(address(vault.asset()), user, additionalAmount);
        vm.startPrank(user);
        vault.asset().approve(address(vault), additionalAmount);

        uint256 expectedShares = 150e18; // 100e18 existing + 50e18 new

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, additionalAmount, additionalAmount);

        // Act
        uint256 shares = vault.deposit(additionalAmount, user);
        vm.stopPrank();

        // Assert - shares added
        assertEq(shares, additionalAmount, "returned shares should equal deposit");
        _assertUserShares(user, expectedShares);

        // Assert - total supply updated
        _assertTotalSupply(expectedShares);
    }

    // =======================================================================
    // NESTED CONDITIONS
    // =======================================================================

    // given user has existing deposit
    //   given vault is nearly at capacity
    //     when deposit would exceed capacity
    //       [X] it reverts

    function test_givenUserHasDeposit_givenVaultNearlyAtCapacity_whenDepositExceeds_reverts()
        public
    {
        // Arrange - fill vault to 90% capacity
        uint256 nearCapacity = (vault.MAX_CAPACITY() * 90) / 100;
        _createDeposit(user, nearCapacity);

        uint256 excessAmount = vault.MAX_CAPACITY() - nearCapacity + 1;
        deal(address(vault.asset()), user, excessAmount);
        vm.startPrank(user);
        vault.asset().approve(address(vault), excessAmount);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(ISimpleVault.VAULT_CapacityExceeded.selector));
        vault.deposit(excessAmount, user);

        vm.stopPrank();
    }
}
```

## Key Standards Demonstrated

| Standard | Example |
|----------|---------|
| One function per file | `deposit.t.sol` only tests `deposit()` |
| Parent contract structure | `SimpleVaultTest` with sections for state, setup, helpers, assertions, modifiers |
| `given*` modifiers | `givenVaultPaused`, `givenUserHasDeposit` |
| Branching tree naming | `test_givenVaultPaused_whenDeposit_reverts()` |
| Error selectors | `abi.encodeWithSelector(ISimpleVault.VAULT_Paused.selector)` |
| Multiple assertions | Event check + share balance + vault balance + total supply |
| Error conditions first | All revert tests come before success tests |
| Nested conditions | Document branching in comments, separate functions for each branch |

## Branching Tree Comment Structure

```solidity
// given vault is below capacity
//   when the deposit causes the vault to hit or exceed capacity
//     [X] it reverts
//   when the deposit does not cause the vault to hit capacity
//     [X] it mints shares
//     [X] it emits Deposit event

function test_givenVaultBelowCapacity_whenDepositExceeds_reverts() public { }
function test_givenVaultBelowCapacity_whenDepositWithinCapacity_mintsShares() public { }
```
