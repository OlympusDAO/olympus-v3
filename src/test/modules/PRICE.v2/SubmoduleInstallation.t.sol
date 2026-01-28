// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

// Bophades
import {Actions, Kernel, Module} from "src/Kernel.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";
import {ModuleWithSubmodules, Submodule} from "src/Submodules.sol";
import {ChainlinkPriceFeeds} from "modules/PRICE/submodules/feeds/ChainlinkPriceFeeds.sol";
import {MockInvalidSubmodule} from "test/mocks/MockInvalidSubmodule.sol";
import {MockSubmoduleNoERC165} from "test/mocks/MockSubmoduleNoERC165.sol";

/// @title     SubmoduleInstallationTest
/// @author    0xJem
/// @notice    Tests for submodule installation validation
contract SubmoduleInstallationTest is Test {
    using ModuleTestFixtureGenerator for Module;

    Kernel internal kernel;
    OlympusPricev2 internal price;
    ChainlinkPriceFeeds internal validSubmodule;
    MockInvalidSubmodule internal invalidSubmodule; // Has supportsInterface but returns false for ISubmodule
    MockSubmoduleNoERC165 internal noERC165Submodule; // No supportsInterface at all

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
        noERC165Submodule = new MockSubmoduleNoERC165(price);
    }

    // ========= TESTS ========== //

    /// @notice Test that installing a valid submodule succeeds
    function test_installSubmodule_givenValidSubmodule_succeeds() public {
        vm.startPrank(moduleWriter);

        // Should succeed without reverting
        price.installSubmodule(validSubmodule);

        vm.stopPrank();
    }

    /// @notice Test that installing a submodule that returns false for ISubmodule reverts
    /// @dev    MockInvalidSubmodule implements supportsInterface but returns false for ISubmodule.interfaceId
    /// @dev    This tests the case where a contract implements ERC-165 but doesn't properly implement ISubmodule
    function test_installSubmodule_givenSubmoduleReturnsFalseForISubmodule_reverts() public {
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

    /// @notice Test that installing a submodule without supportsInterface reverts
    /// @dev    MockSubmoduleNoERC165 doesn't inherit from Submodule, so it has no supportsInterface function
    /// @dev    The staticcall to supportsInterface will fail (success = false), triggering validation failure
    function test_installSubmodule_givenSubmoduleNoSupportsInterface_reverts() public {
        vm.startPrank(moduleWriter);

        // Expect revert with Module_SubmoduleInterfaceNotImplemented error
        // The staticcall to supportsInterface will fail since the function doesn't exist
        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleWithSubmodules.Module_SubmoduleInterfaceNotImplemented.selector,
                address(noERC165Submodule)
            )
        );
        // Cast to Submodule type - this is allowed at compile time but will fail validation at runtime
        price.installSubmodule(Submodule(address(noERC165Submodule)));

        vm.stopPrank();
    }
}
