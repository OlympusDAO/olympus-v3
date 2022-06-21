// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/sorting.sol";
import "test-utils/errors.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "src/modules/TRSRY.sol";
import "src/Kernel.sol";
import {OlympusERC20Token} from "../../external/OlympusERC20.sol";
import {MockModuleWriter} from "../mocks/MockModuleWriter.sol";

contract TRSRYTest is Test {
    using larping for *;
    using errors for bytes4;

    Kernel internal kernel;
    OlympusTreasury public TRSRY;
    MockERC20 public ngmi;
    MockERC20 public dn;
    address public testUser;
    MockModuleWriter public testPolicy;

    uint256 internal constant INITIAL_TOKEN_AMOUNT = 100e18;

    function setUp() public {
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);
        ngmi = new MockERC20("not gonna make it", "NGMI", 18);
        dn = new MockERC20("deez nutz", "DN", 18);

        address[] memory users = (new UserFactory()).create(3);
        testUser = users[0];

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.ApprovePolicy, address(this));

        // Give TRSRY some tokens
        ngmi.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
        dn.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
    }

    function configureReads() external {}

    // Needed to allow this contract to be used as a policy with full access to module
    function requestRoles()
        external
        view
        returns (Kernel.Role[] memory requests)
    {
        requests = TRSRY.ROLES();
    }

    function test_KEYCODE() public {
        assertEq32("TRSRY", Kernel.Keycode.unwrap(TRSRY.KEYCODE()));
    }

    function test_ROLES() public {
        assertEq("TRSRY_Approver", Kernel.Role.unwrap(TRSRY.ROLES()[0]));
        assertEq("TRSRY_Banker", Kernel.Role.unwrap(TRSRY.ROLES()[1]));
        assertEq("TRSRY_DebtAdmin", Kernel.Role.unwrap(TRSRY.ROLES()[2]));
    }

    function test_WithdrawApproval(uint256 amount_) public {
        TRSRY.requestApprovalFor(testUser, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(testUser, ngmi), amount_);
    }

    function test_RevokeApprovals() public {
        TRSRY.requestApprovalFor(testUser, ngmi, INITIAL_TOKEN_AMOUNT);
        TRSRY.requestApprovalFor(testUser, dn, INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.withdrawApproval(testUser, ngmi), INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.withdrawApproval(testUser, dn), INITIAL_TOKEN_AMOUNT);

        ERC20[] memory revokeTokens = new ERC20[](2);
        revokeTokens[0] = ERC20(ngmi);
        revokeTokens[1] = ERC20(dn);

        kernel.executeAction(Actions.TerminatePolicy, address(this));

        TRSRY.revokeApprovals(testUser, revokeTokens);
        assertEq(TRSRY.withdrawApproval(testUser, ngmi), 0);
        assertEq(TRSRY.withdrawApproval(testUser, dn), 0);
    }

    function test_GetReserveBalance() public {
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.getReserveBalance(dn), INITIAL_TOKEN_AMOUNT);
    }

    function test_AuthorizedCanWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        TRSRY.requestApprovalFor(testUser, ngmi, amount_);

        vm.prank(testUser);
        TRSRY.withdrawReserves(address(this), ngmi, amount_);

        assertEq(ngmi.balanceOf(address(this)), amount_);
    }

    // TODO test if can withdraw more than allowed amount

    function test_UnauthorizedCannotWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        // Fail when withdrawal using policy without write access
        vm.expectRevert(TRSRY_NotApproved.selector);
        vm.prank(testUser);
        TRSRY.withdrawReserves(address(this), ngmi, amount_);
    }

    // TODO test debt functions

    function test_LoanReserves(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        // Ensure there is sufficient reserves in the treasury
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(address(this), ngmi, amount_);

        //vm.prank(testUser);
        TRSRY.loanReserves(ngmi, amount_);

        assertEq(ngmi.balanceOf(address(this)), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, address(this)), amount_);
        assertEq(TRSRY.totalDebt(ngmi), amount_);

        // Reserve balance should remain the same, since we withdrew as debt
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function test_UnauthorizedCannotLoanReserves(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);
        vm.assume(amount_ > 0);

        TRSRY.requestApprovalFor(testUser, ngmi, amount_);

        // Fail when withdrawal using policy without write access
        vm.expectRevert(Module_NotAuthorized.selector);
        vm.prank(testUser);
        TRSRY.loanReserves(ngmi, amount_);
    }

    function test_RepayLoan(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(address(this), ngmi, amount_);

        //vm.startPrank(testUser); // TODO need to test with permissioned policy
        TRSRY.loanReserves(ngmi, amount_);

        // Repay loan
        ngmi.approve(address(TRSRY), amount_);
        TRSRY.repayLoan(ngmi, amount_);

        //vm.stopPrank();

        assertEq(ngmi.balanceOf(testUser), 0);
    }

    // TODO test setDebt and clearDebt

    function test_SetDebt() public {
        TRSRY.requestApprovalFor(address(this), ngmi, INITIAL_TOKEN_AMOUNT / 2);
        TRSRY.loanReserves(ngmi, INITIAL_TOKEN_AMOUNT / 2);

        TRSRY.setDebt(ngmi, address(this), INITIAL_TOKEN_AMOUNT / 4);

        assertEq(
            TRSRY.reserveDebt(ngmi, address(this)),
            INITIAL_TOKEN_AMOUNT / 4
        );
        assertEq(TRSRY.totalDebt(ngmi), INITIAL_TOKEN_AMOUNT / 4);
    }

    function test_UnauthorizedCannotSetDebt() public {
        TRSRY.requestApprovalFor(address(this), ngmi, INITIAL_TOKEN_AMOUNT / 2);
        TRSRY.loanReserves(ngmi, INITIAL_TOKEN_AMOUNT / 2);

        // Fail when setDebt using policy without write access
        vm.expectRevert(Module_NotAuthorized.selector);
        vm.prank(testUser);
        TRSRY.setDebt(ngmi, address(this), INITIAL_TOKEN_AMOUNT / 4);
    }

    function test_ClearDebt(uint256 amount_) public {
        TRSRY.requestApprovalFor(address(this), ngmi, INITIAL_TOKEN_AMOUNT);
        TRSRY.loanReserves(ngmi, INITIAL_TOKEN_AMOUNT);

        assertEq(TRSRY.reserveDebt(ngmi, address(this)), INITIAL_TOKEN_AMOUNT);
        assertEq(TRSRY.totalDebt(ngmi), INITIAL_TOKEN_AMOUNT);

        TRSRY.clearDebt(ngmi, address(this), INITIAL_TOKEN_AMOUNT);

        assertEq(TRSRY.reserveDebt(ngmi, address(this)), 0);
        assertEq(TRSRY.totalDebt(ngmi), 0);
    }

    function test_UnauthorizedCannotClearDebt() public {
        TRSRY.requestApprovalFor(address(this), ngmi, INITIAL_TOKEN_AMOUNT);
        TRSRY.loanReserves(ngmi, INITIAL_TOKEN_AMOUNT);

        // Fail when clearDebt using policy without write access
        vm.expectRevert(Module_NotAuthorized.selector);
        vm.prank(testUser);
        TRSRY.clearDebt(ngmi, address(this), INITIAL_TOKEN_AMOUNT);
    }
}
