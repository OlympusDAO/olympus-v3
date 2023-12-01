// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {MockVaultManager} from "test/mocks/MockBLVaultManager.sol";

import {FullMath} from "libraries/FullMath.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

import "src/modules/SPPLY/OlympusSupply.sol";
import {BLVaultSupply} from "src/modules/SPPLY/submodules/BLVaultSupply.sol";

import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";

contract BLVaultSupplyTest is Test {
    using FullMath for uint256;
    using ModuleTestFixtureGenerator for OlympusSupply;

    MockERC20 internal ohm;
    MockGohm internal gOhm;

    Kernel internal kernel;

    OlympusSupply internal moduleSupply;

    BLVaultSupply internal submoduleBLVaultSupply;

    address[] internal vaultManagerAddresses;
    MockVaultManager[] internal vaultManagers;

    address internal writer;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    event VaultManagerAdded(address vaultManager_);
    event VaultManagerRemoved(address vaultManager_);

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

        // Deploy BLV submodule
        {
            // Create vault managers
            MockVaultManager vaultManager1 = new MockVaultManager(1000e9);
            vaultManagers.push(vaultManager1);

            // Add vault managers to list
            vaultManagerAddresses = new address[](1);
            vaultManagerAddresses[0] = address(vaultManager1);

            submoduleBLVaultSupply = new BLVaultSupply(moduleSupply, vaultManagerAddresses);
        }

        // Initialize
        {
            /// Initialize system and kernel
            kernel.executeAction(Actions.InstallModule, address(moduleSupply));
            kernel.executeAction(Actions.ActivatePolicy, address(writer));

            // Install submodules on SPPLY module
            vm.startPrank(writer);
            moduleSupply.installSubmodule(submoduleBLVaultSupply);
            vm.stopPrank();
        }
    }

    // Test checklist
    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode
    // [X] Constructor
    //  [X] Incorrect parent
    //  [X] Duplicate vault managers
    // [X] getCollateralizedOhm
    //  [X] no vault managers
    //  [X] one vault manager
    //  [X] multiple vault managers
    // [X] getProtocolOwnedBorrowableOhm
    // [X] getProtocolOwnedLiquidityOhm
    // [X] getProtocolOwnedTreasuryOhm
    // [X] addVaultManager
    //  [X] not parent
    //  [X] address(0)
    //  [X] already added
    //  [X] success
    // [X] removeVaultManager
    //  [X] not parent
    //  [X] address(0)
    //  [X] not added
    //  [X] success

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleBLVaultSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleBLVaultSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleBLVaultSupply.SUBKEYCODE()), "SPPLY.BLV");
    }

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new BLVaultSupply(Module(newLocations[0]), vaultManagerAddresses);
    }

    function test_submodule_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        OlympusPricev2 modulePrice = new OlympusPricev2(kernel, 18, 8 hours);

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BLVaultSupply(modulePrice, vaultManagerAddresses);
    }

    function test_submodule_addressZeroVaultManager() public {
        vaultManagerAddresses = new address[](1);
        vaultManagerAddresses[0] = address(0);

        // Expect an error to be emitted
        bytes memory err = abi.encodeWithSignature("BLVaultSupply_InvalidParams()");
        vm.expectRevert(err);

        // Create a new BLVaultSupply with duplicate vault managers
        new BLVaultSupply(moduleSupply, vaultManagerAddresses);
    }

    function test_submodule_duplicateVaultManagers() public {
        vaultManagerAddresses = new address[](2);
        vaultManagerAddresses[0] = address(vaultManagers[0]);
        vaultManagerAddresses[1] = address(vaultManagers[0]);

        // Expect an error to be emitted
        bytes memory err = abi.encodeWithSignature("BLVaultSupply_InvalidParams()");
        vm.expectRevert(err);

        // Create a new BLVaultSupply with duplicate vault managers
        new BLVaultSupply(moduleSupply, vaultManagerAddresses);
    }

    function test_submodule_emitsEvent() public {
        // Expect an event to be emitted
        vm.expectEmit(true, false, false, true);
        emit VaultManagerAdded(vaultManagerAddresses[0]);

        // New BLVaultSupply
        BLVaultSupply submoduleVaultSupply = new BLVaultSupply(moduleSupply, vaultManagerAddresses);

        assertEq(submoduleVaultSupply.getSourceCount(), 1);
    }

    // =========  getCollateralizedOhm ========= //

    function test_getCollateralizedOhm_noVaultManagers() public {
        // Create a new BLVaultSupply with no vault managers
        BLVaultSupply newSubmoduleBLVaultSupply = new BLVaultSupply(moduleSupply, new address[](0));

        assertEq(newSubmoduleBLVaultSupply.getCollateralizedOhm(), 0);
    }

    function test_getCollateralizedOhm_oneVaultManager_fuzz(uint256 poolOhmShare_) public {
        uint256 poolOhmShare = bound(poolOhmShare_, 0, 1000e9);
        vaultManagers[0].setPoolOhmShare(poolOhmShare);

        assertEq(submoduleBLVaultSupply.getCollateralizedOhm(), poolOhmShare);
    }

    function test_getCollateralizedOhm_multipleVaultManagers(
        uint256 poolOhmShareOne_,
        uint256 poolOhmShareTwo_
    ) public {
        uint256 poolOhmShareOne = bound(poolOhmShareOne_, 0, 1000e9);
        uint256 poolOhmShareTwo = bound(poolOhmShareTwo_, 0, 1000e9);

        // Create a second vault manager
        MockVaultManager vaultManager2 = new MockVaultManager(2000e9);
        vaultManagers.push(vaultManager2);
        vaultManagerAddresses.push(address(vaultManager2));

        vaultManagers[0].setPoolOhmShare(poolOhmShareOne);
        vaultManagers[1].setPoolOhmShare(poolOhmShareTwo);

        // Create a new BLVaultSupply with multiple vault managers
        BLVaultSupply newSubmoduleBLVaultSupply = new BLVaultSupply(
            moduleSupply,
            vaultManagerAddresses
        );

        assertEq(
            newSubmoduleBLVaultSupply.getCollateralizedOhm(),
            poolOhmShareOne + poolOhmShareTwo
        );
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    function test_getProtocolOwnedBorrowableOhm_fuzz(uint256 poolOhmShare_) public {
        uint256 poolOhmShare = bound(poolOhmShare_, 0, 1000e9);
        vaultManagers[0].setPoolOhmShare(poolOhmShare);

        assertEq(submoduleBLVaultSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    function test_getProtocolOwnedLiquidityOhm_fuzz(uint256 poolOhmShare_) public {
        uint256 poolOhmShare = bound(poolOhmShare_, 0, 1000e9);
        vaultManagers[0].setPoolOhmShare(poolOhmShare);

        assertEq(submoduleBLVaultSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm_fuzz(uint256 poolOhmShare_) public {
        uint256 poolOhmShare = bound(poolOhmShare_, 0, 1000e9);
        vaultManagers[0].setPoolOhmShare(poolOhmShare);

        assertEq(submoduleBLVaultSupply.getProtocolOwnedTreasuryOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    function test_getProtocolOwnedLiquidityReserves_noVaultManagers() public {
        // Create a new BLVaultSupply with no vault managers
        BLVaultSupply newSubmoduleBLVaultSupply = new BLVaultSupply(moduleSupply, new address[](0));

        SPPLYv1.Reserves[] memory reserves = newSubmoduleBLVaultSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 0);
    }

    function test_getProtocolOwnedLiquidityReserves_oneVaultManager_fuzz(
        uint256 poolOhmShare_
    ) public {
        uint256 poolOhmShare = bound(poolOhmShare_, 0, 1000e9);
        vaultManagers[0].setPoolOhmShare(poolOhmShare);

        SPPLYv1.Reserves[] memory reserves = submoduleBLVaultSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 1);
        assertEq(reserves[0].source, address(vaultManagers[0]));
        assertEq(reserves[0].tokens.length, 0);
        assertEq(reserves[0].balances.length, 0);
    }

    function test_getProtocolOwnedLiquidityReserves_multipleVaultManagers(
        uint256 poolOhmShareOne_,
        uint256 poolOhmShareTwo_
    ) public {
        uint256 poolOhmShareOne = bound(poolOhmShareOne_, 0, 1000e9);
        uint256 poolOhmShareTwo = bound(poolOhmShareTwo_, 0, 1000e9);

        // Create a second vault manager
        MockVaultManager vaultManager2 = new MockVaultManager(2000e9);
        vaultManagers.push(vaultManager2);
        vaultManagerAddresses.push(address(vaultManager2));

        vaultManagers[0].setPoolOhmShare(poolOhmShareOne);
        vaultManagers[1].setPoolOhmShare(poolOhmShareTwo);

        // Create a new BLVaultSupply with multiple vault managers
        BLVaultSupply newSubmoduleBLVaultSupply = new BLVaultSupply(
            moduleSupply,
            vaultManagerAddresses
        );

        SPPLYv1.Reserves[] memory reserves = newSubmoduleBLVaultSupply
            .getProtocolOwnedLiquidityReserves();
        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, address(vaultManagers[0]));
        assertEq(reserves[0].tokens.length, 0);
        assertEq(reserves[0].balances.length, 0);

        assertEq(reserves[1].source, address(vaultManagers[1]));
        assertEq(reserves[1].tokens.length, 0);
        assertEq(reserves[1].balances.length, 0);
    }

    // =========  addVaultManager ========= //

    function test_addVaultManager_notParent_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBLVaultSupply.addVaultManager(newLocations[0]);
    }

    function test_addVaultManager_notParent_writer_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleBLVaultSupply.addVaultManager(newLocations[0]);
        vm.stopPrank();
    }

    function test_addVaultManager_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSignature("BLVaultSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleBLVaultSupply.addVaultManager(address(0));
        vm.stopPrank();
    }

    function test_addVaultManager_alreadyAdded_reverts() public {
        bytes memory err = abi.encodeWithSignature("BLVaultSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleBLVaultSupply.addVaultManager(address(vaultManagers[0]));
        vm.stopPrank();
    }

    function test_addVaultManager() public {
        // Create a new vault manager
        MockVaultManager vaultManager2 = new MockVaultManager(2000e9);

        // Add vault manager to list
        vaultManagerAddresses.push(address(vaultManager2));

        // Expect an event
        vm.expectEmit(true, false, false, true);
        emit VaultManagerAdded(address(vaultManager2));

        // Add vault manager to BLVaultSupply
        vm.startPrank(address(moduleSupply));
        submoduleBLVaultSupply.addVaultManager(address(vaultManager2));
        vm.stopPrank();

        // Check that the vault manager was added
        assertEq(address(submoduleBLVaultSupply.vaultManagers(1)), address(vaultManager2));
        assertEq(submoduleBLVaultSupply.getCollateralizedOhm(), 1000e9 + 2000e9);
        assertEq(submoduleBLVaultSupply.getSourceCount(), 2);
    }

    // =========  removeVaultManager ========= //

    function test_removeVaultManager_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBLVaultSupply.removeVaultManager(vaultManagerAddresses[0]);
    }

    function test_removeVaultManager_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writer)
        );
        vm.expectRevert(err);

        vm.startPrank(writer);
        submoduleBLVaultSupply.removeVaultManager(vaultManagerAddresses[0]);
        vm.stopPrank();
    }

    function test_removeVaultManager_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSignature("BLVaultSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleBLVaultSupply.removeVaultManager(address(0));
        vm.stopPrank();
    }

    function test_removeVaultManager_notAdded_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        bytes memory err = abi.encodeWithSignature("BLVaultSupply_InvalidParams()");
        vm.expectRevert(err);

        vm.startPrank(address(moduleSupply));
        submoduleBLVaultSupply.removeVaultManager(newLocations[0]);
        vm.stopPrank();
    }

    function test_removeVaultManager() public {
        vm.expectEmit(true, false, false, true);
        emit VaultManagerRemoved(vaultManagerAddresses[0]);

        // Remove vault manager from BLVaultSupply
        vm.startPrank(address(moduleSupply));
        submoduleBLVaultSupply.removeVaultManager(vaultManagerAddresses[0]);
        vm.stopPrank();

        // Check that the vault manager was removed
        assertEq(submoduleBLVaultSupply.getCollateralizedOhm(), 0);
        assertEq(submoduleBLVaultSupply.getSourceCount(), 0);
    }
}
