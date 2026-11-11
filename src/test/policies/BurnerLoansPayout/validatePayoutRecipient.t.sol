// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansPayoutTest} from "src/test/policies/BurnerLoansPayout/BurnerLoansPayoutTest.sol";

contract BurnerLoansPayoutValidatePayoutRecipientTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-VALIDATE-RECIPIENT-P01.
    function test_whenRecipientValid(
        address caller_,
        address recipient_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        vm.assume(recipient_ != address(0) && recipient_ != address(_payout));
        _setState(_payout, active_, enabled_);
        bytes32 beforeState = _ledgerDigest();
        vm.prank(caller_);
        _payout.validatePayoutRecipient(recipient_);
        assertEq(_ledgerDigest(), beforeState, "Validation preserves custody and all claims");
    }

    // Scenarios: BLCU-VALIDATE-RECIPIENT-I01.
    function test_whenRecipientZero_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(0)
            )
        );
        vm.prank(caller_);
        _payout.validatePayoutRecipient(address(0));
        assertEq(_ledgerDigest(), beforeState, "Zero recipient rejection preserves all claims");
    }

    // Scenarios: BLCU-VALIDATE-RECIPIENT-I02.
    function test_whenRecipientPayout_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        bytes32 beforeState = _ledgerDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        vm.prank(caller_);
        _payout.validatePayoutRecipient(address(_payout));
        assertEq(_ledgerDigest(), beforeState, "Self recipient rejection preserves all claims");
    }

    // Scenarios: BLCU-VALIDATE-RECIPIENT-P02.
    function test_whenAddressBoundaries() public {
        vm.prank(address(0));
        _payout.validatePayoutRecipient(address(1));
        vm.prank(address(type(uint160).max));
        _payout.validatePayoutRecipient(address(type(uint160).max));
    }

    // Scenarios: BLCU-VALIDATE-RECIPIENT-L01.
    function test_givenLifecycleTransitions_whenRecipientValidated() public givenPendingBuckets {
        bytes32 beforeState = _ledgerDigest();
        _assertDestinations();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _assertDestinations();
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _payout.disable("");
        _assertDestinations();
        _kernel.executeAction(Actions.DeactivatePolicy, address(_payout));
        _assertDestinations();
        _kernel.executeAction(Actions.ActivatePolicy, address(_payout));
        _payout.enable("");
        _assertDestinations();
        assertEq(
            _ledgerDigest(),
            beforeState,
            "Lifecycle transitions preserve every pending claim"
        );
    }

    function _assertDestinations() private {
        _payout.validatePayoutRecipient(_keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(0)
            )
        );
        _payout.validatePayoutRecipient(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayout.BurnerLoansPayout_InvalidRecipient.selector,
                address(_payout)
            )
        );
        _payout.validatePayoutRecipient(address(_payout));
    }
}
