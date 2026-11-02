// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";

contract BurnerLoansInventoryConfigTimelockSupportsInterfaceTest is
    BurnerLoansInventoryConfigTimelockTest
{
    // Scenarios: BLINCT-ERC165-P01, BLINCT-ERC165-P02, BLINCT-ERC165-P03, BLINCT-ERC165-P04, BLINCT-ERC165-P05, BLINCT-ERC165-P06, BLINCT-ERC165-P07, BLINCT-ERC165-P08, BLINCT-ERC165-P09, BLINCT-ERC165-I01, BLINCT-ERC165-I02.
    function test_whenInterfacesRead_thenOnlyAdvertisedSet(
        address caller_,
        bool ownActive_,
        bool ownEnabled_,
        bool targetActive_,
        bool targetEnabled_,
        bytes4 candidate_
    ) public givenPendingRecovery {
        _setState(_timelock, ownActive_, ownEnabled_);
        _setState(_inventory, targetActive_, targetEnabled_);
        bytes32 beforeState = _queueDigest(_pendingId);
        vm.mockCallRevert(address(_inventory), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("isEnabled()"),
            hex"deadbeef"
        );

        bytes4[9] memory supported = [
            type(IBurnerLoansInventoryConfigTimelock).interfaceId,
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
            assertTrue(_timelock.supportsInterface(supported[i]), "Advertised interface");
            expected = expected || candidate_ == supported[i];
        }
        vm.prank(caller_);
        assertEq(
            _timelock.supportsInterface(candidate_),
            expected,
            "Only the complete advertised set is supported"
        );
        assertFalse(_timelock.supportsInterface(0xffffffff), "Invalid ERC165 ID rejected");
        assertEq(_queueDigest(_pendingId), beforeState, "Interface queries preserve all state");
    }

    // Scenarios: BLINCT-ERC165-P01, BLINCT-ERC165-P02, BLINCT-ERC165-P03, BLINCT-ERC165-P04, BLINCT-ERC165-P05, BLINCT-ERC165-P06, BLINCT-ERC165-P07, BLINCT-ERC165-P08, BLINCT-ERC165-P09, BLINCT-ERC165-I01, BLINCT-ERC165-I02.
    function test_givenEachLifecyclePair_whenRead_thenIndependent() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_whenInterfacesRead_thenOnlyAdvertisedSet(
                    address(0),
                    active != 0,
                    enabled != 0,
                    active != 0,
                    enabled != 0,
                    0xffffffff
                );
                _restore(checkpoint);
            }
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
