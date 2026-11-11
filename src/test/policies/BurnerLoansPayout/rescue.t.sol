// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unused-return)

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

contract BurnerLoansPayoutRescueTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-RESCUE-P01.
    function test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves(
        uint256 surplus_,
        uint256 reserved_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        surplus_ = bound(surplus_, 1, type(uint256).max);
        reserved_ = bound(reserved_, 0, type(uint256).max - surplus_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedBuckets(reserved_, 0, 0, _keeper);
        _token.mint(address(_payout), surplus_);
        _assertSurplusTransfer(caller_, surplus_, reserved_);
    }

    // Scenarios: BLCU-RESCUE-D01.
    function test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer(
        uint256 reserved_,
        uint256 deficit_,
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        deficit_ = bound(deficit_, 0, reserved_);
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _seedBuckets(reserved_, 0, 0, _keeper);
        _token.burn(address(_payout), deficit_);
        bytes32 state = _ledgerDigest();
        uint256 calls = _token.transferCallCount();
        vm.prank(caller_);
        assertEq(
            _payout.previewRescue(address(_token), _destination),
            0,
            "No surplus in a deficit"
        );
        vm.recordLogs();
        vm.prank(caller_);
        _payout.rescue(address(_token), _destination);
        assertEq(vm.getRecordedLogs().length, 0, "Zero rescue emits no event");
        assertEq(_token.transferCallCount(), calls, "Zero rescue makes no transfer");
        assertEq(_ledgerDigest(), state, "Reserves retained even when custody has a deficit");
    }

    // Scenarios: BLCU-RESCUE-L01.
    function test_givenPayoutActive_whenRescued_thenRecoveryAvailable(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _core.setPayout(address(_otherPayout));
        _setState(_payout, true, enabled_);
        _setState(_core, coreActive_, coreEnabled_);
        _token.mint(address(_payout), 7);
        _assertSurplusTransfer(caller_, 7, 60);
    }

    // Scenarios: BLCU-RESCUE-A01.
    function test_givenUnauthorizedCaller_whenRescued_reverts(
        address caller_
    ) public givenPendingBuckets {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE) && caller_ != _payout.configOperator());
        _token.mint(address(_payout), 7);
        bytes32 state = _ledgerDigest();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _payout.rescue(address(_token), _destination);
        assertEq(_ledgerDigest(), state, "Unauthorized rescue changes no custody");
    }

    // Scenarios: BLCU-RESCUE-A01.
    function test_givenFormerController_whenRescued_reverts() public {
        address former = _controller;
        _payout.setConfigOperator(_recipient);
        test_givenUnauthorizedCaller_whenRescued_reverts(former);
    }

    // Scenarios: BLCU-RESCUE-D02.
    function test_givenBlockedTransfer_whenSurplusRescued_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _token.mint(address(_payout), 7);
        _token.setTransferReverts(_destination, true);
        _expectTransferRejected(
            abi.encodeWithSelector(
                MockRevertingTransferToken.TransferReverted.selector,
                _destination
            ),
            caller_
        );
    }

    // Scenarios: BLCU-RESCUE-D03.
    function test_givenFalseTransfer_whenSurplusRescued_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _token.mint(address(_payout), 7);
        vm.mockCall(
            address(_token),
            abi.encodeCall(_token.transfer, (_destination, uint256(7))),
            abi.encode(false)
        );
        _expectTransferRejected(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(_token)),
            caller_
        );
    }

    function _assertSurplusTransfer(address caller_, uint256 surplus_, uint256 reserved_) internal {
        bytes32 buckets = _bucketDigest(address(_token));
        bytes32 other = _bucketDigest(address(_otherToken));
        bytes32 retired = _retiredDigest();
        uint256 beforeDestination = _token.balanceOf(_destination);
        vm.prank(caller_);
        assertEq(
            _payout.previewRescue(address(_token), _destination),
            surplus_,
            "Preview excludes every obligation"
        );
        vm.expectEmit(address(_payout));
        emit IBurnerLoansPayout.AssetRescued(address(_token), _destination, surplus_);
        vm.prank(caller_);
        _payout.rescue(address(_token), _destination);
        assertEq(
            _token.balanceOf(_destination),
            beforeDestination + surplus_,
            "Destination receives only surplus"
        );
        assertEq(_token.balanceOf(address(_payout)), reserved_, "All reserves stay in custody");
        assertEq(_bucketDigest(address(_token)), buckets, "Every liability and index preserved");
        assertEq(_bucketDigest(address(_otherToken)), other, "Other token untouched");
        assertEq(_retiredDigest(), retired, "Other Payout domain untouched");
    }

    function _expectInvalidRescue(
        bytes memory reason_,
        address caller_,
        address token_,
        address destination_
    ) internal {
        bytes32 state = _ledgerDigest();
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.previewRescue(token_, destination_);
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.rescue(token_, destination_);
        assertEq(
            _ledgerDigest(),
            state,
            "Invalid preview and execution preserve custody and indexes"
        );
    }

    function _expectTransferRejected(bytes memory reason_, address caller_) internal {
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        assertEq(
            _payout.previewRescue(address(_token), _destination),
            7,
            "Preview cannot guarantee token delivery"
        );
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.rescue(address(_token), _destination);
        assertEq(_ledgerDigest(), state, "Strict transfer failure restores the complete state");
    }

    // Scenarios: BLCU-RESCUE-I01.
    function test_givenZeroToken_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector,
                address(0)
            ),
            caller_,
            address(0),
            _destination
        );
    }

    // Scenarios: BLCU-RESCUE-I02.
    function test_givenEoaToken_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidAsset.selector,
                _recipient
            ),
            caller_,
            _recipient,
            _destination
        );
    }

    // Scenarios: BLCU-RESCUE-I03.
    function test_givenZeroDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(0)
            ),
            caller_,
            address(_token),
            address(0)
        );
    }

    // Scenarios: BLCU-RESCUE-I04.
    function test_givenCoreDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_core)
            ),
            caller_,
            address(_token),
            address(_core)
        );
    }

    // Scenarios: BLCU-RESCUE-I05.
    function test_givenSelfDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_payout)
            ),
            caller_,
            address(_token),
            address(_payout)
        );
    }

    // Scenarios: BLCU-RESCUE-I06.
    function test_givenControllerDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                _payout.configOperator()
            ),
            caller_,
            address(_token),
            _payout.configOperator()
        );
    }

    // Scenarios: BLCU-RESCUE-I07.
    function test_givenKernelDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_kernel)
            ),
            caller_,
            address(_token),
            address(_kernel)
        );
    }

    // Scenarios: BLCU-RESCUE-I08.
    function test_givenTokenDestination_whenRecovered_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _expectInvalidRescue(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination.selector,
                address(_token)
            ),
            caller_,
            address(_token),
            address(_token)
        );
    }

    // Scenarios: BLCU-RESCUE-P01.
    function test_givenBackedReserves_givenEachRecoveryRole_whenSurplusRescued_thenOnlyExcessMoves()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves(
                5,
                3,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-D01.
    function test_givenDeficitOrExactBacking_givenEachRecoveryRole_whenRescued_thenNoTransfer()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer(
                3,
                3,
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-L01.
    function test_givenPayoutActive_givenEachRecoveryRole_whenRescued_thenRecoveryAvailable()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenPayoutActive_whenRescued_thenRecoveryAvailable(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap,
                true,
                true,
                true
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-D02.
    function test_givenBlockedTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenBlockedTransfer_whenSurplusRescued_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-D03.
    function test_givenFalseTransfer_givenEachRecoveryRole_whenSurplusRescued_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenFalseTransfer_whenSurplusRescued_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I01.
    function test_givenZeroToken_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenZeroToken_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I02.
    function test_givenEoaToken_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenEoaToken_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I03.
    function test_givenZeroDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenZeroDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I04.
    function test_givenCoreDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenCoreDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I05.
    function test_givenSelfDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenSelfDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I06.
    function test_givenControllerDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenControllerDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I07.
    function test_givenKernelDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenKernelDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-I08.
    function test_givenTokenDestination_givenEachRecoveryRole_whenRecovered_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        RecoveryCaller[3] memory callers = _recoveryCallers();
        for (uint256 i; i < callers.length; ++i) {
            test_givenTokenDestination_whenRecovered_reverts(
                callers[i].account,
                callers[i].operatorOnly,
                callers[i].overlap
            );
            _restore(checkpoint);
        }
    }

    // Scenarios: BLCU-RESCUE-P01.
    function test_givenSurplusAndReserveAtTypeBoundaries_whenRescued_thenOnlyExcessMoves() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves(
            1,
            0,
            address(0xabc1),
            false,
            false
        );
        _restore(checkpoint);
        test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves(
            1,
            type(uint256).max - 1,
            address(0xabc2),
            true,
            false
        );
        _restore(checkpoint);
        test_givenBackedReserves_whenSurplusRescued_thenOnlyExcessMoves(
            type(uint256).max,
            0,
            address(0xabc3),
            false,
            true
        );
    }

    // Scenarios: BLCU-RESCUE-D01.
    function test_givenNoSurplusAtTypeBoundaries_whenRescued_thenNoTransfer() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer(
            0,
            0,
            address(0xabc1),
            false,
            false
        );
        _restore(checkpoint);
        test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer(
            type(uint256).max,
            0,
            address(0xabc2),
            true,
            false
        );
        _restore(checkpoint);
        test_givenDeficitOrExactBacking_whenRescued_thenNoTransfer(
            type(uint256).max,
            type(uint256).max,
            address(0xabc3),
            false,
            true
        );
    }

    // Scenarios: BLCU-RESCUE-L01.
    function test_givenPayoutActive_whenEveryCoreAndEnabledState_thenRecoveryAvailable() public {
        uint256 checkpoint = vm.snapshotState();

        for (uint256 enabled; enabled < 2; ++enabled) {
            for (uint256 coreActive; coreActive < 2; ++coreActive) {
                for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                    test_givenPayoutActive_whenRescued_thenRecoveryAvailable(
                        address(0xabc1),
                        false,
                        false,
                        enabled != 0,
                        coreActive != 0,
                        coreEnabled != 0
                    );
                    _restore(checkpoint);
                }
            }
        }
    }

    // Scenarios: BLCU-RESCUE-L02.
    function test_givenPayoutInactive_whenCalled_reverts(
        address caller_,
        bool operatorOnly_,
        bool overlap_,
        bool enabled_
    ) public givenPendingBuckets {
        _grantRecoveryCaller(caller_, operatorOnly_, overlap_);
        _token.mint(address(_payout), 7);
        _setState(_payout, false, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.previewRescue(address(_token), _destination);
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.rescue(address(_token), _destination);
        assertEq(_ledgerDigest(), state, "Inactive Payout preserves balances and obligations");
    }

    // Scenarios: BLCU-RESCUE-L04.
    function test_givenPayoutInactiveAndBrokenRoles_whenUnauthorizedCallerActs_thenActivityWins(
        address caller_,
        bool enabled_
    ) public givenPendingBuckets {
        _deactivatePayoutWithBrokenRoles(caller_, enabled_);
        bytes32 state = _ledgerDigest();
        _expectInactivePayout();
        vm.prank(caller_);
        _payout.rescue(address(_token), _destination);
        assertEq(_ledgerDigest(), state, "Inactivity rejects before authority or mutation");
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unused-return)
