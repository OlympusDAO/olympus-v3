// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {Ownable} from "@openzeppelin-5.7.0/access/Ownable.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansCompositesTest} from "./fixtures/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesExecuteLifecycleTest is BurnerLoansCompositesTest {
    // Scenarios: BLREX-L01.
    function test_givenEnabled_whenNotOwnerDisables_reverts(address caller_) public {
        uint48 transitionAt = _executor.lastTransitionAt();
        vm.assume(caller_ != _executor.owner());
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller_)
        );
        vm.prank(caller_);
        _executor.disable("");
        _assertLifecycle(_executor, true, transitionAt);
    }

    // Scenarios: BLREX-L02.
    function test_givenDisabled_whenNotOwnerEnables_reverts(address caller_) public {
        vm.prank(_compositesOwner);
        _executor.disable("");
        uint48 transitionAt = _executor.lastTransitionAt();
        vm.assume(caller_ != _executor.owner());
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller_)
        );
        vm.prank(caller_);
        _executor.enable("");
        _assertLifecycle(_executor, false, transitionAt);
    }

    // Scenarios: BLREX-L03.
    function test_givenEnabled_whenOwnerEnablesAgain_reverts() public {
        uint48 transitionAt = _executor.lastTransitionAt();
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(_compositesOwner);
        _executor.enable("");
        _assertLifecycle(_executor, true, transitionAt);
    }

    // Scenarios: BLCDIS-L01.
    function test_givenDisabled_whenOwnerDisablesAgain_reverts() public {
        vm.prank(_compositesOwner);
        _executor.disable("");
        uint48 transitionAt = _executor.lastTransitionAt();
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_compositesOwner);
        _executor.disable("");
        _assertLifecycle(_executor, false, transitionAt);
    }

    // Scenarios: BLCDIS-I01.
    function test_givenEnabled_whenDisableDataIsNonempty_reverts() public {
        uint48 transitionAt = _executor.lastTransitionAt();
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidEnablerData.selector);
        vm.prank(_compositesOwner);
        _executor.disable(hex"01");
        _assertLifecycle(_executor, true, transitionAt);
    }

    // Scenarios: BLREX-L04.
    function test_givenDisabled_whenEnableDataIsNonempty_reverts() public {
        vm.prank(_compositesOwner);
        _executor.disable("");
        uint48 transitionAt = _executor.lastTransitionAt();
        vm.expectRevert(IExecutor.BurnerLoansComposites_InvalidEnablerData.selector);
        vm.prank(_compositesOwner);
        _executor.enable(hex"01");
        _assertLifecycle(_executor, false, transitionAt);
    }

    // Scenarios: BLCDIS-P01.
    function test_givenEnabled_givenCoreUnavailable_whenOwnerDisables() public {
        vm.mockCallRevert(address(_core), bytes(""), hex"deadbeef");
        uint48 pauseAt = _executor.lastTransitionAt() + 1;
        vm.warp(pauseAt);
        _expectTransition(_executor, _compositesOwner, false, pauseAt);
        vm.prank(_compositesOwner);
        _executor.disable("");
        _assertLifecycle(_executor, false, pauseAt);
    }

    // Scenarios: BLREX-L05, BLCEN-P02.
    function test_givenReusableGrant_whenOwnerPausesAndResumes() public givenReusableGrant {
        vm.expectEmit(address(_executor));
        emit IEnabler.Disabled();
        vm.prank(_compositesOwner);
        _executor.disable("");
        assertFalse(_executor.isEnabled(), "Owner paused execution");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _executeDeposit();
        assertEq(_asset.balanceOf(_borrower), 10_000e6, "Pause prevents funding");
        assertEq(_position().depositedCollateral, 0, "Pause prevents lending");
        _resume();
        _executeDeposit();
        assertEq(_position().depositedCollateral, 1, "Installed grant still usable after resume");
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            1,
            "Pause does not replace grant"
        );
    }

    // Scenarios: BLREX-L06.
    function test_givenSignedGrant_givenPaused_whenExecuted_reverts() public {
        IExecutor.SignedGrant memory signed = _fundSignedDeposit();
        vm.prank(_compositesOwner);
        _executor.disable("");
        vm.expectCall(
            address(_auth),
            abi.encodeWithSelector(IOperatorAuth.acceptGrant.selector),
            uint64(0)
        );
        vm.expectCall(
            address(_asset),
            abi.encodeWithSelector(IERC20.transferFrom.selector),
            uint64(0)
        );
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _executeDepositWithGrant(signed);
    }

    // Scenarios: BLREX-L06, BLCEN-P02.
    function test_givenSignedGrant_whenOwnerPausesAndResumes() public {
        IExecutor.SignedGrant memory signed = _fundSignedDeposit();
        vm.prank(_compositesOwner);
        _executor.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        _executeDepositWithGrant(signed);
        assertEq(
            _auth.pairEpochs(_borrower, address(_executor)),
            0,
            "Paused execution cannot accept grant"
        );
        assertEq(_asset.balanceOf(_borrower), 1, "Pause prevents funding");
        _resume();
        _executeDepositWithGrant(signed);
        assertEq(_position().depositedCollateral, 1, "Same signature works after resume");
        assertEq(_auth.pairEpochs(_borrower, address(_executor)), 1, "Grant accepted once");
    }

    function _resume() private {
        uint48 resumeAt = _executor.lastTransitionAt() + 1;
        vm.warp(resumeAt);
        _expectTransition(_executor, _compositesOwner, true, resumeAt);
        vm.prank(_compositesOwner);
        _executor.enable("");
        _assertLifecycle(_executor, true, resumeAt);
    }

    function _expectTransition(
        BurnerLoansComposites executor_,
        address caller_,
        bool enabled_,
        uint48 at_
    ) private {
        vm.expectEmit(address(executor_));
        if (enabled_) emit IEnabler.Enabled();
        else emit IEnabler.Disabled();
        vm.expectEmit(address(executor_));
        emit IEnablerV2.Transition(caller_, enabled_, "", at_);
    }

    function _assertLifecycle(
        BurnerLoansComposites executor_,
        bool enabled_,
        uint48 transitionAt_
    ) private view {
        assertEq(executor_.isEnabled(), enabled_, "Executor enablement matches expected state");
        assertEq(
            executor_.lastTransitionAt(),
            transitionAt_,
            "Executor transition time matches expected time"
        );
    }

    function _executeDeposit() private {
        vm.prank(_borrower);
        _executor.execute(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    function _fundSignedDeposit() private returns (IExecutor.SignedGrant memory) {
        _borrower = vm.addr(_SIGNER_KEY);
        _asset.mint(_borrower, 1);
        vm.prank(_borrower);
        _asset.approve(address(_executor), 1);
        return _signedGrant(_operatorGrant(_borrower, address(_executor), type(uint48).max));
    }

    function _executeDepositWithGrant(IExecutor.SignedGrant memory signed_) private {
        vm.prank(_borrower);
        _executor.executeWithGrant(
            _funding(address(_asset), 1),
            _single(_deposit(1)),
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max,
            signed_
        );
    }

    // Scenarios: BLREX-L07, BLCEN-P01.
    function test_whenDeployed() public {
        BurnerLoansComposites executor = _deploy(_borrower);
        assertEq(executor.owner(), _borrower, "Explicit owner controls the executor");
        _assertLifecycle(executor, false, 0);
        assertTrue(
            executor.supportsInterface(type(IEnabler).interfaceId),
            "Executor advertises lifecycle API"
        );
        assertTrue(
            executor.supportsInterface(type(IEnablerV2).interfaceId),
            "Executor advertises transition API"
        );
        uint48 enableAt = 100;
        vm.warp(enableAt);
        _expectTransition(executor, _borrower, true, enableAt);
        vm.prank(_borrower);
        executor.enable("");
        _assertLifecycle(executor, true, enableAt);
    }

    // Scenarios: BLREX-L08.
    function test_whenOwnerIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        _deploy(address(0));
    }

    function _deploy(address owner_) private returns (BurnerLoansComposites) {
        return
            new BurnerLoansComposites(
                address(_core),
                address(_collateral),
                address(_debt),
                owner_,
                _integrationConfig
            );
    }

    // Scenarios: BLREX-L10.
    function test_whenOwnershipIsAccepted() public {
        vm.prank(_compositesOwner);
        _executor.transferOwnership(_borrower);
        assertEq(
            _executor.owner(),
            _compositesOwner,
            "Current owner retains control until acceptance"
        );
        vm.prank(_borrower);
        _executor.acceptOwnership();
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _compositesOwner)
        );
        vm.prank(_compositesOwner);
        _executor.disable("");
        vm.prank(_borrower);
        _executor.disable("");
        assertFalse(_executor.isEnabled(), "New owner controls pause");
    }
}
