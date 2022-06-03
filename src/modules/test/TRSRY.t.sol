// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/sorting.sol";
import "test-utils/errors.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OlympusTreasury} from "src/modules/TRSRY.sol";
import {LarpKernel} from "../../test/larps/LarpKernel.sol";
import {OlympusERC20Token} from "../../external/OlympusERC20.sol";

contract TRSRYTest is Test {
    using larping for *;
    using sorting for uint256[];

    LarpKernel internal kernel;
    OlympusTreasury public TRSRY;
    MockERC20 public ngmi;
    MockERC20 public dn;
    UserFactory public userCreator;
    address public policyOne;
    address public policyTwo;

    uint256 internal constant INITIAL_TOKEN_AMOUNT = 100e18;

    function setUp() public {
        kernel = new LarpKernel();
        TRSRY = new OlympusTreasury(kernel);
        ngmi = new MockERC20("NOT GONNA MAKE IT", "NGMI", 18);
        dn = new MockERC20("DEEZ NUTZ", "DN", 18);

        userCreator = new UserFactory();
        address[] memory usrs = userCreator.create(3);
        policyOne = usrs[0];
        policyTwo = usrs[1];

        kernel.installModule(address(TRSRY));
        // Approve addresses as policy with write permissions
        kernel.grantWritePermissions(TRSRY.KEYCODE(), address(this));
        kernel.grantWritePermissions(TRSRY.KEYCODE(), policyOne);

        // Give TRSRY some tokens
        ngmi.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
        dn.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
    }

    function test_KEYCODE() public {
        assertEq32("TRSRY", TRSRY.KEYCODE());
    }

    function test_WithdrawApproval(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(policyOne, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(policyOne, ngmi), amount_);
    }

    // TODO test revoke approval

    function test_GetReserveBalance() public {
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function test_AuthorizedCanWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(policyOne, ngmi, amount_);

        vm.prank(policyOne);
        TRSRY.withdrawReserves(ngmi, amount_);

        assertEq(ngmi.balanceOf(policyOne), amount_);
    }

    // TODO test if can withdraw more than allowed amount

    function test_UnauthorizedCannotWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        bytes memory err = abi.encodeWithSelector(
            TRSRY.TRSRY_NotApproved.selector
        );
        vm.expectRevert(err);

        vm.prank(policyTwo);
        TRSRY.withdrawReserves(ngmi, amount_);
    }

    // TODO test debt functions

    function test_LoanReserves(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        // Ensure there is sufficient reserves in the treasury
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(policyOne, ngmi, amount_);

        vm.prank(policyOne);
        TRSRY.loanReserves(ngmi, amount_);

        assertEq(ngmi.balanceOf(policyOne), amount_);
        assertEq(TRSRY.reserveDebt(ngmi, policyOne), amount_);
        assertEq(TRSRY.totalDebt(ngmi), amount_);

        // Reserve balance should remain the same, since we withdrew as debt
        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);
    }

    function test_RepayLoan(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        assertEq(TRSRY.getReserveBalance(ngmi), INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(policyOne, ngmi, amount_);

        vm.startPrank(policyOne);
        TRSRY.loanReserves(ngmi, amount_);

        // Repay loan
        ngmi.approve(address(TRSRY), amount_);
        TRSRY.repayLoan(ngmi, amount_);

        vm.stopPrank();

        assertEq(ngmi.balanceOf(policyOne), 0);
    }

    // TODO test setDebt and clearDebt

    function test_SetDebt(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        vm.startPrank();
    }
}
