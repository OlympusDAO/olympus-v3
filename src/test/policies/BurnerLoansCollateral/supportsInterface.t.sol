// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";

// Contracts
import {BurnerLoansCollateralTest} from "src/test/policies/BurnerLoansCollateral/BurnerLoansCollateralTest.sol";

// Fixed seeds and fixture calls are checked through accounting assertions.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralSupportsInterfaceTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-ERC165-P02.
    function test_whenCoreBindingInterfaceQueried_thenExactAbiIdSupported(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, enabled_);
        // The shared binding contains only core(), independently of the collateral action API.
        bytes4 coreBindingId = bytes4(keccak256("core()"));
        assertEq(
            type(IBurnerLoansCoreBound).interfaceId,
            coreBindingId,
            "Shared binding exposes the exact core() ABI ID"
        );
        vm.prank(caller_);
        assertTrue(
            _collateral.supportsInterface(coreBindingId),
            "Exact core-only binding ID is advertised"
        );
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-ERC165-P01, BLCOL-ERC165-P02, BLCOL-ERC165-P03, BLCOL-ERC165-P04, BLCOL-ERC165-P05, BLCOL-ERC165-P06, BLCOL-ERC165-P07, BLCOL-ERC165-P08, BLCOL-ERC165-P09, BLCOL-ERC165-P10, BLCOL-ERC165-P11.
    function test_whenInterfacesQueried_thenOnlyAdvertisedSet(
        address caller_,
        bytes4 candidate_,
        bool active_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, enabled_);
        bytes4[8] memory ids = [
            type(IBurnerLoansCollateral).interfaceId,
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
            assertTrue(_collateral.supportsInterface(ids[i]), "Advertised interface supported");
            supported = supported || candidate_ == ids[i];
        }
        vm.prank(caller_);
        assertEq(
            _collateral.supportsInterface(candidate_),
            supported,
            "Unknown selector is not advertised"
        );
        assertFalse(_collateral.supportsInterface(0xffffffff), "Invalid ERC165 ID rejected");
        assertFalse(_collateral.supportsInterface(bytes4(0)), "Zero interface rejected");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-ERC165-P01, BLCOL-ERC165-P02, BLCOL-ERC165-P03, BLCOL-ERC165-P04, BLCOL-ERC165-P05, BLCOL-ERC165-P06, BLCOL-ERC165-P07, BLCOL-ERC165-P08, BLCOL-ERC165-P09, BLCOL-ERC165-P10, BLCOL-ERC165-P11.
    function test_whenReadAcrossAllLifecycleStates_thenStable() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_whenInterfacesQueried_thenOnlyAdvertisedSet(
                    address(0xbeef),
                    bytes4(0xffffffff),
                    active != 0,
                    enabled != 0
                );
                assertTrue(vm.revertToState(checkpoint), "Restore state between lifecycle seeds");
            }
        }
        _assertAccountingPreserved();
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
