// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockOhm} from "src/test/mocks/MockOhm.sol";

import {OlympusLender} from "modules/LENDR/OlympusLender.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {ROLESv1, OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {BaseExternalAMO} from "policies/lending/abstracts/BaseExternalAMO.sol";
import "src/Kernel.sol";

// This is a test just for the BaseExternalAMO rather than an implementation contract because
// we won't have a needed implementation before audit. So I'll write a mock implementation in
// this file but it is not fully representative of any actual implementation.

// MockAMO is a mock implementation of BaseExternalAMO
contract MockAMO is BaseExternalAMO {
    constructor(Kernel kernel_) BaseExternalAMO(kernel_) {}

    function deposit(uint256 amount_) external override onlyRole("externalamo_admin") {
        _borrow(amount_);
    }

    function withdraw(uint256 amount_) external override onlyRole("externalamo_admin") {
        _repay(amount_);
    }

    // Unimplemented for now
    function update() external override {}

    // Unimplemented for now
    function harvestYield() external override {}

    function getTargetDeployedSupply() external view override returns (uint256) {
        return 100e9;
    }

    function getBorrowedSupply() external view override returns (uint256) {
        return deployedOHM;
    }
}

contract ExternalAMOTest is Test {
    using ModuleTestFixtureGenerator for OlympusLender;

    address public godmode;

    MockOhm internal ohm;

    Kernel internal kernel;
    OlympusLender internal lender;
    OlympusMinter internal minter;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    MockAMO internal amo;

    function setUp() public {
        // Deploy mock OHM
        {
            ohm = new MockOhm("Olympus", "OHM", 9);
        }

        // Deploy Kernel, modules, and policies
        {
            kernel = new Kernel();

            lender = new OlympusLender(kernel);
            minter = new OlympusMinter(kernel, address(ohm));
            roles = new OlympusRoles(kernel);

            rolesAdmin = new RolesAdmin(kernel);
            amo = new MockAMO(kernel);
        }

        // Generate fixture
        {
            godmode = lender.generateGodmodeFixture(type(OlympusLender).name);
        }

        // Install modules and policies on Kernel
        {
            kernel.executeAction(Actions.InstallModule, address(lender));
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(roles));

            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(amo));
            kernel.executeAction(Actions.ActivatePolicy, godmode);
        }

        // Set roles
        {
            rolesAdmin.grantRole("externalamo_admin", address(this));
        }

        // Approve AMO as market
        {
            vm.startPrank(godmode);
            lender.approveMarket(address(amo));
            lender.setGlobalLimit(100e9);
            lender.setMarketLimit(address(amo), 100e9);
            vm.stopPrank();
        }
    }

    /// [X]  deposit
    ///     [X]  Can only be accessed by externalamo_admin
    ///     [X]  Increases deployedOHM value
    ///     [X]  Mints OHM into AMO

    function testCorrectness_depositCanOnlyBeAccessedByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("externalamo_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        amo.deposit(1e9);
    }

    function testCorrectness_depositIncreasesDeployedOHM(uint256 amount_) public {
        vm.assume(amount_ > 0 && amount_ <= 100e9);

        // Verify initial state
        assertEq(amo.deployedOHM(), 0);

        // Deposit
        amo.deposit(amount_);

        // Verify final state
        assertEq(amo.deployedOHM(), amount_);
    }

    function testCorrectness_depositMintsOHMIntoAMO(uint256 amount_) public {
        vm.assume(amount_ > 0 && amount_ <= 100e9);

        // Verify initial state
        assertEq(ohm.balanceOf(address(amo)), 0);

        // Deposit
        amo.deposit(amount_);

        // Verify final state
        assertEq(ohm.balanceOf(address(amo)), amount_);
    }

    /// [X]  withdraw
    ///     [X]  Can only be accessed by externalamo_admin
    ///     [X]  Decreases deployedOHM value
    ///     [X]  Burns OHM from AMO

    function _withdrawSetup() internal {
        // Deposit
        amo.deposit(100e9);
    }

    function testCorrectness_withdrawCanOnlyBeAccessedByAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("externalamo_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        amo.withdraw(1e9);
    }

    function testCorrectness_withdrawDecreasesDeployedOHM(uint256 amount_) public {
        vm.assume(amount_ > 0 && amount_ <= 100e9);

        // Setup
        _withdrawSetup();

        // Verify initial state
        assertEq(amo.deployedOHM(), 100e9);

        // Withdraw
        amo.withdraw(amount_);

        // Verify final state
        assertEq(amo.deployedOHM(), 100e9 - amount_);
    }

    function testCorrectness_withdrawBurnsOHMFromAMO(uint256 amount_) public {
        vm.assume(amount_ > 0 && amount_ <= 100e9);

        // Setup
        _withdrawSetup();

        // Verify initial state
        assertEq(ohm.balanceOf(address(amo)), 100e9);

        // Withdraw
        amo.withdraw(amount_);

        // Verify final state
        assertEq(ohm.balanceOf(address(amo)), 100e9 - amount_);
    }

    // ========= VIEW FUNCTIONS ========= //

    /// [X]  deployedOHM
    /// [X]  getTargetDeployedSupply
    /// [X]  getBorrowedSupply

    function testCorrectness_deployedOHM() public {
        // Verify initial state
        assertEq(amo.deployedOHM(), 0);

        // Deposit
        amo.deposit(100e9);

        // Verify final state
        assertEq(amo.deployedOHM(), 100e9);
    }

    function testCorrectness_getTargetDeployedSupply() public {
        assertEq(amo.getTargetDeployedSupply(), 100e9);
    }

    function testCorrectness_getBorrowedSupply() public {
        // Verify initial state
        assertEq(amo.getBorrowedSupply(), 0);

        // Deposit
        amo.deposit(100e9);

        // Verify final state
        assertEq(amo.getBorrowedSupply(), 100e9);
    }
}
