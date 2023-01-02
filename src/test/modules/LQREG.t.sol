// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {MockVault} from "test/mocks/MockVault.sol";
import {MockBalancerPool} from "test/mocks/MockBalancerPool.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {StethLiquidityAMO} from "policies/lending/StethLiquidityAMO.sol";
import "modules/LQREG/OlympusLiquidityRegistry.sol";
import "src/Kernel.sol";

contract LQREGTest is Test {
    using ModuleTestFixtureGenerator for OlympusLiquidityRegistry;

    UserFactory public userCreator;
    address internal alice;
    address public godmode;

    MockERC20 internal ohm;
    MockERC20 internal steth;

    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal ethUsdPriceFeed;
    MockPriceFeed internal stethUsdPriceFeed;

    MockVault internal vault1;
    MockVault internal vault2;
    MockBalancerPool internal liquidityPool1;
    MockBalancerPool internal liquidityPool2;

    Kernel internal kernel;
    OlympusMinter internal minter;
    OlympusRoles internal roles;
    OlympusLiquidityRegistry internal lqreg;

    RolesAdmin internal rolesAdmin;
    StethLiquidityAMO internal liquidityAMO1;
    StethLiquidityAMO internal liquidityAMO2;

    function setUp() public {
        userCreator = new UserFactory();

        // Initialize users
        {
            address[] memory users = userCreator.create(1);
            alice = users[0];
        }

        // Deploy mock tokens
        {
            ohm = new MockERC20("Olympus", "OHM", 9);
            steth = new MockERC20("Staked ETH", "stETH", 18);
        }

        // Deploy mock price feeds
        {
            ohmEthPriceFeed = new MockPriceFeed();
            ethUsdPriceFeed = new MockPriceFeed();
            stethUsdPriceFeed = new MockPriceFeed();

            ohmEthPriceFeed.setDecimals(18);
            ethUsdPriceFeed.setDecimals(18);
            stethUsdPriceFeed.setDecimals(18);

            ohmEthPriceFeed.setLatestAnswer(1e16); // 0.01 ETH
            ethUsdPriceFeed.setLatestAnswer(1e21); // 1000 USD
            stethUsdPriceFeed.setLatestAnswer(1e21); // 1000 USD
        }

        // Deploy mock Balancer contracts
        {
            liquidityPool1 = new MockBalancerPool();
            liquidityPool2 = new MockBalancerPool();

            vault1 = new MockVault(address(liquidityPool1), address(ohm), address(steth));
            vault2 = new MockVault(address(liquidityPool2), address(ohm), address(steth));

            vault1.setPoolAmounts(1e7, 1e18);
            vault2.setPoolAmounts(1e7, 1e18);
        }

        // Deploy Kernel and modules
        {
            kernel = new Kernel();
            minter = new OlympusMinter(kernel, address(ohm));
            roles = new OlympusRoles(kernel);
            lqreg = new OlympusLiquidityRegistry(kernel);
        }

        // Deploy policies
        {
            rolesAdmin = new RolesAdmin(kernel);
            liquidityAMO1 = new StethLiquidityAMO(
                kernel,
                address(ohm),
                address(steth),
                address(vault1),
                address(liquidityPool1),
                address(ohmEthPriceFeed),
                address(ethUsdPriceFeed),
                address(stethUsdPriceFeed)
            );
            liquidityAMO2 = new StethLiquidityAMO(
                kernel,
                address(ohm),
                address(steth),
                address(vault2),
                address(liquidityPool2),
                address(ohmEthPriceFeed),
                address(ethUsdPriceFeed),
                address(stethUsdPriceFeed)
            );
        }

        // Generate fixtures
        {
            godmode = lqreg.generateGodmodeFixture(type(OlympusLiquidityRegistry).name);
        }

        // Install modules and policies on Kernel
        {
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(roles));
            kernel.executeAction(Actions.InstallModule, address(lqreg));

            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
            kernel.executeAction(Actions.ActivatePolicy, address(liquidityAMO1));
            kernel.executeAction(Actions.ActivatePolicy, address(liquidityAMO2));
            kernel.executeAction(Actions.ActivatePolicy, godmode);
        }

        // Set roles
        {
            rolesAdmin.grantRole("liquidityamo_admin", address(this));
        }

        // Set price variation threshold to 10%
        {
            liquidityAMO1.setThreshold(100);
            liquidityAMO2.setThreshold(100);
        }

        // Mint stETH to Alice to spend
        {
            steth.mint(alice, 2e18);

            vm.startPrank(alice);
            steth.approve(address(liquidityAMO1), 1e18);
            steth.approve(address(liquidityAMO2), 1e18);
            vm.stopPrank();
        }
    }

    /// [X]  Module Data
    ///     [X]  KEYCODE returns correctly
    ///     [X]  VERSION returns correctly

    function test_KEYCODE() public {
        assertEq("LQREG", fromKeycode(lqreg.KEYCODE()));
    }

    function test_VERSION() public {
        (uint8 major, uint8 minor) = lqreg.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    /// [X]  addAMO
    ///     [X]  Unapproved address cannot call
    ///     [X]  Approved address can add AMO

    function testCorrectness_unapprovedAddressCannotAddAMO(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to add AMO as unapproved user
        vm.prank(user_);
        lqreg.addAMO(address(0));
    }

    function testCorrectness_approvedAddressCanAddAMO() public {
        // Verify initial state
        assertEq(lqreg.activeAMOCount(), 0);

        vm.prank(godmode);
        lqreg.addAMO(address(0));

        // Verify AMO was added
        assertEq(lqreg.activeAMOCount(), 1);
        assertEq(lqreg.activeAMOs(0), address(0));
    }

    /// [X]  removeAMO
    ///     [X]  Unapproved address cannot call
    ///     [X]  Fails if AMO at passed index doesn't match passed AMO
    ///     [X]  Approved address can remove AMO

    function _removeAMOSetup() internal {
        vm.prank(godmode);
        lqreg.addAMO(address(0));
    }

    function testCorrectness_unapprovedAddressCannotRemoveAMO(address user_) public {
        vm.assume(user_ != godmode);

        // Expected error
        bytes memory err = abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, user_);
        vm.expectRevert(err);

        // Try to add AMO as unapproved user
        vm.prank(user_);
        lqreg.removeAMO(0, address(0));
    }

    function testCorrectness_removeAMOFailsWithSanityCheck() public {
        _removeAMOSetup();

        // Expected error
        bytes memory err = abi.encodeWithSignature("LQREG_RemovalMismatch()");
        vm.expectRevert(err);

        // Try to remove AMO with mismatched address
        vm.prank(godmode);
        lqreg.removeAMO(0, address(1));
    }

    function testCorrectness_approvedAddressCanRemoveAMO() public {
        _removeAMOSetup();

        // Add second AMO
        vm.prank(godmode);
        lqreg.addAMO(address(1));

        // Verify initial state
        assertEq(lqreg.activeAMOCount(), 2);
        assertEq(lqreg.activeAMOs(0), address(0));
        assertEq(lqreg.activeAMOs(1), address(1));

        vm.prank(godmode);
        lqreg.removeAMO(0, address(0));

        // Verify AMO was removed
        assertEq(lqreg.activeAMOCount(), 1);
        assertEq(lqreg.activeAMOs(0), address(1));
    }

    /// [X]  reportEmissions
    ///     [X]  Reports emissions values for single installed AMO
    ///     [X]  Reports emissions values for multiple installed AMOs

    function testCorrectness_reportsEmissionsForSingleAMO() public {
        vm.prank(godmode);
        lqreg.addAMO(address(liquidityAMO1));

        // Alice deposits 1 stETH into AMO
        vm.prank(alice);
        liquidityAMO1.deposit(1e18, 1e18);

        // Pool changes in price
        vault1.setPoolAmounts(2e7, 1e18);

        // Verify emissions
        OlympusLiquidityRegistry.AMOEmissions[] memory amoEmissions = lqreg.reportEmissions();
        assertEq(amoEmissions.length, 1);
        assertEq(amoEmissions[0].amo, address(liquidityAMO1));
        assertEq(amoEmissions[0].emissions, 0);
        assertEq(amoEmissions[0].removals, 1e7);
    }

    function testCorrectness_reportsEmissionsForMultipleAMOs() public {
        vm.startPrank(godmode);
        lqreg.addAMO(address(liquidityAMO1));
        lqreg.addAMO(address(liquidityAMO2));
        vm.stopPrank();

        // Alice deposits 1 stETH into each AMO
        vm.startPrank(alice);
        liquidityAMO1.deposit(1e18, 1e18);
        liquidityAMO2.deposit(1e18, 1e18);
        vm.stopPrank();

        // Pools change in price
        vault1.setPoolAmounts(2e7, 1e18);
        vault2.setPoolAmounts(5e6, 1e18);

        // Verify emissions
        OlympusLiquidityRegistry.AMOEmissions[] memory amoEmissions = lqreg.reportEmissions();
        assertEq(amoEmissions.length, 2);
        assertEq(amoEmissions[0].amo, address(liquidityAMO1));
        assertEq(amoEmissions[0].emissions, 0);
        assertEq(amoEmissions[0].removals, 1e7);
        assertEq(amoEmissions[1].amo, address(liquidityAMO2));
        assertEq(amoEmissions[1].emissions, 5e6);
        assertEq(amoEmissions[1].removals, 0);
    }
}
