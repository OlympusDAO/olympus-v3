// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {Kernel} from "src/Kernel.sol";
import {Keycode, Permissions} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";

contract BurnerLoansConfigRequestPermissionsTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-PERMISSIONS-P01.
    function test_whenPermissionsRequested(address caller_, bool active_, bool enabled_) public {
        _setPolicyState(_config, active_, enabled_);
        _assertPermissions(caller_);
    }

    function _assertPermissions(address caller_) internal {
        vm.prank(caller_);
        Permissions[] memory permissions = _config.requestPermissions();
        assertEq(permissions.length, 6, "Six narrowly scoped FLOAN permissions");
        bytes4[6] memory selectors = [
            IFLOANv1.createMarket.selector,
            IFLOANv1.setMarketOriginationsEnabled.selector,
            IFLOANv1.setMarketPrincipalCap.selector,
            IFLOANv1.setMarketRiskConfig.selector,
            IFLOANv1.setMarketBaseFee.selector,
            IFLOANv1.setMarketConfigData.selector
        ];
        for (uint256 i; i < selectors.length; ++i) {
            assertEq(Keycode.unwrap(permissions[i].keycode), bytes5("FLOAN"), "FLOAN keycode only");
            assertEq(permissions[i].funcSelector, selectors[i], "Ordered exact selector");
        }
    }

    // Scenarios: BLCFG-PERMISSIONS-P01.
    function test_givenFreshDeployment_whenPermissionsRequested(address caller_) public {
        _config = new BurnerLoansConfig(_kernel, IBurnerLoansCore(address(_core)));
        _assertPermissions(caller_);
    }

    // Scenarios: BLCFG-PERMISSIONS-P01.
    function test_givenKernelMigration_whenPermissionsRequested(address caller_) public {
        vm.prank(address(_kernel));
        _config.changeKernel(Kernel(_recipient));
        _assertPermissions(caller_);
    }
}
