// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {Kernel} from "src/Kernel.sol";
import {Keycode, Permissions} from "src/Kernel.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

contract BurnerLoansCoreRequestPermissionsTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-PERMISSIONS-P01.
    function test_whenPermissionsRequested(address caller_, bool active_, bool enabled_) public {
        _setCoreLifecycle(active_, enabled_);
        vm.prank(caller_);
        Permissions[] memory result = _core.requestPermissions();
        bytes4[8] memory expected = [
            IFLOANv1.addCollateral.selector,
            IFLOANv1.removeCollateral.selector,
            IFLOANv1.increaseDebt.selector,
            IFLOANv1.createPosition.selector,
            IFLOANv1.decreaseDebt.selector,
            IFLOANv1.extendMaturity.selector,
            IFLOANv1.defaultPosition.selector,
            IFLOANv1.setMarketManager.selector
        ];
        assertEq(result.length, 8, "Exactly eight permissions");
        for (uint256 i; i < 8; ++i) {
            assertEq(Keycode.unwrap(result[i].keycode), bytes5("FLOAN"), "Only FLOAN requested");
            assertEq(result[i].funcSelector, expected[i], "Exact ordered selector");
        }
    }

    // Scenarios: BLCORE-PERMISSIONS-P01.
    function test_givenFreshAndMigratedCore_whenPermissionsRequested(address caller_) public {
        BurnerLoansCore fresh = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        vm.prank(caller_);
        Permissions[] memory initial = fresh.requestPermissions();
        assertEq(initial.length, 8, "Fresh unconfigured policy requests exact permission count");
        bytes32 expected = keccak256(abi.encode(_core.requestPermissions()));
        assertEq(
            keccak256(abi.encode(initial)),
            expected,
            "Permissions independent of activation history"
        );
        vm.prank(address(_kernel));
        _core.changeKernel(Kernel(address(0)));
        vm.prank(caller_);
        assertEq(
            keccak256(abi.encode(_core.requestPermissions())),
            expected,
            "Migration introduces no extra permissions or dependency read"
        );
    }
}
