// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";

contract BurnerLoansPayoutEnableCallbackTest is BurnerLoansPayoutCallbackTest {
    // Scenarios: BLCU-ENABLE-C01.
    function test_givenOutgoingCallback_whenAuthorizedTokenTransitions_thenGuardRejects()
        public
        givenPendingBuckets
    {
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_callbackToken));
        _deferCallbackFee(5);
        _callbackToken.mint(address(_payout), 7);
        _payout.disable("");
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(IEnabler.enable, (bytes(""))),
            false
        );
        _payout.rescue(address(_callbackToken), _destination);
        _assertCallbackRejected();
        assertEq(_payout.isEnabled(), false, "Nested transition rejected");
        assertEq(_callbackToken.balanceOf(_destination), 7, "Outer surplus recovered once");
    }

    // Scenarios: BLCU-ENABLE-C02.
    function test_givenIncomingCallback_whenAuthorizedTokenTransitions_thenCoreGuardRejects()
        public
        givenPendingBuckets
    {
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_callbackToken));
        _payout.disable("");
        _prepareIncoming(abi.encodeCall(IEnabler.enable, (bytes(""))), false);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        _assertCallbackRejected();
        assertEq(_payout.isEnabled(), false, "Nested transition rejected during receipt");
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            100e18,
            "Outer receipt credited once"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
