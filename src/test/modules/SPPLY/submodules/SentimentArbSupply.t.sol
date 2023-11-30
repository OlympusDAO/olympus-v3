// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";

import {FullMath} from "libraries/FullMath.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {SentimentArbSupply} from "src/modules/SPPLY/submodules/SentimentArbSupply.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract SentimentArbSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    SentimentArbSupply internal submoduleSentimentArbSupply;

    address internal writer;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    uint256 internal constant COLLATERALIZED_OHM = 1e9;
    uint256 internal constant PROTOCOL_OWNED_BORROWABLE_OHM = 2e9;
    uint256 internal constant PROTOCOL_OWNED_LIQUIDITY_OHM = 3e9;
    uint256 internal constant PROTOCOL_OWNED_TREASURY_OHM = 0;

    event CollateralizedValueUpdated(uint256 value);
    event ProtocolOwnedBorrowableValueUpdated(uint256 value);
    event ProtocolOwnedLiquidityValueUpdated(uint256 value);
    event SourceValueUpdated(address value);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohm = new MockERC20("OHM", "OHM", 9);
            gOhm = new MockGohm(GOHM_INDEX);
        }

        // Locations
        {
            userFactory = new UserFactory();
        }

        // Bophades
        {
            // Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            // Deploy SPPLY module
            address[2] memory tokens = [address(ohm), address(gOhm)];
            moduleSupply = new OlympusSupply(kernel, tokens, INITIAL_CROSS_CHAIN_SUPPLY);

            // Deploy mock module writer
            writer = moduleSupply.generateGodmodeFixture(type(OlympusSupply).name);
        }

        // Deploy Silo submodule
        {
            submoduleSentimentArbSupply = new SentimentArbSupply(
                moduleSupply,
                COLLATERALIZED_OHM,
                PROTOCOL_OWNED_BORROWABLE_OHM,
                PROTOCOL_OWNED_LIQUIDITY_OHM,
                PROTOCOL_OWNED_TREASURY_OHM
            );
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleSentimentArbSupply);
            vm.stopPrank();
        }
    }

    // Test checklist
    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode
    // [X] Constructor
    //  [X] Parent mot module
    //  [X] Parent not SPPLY
    //  [X] success
    // [X] getCollateralizedOhm
    // [X] getProtocolOwnedBorrowableOhm
    // [X] getProtocolOwnedLiquidityOhm
    // [X] getProtocolOwnedTreasuryOhm
    // [X] setCollateralizedOhm
    //  [X] not parent
    //  [X] success
    // [X] setProtocolOwnedBorrowableOhm
    //  [X] not parent
    //  [X] success
    // [X] setProtocolOwnedLiquidityOhm
    //  [X] not parent
    //  [X] success

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleSentimentArbSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleSentimentArbSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleSentimentArbSupply.SUBKEYCODE()), "SPPLY.SENTIMENTARB");
    }

    // =========  Constructor ========= //

    function test_constructor_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new SentimentArbSupply(
            Module(newLocations[0]),
            COLLATERALIZED_OHM,
            PROTOCOL_OWNED_BORROWABLE_OHM,
            PROTOCOL_OWNED_LIQUIDITY_OHM,
            PROTOCOL_OWNED_TREASURY_OHM
        );
    }

    function test_constructor_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new SentimentArbSupply(
            modulePrice,
            COLLATERALIZED_OHM,
            PROTOCOL_OWNED_BORROWABLE_OHM,
            PROTOCOL_OWNED_LIQUIDITY_OHM,
            PROTOCOL_OWNED_TREASURY_OHM
        );
    }

    function test_constructor() public {
        // Expect events to be emitted
        vm.expectEmit(true, false, false, true);
        emit CollateralizedValueUpdated(COLLATERALIZED_OHM);
        emit ProtocolOwnedBorrowableValueUpdated(PROTOCOL_OWNED_BORROWABLE_OHM);
        emit ProtocolOwnedLiquidityValueUpdated(PROTOCOL_OWNED_LIQUIDITY_OHM);

        // Create a new submodule
        vm.startPrank(writer);
        submoduleSentimentArbSupply = new SentimentArbSupply(
            moduleSupply,
            COLLATERALIZED_OHM,
            PROTOCOL_OWNED_BORROWABLE_OHM,
            PROTOCOL_OWNED_LIQUIDITY_OHM,
            PROTOCOL_OWNED_TREASURY_OHM
        );
        vm.stopPrank();

        assertEq(submoduleSentimentArbSupply.getSourceCount(), 1);
    }

    // =========  getCollateralizedOhm ========= //

    function test_getCollateralizedOhm() public {
        assertEq(submoduleSentimentArbSupply.getCollateralizedOhm(), COLLATERALIZED_OHM);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    function test_getProtocolOwnedBorrowableOhm() public {
        assertEq(
            submoduleSentimentArbSupply.getProtocolOwnedBorrowableOhm(),
            PROTOCOL_OWNED_BORROWABLE_OHM
        );
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    function test_getProtocolOwnedLiquidityOhm() public {
        assertEq(
            submoduleSentimentArbSupply.getProtocolOwnedLiquidityOhm(),
            PROTOCOL_OWNED_LIQUIDITY_OHM
        );
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm() public {
        assertEq(
            submoduleSentimentArbSupply.getProtocolOwnedTreasuryOhm(),
            PROTOCOL_OWNED_TREASURY_OHM
        );
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    function test_getProtocolOwnedLiquidityReserves() public {
        SPPLYv1.Reserves[] memory reserves = submoduleSentimentArbSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);
        assertEq(reserves[0].source, address(0));
        assertEq(reserves[0].tokens.length, 1);
        assertEq(reserves[0].tokens[0], address(ohm));
        assertEq(reserves[0].balances.length, 1);
        assertEq(reserves[0].balances[0], PROTOCOL_OWNED_LIQUIDITY_OHM);
    }

    // =========  setCollateralizedOhm ========= //

    function test_setCollateralizedOhm_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleSentimentArbSupply.setCollateralizedOhm(10e9);
    }

    function test_setCollateralizedOhm_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleSentimentArbSupply.setCollateralizedOhm(10e9);
        vm.stopPrank();
    }

    function test_setCollateralizedOhm() public {
        // Expect event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CollateralizedValueUpdated(10e9);

        // Set the value
        vm.startPrank(address(moduleSupply));
        submoduleSentimentArbSupply.setCollateralizedOhm(10e9);
        vm.stopPrank();

        // Check the value
        assertEq(submoduleSentimentArbSupply.getCollateralizedOhm(), 10e9);
    }

    // =========  setProtocolOwnedBorrowableOhm ========= //

    function test_setProtocolOwnedBorrowableOhm_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleSentimentArbSupply.setProtocolOwnedBorrowableOhm(10e9);
    }

    function test_setProtocolOwnedBorrowableOhm_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleSentimentArbSupply.setProtocolOwnedBorrowableOhm(10e9);
        vm.stopPrank();
    }

    function test_setProtocolOwnedBorrowableOhm() public {
        // Expect event to be emitted
        vm.expectEmit(true, false, false, true);
        emit ProtocolOwnedBorrowableValueUpdated(10e9);

        // Set the value
        vm.startPrank(address(moduleSupply));
        submoduleSentimentArbSupply.setProtocolOwnedBorrowableOhm(10e9);
        vm.stopPrank();

        // Check the value
        assertEq(submoduleSentimentArbSupply.getProtocolOwnedBorrowableOhm(), 10e9);
    }

    // =========  setProtocolOwnedLiquidityOhm ========= //

    function test_setProtocolOwnedLiquidityOhm_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleSentimentArbSupply.setProtocolOwnedLiquidityOhm(10e9);
    }

    function test_setProtocolOwnedLiquidityOhm_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleSentimentArbSupply.setProtocolOwnedLiquidityOhm(10e9);
        vm.stopPrank();
    }

    function test_setProtocolOwnedLiquidityOhm() public {
        // Expect event to be emitted
        vm.expectEmit(true, false, false, true);
        emit ProtocolOwnedLiquidityValueUpdated(10e9);

        // Set the value
        vm.startPrank(address(moduleSupply));
        submoduleSentimentArbSupply.setProtocolOwnedLiquidityOhm(10e9);
        vm.stopPrank();

        // Check the value
        assertEq(submoduleSentimentArbSupply.getProtocolOwnedLiquidityOhm(), 10e9);
    }

    // =========  setSource ========= //

    function test_setSource_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleSentimentArbSupply.setSource(address(0xe));
    }

    function test_setSource_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleSentimentArbSupply.setSource(address(0xe));
        vm.stopPrank();
    }

    function test_setSource() public {
        // Expect event to be emitted
        vm.expectEmit(true, false, false, true);
        emit SourceValueUpdated(address(0xe));

        // Set the value
        vm.startPrank(address(moduleSupply));
        submoduleSentimentArbSupply.setSource(address(0xe));
        vm.stopPrank();

        // Check the value
        SPPLYv1.Reserves[] memory reserves = submoduleSentimentArbSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves[0].source, address(0xe));
    }
}
