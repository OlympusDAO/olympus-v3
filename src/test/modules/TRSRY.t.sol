// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
//import {MockPolicy} from "test/mocks/KernelTestMocks.sol";

import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

import "src/Kernel.sol";

contract TRSRYTest is Test {
    using ModuleTestFixtureGenerator for OlympusTreasury;

    Kernel internal kernel;
    OlympusTreasury public TRSRY;
    MockERC20 public ngmi;
    address public testUser;
    address public godmode;
    address public debtor;

    uint256 internal constant INITIAL_TOKEN_AMOUNT = 100e18;

    function setUp() public {
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);
        ngmi = new MockERC20("not gonna make it", "NGMI", 18);
        kernel.executeAction(Actions.InstallModule, address(TRSRY));

        // Generate test fixture policy addresses with different authorizations
        godmode = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        testUser = TRSRY.generateFunctionFixture(TRSRY.withdrawReserves.selector);
        kernel.executeAction(Actions.ActivatePolicy, testUser);

        debtor = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);
        kernel.executeAction(Actions.ActivatePolicy, debtor);

        // Give TRSRY some tokens
        ngmi.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
    }

    function testCorrectness_KEYCODE() public {
        assertEq32("TRSRY", Keycode.unwrap(TRSRY.KEYCODE()));
    }

    function testCorrectness_IncreaseWithdrawApproval(uint256 amount_) public {
        vm.prank(godmode);
        TRSRY.increaseWithdrawApproval(testUser, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(testUser, ngmi), amount_);
    }

    function testCorrectness_DecreaseWithdrawApproval(uint256 amount_) public {
        vm.prank(godmode);
        TRSRY.increaseWithdrawApproval(testUser, ngmi, amount_);

        vm.prank(godmode);
        TRSRY.decreaseWithdrawApproval(testUser, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(testUser, ngmi), 0);
    }

    function testCorrectness_GetReserveBalance() public {
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function testCorrectness_ApprovedCanWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        vm.prank(godmode);
        TRSRY.increaseWithdrawApproval(testUser, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(testUser, ngmi), amount_);

        vm.prank(testUser);
        TRSRY.withdrawReserves(address(this), ngmi, amount_);

        assertEq(ngmi.balanceOf(address(this)), amount_);
    }

    // TODO test if can withdraw more than allowed amount
    //function testRevert_WithdrawMoreThanApproved(uint256 amount_) public {}

    function testRevert_UnauthorizedCannotWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        // Fail when withdrawal using policy without write access
        vm.expectRevert();
        vm.prank(testUser);
        TRSRY.withdrawReserves(address(this), ngmi, amount_);
    }

    function testCorrectness_IncurDebt(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(debtor, ngmi, amount_);

        vm.prank(debtor);
        TRSRY.incurDebt(ngmi, amount_);

        assertEq(ngmi.balanceOf(debtor), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), amount_);
        assertEq(TRSRY.totalDebt(ngmi), amount_);

        // Reserve balance should remain the same, since we withdrew as debt
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function testRevert_UnauthorizedCannotIncurDebt(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        address unapprovedPolicy = address(0x0);

        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(unapprovedPolicy, ngmi, amount_);

        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            unapprovedPolicy
        );
        vm.expectRevert(err);
        vm.prank(unapprovedPolicy);
        TRSRY.incurDebt(ngmi, amount_);
    }

    function testCorrectness_RepayDebt(uint256 amount_) public {
        vm.assume(amount_ > 0);
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(debtor, ngmi, amount_);

        vm.startPrank(debtor);
        TRSRY.incurDebt(ngmi, amount_);

        assertEq(ngmi.balanceOf(debtor), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), amount_);

        // Repay loan
        ngmi.approve(address(TRSRY), amount_);
        TRSRY.repayDebt(debtor, ngmi, amount_);
        vm.stopPrank();

        assertEq(ngmi.balanceOf(debtor), 0);
    }

    function testCorrectness_SetDebt() public {
        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(debtor, ngmi, INITIAL_TOKEN_AMOUNT);

        vm.prank(debtor);
        TRSRY.incurDebt(ngmi, INITIAL_TOKEN_AMOUNT);

        // Change the debt amount of the debtor to half
        vm.prank(godmode);
        TRSRY.setDebt(debtor, ngmi, INITIAL_TOKEN_AMOUNT / 2);

        assertEq(TRSRY.reserveDebt(ngmi, debtor), INITIAL_TOKEN_AMOUNT / 2);
        assertEq(TRSRY.totalDebt(ngmi), INITIAL_TOKEN_AMOUNT / 2);
    }

    function testRevert_UnauthorizedPolicyCannotSetDebt() public {
        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(debtor, ngmi, INITIAL_TOKEN_AMOUNT);

        vm.prank(debtor);
        TRSRY.incurDebt(ngmi, INITIAL_TOKEN_AMOUNT);

        // Fail when calling setDebt from testUser (policy without setDebt permissions)
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            testUser
        );
        vm.expectRevert(err);
        vm.prank(testUser);
        TRSRY.setDebt(debtor, ngmi, INITIAL_TOKEN_AMOUNT / 2);
    }

    function testCorrectness_ClearDebt() public {
        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(debtor, ngmi, INITIAL_TOKEN_AMOUNT);

        vm.prank(debtor);
        TRSRY.incurDebt(ngmi, INITIAL_TOKEN_AMOUNT);

        assertEq(TRSRY.reserveDebt(ngmi, debtor), INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.totalDebt(ngmi), INITIAL_TOKEN_AMOUNT);

        vm.prank(godmode);
        TRSRY.setDebt(debtor, ngmi, 0);

        assertEq(TRSRY.reserveDebt(ngmi, debtor), 0);
        assertEq(TRSRY.totalDebt(ngmi), 0);
    }

    function testCorrectness_Shutdown(uint256 amount_) public {
        vm.assume(amount_ != 0);
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        // Approve test fixture to withdraw and incurdebt for amount_
        vm.prank(godmode);
        TRSRY.increaseWithdrawApproval(godmode, ngmi, amount_);

        vm.prank(godmode);
        TRSRY.increaseDebtorApproval(debtor, ngmi, amount_);

        // Shutdown the TRSRY
        vm.prank(godmode);
        TRSRY.deactivate();

        // Try to withdraw amount_ and expect revert
        bytes memory err = abi.encodeWithSignature("TRSRY_NotActive()");
        vm.expectRevert(err);
        vm.prank(godmode);
        TRSRY.withdrawReserves(godmode, ngmi, amount_);

        // Try to incur debt and expect revert
        vm.expectRevert(err);
        vm.prank(debtor);
        TRSRY.incurDebt(ngmi, amount_);

        assertEq(ngmi.balanceOf(godmode), 0);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), 0);
        assertEq(ngmi.balanceOf(debtor), 0);

        // Reactivate the system
        vm.prank(godmode);
        TRSRY.activate();

        // Withdraw amount_
        vm.prank(godmode);
        TRSRY.withdrawReserves(godmode, ngmi, amount_);
        assertEq(ngmi.balanceOf(godmode), amount_);

        // Transfer tokens back to TRSRY and incur debt
        vm.prank(godmode);
        ngmi.transfer(address(TRSRY), amount_);

        vm.prank(debtor);
        TRSRY.incurDebt(ngmi, amount_);
        assertEq(ngmi.balanceOf(debtor), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), amount_);

        // Repay loan
        vm.prank(debtor);
        ngmi.approve(address(TRSRY), amount_);
        vm.prank(debtor);
        TRSRY.repayDebt(debtor, ngmi, amount_);

        assertEq(ngmi.balanceOf(debtor), 0);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), 0);
    }

    function testRevert_AddressWithPermCannotShutdownOrRestart() public {
        // Check status of TRSRY
        assertEq(TRSRY.active(), true);

        // Try to deactivate with non-approved user
        bytes memory err = abi.encodeWithSelector(
            Module.Module_PolicyNotPermitted.selector,
            testUser
        );
        vm.expectRevert(err);
        vm.prank(testUser);
        TRSRY.deactivate();

        assertEq(TRSRY.active(), true);

        // Deactivate with approved user
        vm.prank(godmode);
        TRSRY.deactivate();

        assertEq(TRSRY.active(), false);

        // Call deactivate again and expect nothing to happen since it's already deactivated
        vm.prank(godmode);
        TRSRY.deactivate();

        assertEq(TRSRY.active(), false);

        // Try to reactivate with non-approved user
        vm.expectRevert(err);
        vm.prank(testUser);
        TRSRY.activate();

        assertEq(TRSRY.active(), false);

        // Reactivate with approved user
        vm.prank(godmode);
        TRSRY.activate();

        assertEq(TRSRY.active(), true);

        // Call activate again and expect nothing to happen since it's already activated
        vm.prank(godmode);
        TRSRY.activate();

        assertEq(TRSRY.active(), true);
    }
}
