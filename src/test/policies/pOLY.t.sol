// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGenesisClaim} from "test/mocks/MockGenesisClaim.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles, ROLESv1} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {IPOLY, pOLY} from "policies/pOLY.sol";
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

    function totalSupply() external view override returns (uint256) {}

    function balanceOf(address account) external view override returns (uint256) {}

    function transfer(address recipient, uint256 amount) external override returns (bool) {}

    function allowance(address owner, address spender) external view override returns (uint256) {}

    function approve(address spender, uint256 amount) external override returns (bool) {}

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {}

    function mint(address _to, uint256 _amount) external override {}

    function burn(address _from, uint256 _amount) external override {}

    function migrate(address _staking, address _sOHM) external override {}

    function getPriorVotes(
        address account,
        uint256 blockNumber
    ) external view override returns (uint256) {}
}

// solhint-disable-next-line max-states-count
contract pOLYTest is Test {
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
    MockGenesisClaim internal previousGenesis;
    pOLY internal previous;
    pOLY internal poly;

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
            previousGenesis = new MockGenesisClaim();
            previous = new pOLY(
                kernel,
                address(0),
                address(0),
                address(ohm),
                address(gohm),
                address(dai),
                address(this),
                100_000
            );
            poly = new pOLY(
                kernel,
                address(previous),
                address(previousGenesis),
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
            kernel.executeAction(Actions.ActivatePolicy, address(poly));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Set roles
        {
            rolesAdmin.grantRole("poly_admin", address(this));
        }

        // Arbitrary setup
        {
            dai.mint(address(alice), 10_000_000e18);
            dai.mint(address(bob), 10_000_000e18);

            poly.setTerms(alice, 10_000, 0, 100_000e9);
            poly.setTerms(bob, 10_000, 0, 100_000e9);

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
        dai.approve(address(poly), 1000e18);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 0);
        vm.expectRevert(err);

        poly.claim(user_, 100e18);
        vm.stopPrank();
    }

    function test_claimRevertsIfClaimMoreThanVested() public {
        vm.startPrank(alice);

        dai.approve(address(poly), 2_500_000e18); // 2.5%

        bytes memory err = abi.encodeWithSignature(
            "POLY_ClaimMoreThanVested(uint256)",
            100000000000000
        );
        vm.expectRevert(err);

        poly.claim(alice, 2_500_000e18);
        vm.stopPrank();
    }

    function test_claimRevertsIfClaimMoreThanAccountMax() public {
        vm.startPrank(alice);

        dai.approve(address(poly), 150_000e18);

        // TODO revise, this is actually caught by redeemableFor and the ensuing POLY_ClaimMoreThanVested error
        bytes memory err = abi.encodeWithSignature(
            "POLY_ClaimMoreThanVested(uint256)",
            100000000000000
        );
        vm.expectRevert(err);

        poly.claim(alice, 150_000e18);
        vm.stopPrank();
    }

    function test_claimIncreasesUsersGohmClaimedValue() public {
        vm.startPrank(alice);

        dai.approve(address(poly), 100_000e18);

        // Check gOHM claimed before
        (, uint256 gClaimed, ) = poly.terms(alice);
        assertEq(gClaimed, 0);

        poly.claim(alice, 100_000e18);

        (, gClaimed, ) = poly.terms(alice);
        assertEq(gClaimed, 1000e18);
        vm.stopPrank();
    }

    function test_claimTransfersDaiFromUser() public {
        vm.startPrank(alice);

        dai.approve(address(poly), 100_000e18);

        // Check gOHM claimed before
        uint256 daiBalance = dai.balanceOf(alice);
        assertEq(daiBalance, 10_000_000e18);

        poly.claim(alice, 100_000e18);

        daiBalance = dai.balanceOf(alice);
        assertEq(daiBalance, 9_900_000e18);
        vm.stopPrank();
    }

    function test_claimMintsOhmToUser() public {
        vm.startPrank(alice);

        dai.approve(address(poly), 100_000e18);

        // Check gOHM claimed before
        uint256 ohmBalance = ohm.balanceOf(alice);
        assertEq(ohmBalance, 0);

        poly.claim(alice, 100_000e18);

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

        bytes memory err = abi.encodeWithSignature("POLY_NoClaim()");
        vm.expectRevert(err);

        poly.pushWalletChange(bob);
        vm.stopPrank();
    }

    function test_pushWalletChangeFlagsWalletChangeForUser() public {
        vm.startPrank(alice);

        // Check wallet change before
        address newWallet = poly.walletChange(alice);
        assertEq(newWallet, address(0));

        poly.pushWalletChange(bob);

        newWallet = poly.walletChange(alice);
        assertEq(newWallet, bob);
        vm.stopPrank();
    }

    /// [X]  pullWalletChange
    ///     [X]  cannot be called unless the caller is flagged as the user's wallet change
    ///     [X]  adds to the user's terms
    ///     [X]  sets the wallet change to the zero address
    ///     [X]  copies terms from old wallet to new wallet
    ///     [X]  deletes terms for old wallet
    ///     [X]  old wallet can no longer claim

    function test_pullWalletCannotBeCalledByUnflaggedWallet(address user_) public {
        vm.assume(user_ != address(0));
        vm.startPrank(user_);

        bytes memory err = abi.encodeWithSignature("POLY_NoWalletChange()");
        vm.expectRevert(err);

        poly.pullWalletChange(alice);
        vm.stopPrank();
    }

    function test_pullWalletAddsToUsersTerms() public {
        vm.prank(alice);
        poly.pushWalletChange(bob);

        (uint256 percent, uint256 gClaimed, uint256 max) = poly.terms(bob);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        vm.prank(bob);
        poly.pullWalletChange(alice);

        (percent, gClaimed, max) = poly.terms(bob);
        assertEq(percent, 20_000);
        assertEq(gClaimed, 0);
        assertEq(max, 200_000e9);
    }

    function test_pullWalletSetsWalletChangeToZeroAddress(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        poly.pushWalletChange(newWallet_);

        address newWallet = poly.walletChange(alice);
        assertEq(newWallet, newWallet_);

        vm.prank(newWallet_);
        poly.pullWalletChange(alice);

        newWallet = poly.walletChange(alice);
        assertEq(newWallet, address(0));
    }

    function test_pullWalletCopiesTermsFromOldWalletToNewWallet(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        poly.pushWalletChange(newWallet_);

        (uint256 percent, uint256 gClaimed, uint256 max) = poly.terms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        (uint256 newWalletPercent, uint256 newWalletGClaimed, uint256 newWalletMax) = poly.terms(
            newWallet_
        );
        assertEq(newWalletPercent, 0);
        assertEq(newWalletGClaimed, 0);
        assertEq(newWalletMax, 0);

        vm.prank(newWallet_);
        poly.pullWalletChange(alice);

        (newWalletPercent, newWalletGClaimed, newWalletMax) = poly.terms(newWallet_);
        assertEq(newWalletPercent, 10_000);
        assertEq(newWalletGClaimed, 0);
        assertEq(newWalletMax, 100_000e9);
    }

    function test_pullWalletDeletesTermsForOldWallet(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        poly.pushWalletChange(newWallet_);

        (uint256 percent, uint256 gClaimed, uint256 max) = poly.terms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        vm.prank(newWallet_);
        poly.pullWalletChange(alice);

        (percent, gClaimed, max) = poly.terms(alice);
        assertEq(percent, 0);
        assertEq(gClaimed, 0);
        assertEq(max, 0);
    }

    function test_pullWalletOldWalletCanNoLongerClaim(address newWallet_) public {
        vm.assume(newWallet_ != alice && newWallet_ != bob);

        vm.prank(alice);
        poly.pushWalletChange(newWallet_);

        vm.prank(newWallet_);
        poly.pullWalletChange(alice);

        vm.startPrank(alice);
        dai.approve(address(poly), 100_000e18);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 0);
        vm.expectRevert(err);

        poly.claim(alice, 100_000e18);
        vm.stopPrank();
    }

    //============================================================================================//
    //                                       ADMIN FUNCTIONS                                      //
    //============================================================================================//

    /// [X]  migrate
    ///     [X]  can only be called by address with poly_admin role
    ///     [X]  copies terms from previous pOLY contract

    function test_migrateCanOnlyBeCalledByPolyAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("poly_admin")
        );
        vm.expectRevert(err);

        address[] memory users = new address[](1);
        users[0] = alice;

        vm.prank(user_);
        poly.migrate(users);
    }

    function test_migrateCopiesTermsFromPreviousPolyContract(
        address migratedUser1_,
        address migratedUser2_
    ) public {
        vm.assume(
            migratedUser1_ != alice && migratedUser1_ != bob && migratedUser1_ != migratedUser2_
        );
        vm.assume(
            migratedUser2_ != alice && migratedUser2_ != bob && migratedUser2_ != migratedUser1_
        );

        previous.setTerms(migratedUser1_, 10_000, 0, 100_000e9);
        previous.setTerms(migratedUser2_, 5_000, 1e18, 50_000e9);

        (uint256 newPercent1, uint256 newGClaimed1, uint256 newMax1) = poly.terms(migratedUser1_);
        assertEq(newPercent1, 0);
        assertEq(newGClaimed1, 0);
        assertEq(newMax1, 0);

        (uint256 newPercent2, uint256 newGClaimed2, uint256 newMax2) = poly.terms(migratedUser2_);
        assertEq(newPercent2, 0);
        assertEq(newGClaimed2, 0);
        assertEq(newMax2, 0);

        address[] memory users = new address[](2);
        users[0] = migratedUser1_;
        users[1] = migratedUser2_;

        poly.migrate(users);

        (newPercent1, newGClaimed1, newMax1) = poly.terms(migratedUser1_);
        assertEq(newPercent1, 10_000);
        assertEq(newGClaimed1, 0);
        assertEq(newMax1, 100_000e9);

        (newPercent2, newGClaimed2, newMax2) = poly.terms(migratedUser2_);
        assertEq(newPercent2, 5_000);
        assertEq(newGClaimed2, 1e18);
        assertEq(newMax2, 50_000e9);
    }

    /// [X]  migrateGenesis
    ///     [X]  can only be called by address with poly_admin role
    ///     [X]  copies terms from previous GenesisClaim contract

    function test_migrateGenesisCanOnlyBeCalledByPolyAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("poly_admin")
        );
        vm.expectRevert(err);

        address[] memory users = new address[](1);
        users[0] = alice;

        vm.prank(user_);
        poly.migrateGenesis(users);
    }

    function test_migrateGenesisCopiesTermsFromPreviousGenesisClaimContract(
        address migratedUser1_,
        address migratedUser2_
    ) public {
        vm.assume(migratedUser1_ != alice && migratedUser1_ != bob);
        vm.assume(migratedUser2_ != alice && migratedUser2_ != bob);

        previousGenesis.setTerms(migratedUser1_, 10_000, 100e9, 1e18, 100_000e9);
        previousGenesis.setTerms(migratedUser2_, 5_000, 5e9, 5e17, 50_000e9);

        (uint256 newPercent1, uint256 newGClaimed1, uint256 newMax1) = poly.terms(migratedUser1_);
        assertEq(newPercent1, 0);
        assertEq(newGClaimed1, 0);
        assertEq(newMax1, 0);

        (uint256 newPercent2, uint256 newGClaimed2, uint256 newMax2) = poly.terms(migratedUser2_);
        assertEq(newPercent2, 0);
        assertEq(newGClaimed2, 0);
        assertEq(newMax2, 0);

        address[] memory users = new address[](2);
        users[0] = migratedUser1_;
        users[1] = migratedUser2_;

        poly.migrateGenesis(users);

        (newPercent1, newGClaimed1, newMax1) = poly.terms(migratedUser1_);
        assertEq(newPercent1, 10_000);
        assertEq(newGClaimed1, 2e18);
        assertEq(newMax1, 100_000e9);

        (newPercent2, newGClaimed2, newMax2) = poly.terms(migratedUser2_);
        assertEq(newPercent2, 5_000);
        assertEq(newGClaimed2, 55e16);
        assertEq(newMax2, 50_000e9);
    }

    /// [X]  setTerms
    ///     [X]  can only be called by address with poly_admin role
    ///     [X]  can only set terms for account that has no current claim
    ///     [X]  cannot increase total allocation beyond max
    ///     [X]  sets terms for account
    ///     [X]  increases totalAllocated value

    function test_setTermsCanOnlyBeCalledByPolyAdmin(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("poly_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        poly.setTerms(alice, 10_000, 0, 100_000e9);
    }

    function test_setTermsCanOnlySetTermsForAccountThatHasNoCurrentClaim() public {
        bytes memory err = abi.encodeWithSignature("POLY_AlreadyHasClaim()");
        vm.expectRevert(err);

        poly.setTerms(alice, 10_000, 0, 100_000e9);
    }

    function test_setTermsCannotIncreaseTotalAllocationBeyondMax(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        bytes memory err = abi.encodeWithSignature("POLY_AllocationLimitViolation()");
        vm.expectRevert(err);

        poly.setTerms(user_, 100_000, 0, 100_000e9);
    }

    function test_setTermsSetsTermsForAccount(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        (uint256 percent, uint256 gClaimed, uint256 max) = poly.terms(user_);
        assertEq(percent, 0);
        assertEq(gClaimed, 0);
        assertEq(max, 0);

        poly.setTerms(user_, 10_000, 0, 100_000e9);

        (percent, gClaimed, max) = poly.terms(user_);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);
    }

    function test_setTermsIncreasesTotalAllocatedValue(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        uint256 totalAllocated = poly.totalAllocated();
        assertEq(totalAllocated, 20_000);

        poly.setTerms(user_, 10_000, 0, 100_000e9);

        totalAllocated = poly.totalAllocated();
        assertEq(totalAllocated, 30_000);
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    /// [X]  redeemableFor
    /// [X]  getCirculatingSupply
    /// [X]  getAccountClaimed

    function test_redeemableFor() public {
        assertEq(poly.redeemableFor(alice), 100_000e9);

        // Claim 10k
        vm.startPrank(alice);
        dai.approve(address(poly), 10_000e18);
        poly.claim(alice, 10_000e18);
        vm.stopPrank();

        assertEq(poly.redeemableFor(alice), 90_000e9);
    }

    function test_getCirculatingSupply() public {
        assertEq(poly.getCirculatingSupply(), 100_000_000e9);

        vm.prank(address(0));
        ohm.transfer(address(this), 10_000_000e9);

        assertEq(poly.getCirculatingSupply(), 90_000_000e9);

        ohm.mint(address(this), 10_000_000e9);
        assertEq(poly.getCirculatingSupply(), 90_000_000e9);

        ohm.mint(address(0), 10_000_000e9);
        assertEq(poly.getCirculatingSupply(), 100_000_000e9);
    }

    function test_getAccountClaimed() public {
        assertEq(poly.getAccountClaimed(alice), 0);

        // Claim 100k
        vm.startPrank(alice);
        dai.approve(address(poly), 10_000e18);
        poly.claim(alice, 10_000e18);
        vm.stopPrank();

        assertEq(poly.getAccountClaimed(alice), 10_000e9);
    }
}
