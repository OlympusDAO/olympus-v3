// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetConfigOperatorTest is BurnerLoansTest {
    // setConfigOperator
    // given caller does not have the admin role
    //  when setConfigOperator is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoansConfig.setConfigOperator(makeAddr("newConfigOperator"));
    }

    // setConfigOperator
    // given the policy is disabled
    //  when setConfigOperator is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setConfigOperator(makeAddr("newConfigOperator"));
    }

    // setConfigOperator
    // given the config operator address is zero
    //  when setConfigOperator is called by admin
    //   then it revokes delegated access
    function test_givenZeroAddress_clearsConfigOperator() public {
        vm.startPrank(admin);
        burnerLoansConfig.setConfigOperator(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit IBurnerLoansConfig.ConfigOperatorSet(address(0));
        burnerLoansConfig.setConfigOperator(address(0));
        vm.stopPrank();

        assertEq(burnerLoansConfig.configOperator(), address(0), "config operator cleared");
    }

    // setConfigOperator
    // given the config operator address is zero
    //  when an arbitrary non-zero, non-admin address calls a delegated setter
    //   then every delegated action reverts with the caller address
    function test_givenZeroConfigOperator_arbitraryCallerCannotExecuteActions(
        address caller_
    ) public {
        // address(0) cannot be msg.sender for a real transaction or contract call.
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != admin);

        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(0));

        bytes memory expectedRevert = abi.encodeWithSelector(
            IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
            caller_
        );
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        vm.startPrank(caller_);
        vm.expectRevert(expectedRevert);
        burnerLoansConfig.setAssetDebtCap(address(usds), 1);

        vm.expectRevert(expectedRevert);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.expectRevert(expectedRevert);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);

        vm.expectRevert(expectedRevert);
        burnerLoansConfig.setAssetFeeConfig(address(usds), feeConfig);
        vm.stopPrank();

        assertEq(burnerLoansConfig.configOperator(), address(0), "config operator remains cleared");
    }

    // setConfigOperator
    // given the config operator is not a policy
    //  when setConfigOperator is called by admin
    //   then it stores the arbitrary address
    function test_givenConfigOperatorIsNotPolicy_setsConfigOperator() public {
        address newConfigOperator = makeAddr("nonPolicyConfigOperator");

        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(newConfigOperator);

        assertEq(burnerLoansConfig.configOperator(), newConfigOperator, "config operator");
    }

    // setConfigOperator
    // given a non-zero config operator address
    //  when setConfigOperator is called by admin
    //   then it stores the config operator
    function test_givenAdminCaller_setsConfigOperator() public {
        address newConfigOperator = address(configTimelock);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit IBurnerLoansConfig.ConfigOperatorSet(newConfigOperator);
        burnerLoansConfig.setConfigOperator(newConfigOperator);

        assertEq(burnerLoansConfig.configOperator(), newConfigOperator, "config operator");
    }
}
