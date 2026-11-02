// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";

contract BurnerLoansPayoutDisableCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-DISABLE-C01.
    function test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects(
        bool emergency_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantPauseCaller(address(_callbackToken), emergency_, overlap_);
        _deferCallbackFee(5);
        _callbackToken.mint(address(_payout), 7);

        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(IEnabler.disable, (bytes(""))),
            false
        );
        _payout.rescue(address(_callbackToken), _destination);
        _assertCallbackRejected();
        assertEq(_payout.isEnabled(), true, "Nested transition rejected");
        assertEq(_callbackToken.balanceOf(_destination), 7, "Outer surplus recovered once");
    }

    // Scenarios: BLCU-DISABLE-C02.
    function test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects(
        bool emergency_,
        bool overlap_
    ) public givenPendingBuckets {
        _grantPauseCaller(address(_callbackToken), emergency_, overlap_);
        _prepareIncoming(abi.encodeCall(IEnabler.disable, (bytes(""))), false);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        _assertCallbackRejected();
        assertEq(_payout.isEnabled(), true, "Nested transition rejected during receipt");
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            100e18,
            "Outer receipt credited once"
        );
    }

    // Scenarios: BLCU-DISABLE-C01.
    function test_givenEachPauseRole_whenOutgoingCallbackTransitions_thenRejected() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects(false, false);
        _restore(checkpoint);
        test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects(true, false);
        _restore(checkpoint);
        test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects(false, true);
    }

    // Scenarios: BLCU-DISABLE-C02.
    function test_givenEachPauseRole_whenIncomingCallbackTransitions_thenRejected() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects(
            false,
            false
        );
        _restore(checkpoint);
        test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects(true, false);
        _restore(checkpoint);
        test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects(false, true);
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
