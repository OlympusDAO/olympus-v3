// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Bophades
import {Actions, Kernel, Module} from "src/Kernel.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ModuleWithSubmodules} from "src/Submodules.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {MockInvalidSubmodule} from "test/mocks/MockInvalidSubmodule.sol";

/// @title     SubmoduleInstallationTest
/// @author    0xJem
/// @notice    Tests for submodule installation validation
contract SubmoduleInstallationTest is Test {
    using ModuleTestFixtureGenerator for Module;

    Kernel internal kernel;
    OlympusPricev2 internal price;
    ChainlinkPriceFeeds internal validSubmodule;
    MockInvalidSubmodule internal invalidSubmodule;

    address internal moduleWriter;

    function setUp() public {
        // Deploy kernel
        kernel = new Kernel();

        // Deploy price module
        price = new OlympusPricev2(kernel, 18, 3600);

        // Deploy mock module writer
        moduleWriter = ModuleTestFixtureGenerator.generateGodmodeFixture(
            Module(address(price)),
            type(ModuleWithSubmodules).name
        );

        // Initialize system and kernel
        kernel.executeAction(Actions.InstallModule, address(price));
        kernel.executeAction(Actions.ActivatePolicy, address(moduleWriter));

        // Deploy submodules
        validSubmodule = new ChainlinkPriceFeeds(price);
        invalidSubmodule = new MockInvalidSubmodule(price);
    }

    // ========= TESTS ========== //

    /// @notice Test that installing a valid submodule succeeds
    function test_installSubmodule_givenValidSubmodule_succeeds() public {
        vm.startPrank(moduleWriter);

        // Should succeed without reverting
        price.installSubmodule(validSubmodule);

        vm.stopPrank();
    }

    /// @notice Test that installing a submodule that doesn't implement ISubmodule reverts
    function test_installSubmodule_givenSubmoduleDoesNotImplementISubmodule_reverts() public {
        vm.startPrank(moduleWriter);

        // Expect revert with Module_SubmoduleInterfaceNotImplemented error
        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleWithSubmodules.Module_SubmoduleInterfaceNotImplemented.selector,
                address(invalidSubmodule)
            )
        );
        price.installSubmodule(invalidSubmodule);

        vm.stopPrank();
    }
}
