// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";

import {Actions} from "src/Kernel.sol";
import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

contract ConfigureDependenciesCDFTest is ConvertibleDepositFacilityTest {
    // when the CDEPO module is upgraded
    //  [X] it reverts

    function test_cdepoUpgrade_reverts() public {
        convertibleDepository = new OlympusConvertibleDepository(
            address(kernel),
            address(vault),
            RECLAIM_RATE
        );

        // Expect revert
        // CDFacility is installed first, so it will have configuredDependencies called first and revert first
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepositFacility.CDF_InvalidArgs.selector, "CDEPO")
        );

        // Upgrade the module
        kernel.executeAction(Actions.UpgradeModule, address(convertibleDepository));
    }
}
