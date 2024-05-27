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
    address internal constant POL_LOCATION_4 = address(0x4);

    uint256 internal constant OHM_AMOUNT_1 = 1e9;
    uint256 internal constant OHM_AMOUNT_2 = 2e9;
    uint256 internal constant GOHM_AMOUNT_1 = 3e18;
    uint256 internal constant GOHM_AMOUNT_2 = 4e18;

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
            polOhmAmounts[0] = OHM_AMOUNT_1;
            polOhmAmounts[1] = OHM_AMOUNT_2;

            address[] memory polOhmSources = new address[](2);
            polOhmSources[0] = POL_LOCATION_1;
            polOhmSources[1] = POL_LOCATION_2;

            uint256[] memory gOhmAmounts = new uint256[](1);
            gOhmAmounts[0] = GOHM_AMOUNT_1;

            address[] memory gOhmSources = new address[](1);
            gOhmSources[0] = POL_LOCATION_3;

            submoduleLiquiditySupply = new LiquiditySupply(
                spply,
                polOhmAmounts,
                polOhmSources,
                gOhmAmounts,
                gOhmSources
            );
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

    function _getGOhmInOhm(uint256 gOhmAmount) internal pure returns (uint256) {
        return (gOhmAmount * GOHM_INDEX) / 1e18;
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

    function test_constructor_whenOhmSourceIsZeroAddress() public {
        uint256[] memory ohmAmounts = new uint256[](2);
        ohmAmounts[0] = OHM_AMOUNT_1;
        ohmAmounts[1] = OHM_AMOUNT_2;

        address[] memory ohmSources = new address[](2);
        ohmSources[0] = POL_LOCATION_1;
        ohmSources[1] = address(0);

        uint256[] memory gOhmAmounts = new uint256[](0);

        address[] memory gOhmSources = new address[](0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        new LiquiditySupply(spply, ohmAmounts, ohmSources, gOhmAmounts, gOhmSources);
    }

    function test_constructor_whenOhmSourceIsDuplicated() public {
        uint256[] memory ohmAmounts = new uint256[](2);
        ohmAmounts[0] = OHM_AMOUNT_1;
        ohmAmounts[1] = OHM_AMOUNT_2;

        address[] memory ohmSources = new address[](2);
        ohmSources[0] = POL_LOCATION_1;
        ohmSources[1] = POL_LOCATION_1;

        uint256[] memory gOhmAmounts = new uint256[](0);

        address[] memory gOhmSources = new address[](0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        new LiquiditySupply(spply, ohmAmounts, ohmSources, gOhmAmounts, gOhmSources);
    }

    function test_constructor_whenGOhmSourceIsZeroAddress() public {
        uint256[] memory ohmAmounts = new uint256[](0);

        address[] memory ohmSources = new address[](0);

        uint256[] memory gOhmAmounts = new uint256[](2);
        gOhmAmounts[0] = OHM_AMOUNT_1;
        gOhmAmounts[1] = OHM_AMOUNT_2;

        address[] memory gOhmSources = new address[](2);
        gOhmSources[0] = POL_LOCATION_1;
        gOhmSources[1] = address(0);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        new LiquiditySupply(spply, ohmAmounts, ohmSources, gOhmAmounts, gOhmSources);
    }

    function test_constructor_whenGOhmSourceIsDuplicated() public {
        uint256[] memory ohmAmounts = new uint256[](0);

        address[] memory ohmSources = new address[](0);

        uint256[] memory gOhmAmounts = new uint256[](2);
        gOhmAmounts[0] = OHM_AMOUNT_1;
        gOhmAmounts[1] = OHM_AMOUNT_2;

        address[] memory gOhmSources = new address[](2);
        gOhmSources[0] = POL_LOCATION_1;
        gOhmSources[1] = POL_LOCATION_1;

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        new LiquiditySupply(spply, ohmAmounts, ohmSources, gOhmAmounts, gOhmSources);
    }

    function test_constructor_ohm() public {
        uint256[] memory ohmAmounts = new uint256[](2);
        ohmAmounts[0] = OHM_AMOUNT_1;
        ohmAmounts[1] = OHM_AMOUNT_2;

        address[] memory ohmSources = new address[](2);
        ohmSources[0] = POL_LOCATION_1;
        ohmSources[1] = POL_LOCATION_2;

        uint256[] memory gOhmAmounts = new uint256[](0);

        address[] memory gOhmSources = new address[](0);

        // Call function
        LiquiditySupply liquiditySupply = new LiquiditySupply(
            spply,
            ohmAmounts,
            ohmSources,
            gOhmAmounts,
            gOhmSources
        );

        // Assert
        assertEq(liquiditySupply.getProtocolOwnedLiquidityOhm(), OHM_AMOUNT_1 + OHM_AMOUNT_2);
        assertEq(liquiditySupply.getSourceCount(), 2);
    }

    function test_constructor_gOhm() public {
        uint256[] memory ohmAmounts = new uint256[](0);

        address[] memory ohmSources = new address[](0);

        uint256[] memory gOhmAmounts = new uint256[](2);
        gOhmAmounts[0] = OHM_AMOUNT_1;
        gOhmAmounts[1] = OHM_AMOUNT_2;

        address[] memory gOhmSources = new address[](2);
        gOhmSources[0] = POL_LOCATION_1;
        gOhmSources[1] = POL_LOCATION_2;

        // Call function
        LiquiditySupply liquiditySupply = new LiquiditySupply(
            spply,
            ohmAmounts,
            ohmSources,
            gOhmAmounts,
            gOhmSources
        );

        // Assert
        assertEq(
            liquiditySupply.getProtocolOwnedLiquidityOhm(),
            _getGOhmInOhm(OHM_AMOUNT_1 + OHM_AMOUNT_2)
        );
        assertEq(liquiditySupply.getSourceCount(), 2);
    }

    function test_constructor_ohmAndGOhm() public {
        uint256[] memory ohmAmounts = new uint256[](1);
        ohmAmounts[0] = OHM_AMOUNT_1;

        address[] memory ohmSources = new address[](1);
        ohmSources[0] = POL_LOCATION_1;

        uint256[] memory gOhmAmounts = new uint256[](2);
        gOhmAmounts[0] = GOHM_AMOUNT_1;
        gOhmAmounts[1] = GOHM_AMOUNT_2;

        address[] memory gOhmSources = new address[](2);
        gOhmSources[0] = POL_LOCATION_3;
        gOhmSources[1] = POL_LOCATION_4;

        // Call function
        LiquiditySupply liquiditySupply = new LiquiditySupply(
            spply,
            ohmAmounts,
            ohmSources,
            gOhmAmounts,
            gOhmSources
        );

        // Assert
        assertEq(
            liquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + _getGOhmInOhm(GOHM_AMOUNT_1 + GOHM_AMOUNT_2)
        );
        assertEq(liquiditySupply.getSourceCount(), 3);
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
            OHM_AMOUNT_1 + OHM_AMOUNT_2 + _getGOhmInOhm(GOHM_AMOUNT_1)
        );
    }

    // ========= getProtocolOwnedLiquidityReserves ========= //

    // [X] it returns the sources and balances

    function test_getProtocolOwnedLiquidityReserves() public {
        // Call function
        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        // Assert
        assertEq(reserves.length, 3);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], OHM_AMOUNT_2);

        assertEq(reserves[2].source, POL_LOCATION_3);
        assertEq(reserves[2].tokens.length, 1);
        assertEq(reserves[2].tokens[0], address(ohm));
        assertEq(reserves[2].balances.length, 1);
        assertEq(reserves[2].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1));
    }

    // ========= getSourceCount ========= //

    // [X] it returns the length of the sources array

    function test_getSourceCount() public {
        assertEq(submoduleLiquiditySupply.getSourceCount(), 3);
    }

    // ========= addOhmLiquidity ========= //

    // [X] if called by a non-parent
    //  [X] it reverts
    // [X] if the source is the zero address
    //  [X] it reverts
    // [X] if the source is duplicated
    //  [X] it reverts
    // [X] it adds the source and balance, and the total amount is accurate

    function test_addOhmLiquidity_whenCalledByNonParent() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Submodule.Submodule_OnlyParent.selector,
            CALLER_NOT_PARENT
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(CALLER_NOT_PARENT);
        submoduleLiquiditySupply.addOhmLiquidity(1, POL_LOCATION_3);
    }

    function test_addOhmLiquidity_whenSourceIsZeroAddress() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addOhmLiquidity(1, address(0));
    }

    function test_addOhmLiquidity_whenSourceIsDuplicated() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addOhmLiquidity(1, POL_LOCATION_1);
    }

    function test_addOhmLiquidity() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addOhmLiquidity(3e9, POL_LOCATION_3);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + OHM_AMOUNT_2 + 3e9 + _getGOhmInOhm(GOHM_AMOUNT_1)
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 4);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 4);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], OHM_AMOUNT_2);

        assertEq(reserves[2].source, POL_LOCATION_3);
        assertEq(reserves[2].tokens.length, 1);
        assertEq(reserves[2].tokens[0], address(ohm));
        assertEq(reserves[2].balances.length, 1);
        assertEq(reserves[2].balances[0], 3e9);

        assertEq(reserves[3].source, POL_LOCATION_3);
        assertEq(reserves[3].tokens.length, 1);
        assertEq(reserves[3].tokens[0], address(ohm));
        assertEq(reserves[3].balances.length, 1);
        assertEq(reserves[3].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1));
    }

    // ========= addGOhmLiquidity ========= //

    // [X] if called by a non-parent
    //  [X] it reverts
    // [X] if the source is the zero address
    //  [X] it reverts
    // [X] if the source is duplicated
    //  [X] it reverts
    // [X] it adds the source and balance, and the total amount is accurate

    function test_addGOhmLiquidity_whenCalledByNonParent() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Submodule.Submodule_OnlyParent.selector,
            CALLER_NOT_PARENT
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(CALLER_NOT_PARENT);
        submoduleLiquiditySupply.addGOhmLiquidity(1, POL_LOCATION_3);
    }

    function test_addGOhmLiquidity_whenSourceIsZeroAddress() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addGOhmLiquidity(1, address(0));
    }

    function test_addGOhmLiquidity_whenSourceIsDuplicated() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addGOhmLiquidity(1, POL_LOCATION_3);
    }

    function test_addGOhmLiquidity() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.addGOhmLiquidity(GOHM_AMOUNT_2, POL_LOCATION_4);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + OHM_AMOUNT_2 + _getGOhmInOhm(GOHM_AMOUNT_1 + GOHM_AMOUNT_2),
            "POL OHM"
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 4, "source count");

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 4, "reserves length");

        assertEq(reserves[0].source, POL_LOCATION_1, "source 1");
        assertEq(reserves[0].tokens.length, 1, "tokens length 1");
        assertEq(reserves[0].tokens[0], address(ohm), "tokens 1");
        assertEq(reserves[0].balances.length, 1, "balances length 1");
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1, "balances 1");

        assertEq(reserves[1].source, POL_LOCATION_2, "source 2");
        assertEq(reserves[1].tokens.length, 1, "tokens length 2");
        assertEq(reserves[1].tokens[0], address(ohm), "tokens 2");
        assertEq(reserves[1].balances.length, 1, "balances length 2");
        assertEq(reserves[1].balances[0], OHM_AMOUNT_2, "balances 2");

        assertEq(reserves[2].source, POL_LOCATION_3, "source 3");
        assertEq(reserves[2].tokens.length, 1, "tokens length 3");
        assertEq(reserves[2].tokens[0], address(ohm), "tokens 3");
        assertEq(reserves[2].balances.length, 1, "balances length 3");
        assertEq(reserves[2].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1), "balances 3");

        assertEq(reserves[3].source, POL_LOCATION_4, "source 4");
        assertEq(reserves[3].tokens.length, 1, "tokens length 4");
        assertEq(reserves[3].tokens[0], address(ohm), "tokens 4");
        assertEq(reserves[3].balances.length, 1, "balances length 4");
        assertEq(reserves[3].balances[0], _getGOhmInOhm(GOHM_AMOUNT_2), "balances 4");
    }

    // ========= removeOhmLiquidity ========= //

    // [X] if called by a non-parent
    //  [X] it reverts
    // [X] if the source is not in the sources array
    //  [X] it reverts
    // [X] if the last source is removed
    //  [X] it removes the source and balance, and the total amount is accurate
    // [X] it removes the source and balance, and the total amount is accurate

    function test_removeOhmLiquidity_whenCalledByNonParent() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Submodule.Submodule_OnlyParent.selector,
            CALLER_NOT_PARENT
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(CALLER_NOT_PARENT);
        submoduleLiquiditySupply.removeOhmLiquidity(POL_LOCATION_3);
    }

    function test_removeOhmLiquidity_whenSourceIsNotInSourcesArray() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeOhmLiquidity(POL_LOCATION_3);
    }

    function test_removeOhmLiquidity_whenLastSourceIsRemoved() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeOhmLiquidity(POL_LOCATION_2);

        vm.prank(address(spply));
        submoduleLiquiditySupply.removeOhmLiquidity(POL_LOCATION_1);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            _getGOhmInOhm(GOHM_AMOUNT_1)
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 1);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, POL_LOCATION_3);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1));
    }

    function test_removeOhmLiquidity_indexOne() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeOhmLiquidity(POL_LOCATION_2);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + _getGOhmInOhm(GOHM_AMOUNT_1)
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 2);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_3);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1));
    }

    function test_removeOhmLiquidity_indexZero() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeOhmLiquidity(POL_LOCATION_1);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_2 + _getGOhmInOhm(GOHM_AMOUNT_1)
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 2);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, POL_LOCATION_2);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_2);

        assertEq(reserves[1].source, POL_LOCATION_3);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1));
    }

    // ========= removeGOhmLiquidity ========= //

    // [X] if called by a non-parent
    //  [X] it reverts
    // [X] if the source is not in the sources array
    //  [X] it reverts
    // [X] if the last source is removed
    //  [X] it removes the source and balance, and the total amount is accurate
    // [X] it removes the source and balance, and the total amount is accurate

    function test_removeGOhmLiquidity_whenCalledByNonParent() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            Submodule.Submodule_OnlyParent.selector,
            CALLER_NOT_PARENT
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(CALLER_NOT_PARENT);
        submoduleLiquiditySupply.removeGOhmLiquidity(POL_LOCATION_1);
    }

    function test_removeGOhmLiquidity_whenSourceIsNotInSourcesArray() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            LiquiditySupply.LiquiditySupply_InvalidParams.selector
        );
        vm.expectRevert(err);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeGOhmLiquidity(POL_LOCATION_1);
    }

    function test_removeGOhmLiquidity_whenLastSourceIsRemoved() public {
        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeGOhmLiquidity(POL_LOCATION_3);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + OHM_AMOUNT_2
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 2);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], OHM_AMOUNT_2);
    }

    function test_removeGOhmLiquidity_indexZero() public {
        vm.prank(address(spply));
        submoduleLiquiditySupply.addGOhmLiquidity(GOHM_AMOUNT_2, POL_LOCATION_4);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeGOhmLiquidity(POL_LOCATION_3);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + OHM_AMOUNT_2 + _getGOhmInOhm(GOHM_AMOUNT_2)
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 3);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 3);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], OHM_AMOUNT_2);

        assertEq(reserves[2].source, POL_LOCATION_4);
        assertEq(reserves[2].tokens.length, 1);
        assertEq(reserves[2].tokens[0], address(ohm));
        assertEq(reserves[2].balances.length, 1);
        assertEq(reserves[2].balances[0], _getGOhmInOhm(GOHM_AMOUNT_2));
    }

    function test_removeGOhmLiquidity_indexOne() public {
        vm.prank(address(spply));
        submoduleLiquiditySupply.addGOhmLiquidity(GOHM_AMOUNT_2, POL_LOCATION_4);

        // Call function
        vm.prank(address(spply));
        submoduleLiquiditySupply.removeGOhmLiquidity(POL_LOCATION_4);

        // Assert
        assertEq(
            submoduleLiquiditySupply.getProtocolOwnedLiquidityOhm(),
            OHM_AMOUNT_1 + OHM_AMOUNT_2 + _getGOhmInOhm(GOHM_AMOUNT_1)
        );
        assertEq(submoduleLiquiditySupply.getSourceCount(), 3);

        SPPLYv1.Reserves[] memory reserves = submoduleLiquiditySupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 3);

        assertEq(reserves[0].source, POL_LOCATION_1);
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], OHM_AMOUNT_1);

        assertEq(reserves[1].source, POL_LOCATION_2);
        assertEq(reserves[1].tokens.length, 1);
        assertEq(reserves[1].tokens[0], address(ohm));
        assertEq(reserves[1].balances.length, 1);
        assertEq(reserves[1].balances[0], OHM_AMOUNT_2);

        assertEq(reserves[2].source, POL_LOCATION_3);
        assertEq(reserves[2].tokens.length, 1);
        assertEq(reserves[2].tokens[0], address(ohm));
        assertEq(reserves[2].balances.length, 1);
        assertEq(reserves[2].balances[0], _getGOhmInOhm(GOHM_AMOUNT_1));
    }
}
