// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {CoreAuthorizationAdmissionTest} from "./fixtures/CoreAuthorizationAdmissionTest.sol";

contract BurnerLoansCoreAuthorizationInvariantTest is CoreAuthorizationAdmissionTest {
    // Scenarios: BLCORE-SETTLE-BORROW-A02.
    function invariant_lifecycleAuthorizationAndCustodyStayIndependent() public view {
        assertEq(
            _core.isActive(),
            _admissionHandler.expectedActive(),
            "Kernel activity matches transition model"
        );
        assertEq(
            _core.isEnabled(),
            _admissionHandler.expectedEnabled(),
            "Local flag matches independent transition model"
        );
        assertEq(
            _auth.pairEpochs(address(_admissionHandler), _admissionHandler.OPERATOR()),
            _admissionHandler.expectedNonce(),
            "Only successful grant and cancellation consume nonce"
        );
        assertEq(
            _auth.getGrant(address(_admissionHandler), _admissionHandler.OPERATOR()).deadline,
            _admissionHandler.expectedDeadline(),
            "Only owner's grant/cancellation controls operator"
        );
        assertEq(
            _ledger(),
            _admissionLedger,
            "Governance admission and authorization sequences move no custody or principal"
        );
    }
}
