// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";

contract BurnerLoansCompositesExecuteGrantConditionsTest is BurnerLoansCompositesGrantModesTest {
    // Scenarios: BLREX-P19.
    function test_givenCollateralBelowCeiling_whenDepositFitsGrantCeiling(
        uint128 amount_,
        uint128 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralBelowCeiling {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        // Both intervals fit uint128 and include the exact 1000e6 ceiling boundary.
        // forge-lint: disable-start(unsafe-typecast)
        uint128 amount = uint128(bound(amount_, 1, 600e6));
        permissions.maxCollateral = uint128(bound(limit_, 1000e6, type(uint128).max));
        // forge-lint: disable-end(unsafe-typecast)
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), amount),
            _single(_deposit(amount)),
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 1, "Allowed deposit executes once");
        // Add the raw deposit to the existing 400e6 collateral (six decimals).
        _assertSettled(400e6 + amount, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet - amount,
            "Only the accepted deposit is spent"
        );
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-A13.
    function test_givenCollateralBelowCeiling_whenDepositExceedsGrantCeiling_reverts(
        uint128 amount_,
        uint128 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralBelowCeiling {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        // Keep the resulting collateral representable so the grant limit decides the result.
        // forge-lint: disable-start(unsafe-typecast)
        uint128 amount = uint128(bound(amount_, 600e6 + 1, type(uint128).max - 400e6));
        permissions.maxCollateral = uint128(bound(limit_, 0, 1000e6));
        // forge-lint: disable-end(unsafe-typecast)
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        _asset.mint(_borrower, amount);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        // Existing 400e6 plus any selected deposit exceeds every ceiling in [0, 1000e6].
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), amount),
            _single(_deposit(amount)),
            new IExecutor.Output[](0)
        );
        _assertSettled(400e6, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Grant violation restores collected collateral"
        );
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-P20.
    function test_givenCollateralPosition_whenBorrowFitsGrantDebtCeiling(
        uint128 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        // bound() stays inside the exact permitted grant-bound interval.
        // The upper bound fits uint128, so this cast cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        permissions.maxDebt = uint128(bound(limit_, 100e9, type(uint128).max));
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _borrower)),
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 1, "Allowed borrow executes once");
        _assertSettled(2000e6, 100e9);
        assertEq(_ohm.balanceOf(_borrower), 100e9, "Requested OHM principal is delivered");
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-A15.
    function test_givenCollateralPosition_whenBorrowExceedsGrantDebtCeiling_reverts(
        uint128 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        // bound() stays inside the exact violating grant-bound interval.
        // The upper bound fits uint128, so this cast cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        permissions.maxDebt = uint128(bound(limit_, 0, 100e9));
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9 + 1, 1e6, _borrower)),
            new IExecutor.Output[](0)
        );
        _assertSettled(2000e6, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Debt-cap violation restores fee funding"
        );
        assertEq(_ohm.balanceOf(_borrower), 0, "Debt-cap violation delivers no principal");
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-P21.
    function test_givenCollateralPosition_whenWithdrawalRespectsGrantFloor(
        uint128 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        // bound() stays inside the exact permitted grant-bound interval.
        // The upper bound fits uint128, so this cast cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        permissions.minCollateral = uint128(bound(limit_, 0, 1000e6));
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_withdraw(1000e6)),
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 1, "Allowed withdrawal executes once");
        // Remaining 2000e6 - 1000e6 = 1000e6, at or above every selected floor.
        _assertSettled(1000e6, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet + 1000e6,
            "Allowed collateral is returned"
        );
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-A24.
    function test_givenCollateralPosition_whenWithdrawBreachesGrantFloor_reverts(
        uint128 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        // bound() stays inside the exact violating grant-bound interval.
        // The upper bound fits uint128, so this cast cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        permissions.minCollateral = uint128(bound(limit_, 1000e6, type(uint128).max));
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        // Remaining 1000e6-1 is below every selected floor in [1000e6, uint128.max].
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_withdraw(1000e6 + 1)),
            new IExecutor.Output[](0)
        );
        _assertSettled(2000e6, 0);
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Floor violation returns no collateral"
        );
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-P22.
    function test_givenOlderDebt_whenExtensionFitsGrantMaturityCeiling(
        uint48 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        uint48 nextMaturity = _position().maturity + 30 days;
        // The interval is bounded by uint48.max before converting the fuzzed grant ceiling.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 ceiling = uint48(bound(limit_, nextMaturity, type(uint48).max));
        _extendWithinGrantedMaturity(ceiling, inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A25.
    function test_givenOlderDebt_whenExtendExceedsGrantMaturityCeiling_reverts(
        uint48 limit_,
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        uint48 nextMaturity = _position().maturity + 30 days;
        // The interval is bounded by uint48.max before converting the fuzzed grant ceiling.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 ceiling = uint48(bound(limit_, 0, nextMaturity - 1));
        _extendAboveGrantedMaturity(ceiling, inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-P23.
    function test_givenOlderDebt_whenRepayEqualsExplicitFunding(
        uint128 amount_,
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        // The upper bound fits uint128.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amount = uint128(bound(amount_, 1, 50e9));
        uint128 remaining = 100e9 - amount;
        uint256 supplyBefore = _ohm.totalSupply();
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_ohm), amount),
            _single(_repay(amount)),
            new IExecutor.Output[](0)
        );
        assertEq(
            abi.decode(results[0], (uint128)),
            remaining,
            "Only the explicitly funded repayment is applied"
        );
        assertEq(_ohm.balanceOf(_borrower), remaining, "Unlisted wallet OHM is not pulled");
        assertEq(
            _ohm.totalSupply(),
            supplyBefore - amount,
            "Exactly the repaid minted OHM is burned"
        );
        _assertSettled(2000e6, remaining);
        _assertAcceptedGrant(multiple_);
    }

    // Scenarios: BLREX-T12.
    function test_givenOlderDebt_whenRepayExceedsExplicitFunding_reverts(
        uint128 amount_,
        bool inlineGrant_,
        bool multiple_
    ) public givenOlderDebt {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        deal(address(_ohm), address(_executor), 20e9, true);
        uint256 supplyBefore = _ohm.totalSupply();
        // The upper bound fits uint128.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amount = uint128(bound(amount_, 50e9 + 1, type(uint128).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_ohm),
                amount,
                50e9
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_ohm), 50e9),
            _single(_repay(amount)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _position().debtOhm,
            100e9,
            "Excess repayment leaves canonical principal unchanged"
        );
        assertEq(_core.totalActiveDebtOhm(), 100e9, "Core principal aggregate is unchanged");
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9,
            "Inventory principal aggregate is unchanged"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "Collateral custody is unchanged"
        );
        assertEq(
            _ohm.balanceOf(_borrower),
            100e9,
            "Collected input rolls back without an extra wallet pull"
        );
        assertEq(
            _ohm.balanceOf(address(_executor)),
            20e9,
            "Protected pre-existing OHM cannot fund excess repayment"
        );
        assertEq(_ohm.totalSupply(), supplyBefore, "Rejected repayment burns no OHM");
        assertEq(
            _ohm.allowance(address(_executor), address(_core)),
            0,
            "No repayment allowance survives"
        );
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A14.
    function test_givenCollateralPosition_whenBorrowRecipientViolatesGrant_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.borrowRecipient = _recipient;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_RecipientMismatch.selector,
                _recipient,
                _borrower
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1e6),
            _single(_borrow(100e9, 1e6, _borrower)),
            new IExecutor.Output[](0)
        );
        assertEq(_asset.balanceOf(_borrower), beforeWallet, "Wrong recipient restores fee funding");
        assertEq(_ohm.balanceOf(_borrower), 0, "Wrong recipient receives no principal");
        _assertSettled(2000e6, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A28.
    function test_givenCollateralPosition_whenWithdrawRecipientViolatesGrant_reverts(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        permissions.withdrawRecipient = _recipient;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansAuth.BurnerLoansAuth_RecipientMismatch.selector,
                _recipient,
                address(_executor)
            )
        );
        _executeGrantMode(
            inlineGrant_,
            signed,
            new IExecutor.Funding[](0),
            _single(_withdraw(1000e6)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Wrong withdrawal recipient receives no proceeds"
        );
        _assertSettled(2000e6, 0);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }

    // Scenarios: BLREX-A30.
    function test_givenReusableGrant_whenExecutionIsAfterGrantExpiry_reverts(
        bool inlineGrant_
    ) public {
        IOperatorAuth.Grant memory grant = _grant(true);
        // This fixture's timestamp is representable as uint48; expiry includes the exact second.
        grant.deadline = 100;
        vm.warp(100);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 1, "Installed grant executes at its inclusive deadline");
        vm.warp(101);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, uint48(100))
        );
        _account.runWithExistingGrant(
            _executor,
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Expired installed authority collects no new funds"
        );
        _assertSettled(1, 0);
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            1,
            "Expiry does not accept or consume another grant"
        );
    }

    // Scenarios: BLREX-P19.
    function test_whenDepositGrantHappyBoundarySeeds() public {
        uint128[3] memory limits = [uint128(1000e6), uint128(1000e6 + 1), type(uint128).max];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenCollateralBelowCeiling_whenDepositFitsGrantCeiling(
                        600e6,
                        limits[i],
                        inlineMode == 1,
                        lifetime == 1
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
        test_givenCollateralBelowCeiling_whenDepositFitsGrantCeiling(1, 1000e6, true, false);
    }

    // Scenarios: BLREX-A13.
    function test_whenDepositGrantFailureBoundarySeeds() public {
        uint128[4] memory limits = [uint128(0), uint128(1), uint128(1000e6 - 1), uint128(1000e6)];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenCollateralBelowCeiling_whenDepositExceedsGrantCeiling_reverts(
                        600e6 + 1,
                        limits[i],
                        inlineMode == 1,
                        lifetime == 1
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
        test_givenCollateralBelowCeiling_whenDepositExceedsGrantCeiling_reverts(
            type(uint128).max - 400e6,
            1000e6,
            true,
            false
        );
    }

    // Scenarios: BLREX-P23.
    function test_whenFundedRepaymentAmountBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOlderDebt_whenRepayEqualsExplicitFunding(1, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore funding and debt for the upper boundary");
        test_givenOlderDebt_whenRepayEqualsExplicitFunding(50e9, true, false);
    }

    // Scenarios: BLREX-T12.
    function test_whenUnfundedRepaymentAmountBoundarySeeds() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOlderDebt_whenRepayExceedsExplicitFunding_reverts(50e9 + 1, true, false);
        assertTrue(vm.revertToState(checkpoint), "Restore funding and debt for the upper boundary");
        test_givenOlderDebt_whenRepayExceedsExplicitFunding_reverts(type(uint128).max, true, false);
    }

    // Scenarios: BLREX-P20.
    function test_whenDebtGrantHappyBoundarySeeds() public {
        uint128[3] memory limits = [uint128(100e9), uint128(100e9 + 1), type(uint128).max];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenCollateralPosition_whenBorrowFitsGrantDebtCeiling(
                        limits[i],
                        inlineMode == 1,
                        lifetime == 1
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
    }

    // Scenarios: BLREX-A15.
    function test_whenDebtGrantFailureBoundarySeeds() public {
        uint128[4] memory limits = [uint128(0), uint128(1), uint128(100e9 - 1), uint128(100e9)];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenCollateralPosition_whenBorrowExceedsGrantDebtCeiling_reverts(
                        limits[i],
                        inlineMode == 1,
                        lifetime == 1
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
    }

    // Scenarios: BLREX-P21.
    function test_whenWithdrawalGrantHappyBoundarySeeds() public {
        uint128[4] memory limits = [uint128(0), uint128(1), uint128(1000e6 - 1), uint128(1000e6)];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenCollateralPosition_whenWithdrawalRespectsGrantFloor(
                        limits[i],
                        inlineMode == 1,
                        lifetime == 1
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
    }

    // Scenarios: BLREX-A24.
    function test_whenWithdrawalGrantFailureBoundarySeeds() public {
        uint128[3] memory limits = [uint128(1000e6), uint128(1000e6 + 1), type(uint128).max];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenCollateralPosition_whenWithdrawBreachesGrantFloor_reverts(
                        limits[i],
                        inlineMode == 1,
                        lifetime == 1
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
    }

    // Scenarios: BLREX-P22.
    function test_whenMaturityGrantHappyBoundarySeeds() public givenOlderDebt {
        uint48 nextMaturity = _position().maturity + 30 days;
        uint48[3] memory limits = [nextMaturity, nextMaturity + 1, type(uint48).max];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    _extendWithinGrantedMaturity(limits[i], inlineMode == 1, lifetime == 1);
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
    }

    // Scenarios: BLREX-A25.
    function test_whenMaturityGrantFailureBoundarySeeds() public givenOlderDebt {
        uint48 nextMaturity = _position().maturity + 30 days;
        uint48[3] memory limits = [uint48(0), uint48(1), nextMaturity - 1];
        for (uint256 i; i < limits.length; ++i) {
            for (uint256 inlineMode; inlineMode < 2; ++inlineMode) {
                for (uint256 lifetime; lifetime < 2; ++lifetime) {
                    uint256 checkpoint = vm.snapshotState();
                    _extendAboveGrantedMaturity(limits[i], inlineMode == 1, lifetime == 1);
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore the independent grant-bound seed state"
                    );
                }
            }
        }
    }

    function _extendWithinGrantedMaturity(
        uint48 limit_,
        bool inlineGrant_,
        bool multiple_
    ) private {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        uint48 expectedMaturity = _position().maturity + 30 days;
        permissions.maxMaturity = limit_;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7), uint256(0))
        );
        bytes[] memory results = _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 7),
            _single(_extend(1)),
            new IExecutor.Output[](0)
        );
        assertEq(results.length, 1, "Allowed extension executes once");
        assertEq(_position().maturity, expectedMaturity, "Expected resulting maturity is reached");
        _assertSettled(2000e6, 100e9);
        _assertAcceptedGrant(multiple_);
    }

    function _extendAboveGrantedMaturity(uint48 limit_, bool inlineGrant_, bool multiple_) private {
        IOperatorAuth.Grant memory grant = _grant(multiple_);
        IBurnerLoansAuth.Permissions memory permissions = abi.decode(
            grant.permissions,
            (IBurnerLoansAuth.Permissions)
        );
        uint48 beforeMaturity = _position().maturity;
        permissions.maxMaturity = limit_;
        grant.permissions = abi.encode(permissions);
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, grant);
        uint256 beforeWallet = _asset.balanceOf(_borrower);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(7), uint256(0))
        );
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ResultOutsideGrant.selector);
        _executeGrantMode(
            inlineGrant_,
            signed,
            _funding(address(_asset), 7),
            _single(_extend(1)),
            new IExecutor.Output[](0)
        );
        assertEq(
            _position().maturity,
            beforeMaturity,
            "Maturity-cap violation restores original expiry"
        );
        assertEq(
            _asset.balanceOf(_borrower),
            beforeWallet,
            "Maturity-cap violation restores fee funding"
        );
        _assertSettled(2000e6, 100e9);
        _assertGrantAfterRevert(inlineGrant_, multiple_);
    }
}
