// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

import {OlympusConvertibleDepository} from "src/modules/CDEPO/OlympusConvertibleDepository.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract ConstructorCDEPOTest is CDEPOTest {
    // when the vault address is zero
    //  [X] it reverts
    // [X] the name is set to "cd" + the asset symbol
    // [X] the symbol is set to "cd" + the asset symbol
    // [X] the decimals are set to the asset decimals
    // [X] the asset is recorded
    // [X] the vault is recorded

    function test_vault_zeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert();

        // Call function
        new OlympusConvertibleDepository(address(kernel), address(0));
    }

    function test_stateVariables() public {
        assertEq(address(CDEPO.kernel()), address(kernel), "kernel");
        assertEq(CDEPO.name(), "cdRST", "name");
        assertEq(CDEPO.symbol(), "cdRST", "symbol");
        assertEq(CDEPO.decimals(), 18, "decimals");
        assertEq(address(CDEPO.asset()), address(reserveToken), "asset");
        assertEq(address(CDEPO.vault()), address(vault), "vault");
    }
}
