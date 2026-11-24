// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesExecuteAuthorizationTest is BurnerLoansCompositesTest {
    // Scenarios: BLREX-A04.
    function test_givenVictimGrant_whenCallerHasNoGrant_reverts(
        address caller_
    ) public givenReusableGrant {
        vm.assume(caller_ != _borrower);
        // Auth permits account == operator; its protected-funds boundary is tested separately.
        vm.assume(caller_ != address(_executor));
        vm.assume(caller_ != address(0));
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(caller_);
        _executor.execute(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(
            _asset.balanceOf(_borrower),
            10_000e6,
            "Victim wallet approval cannot fund unrelated caller"
        );
        assertEq(_position().depositedCollateral, 0, "Victim position unchanged");
    }

    // Scenarios: BLREX-A31.
    function test_givenVictimGrant_whenCallerIsExecutor_reverts() public givenReusableGrant {
        _asset.mint(address(_executor), 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                address(_asset),
                1,
                0
            )
        );
        vm.prank(address(_executor));
        _executor.execute(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(
            _asset.balanceOf(address(_executor)),
            100,
            "Self-authority cannot spend protected balances"
        );
        assertEq(
            _position().depositedCollateral,
            0,
            "Self-authority cannot select victim position"
        );
        assertEq(
            _lens.getPosition(address(_asset), address(_executor)).depositedCollateral,
            0,
            "No executor collateral credited"
        );
    }

    // Scenarios: BLREX-A11.
    function test_givenVictimGrant_whenCallerIsZero_reverts() public givenReusableGrant {
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(address(0));
        _executor.execute(
            new IExecutor.Funding[](0),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_position().depositedCollateral, 0, "Zero caller cannot select victim");
    }

    // Scenarios: BLREX-A09.
    function test_whenGrantDoesNotPermitDeposit_reverts() public {
        IOperatorAuth.Grant memory grant = _operatorGrant(
            _borrower,
            address(_executor),
            type(uint48).max
        );
        grant.actions = 2;
        vm.prank(_borrower);
        _auth.approveGrant(grant);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidContext.selector);
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 1e6),
            _single(_deposit(1e6)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Disallowed action collects nothing");
    }
}
