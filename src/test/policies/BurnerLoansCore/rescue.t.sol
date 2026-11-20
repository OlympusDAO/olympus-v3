// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreCallbackToken} from "./fixtures/CoreCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCoreRescueTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-RESCUE-A01.
    function test_givenUnauthorized_whenRescued_reverts(address caller_, bool invalid_) public {
        vm.assume(caller_ != address(_config) && !_roles.hasRole(caller_, ADMIN_ROLE));
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _core.rescue(invalid_ ? address(0) : address(_asset), invalid_ ? address(0) : _recipient);
    }

    // Scenarios: BLCORE-RESCUE-A01.
    function test_givenUnauthorized_whenPreviewed(address caller_) public {
        vm.assume(caller_ != address(_config) && !_roles.hasRole(caller_, ADMIN_ROLE));
        _asset.mint(address(_core), 7);
        bytes32 beforeLedger = _ledger();
        vm.prank(caller_);
        assertEq(
            _core.previewRescue(address(_asset), _recipient),
            7,
            "unrelated viewer quotes current balance"
        );
        assertEq(_ledger(), beforeLedger, "quote preserves ledgers");
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        vm.prank(caller_);
        _core.rescue(address(_asset), _recipient);
    }

    // Scenarios: BLCORE-RESCUE-L01, BLCORE-RESCUE-L02, BLCORE-RESCUE-P01, BLCORE-RESCUE-P02.
    function test_givenAuthorized_whenRescued(
        address caller_,
        uint256 balance_,
        bool enabled_,
        bool configOnly_
    ) public {
        if (configOnly_) caller_ = address(_config);
        else _grantAdmin(caller_);
        if (!enabled_) _core.disable("");
        MockERC20 token = new MockERC20("Surplus", "SUR", 18);
        token.mint(address(_core), balance_);
        bytes32 ledger = _ledger();
        vm.prank(caller_);
        uint256 quote = _core.previewRescue(address(token), _recipient);
        assertEq(quote, balance_, "Preview equals independent direct balance");
        assertEq(token.balanceOf(address(_core)), balance_, "Preview transfers nothing");
        vm.recordLogs();
        if (balance_ > 0) {
            vm.expectEmit(true, true, false, true, address(_core));
            emit IBurnerLoansCore.AssetRescued(address(token), _recipient, balance_);
        }
        vm.prank(caller_);
        _core.rescue(address(token), _recipient);
        if (balance_ == 0)
            assertEq(
                vm.getRecordedLogs().length,
                0,
                "Zero surplus emits no recovery or transfer event"
            );
        assertEq(token.balanceOf(address(_core)), 0, "All direct surplus recovered");
        assertEq(token.balanceOf(_recipient), balance_, "Exact recipient delta");
        assertEq(_ledger(), ledger, "No managed custody or debt changes");
    }

    // Scenarios: BLCORE-RESCUE-P01, BLCORE-RESCUE-P02.
    function test_whenSurplusBoundarySeeds() public {
        test_givenAuthorized_whenRescued(_recipient, 0, true, false);
        test_givenAuthorized_whenRescued(_recipient, 1, true, true);
        test_givenAuthorized_whenRescued(_recipient, type(uint256).max, false, false);
    }

    // Scenarios: BLCORE-RESCUE-L01, BLCORE-RESCUE-P02.
    function test_givenConfigAlsoAdmin_whenRescued() public {
        test_givenAuthorized_whenRescued(address(_config), 1, true, false);
    }

    // Scenarios: BLCORE-RESCUE-L03, BLCORE-RESCUE-L04.
    function test_givenCoreInactive_whenRescued_reverts(bool enabled_) public {
        _setCoreLifecycle(false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        _core.previewRescue(address(_asset), _recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        _core.rescue(address(_asset), _recipient);
    }

    // Scenarios: BLCORE-RESCUE-I03.
    function test_givenZeroDestination_whenRescued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(0)
            )
        );
        _core.previewRescue(address(_asset), address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(0)
            )
        );
        _core.rescue(address(_asset), address(0));
    }

    // Scenarios: BLCORE-RESCUE-I04.
    function test_givenCoreDestination_whenRescued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_core)
            )
        );
        _core.previewRescue(address(_asset), address(_core));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_core)
            )
        );
        _core.rescue(address(_asset), address(_core));
    }

    // Scenarios: BLCORE-RESCUE-I05.
    function test_givenTokenDestination_whenRescued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_asset)
            )
        );
        _core.previewRescue(address(_asset), address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_asset)
            )
        );
        _core.rescue(address(_asset), address(_asset));
    }

    // Scenarios: BLCORE-RESCUE-I06.
    function test_givenPayoutDestination_whenRescued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_payout)
            )
        );
        _core.previewRescue(address(_asset), address(_payout));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_payout)
            )
        );
        _core.rescue(address(_asset), address(_payout));
    }

    // Scenarios: BLCORE-RESCUE-I07.
    function test_givenConfigDestination_whenRescued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_config)
            )
        );
        _core.previewRescue(address(_asset), address(_config));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_config)
            )
        );
        _core.rescue(address(_asset), address(_config));
    }

    // Scenarios: BLCORE-RESCUE-I08.
    function test_givenKernelDestination_whenRescued_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_kernel)
            )
        );
        _core.previewRescue(address(_asset), address(_kernel));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_kernel)
            )
        );
        _core.rescue(address(_asset), address(_kernel));
    }

    // Scenarios: BLCORE-RESCUE-I01, BLCORE-RESCUE-I02.
    function test_givenTokenWithoutCode_whenRescued_reverts(address token_) public {
        vm.assume(token_.code.length == 0);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector, token_)
        );
        _core.previewRescue(token_, _recipient);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector, token_)
        );
        _core.rescue(token_, _recipient);
    }

    // Scenarios: BLCORE-RESCUE-C01.
    function test_givenTransferFailure_whenRescued_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("requireNotReentrant()"),
            false
        );
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSignature("transfer(address,uint256)", _recipient, 1),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(DependencyFailed.selector);
        _core.rescue(address(token), _recipient);
        assertEq(token.balanceOf(address(_core)), 1, "Mandatory transfer rolls back");
    }

    // Scenarios: BLCORE-RESCUE-C02.
    function test_givenAuthorizedCallback_whenCaughtRescue() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized nested action reaches guard"
        );
        assertEq(token.balanceOf(_recipient), 1, "Outer rescue completes once");
    }

    // Scenarios: BLCORE-RESCUE-C03.
    function test_givenAuthorizedCallback_whenPropagatedRescue() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("rescue(address,address)", address(_asset), _recipient),
            true
        );
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _core.rescue(address(token), _recipient);
        assertEq(token.balanceOf(address(_core)), 1, "Propagated callback rolls back transfer");
    }

    // Scenarios: BLCORE-RESCUE-C02.
    function test_givenBusyCore_whenPreviewed_reverts() public {
        CoreCallbackToken token = _armRescue(
            abi.encodeWithSignature("previewRescue(address,address)", address(_asset), _recipient),
            false
        );
        _core.rescue(address(token), _recipient);
        assertEq(
            token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Authorized preview shares busy-settlement admission"
        );
    }

    // Scenarios: BLCORE-RESCUE-A02.
    function test_whenAnyViewerQuotesRecovery(address viewer_, uint256 balance_) public {
        MockERC20 token = new MockERC20("Quote Surplus", "QS", 18);
        token.mint(address(_core), balance_);
        bytes32 beforeLedger = _ledger();
        vm.recordLogs();
        vm.prank(viewer_);
        assertEq(
            _core.previewRescue(address(token), _recipient),
            balance_,
            "every viewer receives the exact direct balance"
        );
        assertEq(vm.getRecordedLogs().length, 0, "recovery quote emits no logs");
        assertEq(_ledger(), beforeLedger, "recovery quote changes no accounting");
        assertEq(token.balanceOf(address(_core)), balance_, "recovery quote transfers nothing");
    }

    // Scenarios: BLCORE-RESCUE-A02.
    function test_whenRecoveryQuoteBalanceBoundaries() public {
        test_whenAnyViewerQuotesRecovery(address(0), 0);
        test_whenAnyViewerQuotesRecovery(address(0), 1);
        test_whenAnyViewerQuotesRecovery(address(0), type(uint256).max);
    }

    // Scenarios: BLCORE-RESCUE-A03.
    function test_givenPausedCore_whenAnyViewerQuotesRecovery(address viewer_) public {
        _core.disable("");
        _asset.mint(address(_core), 7);
        vm.prank(viewer_);
        assertEq(
            _core.previewRescue(address(_asset), _recipient),
            7,
            "paused recovery quote remains permissionless"
        );
    }
}
