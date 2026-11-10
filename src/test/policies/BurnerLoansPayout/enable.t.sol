// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

contract BurnerLoansPayoutEnableTest is BurnerLoansPayoutTest {
    error CoreInterfaceReadFailed();

    // Scenarios: BLCU-ENABLE-L01.
    function test_givenPaused_whenEnabled_thenExactTransition(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        vm.assume(caller_ != address(0));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _payout.disable("");
        _setState(_core, coreActive_, coreEnabled_);
        bytes32 state = _ledgerDigest();
        vm.warp(2);
        vm.expectEmit(address(_payout));
        emit IEnabler.Enabled();
        vm.expectEmit(address(_payout));
        emit IEnablerV2.Transition(caller_, true, "", 2);
        vm.prank(caller_);
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Enabled");
        assertEq(_payout.lastTransitionAt(), 2, "Exact history");
        assertEq(_ledgerDigest(), state, "Activation preserves custody and obligations");
    }

    // Scenarios: BLCU-ENABLE-D01.
    function test_givenUnreadableCoreReadiness_whenEnabled(
        bytes memory data_
    ) public givenPendingBuckets {
        _payout.disable("");
        vm.mockCall(address(_core), abi.encodeWithSignature("isEnabled()"), data_);
        vm.expectCall(address(_core), abi.encodeWithSignature("isEnabled()"), uint64(0));
        vm.expectCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_core)),
            uint64(0)
        );
        bytes32 state = _ledgerDigest();
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Enabled despite unreadable Core lifecycle");
        assertEq(_ledgerDigest(), state, "Obligations and custody preserved");
        _payout.disable("");
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Repeated activation remains independent");
        assertEq(_ledgerDigest(), state, "Repeated activation preserves obligations");
    }

    // Scenarios: BLCU-ENABLE-A01.
    function test_givenUnauthorized_whenEnabled_reverts(
        address caller_
    ) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _payout.disable("");
        _expectEnableRejected(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE),
            caller_,
            ""
        );
    }

    // Scenarios: BLCU-ENABLE-L02.
    function test_givenInactiveDisabled_whenEnabled_reverts() public givenPendingBuckets {
        _setState(_payout, false, false);
        _expectEnableRejected(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_payout)
            ),
            address(this),
            ""
        );
    }

    // Scenarios: BLCU-ENABLE-L03, BLCU-ENABLE-L04.
    function test_givenAlreadyEnabled_whenEnabled_reverts(bool active_) public givenPendingBuckets {
        _setState(_payout, active_, true);
        _expectEnableRejected(
            abi.encodeWithSelector(IEnabler.NotDisabled.selector),
            address(this),
            ""
        );
    }

    // Scenarios: BLCU-ENABLE-I01.
    function test_whenNonemptyData_reverts(bytes memory data_) public givenPendingBuckets {
        vm.assume(data_.length > 0 && data_.length <= 256);
        _payout.disable("");
        _expectEnableRejected(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector),
            address(this),
            data_
        );
    }

    // Scenarios: BLCU-ENABLE-I01.
    function test_whenNonemptyDataAtBoundaries_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        test_whenNonemptyData_reverts(hex"00");
        _restore(checkpoint);
        test_whenNonemptyData_reverts(abi.encode(uint256(0)));
        _restore(checkpoint);
        test_whenNonemptyData_reverts(new bytes(256));
    }

    // Scenarios: BLCU-ENABLE-C02.
    function test_givenCoreBusy_whenEnabled_reverts() public givenPendingBuckets {
        _payout.disable("");
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.requireNotReentrant, ()),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
        _expectEnableRejected(
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            address(this),
            ""
        );
    }

    function _expectEnableRejected(
        bytes memory reason_,
        address caller_,
        bytes memory data_
    ) internal {
        bytes32 state = _ledgerDigest();
        bool enabled = _payout.isEnabled();
        uint48 last = _payout.lastTransitionAt();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.enable(data_);
        assertEq(_payout.isEnabled(), enabled, "Failed enable preserves state");
        assertEq(_payout.lastTransitionAt(), last, "Failed enable preserves history");
        assertEq(_ledgerDigest(), state, "Failed enable preserves obligations and balances");
    }

    // Scenarios: BLCU-ENABLE-D06.
    function test_givenMissingCoreInterface_whenActivated_reverts() public {
        _payout.disable("");
        uint48 transition = _payout.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, abi.encode(false));
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(address(this));
        _payout.enable("");
        assertFalse(_payout.isEnabled(), "Core incompatibility preserves paused state");
        assertEq(_payout.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        vm.prank(address(this));
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLCU-ENABLE-D07.
    function test_givenRevertingCoreInterface_whenActivated_reverts() public {
        _payout.disable("");
        uint48 transition = _payout.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCallRevert(
            address(_core),
            probe,
            abi.encodeWithSelector(CoreInterfaceReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(address(this));
        _payout.enable("");
        assertFalse(_payout.isEnabled(), "Core incompatibility preserves paused state");
        assertEq(_payout.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        vm.prank(address(this));
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLCU-ENABLE-D08.
    function test_givenMalformedCoreInterface_whenActivated_reverts() public {
        _payout.disable("");
        uint48 transition = _payout.lastTransitionAt();
        bytes memory probe = abi.encodeCall(
            IERC165.supportsInterface,
            (type(IBurnerLoansCore).interfaceId)
        );
        vm.mockCall(address(_core), probe, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidCore.selector,
                address(_core)
            )
        );
        vm.prank(address(this));
        _payout.enable("");
        assertFalse(_payout.isEnabled(), "Core incompatibility preserves paused state");
        assertEq(_payout.lastTransitionAt(), transition, "Rejection preserves transition time");
        vm.clearMockedCalls();
        vm.prank(address(this));
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored interface permits retry");
    }

    // Scenarios: BLCU-ENABLE-K03.
    function test_givenMalformedCoreKernel_whenActivated_revertsThenRestored(
        bytes memory data_
    ) public {
        _payout.disable("");
        vm.assume(data_.length != 32);
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), data_);
        _expectEnableRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            ),
            address(this),
            ""
        );
        vm.clearMockedCalls();
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored Core permits activation");
    }

    // Scenarios: BLCU-ENABLE-K03.
    function test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored() public {
        _payout.disable("");
        bytes[6] memory responses = [
            new bytes(0),
            new bytes(1),
            new bytes(31),
            new bytes(33),
            new bytes(64),
            abi.encode(type(uint256).max)
        ];
        // Every response must fail with the same owned error and preserve state.
        // forge-lint: disable-next-line(calls-loop)
        for (uint256 i; i < responses.length; ++i) {
            vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), responses[i]);
            _expectEnableRejected(
                abi.encodeWithSelector(
                    PolicyDependency.PolicyDependency_InvalidDependency.selector,
                    address(_core)
                ),
                address(this),
                ""
            );
        }
        vm.clearMockedCalls();
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored Core permits activation");
    }

    // Scenarios: BLCU-ENABLE-K01.
    function test_givenDifferentCoreKernel_whenActivated_revertsThenRestored() public {
        _payout.disable("");
        address otherKernel = address(new Kernel());
        vm.mockCall(address(_core), abi.encodeWithSignature("kernel()"), abi.encode(otherKernel));
        _expectEnableRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                otherKernel
            ),
            address(this),
            ""
        );
        vm.clearMockedCalls();
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored Core permits activation");
    }

    // Scenarios: BLCU-ENABLE-K02.
    function test_givenRevertingCoreKernel_whenActivated_revertsThenRestored(
        bytes memory data_
    ) public {
        _payout.disable("");
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), data_);
        _expectEnableRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_core)
            ),
            address(this),
            ""
        );
        vm.clearMockedCalls();
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored Core permits activation");
    }

    // Scenarios: BLCU-ENABLE-K04.
    function test_givenCoreMigrated_whenActivated_revertsThenRestored() public givenPendingBuckets {
        Kernel next = new Kernel();
        vm.prank(address(_kernel));
        _core.changeKernel(next);
        assertTrue(_kernel.isPolicyActive(_core), "Old Kernel still records Core membership");
        _payout.disable("");
        _expectEnableRejected(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_core),
                address(_kernel),
                address(next)
            ),
            address(this),
            ""
        );
        vm.prank(address(next));
        _core.changeKernel(_kernel);
        _payout.enable("");
        assertTrue(_payout.isEnabled(), "Restored Core permits activation");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
