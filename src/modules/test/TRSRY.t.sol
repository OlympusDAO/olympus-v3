// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/sorting.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OlympusTreasury} from "src/modules/TRSRY.sol";
import {LarpKernel} from "../../test/larps/LarpKernel.sol";
import {OlympusERC20Token} from "../../external/OlympusERC20.sol";

contract TRSRYTest is Test {
    using larping for *;
    using sorting for uint256[];

    LarpKernel internal kernel;
    OlympusTreasury TRSRY;
    MockERC20 ngmi;
    MockERC20 dn;
    UserFactory userCreator;
    address alice;
    address bob;

    uint256 constant INITIAL_TOKEN_AMOUNT = 100e18;

    function setUp() public {
        kernel = new LarpKernel();
        TRSRY = new OlympusTreasury(kernel);
        ngmi = new MockERC20("NOT GONNA MAKE IT", "NGMI", 18);
        dn = new MockERC20("DEEZ NUTZ", "DN", 18);

        userCreator = new UserFactory();
        address[] memory usrs = userCreator.create(2);
        alice = usrs[0];
        bob = usrs[1];

        kernel.installModule(address(TRSRY));
        // Approve addresses as policy with write permissions
        kernel.grantWritePermissions(TRSRY.KEYCODE(), address(this));
        kernel.grantWritePermissions(TRSRY.KEYCODE(), alice);

        // Treasury setup
        TRSRY.declareReserve(ngmi);
        TRSRY.declareReserve(dn);

        // Give TRSRY some tokens
        ngmi.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
        dn.mint(address(TRSRY), INITIAL_TOKEN_AMOUNT);
    }

    function test_KEYCODE() public {
        assertEq32("TRSRY", TRSRY.KEYCODE());
    }

    function test_WithdrawApproval(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(alice, ngmi, amount_);

        assertEq(TRSRY.withdrawApproval(alice, ngmi), amount_);
    }

    function test_AuthorizedCanWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        TRSRY.requestApprovalFor(alice, ngmi, amount_);

        vm.prank(alice);
        TRSRY.withdrawReserves(ngmi, amount_);

        assertEq(ngmi.balanceOf(alice), amount_);
    }

    // TODO test if can withdraw more than allowed amount

    function testFail_UnauthorizedCannotWithdrawToken(uint256 amount_) public {
        vm.assume(amount_ < INITIAL_TOKEN_AMOUNT);

        vm.prank(bob);
        TRSRY.withdrawReserves(ngmi, amount_);
    }
}
