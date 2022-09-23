// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OlympusERC20Token} from "src/external/OlympusERC20.sol";
import {MockPolicy} from "test/mocks/KernelTestMocks.sol";

import "src/modules/TRSRY.sol";
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

        address[] memory users = (new UserFactory()).create(3);
        testUser = users[0];

        kernel.executeAction(Actions.InstallModule, address(TRSRY));

        // Generate test fixture policy addresses with different authorizations
        godmode = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);
        kernel.executeAction(Actions.ActivatePolicy, godmode);

        debtor = TRSRY.generateFunctionFixture(TRSRY.getLoan.selector);
        kernel.executeAction(Actions.ActivatePolicy, debtor);

        // Give TRSRY some tokens
        ngmi.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
    }

    function testCorrectness_KEYCODE() public {
        assertEq32("TRSRY", Keycode.unwrap(TRSRY.KEYCODE()));
    }

    function testCorrectness_WithdrawApproval(uint256 amount_) public {
        vm.prank(godmode);
        TRSRY.setApprovalFor(testUser, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(testUser, ngmi), amount_);
    }

    /*
    function testCorrectness_RevokeApprovals() public {
        TRSRY.setApprovalFor(testUser, ngmi, INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.withdrawApproval(testUser, ngmi), INITIAL_TOKEN_AMOUNT);

        ERC20[] memory revokeTokens = new ERC20[](2);
        revokeTokens[0] = ERC20(ngmi);

        kernel.executeAction(Actions.DeactivatePolicy, address(this));

        TRSRY.revokeApprovals(testUser, revokeTokens);
        assertEq(TRSRY.withdrawApproval(testUser, ngmi), 0);
    }
    */

    function testCorrectness_GetReserveBalance() public {
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function testCorrectness_ApprovedCanWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        vm.prank(godmode);
        TRSRY.setApprovalFor(testUser, ngmi, amount_);

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
        vm.expectRevert(TRSRY_NotApproved.selector);
        vm.prank(testUser);
        TRSRY.withdrawReserves(address(this), ngmi, amount_);
    }

    function testCorrectness_GetLoan(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        vm.prank(godmode);
        TRSRY.setApprovalFor(debtor, ngmi, amount_);

        vm.prank(debtor);
        TRSRY.getLoan(ngmi, amount_);

        assertEq(ngmi.balanceOf(debtor), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), amount_);
        assertEq(TRSRY.totalDebt(ngmi), amount_);

        // Reserve balance should remain the same, since we withdrew as debt
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function testRevert_UnauthorizedCannotGetLoan(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        address unapprovedPolicy = address(new MockPolicy(kernel));

        vm.prank(godmode);
        TRSRY.setApprovalFor(unapprovedPolicy, ngmi, amount_);

        bytes memory err = abi.encodeWithSelector(
            Module_PolicyNotPermitted.selector,
            unapprovedPolicy
        );
        vm.expectRevert(err);
        vm.prank(unapprovedPolicy);
        TRSRY.getLoan(ngmi, amount_);
    }

    function testCorrectness_RepayLoan(uint256 amount_) public {
        vm.assume(amount_ > 0);
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        vm.prank(godmode);
        TRSRY.setApprovalFor(debtor, ngmi, amount_);

        vm.startPrank(debtor);
        TRSRY.getLoan(ngmi, amount_);

        assertEq(ngmi.balanceOf(debtor), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, debtor), amount_);

        // Repay loan
        ngmi.approve(address(TRSRY), amount_);
        TRSRY.repayLoan(ngmi, amount_);
        vm.stopPrank();

        assertEq(ngmi.balanceOf(debtor), 0);
    }

    // TODO test RepayLoan with no loan outstanding. should revert

    function testCorrectness_SetDebt() public {
        vm.prank(godmode);
        TRSRY.setApprovalFor(debtor, ngmi, INITIAL_TOKEN_AMOUNT);

        vm.prank(debtor);
        TRSRY.getLoan(ngmi, INITIAL_TOKEN_AMOUNT);

        // Change the debt amount of the debtor to half
        vm.prank(godmode);
        TRSRY.setDebt(ngmi, debtor, INITIAL_TOKEN_AMOUNT / 2);

        assertEq(TRSRY.reserveDebt(ngmi, debtor), INITIAL_TOKEN_AMOUNT / 2);
        assertEq(TRSRY.totalDebt(ngmi), INITIAL_TOKEN_AMOUNT / 2);
    }

    function testRevert_UnauthorizedPolicyCannotSetDebt() public {
        vm.prank(godmode);
        TRSRY.setApprovalFor(debtor, ngmi, INITIAL_TOKEN_AMOUNT);

        vm.prank(debtor);
        TRSRY.getLoan(ngmi, INITIAL_TOKEN_AMOUNT);

        // Fail when calling setDebt from debtor (policy without setDebt permissions)
        bytes memory err = abi.encodeWithSelector(Module_PolicyNotPermitted.selector, debtor);
        vm.expectRevert(err);
        vm.prank(debtor);
        TRSRY.setDebt(ngmi, debtor, INITIAL_TOKEN_AMOUNT / 2);
    }

    function testCorrectness_ClearDebt() public {
        vm.prank(godmode);
        TRSRY.setApprovalFor(debtor, ngmi, INITIAL_TOKEN_AMOUNT);

        vm.prank(debtor);
        TRSRY.getLoan(ngmi, INITIAL_TOKEN_AMOUNT);

        assertEq(TRSRY.reserveDebt(ngmi, debtor), INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.totalDebt(ngmi), INITIAL_TOKEN_AMOUNT);

        vm.prank(godmode);
        TRSRY.setDebt(ngmi, debtor, 0);

        assertEq(TRSRY.reserveDebt(ngmi, debtor), 0);
        assertEq(TRSRY.totalDebt(ngmi), 0);
    }
}
