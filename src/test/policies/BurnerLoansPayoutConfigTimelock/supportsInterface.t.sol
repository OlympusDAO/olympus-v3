// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";

contract BurnerLoansPayoutConfigTimelockSupportsInterfaceTest is
    BurnerLoansPayoutConfigTimelockTest
{
    // Scenarios: BLCUCT-ERC165-V01, BLCUCT-ERC165-V02, BLCUCT-ERC165-V03, BLCUCT-ERC165-V04, BLCUCT-ERC165-V05, BLCUCT-ERC165-V06, BLCUCT-ERC165-V07, BLCUCT-ERC165-V08, BLCUCT-ERC165-V09, BLCUCT-ERC165-I01.
    function test_whenInterfacesRead_thenOnlyAdvertisedSet(
        address caller_,
        bool ownActive_,
        bool ownEnabled_,
        bool targetActive_,
        bool targetEnabled_,
        bytes4 candidate_
    ) public givenPendingRecovery {
        _setState(_payoutTimelock, ownActive_, ownEnabled_);
        _setState(_payout, targetActive_, targetEnabled_);
        bytes32 beforeState = _queueDigest(_pendingId);
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(address(_payout), abi.encodeWithSignature("isEnabled()"), hex"deadbeef");

        bytes4[9] memory supported = [
            type(IBurnerLoansPayoutConfigTimelock).interfaceId,
            type(IVersioned).interfaceId,
            type(IERC165).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId,
            type(ITimelockBatchQueue).interfaceId,
            type(IConfigTimelockBatchQueue).interfaceId
        ];
        bool expected;
        for (uint256 i; i < supported.length; ++i) {
            vm.prank(caller_);
            assertTrue(_payoutTimelock.supportsInterface(supported[i]), "Advertised interface");
            expected = expected || candidate_ == supported[i];
        }
        vm.prank(caller_);
        assertEq(
            _payoutTimelock.supportsInterface(candidate_),
            expected,
            "Only the complete advertised set is supported"
        );
        assertFalse(_payoutTimelock.supportsInterface(0xffffffff), "Invalid ERC165 ID rejected");
        assertEq(_queueDigest(_pendingId), beforeState, "Interface queries preserve all state");
    }

    // Scenarios: BLCUCT-ERC165-V01, BLCUCT-ERC165-V02, BLCUCT-ERC165-V03, BLCUCT-ERC165-V04, BLCUCT-ERC165-V05, BLCUCT-ERC165-V06, BLCUCT-ERC165-V07, BLCUCT-ERC165-V08, BLCUCT-ERC165-V09, BLCUCT-ERC165-I01.
    function test_givenEachLifecyclePair_whenRead_thenIndependent() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 a; a < 2; ++a)
            for (uint256 e; e < 2; ++e)
                for (uint256 ta; ta < 2; ++ta)
                    for (uint256 te; te < 2; ++te) {
                        test_whenInterfacesRead_thenOnlyAdvertisedSet(
                            address(0),
                            a != 0,
                            e != 0,
                            ta != 0,
                            te != 0,
                            bytes4(0)
                        );
                        _restore(checkpoint);
                    }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
