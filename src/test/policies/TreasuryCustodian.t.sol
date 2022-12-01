// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {TreasuryCustodian} from "src/policies/TreasuryCustodian.sol";
import "src/Kernel.sol";

contract TreasuryCustodianTest is Test {
    address internal randomWallet;
    address internal guardian;

    Kernel internal kernel;

    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;
    TreasuryCustodian internal custodian;
    RolesAdmin internal rolesAdmin;

    MockERC20 public ngmi;

    function setUp() public {
        address[] memory users = (new UserFactory()).create(2);
        randomWallet = users[0];
        guardian = users[1];

        ngmi = new MockERC20("not gonna make it", "NGMI", 18);

        kernel = new Kernel(); // this contract will be the executor

        TRSRY = new OlympusTreasury(kernel);
        ROLES = new OlympusRoles(kernel);

        custodian = new TreasuryCustodian(kernel);
        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        kernel.executeAction(Actions.ActivatePolicy, address(custodian));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        /// Configure access control
        rolesAdmin.grantRole("custodian", guardian);
    }

    function test_UnauthorizedChangeDebt(uint256 amount_) public {
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("custodian")
        );
        vm.expectRevert(err);
        vm.prank(randomWallet);
        custodian.increaseDebt(ngmi, randomWallet, amount_);

        vm.expectRevert(err);
        vm.prank(randomWallet);
        custodian.decreaseDebt(ngmi, randomWallet, amount_);
    }

    function test_ChangeDebt(uint256 amount_) public {
        vm.prank(guardian);
        custodian.increaseDebt(ngmi, randomWallet, amount_);
        assertEq(TRSRY.reserveDebt(ngmi, randomWallet), amount_);
        assertEq(TRSRY.totalDebt(ngmi), amount_);

        vm.prank(guardian);
        custodian.decreaseDebt(ngmi, randomWallet, amount_);
        assertEq(TRSRY.reserveDebt(ngmi, randomWallet), 0);
        assertEq(TRSRY.totalDebt(ngmi), 0);
    }

    function test_GrantWithdrawerApproval(uint256 amount_) public {
        vm.prank(guardian);
        custodian.grantWithdrawerApproval(randomWallet, ngmi, amount_);
        assertEq(TRSRY.withdrawApproval(randomWallet, ngmi), amount_);
    }

    function test_GrantDebtorApproval(uint256 amount_) public {
        vm.prank(guardian);
        custodian.grantDebtorApproval(randomWallet, ngmi, amount_);
        assertEq(TRSRY.debtApproval(randomWallet, ngmi), amount_);
    }

    function test_RevokeOldPolicyApproval() public {
        uint256 amount = 100;

        // Use second custodian as dummy policy
        TreasuryCustodian dummyPolicy = new TreasuryCustodian(kernel);
        address dummy = address(dummyPolicy);

        kernel.executeAction(Actions.ActivatePolicy, dummy);

        vm.prank(guardian);
        custodian.grantWithdrawerApproval(dummy, ngmi, amount);
        assertEq(TRSRY.withdrawApproval(dummy, ngmi), amount);

        // deactivate second custodian to test approval revocation
        kernel.executeAction(Actions.DeactivatePolicy, dummy);
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = ngmi;

        vm.prank(guardian);
        custodian.revokePolicyApprovals(dummy, tokens);
        assertEq(TRSRY.withdrawApproval(dummy, ngmi), 0);
    }
}
