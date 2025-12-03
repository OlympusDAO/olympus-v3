// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ERC165Helper} from "src/test/lib/ERC165.sol";

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

contract ConvertibleDepositFacilitySupportsInterfaceTest is ConvertibleDepositFacilityTest {
    function test_supportsInterface() public view {
        // Validate ERC165 compliance
        ERC165Helper.validateSupportsInterface(address(facility));

        // Test IERC165
        assertEq(facility.supportsInterface(type(IERC165).interfaceId), true, "IERC165 mismatch");

        // Test IConvertibleDepositFacility
        assertEq(
            facility.supportsInterface(type(IConvertibleDepositFacility).interfaceId),
            true,
            "IConvertibleDepositFacility mismatch"
        );

        // Test IDepositFacility
        assertEq(
            facility.supportsInterface(type(IDepositFacility).interfaceId),
            true,
            "IDepositFacility mismatch"
        );

        // Test IPeriodicTask
        assertEq(
            facility.supportsInterface(type(IPeriodicTask).interfaceId),
            true,
            "IPeriodicTask mismatch"
        );

        // Test IEnabler
        assertEq(facility.supportsInterface(type(IEnabler).interfaceId), true, "IEnabler mismatch");

        // Test non-implemented interfaces (should be false)
        assertEq(
            facility.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
        assertEq(
            facility.supportsInterface(type(IERC4626).interfaceId),
            false,
            "Should not support IERC4626"
        );
    }
}
