// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {UserFactory} from "src/test/lib/UserFactory.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {pOLY} from "policies/pOLY.sol";
import {ClaimTransfer} from "src/external/ClaimTransfer.sol";
import {Actions, Kernel} from "src/Kernel.sol";

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
contract ClaimTransferTest is Test {
    UserFactory public userCreator;
    address internal alice;
    address internal bob;

    MockERC20 internal ohm;
    MockERC20 internal dai;
    MockGohm internal gohm;

    Kernel internal kernel;

    OlympusMinter internal mintr;
    OlympusTreasury internal trsry;
    OlympusRoles internal roles;

    RolesAdmin internal rolesAdmin;
    pOLY internal poly;

    ClaimTransfer internal claimTransfer;

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
            poly = new pOLY(
                kernel,
                address(0),
                address(0),
                address(ohm),
                address(gohm),
                address(dai),
                address(this),
                100_000
            );
            rolesAdmin = new RolesAdmin(kernel);
        }

        // Deploy claim transfer
        {
            claimTransfer = new ClaimTransfer(
                address(poly),
                address(ohm),
                address(dai),
                address(gohm)
            );
        }

        // Initialize system
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(trsry));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Activate policies
            kernel.executeAction(Actions.ActivatePolicy, address(poly));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Set roles
        {
            rolesAdmin.grantRole("poly_admin", address(this));
        }

        // Other setup
        {
            dai.mint(alice, 10_000_000e18);
            dai.mint(bob, 10_000_000e18);

            poly.setTerms(alice, 10_000, 0, 100_000e9);
            poly.setTerms(bob, 10_000, 0, 100_000e9);

            ohm.mint(address(0), 100_000_000e9);
        }
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// [X]  fractionalizeClaim
    ///     [X]  reverts if user has no claim
    ///     [X]  fails if user has not pushed wallet change
    ///     [X]  sets fractionalizedTerms

    function testCorrectness_fractionalizeClaimRevertsIfUserHasNoClaim(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        bytes memory err = abi.encodeWithSignature("POLY_NoWalletChange()");
        vm.expectRevert(err);

        vm.prank(user_);
        claimTransfer.fractionalizeClaim();
    }

    function testCorrectness_cannotFractionalizeWithoutPushingWalletChange() public {
        bytes memory err = abi.encodeWithSignature("POLY_NoWalletChange()");
        vm.expectRevert(err);

        vm.prank(alice);
        claimTransfer.fractionalizeClaim();
    }

    function testCorrectness_fractionalizeClaimSetsTerms() public {
        uint256 redeemableBefore = poly.redeemableFor(alice);

        (uint256 percent, uint256 gClaimed, uint256 max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 0);
        assertEq(gClaimed, 0);
        assertEq(max, 0);

        // redeemableFor should be 0, no terms set yet
        (uint256 redeemable, uint256 daiRequired) = claimTransfer.redeemableFor(alice);
        assertEq(redeemable, 0, "claimTransfer: redeemableFor is not 0");
        assertEq(daiRequired, 0, "claimTransfer: daiRequired is not 0");

        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));

        claimTransfer.fractionalizeClaim();
        vm.stopPrank();

        (percent, gClaimed, max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 0);
        assertEq(max, 100_000e9);

        // 1 OHM = 1 DAI, adjusted for decimal scale
        uint256 redeemableExpected = (redeemableBefore * 1e18) / 1e9;

        // redeemableFor should be the same as before
        (redeemable, daiRequired) = claimTransfer.redeemableFor(alice);
        assertEq(redeemable, redeemableBefore, "claimTransfer: redeemableFor differs");
        assertEq(daiRequired, redeemableExpected, "claimTransfer: daiRequired differs");
    }

    /// [X]  claim
    ///     [X]  fails if user has no fractionalized claim
    ///     [X]  cannot claim more than vested
    ///     [X]  cannot claim more than max
    ///     [X]  increases user's gClaimed
    ///     [X]  transfers DAI from user
    ///     [X]  sends OHM to user

    function testCorrectness_claimRevertsIfUserHasNoClaim(address user_) public {
        vm.assume(user_ != alice && user_ != bob);

        dai.mint(user_, 1_000e18);

        vm.startPrank(user_);
        dai.approve(address(claimTransfer), 1_000e18);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 0);
        vm.expectRevert(err);

        claimTransfer.claim(1_000e18);
        vm.stopPrank();
    }

    function testCorrectness_claimRevertsIfClaimMoreThanVested() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));

        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 250_000e18);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 100_000e9);
        vm.expectRevert(err);

        claimTransfer.claim(250_000e18);
        vm.stopPrank();
    }

    function testCorrectness_claimRevertsIfClaimMoreThanMax() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));

        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 100_001e18);

        // Set circulating supply to be massive
        ohm.mint(address(0), 100_000_000_000e9);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 100_000e9);
        vm.expectRevert(err);

        claimTransfer.claim(100_001e18);
        vm.stopPrank();
    }

    function testCorrectness_claimIncreasesGClaimed() public {
        uint256 redeemableBefore = poly.redeemableFor(alice);

        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));

        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 1_000e18);

        claimTransfer.claim(1_000e18);
        vm.stopPrank();

        (uint256 percent, uint256 gClaimed, uint256 max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 10e18);
        assertEq(max, 100_000e9);

        // redeemableFor should be adjusted
        // 1 OHM = 1 DAI
        uint256 redeemedExpected = (1_000e18 * 1e9) / 1e18;
        uint256 daiRequiredExpected = ((redeemableBefore - redeemedExpected) * 1e18) / 1e9;

        (uint256 redeemable, uint256 daiRequired) = claimTransfer.redeemableFor(alice);
        assertEq(
            redeemable,
            redeemableBefore - redeemedExpected,
            "claimTransfer: redeemableFor is not adjusted"
        );
        assertEq(daiRequired, daiRequiredExpected, "claimTransfer: daiRequired is not adjusted");
    }

    function testCorrectness_claimTransfersDaiFromUser() public {
        assertEq(dai.balanceOf(alice), 10_000_000e18);

        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));

        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 1_000e18);

        claimTransfer.claim(1_000e18);
        vm.stopPrank();

        assertEq(dai.balanceOf(alice), 9_999_000e18);
    }

    function testCorrectness_claimSendsOhmToUser() public {
        assertEq(ohm.balanceOf(alice), 0);

        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));

        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 1_000e18);

        claimTransfer.claim(1_000e18);
        vm.stopPrank();

        assertEq(ohm.balanceOf(alice), 1_000e9);
    }

    /// [X]  approve
    ///     [X]  can be called by anyone
    ///     [X]  sets allowance for user-spender pair
    ///     [X]  returns true

    function testCorrectness_approveCanBeCalledByAnyone(address caller_) public {
        vm.prank(caller_);
        claimTransfer.approve(address(this), 100);
    }

    function testCorrectness_approveSetsAllowance(
        address owner_,
        address spender_,
        uint256 amount_
    ) public {
        vm.prank(owner_);
        claimTransfer.approve(spender_, amount_);
        assertEq(claimTransfer.allowance(owner_, spender_), amount_);
    }

    function testCorrectness_approveReturnsTrue() public {
        assertEq(claimTransfer.approve(address(this), 100), true);
    }

    /// [X]  transfer
    ///     [X]  cannot transfer if you have no claim
    ///     [X]  cannot transfer more than percent
    ///     [X]  transfer properly updates max
    ///     [X]  cannot transfer more than unclaimed portion of max
    ///     [X]  transfer does not allow illegal vesting
    ///     [X]  updates fractionalizedTerms
    ///     [X]  returns true

    function testCorrectness_transferCannotTransferIfYouHaveNoClaim() public {
        vm.expectRevert(stdError.divisionError);
        claimTransfer.transfer(bob, 1_000);
    }

    function testCorrectness_transferCannotTransferMoreThanPercent() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        claimTransfer.transfer(bob, 100_000);
    }

    function testCorrectness_transferProperlyUpdatesMax() public {
        // CASE: User claims 10000 OHM (100 gOHM). They can only then transfer up to 90000 OHM (900 gOHM).
        // Their max is reduced by taking into consideration their gClaimed. Transfer 50% of their claim,
        // and their max is reduced by 50000 OHM + 50% of their gClaimed converted to OHM (5000 OHM).
        // Their max is now 45000 OHM with 50 gOHM claimed, leaving a claimable amount of 40000 OHM. The
        // recipient gets a max value of 55000 OHM and the commensurate gClaimed (50) so they have a true claimable
        // amount of 50000 OHM. The sender's fractionalized claim is updated to reflect the transfer.

        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 10_000e18);
        claimTransfer.claim(10_000e18);

        // Make assertions
        (uint256 percent, uint256 gClaimed, uint256 max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 100e18);
        assertEq(max, 100_000e9);

        // Transfer 50% of alice's claim
        claimTransfer.transfer(bob, 5_000);

        // Make assertions
        (percent, gClaimed, max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 5_000);
        assertEq(gClaimed, 50e18);
        assertEq(max, 45_000e9);

        (uint256 bobPercent, uint256 bobGClaimed, uint256 bobMax) = claimTransfer
            .fractionalizedTerms(bob);
        assertEq(bobPercent, 5_000);
        assertEq(bobGClaimed, 50e18);
        assertEq(bobMax, 55_000e9);
        vm.stopPrank();
    }

    function testCorrectness_transferCannotTransferMoreThanUnclaimedPortionOfMax() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 10_000e18);
        claimTransfer.claim(10_000e18);

        // Try to transfer 100% of alice's claim
        vm.expectRevert(stdError.arithmeticError);
        claimTransfer.transfer(bob, 10_000e9);
        vm.stopPrank();
    }

    function testCorrectness_transferDoesNotAllowIllegalVesting() public {
        // Burn almost all of the supply so only 50k OHM should be claimable
        ohm.burn(address(0), 95_000_000e9);

        // Alice claims 50k OHM (max for given circulating supply)
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 50_000e18);
        claimTransfer.claim(50_000e18);

        // Alice tries to transfer rest of claim to bob to try to claim more
        claimTransfer.transfer(bob, 5_000);
        vm.stopPrank();

        // Bob tries to claim. Technically alice's claim increases the circulating supply so he's eligible to claim 250 OHM. We try to claim one above that.
        vm.startPrank(bob);
        dai.approve(address(claimTransfer), 251e18);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 250e9);
        vm.expectRevert(err);

        claimTransfer.claim(251e18);
        vm.stopPrank();
    }

    function testCorrectness_transferUpdatesFractionalizedTerms() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        vm.stopPrank();

        vm.startPrank(alice);
        claimTransfer.transfer(bob, 1_000);
        vm.stopPrank();

        (uint256 percent, uint256 gClaimed, uint256 max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 9_000);
        assertEq(gClaimed, 0);
        assertEq(max, 90_000e9);

        (percent, gClaimed, max) = claimTransfer.fractionalizedTerms(bob);
        assertEq(percent, 1_000);
        assertEq(gClaimed, 0);
        assertEq(max, 10_000e9);
    }

    function testCorrectness_transferReturnsTrue() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        assertEq(claimTransfer.transfer(bob, 1_000), true);
        vm.stopPrank();
    }

    /// [X]  transferFrom
    ///     [X]  cannot be called without allowance
    ///     [X]  cannot transfer more than percent
    ///     [X]  transferFrom properly updates max
    ///     [X]  cannot transfer more than unclaimed portion of max
    ///     [X]  transferFrom does not allow illegal vesting
    ///     [X]  updates fractionalizedTerms
    ///     [X]  returns true

    function testCorrectness_transferFromCannotBeCalledWithoutAllowance() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(stdError.arithmeticError);
        claimTransfer.transferFrom(alice, bob, 1_000);
    }

    function testCorrectness_transferFromCannotTransferMoreThanPercent() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        claimTransfer.approve(address(this), 100_000);
        vm.stopPrank();

        vm.expectRevert(stdError.arithmeticError);
        claimTransfer.transferFrom(alice, bob, 100_000);
    }

    function testCorrectness_transferFromProperlyUpdatesMax() public {
        // CASE: User claims 10000 OHM (100 gOHM). They can only then transfer up to 90000 OHM (900 gOHM).
        // Their max is reduced by taking into consideration their gClaimed. Transfer 50% of their claim,
        // and their max is reduced by 50000 OHM + 50% of their gClaimed converted to OHM (5000 OHM).
        // Their max is now 45000 OHM.

        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 10_000e18);
        claimTransfer.claim(10_000e18);

        // Make assertions
        (uint256 percent, uint256 gClaimed, uint256 max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 10_000);
        assertEq(gClaimed, 100e18);
        assertEq(max, 100_000e9);

        claimTransfer.approve(address(this), 5_000);
        vm.stopPrank();

        // Transfer 50% of alice's claim
        claimTransfer.transferFrom(alice, bob, 5_000);

        // Make assertions
        (percent, gClaimed, max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 5_000);
        assertEq(gClaimed, 50e18);
        assertEq(max, 45_000e9);

        (uint256 bobPercent, uint256 bobGClaimed, uint256 bobMax) = claimTransfer
            .fractionalizedTerms(bob);
        assertEq(bobPercent, 5_000);
        assertEq(bobGClaimed, 50e18);
        assertEq(bobMax, 55_000e9);
    }

    function testCorrectness_transferFromCannotTransferMoreThanUnclaimedPortionOfMax() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        claimTransfer.approve(address(this), 10_000);

        dai.approve(address(claimTransfer), 10_000e18);
        claimTransfer.claim(10_000e18);
        vm.stopPrank();

        vm.expectRevert(stdError.arithmeticError);
        claimTransfer.transferFrom(alice, bob, 10_000);
    }

    function testCorrectness_transferFromDoesNotAllowIllegalVesting() public {
        // Burn almost all of the supply so only 50k OHM should be claimable
        ohm.burn(address(0), 95_000_000e9);

        // Alice claims 50k OHM (max for given circulating supply)
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();

        dai.approve(address(claimTransfer), 50_000e18);
        claimTransfer.claim(50_000e18);

        claimTransfer.approve(address(this), 5_000);
        vm.stopPrank();

        // transferFrom to bob
        claimTransfer.transferFrom(alice, bob, 5_000);

        // Bob tries to claim. Technically alice's claim increases the circulating supply so he's eligible to claim 250 OHM. We try to claim one above that.
        vm.startPrank(bob);
        dai.approve(address(claimTransfer), 251e18);

        bytes memory err = abi.encodeWithSignature("POLY_ClaimMoreThanVested(uint256)", 250e9);
        vm.expectRevert(err);

        claimTransfer.claim(251e18);
        vm.stopPrank();
    }

    function testCorrectness_transferFromUpdatesFractionalizedTerms() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        claimTransfer.approve(address(this), 1_000);
        vm.stopPrank();

        claimTransfer.transferFrom(alice, bob, 1_000);

        (uint256 percent, uint256 gClaimed, uint256 max) = claimTransfer.fractionalizedTerms(alice);
        assertEq(percent, 9_000);
        assertEq(gClaimed, 0);
        assertEq(max, 90_000e9);

        (percent, gClaimed, max) = claimTransfer.fractionalizedTerms(bob);
        assertEq(percent, 1_000);
        assertEq(gClaimed, 0);
        assertEq(max, 10_000e9);
    }

    function testCorrectness_transferFromReturnsTrue() public {
        vm.startPrank(alice);
        poly.pushWalletChange(address(claimTransfer));
        claimTransfer.fractionalizeClaim();
        claimTransfer.approve(address(this), 1_000);
        vm.stopPrank();

        assertEq(claimTransfer.transferFrom(alice, bob, 1_000), true);
    }
}
