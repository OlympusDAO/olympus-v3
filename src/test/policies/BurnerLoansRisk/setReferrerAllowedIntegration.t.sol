// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansRiskUpstreamTest} from "./fixtures/BurnerLoansRiskUpstreamTest.sol";

contract BurnerLoansRiskSetReferrerAllowedIntegrationTest is BurnerLoansRiskUpstreamTest {
    // Scenarios: BLRISK-REFERRER-D01.
    function test_givenIndependentUpstreamLifecycle_whenConfigured(
        UpstreamState memory state_,
        bool operator_
    ) public {
        _expectNoUpstreamMetadataCalls();
        _exerciseIndependentUpstreamState(state_, operator_);
    }

    function _exerciseIndependentUpstreamState(
        UpstreamState memory state_,
        bool operator_
    ) private {
        _setUpstreamState(state_);
        bytes32 beforeAccounting = _unaffectedAccounting();
        address caller = operator_ ? address(_timelock) : address(this);
        vm.expectEmit(address(_risk));
        emit IBurnerLoansRisk.ReferrerAllowedSet(_recipient, true);
        vm.prank(caller);
        _risk.setReferrerAllowed(_recipient, true);
        assertTrue(_risk.isReferrerAllowed(_recipient), "changed referrer eligibility");
        assertEq(
            _unaffectedAccounting(),
            beforeAccounting,
            "configuration leaves positions, custody and earned rewards unchanged"
        );
        assertEq(_risk.configOperator(), address(_timelock), "selected operator identity retained");
    }

    // Scenarios: BLRISK-REFERRER-D01.
    function test_givenEveryIndependentUpstreamState_whenConfigured() public {
        _expectNoUpstreamMetadataCalls();
        uint256 checkpoint = vm.snapshotState();
        for (uint8 bits; bits < 64; ++bits) {
            UpstreamState memory state = _upstreamState(bits);
            _exerciseIndependentUpstreamState(state, false);
            _restore(checkpoint);
            _exerciseIndependentUpstreamState(state, true);
            _restore(checkpoint);
        }
    }
}
