// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansCompositesGrantModesTest} from "./fixtures/BurnerLoansCompositesGrantModesTest.sol";

contract BurnerLoansCompositesExecuteDependencyLifecycleTest is
    BurnerLoansCompositesGrantModesTest
{
    // Scenarios: BLREX-D01.
    function test_whenCollateralIsDisabledThenRestored(bool inlineGrant_, bool multiple_) public {
        _checkPausedThenRestored(address(_collateral), _deposit(1e6), inlineGrant_, multiple_);
        _assertSettled(1e6, 0);
    }

    // Scenarios: BLREX-D01.
    function test_whenCollateralIsInactiveThenRestored(bool inlineGrant_, bool multiple_) public {
        _checkInactiveThenRestored(address(_collateral), _deposit(1e6), inlineGrant_, multiple_);
        _assertSettled(1e6, 0);
    }

    // Scenarios: BLREX-D02.
    function test_givenCollateralPosition_whenDebtIsDisabledThenRestored(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        _checkPausedThenRestored(
            address(_debt),
            _borrow(100e9, 1e6, _borrower),
            inlineGrant_,
            multiple_
        );
        _assertSettled(2000e6, 100e9);
    }

    // Scenarios: BLREX-D02.
    function test_givenCollateralPosition_whenDebtIsInactiveThenRestored(
        bool inlineGrant_,
        bool multiple_
    ) public givenCollateralPosition {
        _checkInactiveThenRestored(
            address(_debt),
            _borrow(100e9, 1e6, _borrower),
            inlineGrant_,
            multiple_
        );
        _assertSettled(2000e6, 100e9);
    }

    // Scenarios: BLREX-D03.
    function test_whenCoreIsDisabledThenRestored(bool inlineGrant_, bool multiple_) public {
        _checkPausedThenRestored(address(_core), _deposit(1e6), inlineGrant_, multiple_);
        _assertSettled(1e6, 0);
    }

    // Scenarios: BLREX-D03.
    function test_whenCoreIsInactiveThenRestored(bool inlineGrant_, bool multiple_) public {
        _checkInactiveThenRestored(address(_core), _deposit(1e6), inlineGrant_, multiple_);
        _assertSettled(1e6, 0);
    }

    function _checkPausedThenRestored(
        address dependency_,
        IExecutor.Operation memory op_,
        bool inlineGrant_,
        bool multiple_
    ) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        vm.prank(_fixtureAdmin);
        IEnabler(dependency_).disable("");
        bytes memory reason = dependency_ == address(_core)
            ? _coreError()
            : abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        _assertPausedExecution(reason, op_, inlineGrant_, signed);
        vm.prank(_fixtureAdmin);
        IEnabler(dependency_).enable("");
        _retry(op_, inlineGrant_, signed);
    }

    function _checkInactiveThenRestored(
        address dependency_,
        IExecutor.Operation memory op_,
        bool inlineGrant_,
        bool multiple_
    ) private {
        IExecutor.SignedGrant memory signed = _prepareGrantMode(inlineGrant_, _grant(multiple_));
        _executeFixtureKernelAction(Actions.DeactivatePolicy, dependency_);
        bytes memory reason = dependency_ == address(_core)
            ? _coreError()
            : abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                dependency_
            );
        _assertPausedExecution(reason, op_, inlineGrant_, signed);
        _executeFixtureKernelAction(Actions.ActivatePolicy, dependency_);
        _retry(op_, inlineGrant_, signed);
    }

    function _assertPausedExecution(
        bytes memory reason_,
        IExecutor.Operation memory op_,
        bool inlineGrant_,
        IExecutor.SignedGrant memory signed_
    ) private {
        uint256 funds = _asset.balanceOf(_borrower);
        uint256 custody = _asset.balanceOf(address(_depositManager));
        vm.expectRevert(reason_);
        _run(op_, inlineGrant_, signed_);
        assertEq(_asset.balanceOf(_borrower), funds, "Wallet input unchanged");
        assertEq(_asset.balanceOf(address(_depositManager)), custody, "Custody unchanged");
        assertEq(
            _core.totalActiveDebtOhm(),
            0,
            "No principal created while dependencies unavailable"
        );
        _assertGrantAfterRevert(inlineGrant_, signed_.grant.multiple);
    }

    function _retry(
        IExecutor.Operation memory op_,
        bool inlineGrant_,
        IExecutor.SignedGrant memory signed_
    ) private {
        _run(op_, inlineGrant_, signed_);
        _assertAcceptedGrant(signed_.grant.multiple);
    }

    function _run(
        IExecutor.Operation memory op_,
        bool inlineGrant_,
        IExecutor.SignedGrant memory signed_
    ) private {
        _executeGrantMode(
            inlineGrant_,
            signed_,
            _funding(address(_asset), 1e6),
            _single(op_),
            new IExecutor.Output[](0)
        );
    }

    function _coreError() private view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            );
    }
}
