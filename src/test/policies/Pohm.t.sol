// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Pohm} from "policies/Pohm.sol";
import "src/Kernel.sol";

import {IgOHM} from "interfaces/IgOHM.sol";

// Mock gOHM
contract MockGohm is IgOHM {
    uint256 public index = 100e9;

    constructor() {}

    function balanceFrom(uint256 gohmAmount_) public view returns (uint256) {
        return (gohmAmount_ * index) / 1e9;
    }

    function balanceTo(uint256 ohmAmount_) public view returns (uint256) {
        return (ohmAmount_ * 1e18) / index;
    }
}

// solhint-disable-next-line max-states-count
contract PohmTest is Test {
    UserFactory public userCreator;
    address internal alice;
    address internal bob;

    MockERC20 internal ohm;
    MockGohm internal gohm;
    MockERC20 internal dai;

    Kernel internal kernel;

    OlympusMinter internal mintr;
    OlympusTreasury internal trsry;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    Pohm internal previous;
    Pohm internal pohm;

    function setUp() public {
        userCreator = new UserFactory();

        // Deploy accounts
        {
            address[] memory users = userCreator.create(2);
            alice = users[0];
            bob = users[1];
        }

        // Deploy tokens
        {
            ohm = new MockERC20("Olympus", "OHM", 9);
            gohm = new MockGohm();
            dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        }

        // Deploy Kernel and Modules
        {
            kernel = new Kernel();

            mintr = new OlympusMinter(kernel, address(ohm));
            trsry = new OlympusTreasury(kernel);
            roles = new OlympusRoles(kernel);
        }

        // Deploy policies
        {
            previous = new Pohm(
                kernel,
                address(0),
                address(ohm),
                address(gohm),
                address(dai),
                100_000
            );
            pohm = new Pohm(
                kernel,
                address(previous),
                address(ohm),
                address(gohm),
                address(dai),
                100_000
            );
            rolesAdmin = new RolesAdmin(kernel);
        }

        // Initialize system
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(trsry));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(previous));
            kernel.executeAction(Actions.ActivatePolicy, address(pohm));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Set roles
        {
            rolesAdmin.grantRole("pohm_admin", address(this));
        }

        // Arbitrary setup
        {
            dai.mint(address(alice), 10_000_000e18);
            dai.mint(address(bob), 10_000_000e18);

            pohm.setTerms(alice, 10_000, 0, 100_000e9);
            pohm.setTerms(bob, 10_000, 0, 100_000e9);
        }
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// [X]  claim
    ///     [X]  fails if user is not approved
    ///     [X]  cannot claim more than vested
    ///     [X]  cannot claim more than account max
    ///     [X]  increases user's gOHM claimed value
    ///     [X]  transfers DAI from user
    ///     [X]  mints OHM to user

    function test_claimRevertsIfUserNotApproved(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        dai.mint(user_, 1000e18);

        vm.startPrank(user_);
        dai.approve(address(pohm), 1000e18);

        bytes memory err = abi.encodeWithSignature("POHM_ClaimMoreThanVested()");
        vm.expectRevert(err);

        pohm.claim(user_, 100e18);
        vm.stopPrank();
    }

    function test_claimRevertsIfClaimMoreThanVested() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 2_500_000e18); // 2.5%

        bytes memory err = abi.encodeWithSignature("POHM_ClaimMoreThanVested()");
        vm.expectRevert(err);

        pohm.claim(alice, 2_500_000e18);
        vm.stopPrank();
    }

    function test_claimRevertsIfClaimMoreThanAccountMax() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 150_000e18);

        // TODO revise, this is actually caught by redeemableFor and the ensuing POHM_ClaimMoreThanVested error
        bytes memory err = abi.encodeWithSignature("POHM_ClaimMoreThanVested()");
        vm.expectRevert(err);

        pohm.claim(alice, 150_000e18);
        vm.stopPrank();
    }

    function test_claimIncreasesUsersGohmClaimedValue() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 100_000e18);

        // Check gOHM claimed before
        (, uint256 gClaimed, ) = pohm.terms(alice);
        assertEq(gClaimed, 0);

        pohm.claim(alice, 100_000e18);

        (, gClaimed, ) = pohm.terms(alice);
        assertEq(gClaimed, 1000e18);
        vm.stopPrank();
    }

    function test_claimTransfersDaiFromUser() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 100_000e18);

        // Check gOHM claimed before
        uint256 daiBalance = dai.balanceOf(alice);
        assertEq(daiBalance, 10_000_000e18);

        pohm.claim(alice, 100_000e18);

        daiBalance = dai.balanceOf(alice);
        assertEq(daiBalance, 9_900_000e18);
        vm.stopPrank();
    }

    function test_claimMintsOhmToUser() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 100_000e18);

        // Check gOHM claimed before
        uint256 ohmBalance = ohm.balanceOf(alice);
        assertEq(ohmBalance, 0);

        pohm.claim(alice, 100_000e18);

        ohmBalance = ohm.balanceOf(alice);
        assertEq(ohmBalance, 100_000e9);
        vm.stopPrank();
    }
}
