// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {CoreAuthorizationAdmissionTest} from "src/test/policies/BurnerLoansCore/fixtures/CoreAuthorizationAdmissionTest.sol";

contract BurnerLoansAuthApproveGrantCoreIntegrationTest is CoreAuthorizationAdmissionTest {
    // Scenarios: BLAUTH-APPROVE-P05.
    // Fuzz bounds and the controlled fixture clock keep these values within their target widths.
    // forge-lint: disable-start(unsafe-typecast)
    function test_whenReusableGrantApproved(uint48 deadline_) public {
        deadline_ = uint48(bound(deadline_, block.timestamp, type(uint48).max));
        _approveOperator(_borrower, _recipient, deadline_);
        assertEq(_auth.pairEpochs(_borrower, _recipient), 1, "Pair epoch consumed");
        vm.warp(deadline_);
        assertTrue(_isSenderAuthorized(_recipient, _borrower), "Deadline inclusive");
        vm.warp(uint256(deadline_) + 1);
        assertFalse(
            _isSenderAuthorized(_recipient, _borrower),
            "Full width timestamp expires grant"
        );
    }

    // forge-lint: disable-end(unsafe-typecast)

    // Scenarios: BLAUTH-APPROVE-P06.
    function test_whenRepeatedApprovals() public {
        _approveOperator(_borrower, _recipient, type(uint48).max);
        _approveOperator(_borrower, _recipient, type(uint48).max);
        assertEq(_auth.pairEpochs(_borrower, _recipient), 2, "Each acceptance consumes one epoch");
    }

    // Scenarios: BLAUTH-APPROVE-I07.
    function test_whenSelfGrant_reverts() public {
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, _borrower, type(uint48).max);
        vm.expectRevert(IOperatorAuth.OperatorAuth_SelfGrant.selector);
        vm.prank(_borrower);
        _auth.approveGrant(grant);
    }

    // Scenarios: BLAUTH-APPROVE-I08.
    function test_whenExpiredGrant_reverts() public {
        vm.warp(2);
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, _recipient, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, uint48(1))
        );
        vm.prank(_borrower);
        _auth.approveGrant(grant);
        assertEq(_auth.pairEpochs(_borrower, _recipient), 0, "Expired acceptance rolls back epoch");
    }

    // Scenarios: BLAUTH-APPROVE-I09.
    function test_whenPairEpochExhausted_reverts() public {
        _setPairEpoch(_borrower, _recipient, type(uint256).max);
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, _recipient, type(uint48).max);
        vm.expectRevert(IOperatorAuth.OperatorAuth_EpochExhausted.selector);
        vm.prank(_borrower);
        _auth.approveGrant(grant);
    }

    // Scenarios: BLAUTH-APPROVE-N05.
    function test_whenLastPairEpochAccepted() public {
        _setPairEpoch(_borrower, _recipient, type(uint256).max - 1);
        _approveOperator(_borrower, _recipient, type(uint48).max);
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            type(uint256).max,
            "Final epoch accepted once"
        );
        assertTrue(_isSenderAuthorized(_recipient, _borrower), "Final epoch grant remains usable");
    }

    // Scenarios: BLAUTH-APPROVE-A01.
    function test_whenUnauthorizedAccountApproves_reverts(address caller_) public {
        vm.assume(caller_ != _borrower);
        IOperatorAuth.Grant memory grant = _operatorGrant(_borrower, _recipient, type(uint48).max);
        vm.expectRevert(IOperatorAuth.OperatorAuth_InvalidIdentity.selector);
        vm.prank(caller_);
        _auth.approveGrant(grant);
        assertEq(
            _auth.pairEpochs(_borrower, _recipient),
            0,
            "Unrelated caller cannot approve authority"
        );
    }
}
