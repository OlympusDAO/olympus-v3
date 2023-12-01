// SPDX-License-Identifier: Unlicense
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
import {MigrationOffsetSupply} from "src/modules/SPPLY/submodules/MigrationOffsetSupply.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract MigrationOffsetSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    MigrationOffsetSupply internal submoduleMigrationOffsetSupply;

    address internal writer;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    event GOhmOffsetUpdated(uint256 gOhmOffset_);

    uint256 internal constant GOHM_OFFSET = 2013e18;
    address internal constant MIGRATION_CONTRACT = 0x184f3FAd8618a6F458C16bae63F70C426fE784B3;

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

        // Deploy submodule
        {
            submoduleMigrationOffsetSupply = new MigrationOffsetSupply(
                moduleSupply,
                MIGRATION_CONTRACT,
                GOHM_OFFSET
            );
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleMigrationOffsetSupply);
            vm.stopPrank();
        }
    }

    // Test checklist
    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode
    // [X] Constructor
    //  [X] Incorrect parent
    //  [X] Success
    // [X] getProtocolOwnedTreasuryOhm
    // [X] getProtocolOwnedBorrowableOhm
    // [X] getProtocolOwnedLiquidityOhm
    // [X] setGOhmOffset
    //  [X] not parent
    //  [X] success

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleMigrationOffsetSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleMigrationOffsetSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleMigrationOffsetSupply.SUBKEYCODE()), "SPPLY.MIGOFFSET");
    }

    // =========  Constructor ========= //

    function test_constructor_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new MigrationOffsetSupply(Module(newLocations[0]), MIGRATION_CONTRACT, 0);
    }

    function test_constructor_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new MigrationOffsetSupply(modulePrice, MIGRATION_CONTRACT, 0);
    }

    function test_constructor_emitsEvent() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit GOhmOffsetUpdated(2e18);

        // New MigrationOffsetSupply
        submoduleMigrationOffsetSupply = new MigrationOffsetSupply(
            moduleSupply,
            MIGRATION_CONTRACT,
            2e18
        );

        assertEq(submoduleMigrationOffsetSupply.gOhmOffset(), 2e18);
    }

    // =========  getProtocolOwnedTreasuryOhm ========= //

    function test_getProtocolOwnedTreasuryOhm() public {
        uint256 expectedOffset = GOHM_OFFSET.mulDiv(GOHM_INDEX, 1e18); // Scale: 9 decimals

        assertEq(submoduleMigrationOffsetSupply.getProtocolOwnedTreasuryOhm(), expectedOffset);
    }

    function test_getProtocolOwnedTreasuryOhm_fuzz(uint256 gOhmOffset_) public {
        uint256 gOhmOffset = bound(gOhmOffset_, 1e18, 20e18);
        vm.startPrank(address(moduleSupply));
        submoduleMigrationOffsetSupply.setGOhmOffset(gOhmOffset);
        vm.stopPrank();

        uint256 expectedOffset = gOhmOffset.mulDiv(GOHM_INDEX, 1e18); // Scale: 9 decimals

        assertEq(submoduleMigrationOffsetSupply.getProtocolOwnedTreasuryOhm(), expectedOffset);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    function test_getProtocolOwnedBorrowableOhm() public {
        assertEq(submoduleMigrationOffsetSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    function test_getProtocolOwnedLiquidityOhm() public {
        assertEq(submoduleMigrationOffsetSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    // =========  setGOhmOffset ========= //

    function test_setGOhmOffset_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleMigrationOffsetSupply.setGOhmOffset(3e18);
    }

    function test_setGOhmOffset_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleMigrationOffsetSupply.setGOhmOffset(3e18);
        vm.stopPrank();
    }

    function test_setGOhmOffset() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit GOhmOffsetUpdated(3e18);

        // Set the value
        vm.startPrank(address(moduleSupply));
        submoduleMigrationOffsetSupply.setGOhmOffset(3e18);
        vm.stopPrank();

        assertEq(submoduleMigrationOffsetSupply.gOhmOffset(), 3e18);
    }
}
