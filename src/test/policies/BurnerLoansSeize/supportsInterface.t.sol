// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

// Contracts
import {BurnerLoansSeizeLifecycleTest} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeLifecycleTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

contract BurnerLoansSeizeSupportsInterfaceTest is BurnerLoansSeizeLifecycleTest {
    // Scenarios: BLLIQ-ERC165-P01, BLLIQ-ERC165-P02, BLLIQ-ERC165-P03, BLLIQ-ERC165-P04, BLLIQ-ERC165-P05, BLLIQ-ERC165-P06, BLLIQ-ERC165-P07, BLLIQ-ERC165-P08, BLLIQ-ERC165-P09, BLLIQ-ERC165-P10, BLLIQ-ERC165-P11.
    function test_whenInterfacesQueried_thenOnlyAdvertisedSet(
        address caller_,
        bytes4 candidate_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_liquidation, active_, enabled_);
        bytes4[8] memory ids = [
            _INTERFACE_ID,
            type(IBurnerLoansCoreBound).interfaceId,
            type(IVersioned).interfaceId,
            type(IERC165).interfaceId,
            type(IEnabler).interfaceId,
            type(IEnablerV2).interfaceId,
            type(IReEnabler).interfaceId,
            type(IGracePeriod).interfaceId
        ];
        bool supported;
        for (uint256 i; i < ids.length; ++i) {
            vm.prank(caller_);
            assertTrue(_liquidation.supportsInterface(ids[i]), "Advertised interface supported");
            supported = supported || candidate_ == ids[i];
        }
        vm.prank(caller_);
        assertEq(
            _liquidation.supportsInterface(candidate_),
            supported,
            "Unknown selector is not advertised"
        );
        assertFalse(_liquidation.supportsInterface(0xffffffff), "Invalid ERC165 ID rejected");
        assertFalse(_liquidation.supportsInterface(bytes4(0)), "Zero interface rejected");
        _assertLoansPreserved();
    }

    // Scenarios: BLLIQ-ERC165-P01, BLLIQ-ERC165-P02, BLLIQ-ERC165-P03, BLLIQ-ERC165-P04, BLLIQ-ERC165-P05, BLLIQ-ERC165-P06, BLLIQ-ERC165-P07, BLLIQ-ERC165-P08, BLLIQ-ERC165-P09, BLLIQ-ERC165-P10, BLLIQ-ERC165-P11.
    function test_whenReadAcrossAllLifecycleStates_thenStable() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_whenInterfacesQueried_thenOnlyAdvertisedSet(
                    address(0xbeef),
                    0xffffffff,
                    active != 0,
                    enabled != 0
                );
                assertTrue(
                    vm.revertToState(checkpoint),
                    "Restore initial state for next lifecycle seed"
                );
            }
        }
        _assertLoansPreserved();
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
