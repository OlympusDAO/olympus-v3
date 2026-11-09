// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// forge-lint: disable-start(calls-loop)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";

contract BurnerLoansPayoutSupportsInterfaceTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-ERC165-P01, BLCU-ERC165-P02, BLCU-ERC165-P03, BLCU-ERC165-P04, BLCU-ERC165-P05, BLCU-ERC165-P06, BLCU-ERC165-P07, BLCU-ERC165-P08, BLCU-ERC165-P09, BLCU-ERC165-P10, BLCU-ERC165-P11, BLCU-ERC165-P12.
    function test_whenInterfacesRead_thenExactAdvertisedSet(
        address caller_,
        bool active_,
        bool enabled_,
        bytes4 candidate_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        bytes32 state = _ledgerDigest();
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(_core.requireNotReentrant, ()),
            hex"deadbeef"
        );
        bytes4[9] memory ids = [
            type(IBurnerLoansPayout).interfaceId,
            type(IBurnerLoansCoreBound).interfaceId,
            type(IERC165).interfaceId,
            type(IVersioned).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IConfigOperator).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId
        ];
        bool expected;
        for (uint256 i; i < ids.length; ++i) {
            vm.prank(caller_);
            assertTrue(_payout.supportsInterface(ids[i]), "Advertised interface accepted");
            expected = expected || candidate_ == ids[i];
        }
        vm.prank(caller_);
        assertEq(_payout.supportsInterface(candidate_), expected, "Only advertised set accepted");
        assertFalse(_payout.supportsInterface(0xffffffff), "Reserved ID rejected");
        assertFalse(_payout.supportsInterface(0), "Zero ID rejected");
        assertEq(_ledgerDigest(), state, "Discovery leaves custody intact");
    }
}

// forge-lint: disable-end(calls-loop)
