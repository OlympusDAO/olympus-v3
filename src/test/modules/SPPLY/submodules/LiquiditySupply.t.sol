// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";

import {Kernel, Actions, fromKeycode} from "src/Kernel.sol";
import {Submodule, fromSubKeycode} from "src/Submodules.sol";

import {SPPLYv1} from "src/modules/SPPLY/SPPLY.v1.sol";
import {OlympusSupply} from "src/modules/SPPLY/OlympusSupply.sol";
import {LiquiditySupply} from "src/modules/SPPLY/submodules/LiquiditySupply.sol";

contract LiquiditySupplyTest is Test {
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal spply;

    LiquiditySupply internal submoduleLiquiditySupply;

    address internal godmode;

    address internal constant CALLER_NOT_PARENT = address(0x10);

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals

    address internal constant POL_LOCATION_1 = address(0x1);
    address internal constant POL_LOCATION_2 = address(0x2);
    address internal constant POL_LOCATION_3 = address(0x3);

    uint256 internal constant POL_AMOUNT_1 = 1e9;
    uint256 internal constant POL_AMOUNT_2 = 2e9;
    uint256 internal constant POL_AMOUNT_3 = 3e9;

    function setUp() public {
        // Create tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            gOhm = new MockGohm(GOHM_INDEX);
        }

        // Create kernel and modules
        {
            kernel = new Kernel();

            address[2] memory tokens = [address(ohm), address(gOhm)];
            spply = new OlympusSupply(kernel, tokens, 0, uint32(8 hours));
        }

        // Create submodule
        {
            uint256[] memory polOhmAmounts = new uint256[](2);
            polOhmAmounts[0] = POL_AMOUNT_1;
            polOhmAmounts[1] = POL_AMOUNT_2;

            address[] memory polSources = new address[](2);
            polSources[0] = POL_LOCATION_1;
            polSources[1] = POL_LOCATION_2;

            submoduleLiquiditySupply = new LiquiditySupply(spply, polOhmAmounts, polSources);
        }

        // Create godmode
        {
            godmode = spply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Install modules and submodules
        {
            kernel.executeAction(Actions.InstallModule, address(spply));
            kernel.executeAction(Actions.ActivatePolicy, godmode);

            vm.prank(godmode);
            spply.installSubmodule(submoduleLiquiditySupply);
        }
    }

    // ========= Module Information ========= //

    // [X]  VERSION
    // [X]  PARENT
    // [X]  SUBKEYCODE

    function test_VERSION() public {
        (uint8 major, uint8 minor) = submoduleLiquiditySupply.VERSION();

        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_PARENT() public {
        assertEq(fromKeycode(submoduleLiquiditySupply.PARENT()), "SPPLY");
    }

    function test_SUBKEYCODE() public {
        assertEq(fromSubKeycode(submoduleLiquiditySupply.SUBKEYCODE()), "SPPLY.LIQSPPLY");
    }

    // ========= Constructor ========= //

    // [X] if a source is the zero address
    //  [X] it reverts
    // [X] if a source is duplicated in the sources array
    //  [X] it reverts
    // [X] it adds the sources and balances

    function test_constructor_whenSourceIsZeroAddress() public {
        uint256[] memory polOhmAmounts = new uint256[](2);
        polOhmAmounts[0] = POL_AMOUNT_1;
        polOhmAmounts[1] = POL_AMOUNT_2;

        address[] memory polSources = new address[](2);
        polSources[0] = POL_LOCATION_1;
        polSources[1] = address(0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        new LiquiditySupply(spply, polOhmAmounts, polSources);
    }

    function test_constructor_whenSourceIsDuplicated() public {
        uint256[] memory polOhmAmounts = new uint256[](2);
        polOhmAmounts[0] = POL_AMOUNT_1;
        polOhmAmounts[1] = POL_AMOUNT_2;

        address[] memory polSources = new address[](2);
        polSources[0] = POL_LOCATION_1;
        polSources[1] = POL_LOCATION_1;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        new LiquiditySupply(spply, polOhmAmounts, polSources);
    }

    function test_constructor() public {
        uint256[] memory polOhmAmounts = new uint256[](2);
        polOhmAmounts[0] = POL_AMOUNT_1;
        polOhmAmounts[1] = POL_AMOUNT_2;

        address[] memory polSources = new address[](2);
        polSources[0] = POL_LOCATION_1;
        polSources[1] = POL_LOCATION_2;

        // Call function
        LiquiditySupply liquiditySupply = new LiquiditySupply(spply, polOhmAmounts, polSources);

        // Assert
        assertEq(liquiditySupply.getProtocolOwnedLiquidityOhm(), POL_AMOUNT_1 + POL_AMOUNT_2);
        assertEq(liquiditySupply.getSourceCount(), 2);
    }

    // ========= getProtocolOwnedTreasuryOhm ========= //

    // [X] it returns 0

    function test_getProtocolOwnedTreasuryOhm() public {
        assertEq(submoduleLiquiditySupply.getProtocolOwnedTreasuryOhm(), 0);
    }

    // ========= getProtocolOwnedBorrowableOhm ========= //

    // [X] it returns 0

    function test_getProtocolOwnedBorrowableOhm() public {
        assertEq(submoduleLiquiditySupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // ========= getProtocolOwnedLiquidityOhm ========= //

    // [X] it returns the sum of the polOhmAmounts

    function test_getProtocolOwnedLiquidityOhm() public {
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            POL_AMOUNT_1 + POL_AMOUNT_2
        );
    }

    // ========= getProtocolOwnedLiquidityReserves ========= //

    // [X] it returns the sources and balances

    function test_getProtocolOwnedLiquidityReserves() public {
        // Call function
        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        // Assert
        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], POL_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], POL_AMOUNT_2);
    }

    // ========= getSourceCount ========= //

    // [X] it returns the length of the sources array

    function test_getSourceCount() public {
        assertEq(submoduleLiquiditySupply.getSourceCount(), 2);
    }

    // ========= addLiquiditySupply ========= //

    // [X] if called by a non-parent
    //  [X] it reverts
    // [X] if the source is the zero address
    //  [X] it reverts
    // [X] if the source is duplicated
    //  [X] it reverts
    // [X] it adds the source and balance, and the total amount is accurate

    function test_addLiquiditySupply_whenCalledByNonParent() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Submodule.Submodule_OnlyParent.selector,
            CALLER_NOT_PARENT
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(CALLER_NOT_PARENT);
        submoduleLiquiditySupply.addLiquiditySupply(1, POL_LOCATION_3);
    }

    function test_addLiquiditySupply_whenSourceIsZeroAddress() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addLiquiditySupply(1, address(0));
    }

    function test_addLiquiditySupply_whenSourceIsDuplicated() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addLiquiditySupply(1, POL_LOCATION_1);
    }

    function test_addLiquiditySupply() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addLiquiditySupply(POL_AMOUNT_3, POL_LOCATION_3);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            POL_AMOUNT_1 + POL_AMOUNT_2 + POL_AMOUNT_3
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 3);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 3);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], POL_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], POL_AMOUNT_2);

        assertEq(reserves[2].source, POL_LOCATION_3);
        assertEq(reserves[2].tokens.length, 1);
        assertEq(reserves[2].tokens[0], address(ohm));
        assertEq(reserves[2].balances.length, 1);
        assertEq(reserves[2].balances[0], POL_AMOUNT_3);
    }

    // ========= removeLiquiditySupply ========= //

    // [X] if called by a non-parent
    //  [X] it reverts
    // [X] if the source is not in the sources array
    //  [X] it reverts
    // [X] if the last source is removed
    //  [X] it removes the source and balance, and the total amount is accurate
    // [X] it removes the source and balance, and the total amount is accurate

    function test_removeLiquiditySupply_whenCalledByNonParent() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Submodule.Submodule_OnlyParent.selector,
            CALLER_NOT_PARENT
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(CALLER_NOT_PARENT);
        submoduleLiquiditySupply.removeLiquiditySupply(POL_LOCATION_3);
    }

    function test_removeLiquiditySupply_whenSourceIsNotInSourcesArray() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeLiquiditySupply(POL_LOCATION_3);
    }

    function test_removeLiquiditySupply_whenLastSourceIsRemoved() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeLiquiditySupply(POL_LOCATION_2);

        vm.prank(address(spply));
        submoduleLiquiditySupply.removeLiquiditySupply(POL_LOCATION_1);

        // Assert
        assertEq(submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(), 0);
        assertEq(submoduleLiquiditySupply.getSourceCount(), 0);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 0);
    }

    function test_removeLiquiditySupply_indexOne() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeLiquiditySupply(POL_LOCATION_2);

        // Assert
        assertEq(submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(), POL_AMOUNT_1);
        assertEq(submoduleLiquiditySupply.getSourceCount(), 1);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], POL_AMOUNT_1);
    }

    function test_removeLiquiditySupply_indexZero() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeLiquiditySupply(POL_LOCATION_1);

        // Assert
        assertEq(submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(), POL_AMOUNT_2);
        assertEq(submoduleLiquiditySupply.getSourceCount(), 1);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, POL_LOCATION_2);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], POL_AMOUNT_2);
    }
}
