// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {BurnerLoansYieldClaimerTaskTest} from "./BurnerLoansYieldClaimerTaskTest.sol";

contract BurnerLoansYieldClaimerTaskClaimYieldForwardingTest is BurnerLoansYieldClaimerTaskTest {
    // Scenarios: BLYC-CLAIM-YIELD-A01.
    function test_givenAuthoritativeSettlementOutput_whenClaimed(
        address caller_,
        address output_,
        uint256 amount_
    ) public {
        address asset = target.getAssetAt(0);
        bytes memory settlement = abi.encodeCall(
            IBurnerLoansCore.settleYield,
            (asset, 1, address(0xBEEF))
        );
        vm.mockCall(address(target), settlement, abi.encode(output_, amount_));
        vm.expectCall(address(target), settlement, uint64(1));
        vm.prank(caller_);
        (address output, uint256 amount) = claimer.claimYield(asset);
        assertEq(output, output_, "Action forwards Core's output token unchanged");
        assertEq(amount, amount_, "Action forwards authoritative settled output unchanged");
    }
}
