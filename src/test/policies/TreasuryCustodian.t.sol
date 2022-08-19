// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "src/Kernel.sol";

import {OlympusTreasury} from "src/modules/TRSRY.sol";
import {TreasuryCustodian} from "src/policies/TreasuryCustodian.sol";

contract TreasuryCustodianTest is Test {
    UserFactory public userCreator;
    address internal randomWallet;

    Kernel internal kernel;

    OlympusTreasury internal TRSRY;
    TreasuryCustodian internal custodian;

    MockERC20 public ngmi;

    function setUp() public {
        userCreator = new UserFactory();

        /// Create Voters
        address[] memory users = userCreator.create(2);
        randomWallet = users[0];

        ngmi = new MockERC20("not gonna make it", "NGMI", 18);

        /// Deploy kernel
        kernel = new Kernel(); // this contract will be the executor

        /// Deploy modules (some mocks)
        TRSRY = new OlympusTreasury(kernel);

        /// Deploy policies
        custodian = new TreasuryCustodian(kernel);

        /// Install modules
        kernel.executeAction(Actions.InstallModule, address(TRSRY));

        /// Approve policies`
        kernel.executeAction(Actions.ActivatePolicy, address(custodian));

        /// Configure access control
        kernel.grantRole(toRole("custodian"), address(this));
    }

    function test_UnauthorizedChangeDebt(uint256 amount_) public {
        bytes memory err = abi.encodeWithSelector(Policy_OnlyRole.selector, toRole("custodian"));
        vm.expectRevert(err);
        vm.prank(randomWallet);
        custodian.increaseDebt(ngmi, randomWallet, amount_);

        vm.expectRevert(err);
        vm.prank(randomWallet);
        custodian.decreaseDebt(ngmi, randomWallet, amount_);
    }

    function test_ChangeDebt(uint256 amount_) public {
        custodian.increaseDebt(ngmi, randomWallet, amount_);
        assertEq(TRSRY.reserveDebt(ngmi, randomWallet), amount_);
        assertEq(TRSRY.totalDebt(ngmi), amount_);

        custodian.decreaseDebt(ngmi, randomWallet, amount_);
        assertEq(TRSRY.reserveDebt(ngmi, randomWallet), 0);
        assertEq(TRSRY.totalDebt(ngmi), 0);
    }

    function test_GrantApproval(uint256 amount_) public {
        custodian.grantApproval(randomWallet, ngmi, amount_);
        assertEq(TRSRY.withdrawApproval(randomWallet, ngmi), amount_);
    }

    function test_RevokeOldPolicyApproval() public {
        uint256 amount = 100;

        // Use second custodian as dummy policy
        TreasuryCustodian dummyPolicy = new TreasuryCustodian(kernel);
        address dummy = address(dummyPolicy);

        kernel.executeAction(Actions.ActivatePolicy, dummy);

        custodian.grantApproval(dummy, ngmi, amount);
        assertEq(TRSRY.withdrawApproval(dummy, ngmi), amount);

        // deactivate second custodian to test approval revocation
        kernel.executeAction(Actions.DeactivatePolicy, dummy);
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = ngmi;

        custodian.revokePolicyApprovals(dummy, tokens);
        assertEq(TRSRY.withdrawApproval(dummy, ngmi), 0);
    }
}
