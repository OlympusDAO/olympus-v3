// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansCollateralTest} from "src/test/policies/BurnerLoansCollateral/BurnerLoansCollateralTest.sol";

// Fixed seeds and fixture calls are checked through accounting assertions.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralVERSIONTest is BurnerLoansCollateralTest {
    // Scenarios: BLCOL-VERSION-P01.
    function test_whenVersionRead_thenConstant(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenCollateralEnabled {
        _setPolicyState(_collateral, active_, enabled_);
        vm.prank(caller_);
        (uint8 major, uint8 minor) = _collateral.VERSION();
        assertEq(major, 1, "Major version");
        assertEq(minor, 0, "Minor version");
        _assertAccountingPreserved();
    }

    // Scenarios: BLCOL-VERSION-P01.
    function test_whenReadAcrossAllLifecycleStates_thenStable() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                uint256 checkpoint = vm.snapshotState();
                test_whenVersionRead_thenConstant(address(0xbeef), active != 0, enabled != 0);
                assertTrue(vm.revertToState(checkpoint), "Restore state between lifecycle seeds");
            }
        }
        _assertAccountingPreserved();
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
