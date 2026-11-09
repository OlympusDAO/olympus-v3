// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Independent token amounts in callback proofs.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {BurnerLoansPayoutCallbackTest} from "./fixtures/BurnerLoansPayoutCallbackTest.sol";

contract BurnerLoansPayoutReEnableCallbackTest is BurnerLoansPayoutCallbackTest {
    modifier givenAuthorizedPausedPayout() {
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_callbackToken));
        _payout.disable("");
        _;
    }

    // Scenarios: BLCU-REENABLE-C01.
    function test_givenOutgoingCallback_whenReEnableCaught()
        public
        givenPendingBuckets
        givenAuthorizedPausedPayout
    {
        _callbackToken.mint(address(_payout), 7);
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(IReEnabler.reEnable, ()),
            false
        );
        uint48 last = _payout.lastTransitionAt();
        _payout.rescue(address(_callbackToken), _destination);
        _assertCallbackRejected();
        assertFalse(_payout.isEnabled(), "Nested re-enable rejected");
        assertEq(_payout.lastTransitionAt(), last, "Nested call preserves history");
        assertEq(_callbackToken.balanceOf(_destination), 7, "Outer recovery pays once");
        assertEq(_callbackToken.balanceOf(address(_payout)), 0, "No surplus left");
    }

    // Scenarios: BLCU-REENABLE-C02.
    function test_givenOutgoingCallback_whenReEnablePropagated_reverts()
        public
        givenPendingBuckets
        givenAuthorizedPausedPayout
    {
        _callbackToken.mint(address(_payout), 7);
        _callbackToken.armOutgoing(
            address(_payout),
            _destination,
            abi.encodeCall(IReEnabler.reEnable, ()),
            true
        );
        bytes32 ledger = _ledgerDigest();
        bytes32 callbackState = _callbackDigest();
        uint48 last = _payout.lastTransitionAt();
        // LoanPayouts' strict recovery transfer preserves the underlying token revert bytes.
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _payout.rescue(address(_callbackToken), _destination);
        assertFalse(_payout.isEnabled(), "Failed recovery cannot re-enable");
        assertEq(_payout.lastTransitionAt(), last, "History rolled back");
        assertEq(_ledgerDigest(), ledger, "All claims unchanged");
        assertEq(_callbackDigest(), callbackState, "Mandatory transfer rolled back");
    }

    // Scenarios: BLCU-REENABLE-C03.
    function test_givenIncomingCallback_whenReEnableCaught()
        public
        givenPendingBuckets
        givenAuthorizedPausedPayout
    {
        _prepareIncoming(abi.encodeCall(IReEnabler.reEnable, ()), false);
        uint48 last = _payout.lastTransitionAt();
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        _assertCallbackRejected();
        assertFalse(_payout.isEnabled(), "Core settlement cannot re-enable Payout");
        assertEq(_payout.lastTransitionAt(), last, "History unchanged during receipt");
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            100e18,
            "Deposit credited once"
        );
    }

    // Scenarios: BLCU-REENABLE-C04.
    function test_givenIncomingCallback_whenReEnablePropagated_reverts()
        public
        givenPendingBuckets
        givenAuthorizedPausedPayout
    {
        _prepareIncoming(abi.encodeCall(IReEnabler.reEnable, ()), true);
        uint256 borrowerBalance = _callbackToken.balanceOf(_borrower);
        bytes32 ledger = _ledgerDigest();
        uint48 last = _payout.lastTransitionAt();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_callbackToken), 100e18, _borrower);
        assertFalse(_payout.isEnabled(), "Rejected receipt cannot re-enable");
        assertEq(_payout.lastTransitionAt(), last, "History rolled back");
        assertEq(
            _callbackToken.balanceOf(_borrower),
            borrowerBalance,
            "Borrower transfer rolled back"
        );
        assertEq(
            _lens.getPosition(address(_callbackToken), _borrower).depositedCollateral,
            0,
            "No deposit credit"
        );
        assertEq(_ledgerDigest(), ledger, "Payout claims unchanged");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
