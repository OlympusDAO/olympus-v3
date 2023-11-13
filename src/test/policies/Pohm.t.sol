// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Pohm} from "policies/Pohm.sol";
import "src/Kernel.sol";

import {IgOHM} from "interfaces/IgOHM.sol";

// Mock gOHM
contract MockGohm is IgOHM {
    uint256 public index = 100e9;

    constructor() {}

    function balanceFrom(uint256 gohmAmount_) public view returns (uint256) {
        return (gohmAmount_ * index) / 1e18;
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
                address(this),
                100_000
            );
            pohm = new Pohm(
                kernel,
                address(previous),
                address(ohm),
                address(gohm),
                address(dai),
                address(this),
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

            // Set OHM circulating supply
            ohm.mint(address(0), 100_000_000e9);
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

        bytes memory err = abi.encodeWithSignature("POHM_ClaimMoreThanVested(uint256)", 0);
        vm.expectRevert(err);

        pohm.claim(user_, 100e18);
        vm.stopPrank();
    }

    function test_claimRevertsIfClaimMoreThanVested() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 2_500_000e18); // 2.5%

        bytes memory err = abi.encodeWithSignature(
            "POHM_ClaimMoreThanVested(uint256)",
            100000000000000
        );
        vm.expectRevert(err);

        pohm.claim(alice, 2_500_000e18);
        vm.stopPrank();
    }

    function test_claimRevertsIfClaimMoreThanAccountMax() public {
        vm.startPrank(alice);

        dai.approve(address(pohm), 150_000e18);

        // TODO revise, this is actually caught by redeemableFor and the ensuing POHM_ClaimMoreThanVested error
        bytes memory err = abi.encodeWithSignature(
            "POHM_ClaimMoreThanVested(uint256)",
            100000000000000
        );
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

    //============================================================================================//
    //                                   MANAGEMENT FUNCTIONS                                     //
    //============================================================================================//

    /// [X]  pushWalletChange
    ///     [X]  cannot be called by someone without a claim
    ///     [X]  flags a wallet change for the user

    function test_pushWalletChangeCannotBeCalledWithoutClaim(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        vm.startPrank(user_);

        bytes memory err = abi.encodeWithSignature("POHM_NoClaim()");
        vm.expectRevert(err);

        pohm.pushWalletChange(bob);
        vm.stopPrank();
    }

    function test_pushWalletChangeFlagsWalletChangeForUser() public {
        vm.startPrank(alice);

        // Check wallet change before
        address newWallet = pohm.walletChange(alice);
        assertEq(newWallet, address(0));

        pohm.pushWalletChange(bob);

        newWallet = pohm.walletChange(alice);
        assertEq(newWallet, bob);
        vm.stopPrank();
    }

    /// [X]  pullWalletChange
    ///     [X]  cannot be called unless the caller is flagged as the user's wallet change
    ///     [X]  adds to the user's terms
    ///     [X]  sets the wallet change to the zero address
    ///     [X]  copies terms from old wallet to new wallet
    ///     [X]  deletes terms for old wallet

    function test_pullWalletCannotBeCalledByUnflaggedWallet(address user_) public {
        vm.assume(user_ != address(0));
        vm.startPrank(user_);

        bytes memory err = abi.encodeWithSignature("POHM_NoWalletChange()");
        vm.expectRevert(err);

        pohm.pullWalletChange(alice);
        vm.stopPrank();
    }

    function test_pullWalletAddsToUsersTerms() public {
        vm.prank(alice);
        pohm.pushWalletChange(bob);

        (uint256 percent, uint256 gClaimed, uint256 max) = pohm.terms(bob);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        vm.prank(bob);
        pohm.pullWalletChange(alice);

        (percent, gClaimed, max) = pohm.terms(bob);
        assertEq(percent, 20_000);
        assertEq(gClaimed, 0);
        assertEq(max, 200_000e9);
    }

    function test_pullWalletSetsWalletChangeToZeroAddress(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        pohm.pushWalletChange(newWallet_);

        address newWallet = pohm.walletChange(alice);
        assertEq(newWallet, newWallet_);

        vm.prank(newWallet_);
        pohm.pullWalletChange(alice);

        newWallet = pohm.walletChange(alice);
        assertEq(newWallet, address(0));
    }

    function test_pullWalletCopiesTermsFromOldWalletToNewWallet(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        pohm.pushWalletChange(newWallet_);

        (uint256 percent, uint256 gClaimed, uint256 max) = pohm.terms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        (uint256 newWalletPercent, uint256 newWalletGClaimed, uint256 newWalletMax) = pohm.terms(
            newWallet_
        );
        assertEq(newWalletPercent, 0);
        assertEq(newWalletGClaimed, 0);
        assertEq(newWalletMax, 0);

        vm.prank(newWallet_);
        pohm.pullWalletChange(alice);

        (newWalletPercent, newWalletGClaimed, newWalletMax) = pohm.terms(newWallet_);
        assertEq(newWalletPercent, 10_000);
        assertEq(newWalletGClaimed, 0);
        assertEq(newWalletMax, 100_000e9);
    }

    function test_pullWalletDeletesTermsForOldWallet(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        pohm.pushWalletChange(newWallet_);

        (uint256 percent, uint256 gClaimed, uint256 max) = pohm.terms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        vm.prank(newWallet_);
        pohm.pullWalletChange(alice);

        (percent, gClaimed, max) = pohm.terms(alice);
        assertEq(percent, 0);
        assertEq(gClaimed, 0);
        assertEq(max, 0);
    }

    //============================================================================================//
    //                                       ADMIN FUNCTIONS                                      //
    //============================================================================================//

    /// [X]  migrate
    ///     [X]  can only be called by address with pohm_admin role
    ///     [X]  copies terms from previous pOHM contract

    function test_migrateCanOnlyBeCalledByPohmAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("pohm_admin")
        );
        vm.expectRevert(err);

        address[] memory users = new address[](1);
        users[0] = alice;

        vm.prank(user_);
        pohm.migrate(users);
    }

    function test_migrateCopiesTermsFromPreviousPohmContract(address migratedUser_) public {
        vm.assume(migratedUser_ != alice && migratedUser_ != bob);

        previous.setTerms(migratedUser_, 10_000, 0, 100_000e9);

        (uint256 percent, uint256 gClaimed, uint256 max) = previous.terms(migratedUser_);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        (uint256 newPercent, uint256 newGClaimed, uint256 newMax) = pohm.terms(migratedUser_);
        assertEq(newPercent, 0);
        assertEq(newGClaimed, 0);
        assertEq(newMax, 0);

        address[] memory users = new address[](1);
        users[0] = migratedUser_;

        pohm.migrate(users);

        (newPercent, newGClaimed, newMax) = pohm.terms(migratedUser_);
        assertEq(newPercent, 10_000);
        assertEq(newGClaimed, 0);
        assertEq(newMax, 100_000e9);
    }

    /// [X]  setTerms
    ///     [X]  can only be called by address with pohm_admin role
    ///     [X]  can only set terms for account that has no current claim
    ///     [X]  cannot increase total allocation beyond max
    ///     [X]  sets terms for account
    ///     [X]  increases totalAllocated value

    function test_setTermsCanOnlyBeCalledByPohmAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("pohm_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        pohm.setTerms(alice, 10_000, 0, 100_000e9);
    }

    function test_setTermsCanOnlySetTermsForAccountThatHasNoCurrentClaim() public {
        bytes memory err = abi.encodeWithSignature("POHM_AlreadyHasClaim()");
        vm.expectRevert(err);

        pohm.setTerms(alice, 10_000, 0, 100_000e9);
    }

    function test_setTermsCannotIncreaseTotalAllocationBeyondMax(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        bytes memory err = abi.encodeWithSignature("POHM_AllocationLimitViolation()");
        vm.expectRevert(err);

        pohm.setTerms(user_, 100_000, 0, 100_000e9);
    }

    function test_setTermsSetsTermsForAccount(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        (uint256 percent, uint256 gClaimed, uint256 max) = pohm.terms(user_);
        assertEq(percent, 0);
        assertEq(gClaimed, 0);
        assertEq(max, 0);

        pohm.setTerms(user_, 10_000, 0, 100_000e9);

        (percent, gClaimed, max) = pohm.terms(user_);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);
    }

    function test_setTermsIncreasesTotalAllocatedValue(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        uint256 totalAllocated = pohm.totalAllocated();
        assertEq(totalAllocated, 20_000);

        pohm.setTerms(user_, 10_000, 0, 100_000e9);

        totalAllocated = pohm.totalAllocated();
        assertEq(totalAllocated, 30_000);
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// [X]  redeemableFor
    /// [X]  getCirculatingSupply
    /// [X]  getAccountClaimed

    function test_redeemableFor() public {
        assertEq(pohm.redeemableFor(alice), 100_000e9);

        // Claim 10k
        vm.startPrank(alice);
        dai.approve(address(pohm), 10_000e18);
        pohm.claim(alice, 10_000e18);
        vm.stopPrank();

        assertEq(pohm.redeemableFor(alice), 90_000e9);
    }

    function test_getCirculatingSupply() public {
        assertEq(pohm.getCirculatingSupply(), 100_000_000e9);

        vm.prank(address(0));
        ohm.transfer(address(this), 10_000_000e9);

        assertEq(pohm.getCirculatingSupply(), 90_000_000e9);

        ohm.mint(address(this), 10_000_000e9);
        assertEq(pohm.getCirculatingSupply(), 90_000_000e9);

        ohm.mint(address(0), 10_000_000e9);
        assertEq(pohm.getCirculatingSupply(), 100_000_000e9);
    }

    function test_getAccountClaimed() public {
        assertEq(pohm.getAccountClaimed(alice), 0);

        // Claim 100k
        vm.startPrank(alice);
        dai.approve(address(pohm), 10_000e18);
        pohm.claim(alice, 10_000e18);
        vm.stopPrank();

        assertEq(pohm.getAccountClaimed(alice), 10_000e9);
    }
}
