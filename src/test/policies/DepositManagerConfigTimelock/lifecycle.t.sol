// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockLifecycleTest is DepositManagerConfigTimelockTest {
    function test_givenDepositManagerIsInactive_enableReverts() public {
        DepositManager inactiveDepositManager = new DepositManager(
            address(kernel),
            address(receiptTokenManager)
        );
        DepositManagerConfigTimelock inactiveTargetTimelock = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(inactiveDepositManager))
        );
        vm.prank(ADMIN);
        kernel.executeAction(Actions.ActivatePolicy, address(inactiveTargetTimelock));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(inactiveDepositManager)
            )
        );
        vm.prank(ADMIN);
        inactiveTargetTimelock.enable("");
    }

    function test_givenTimelockIsDisabled_queueReverts() public {
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    function test_givenDepositManagerIsDisabled_queueReverts() public {
        vm.prank(EMERGENCY);
        depositManager.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    function test_givenTimelockPolicyIsInactive_queueReverts() public {
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(_configTimelock));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(_configTimelock)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    function test_givenDepositManagerPolicyIsInactive_queueReverts() public {
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_PolicyInactive.selector,
                address(depositManager)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    function test_givenConfigOperatorChanged_queueReverts() public {
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    function test_givenConfigOperatorChanged_executionReverts() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        _warpReady();

        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_configTimelock)
            )
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenConfigOperatorChangedAwayAndBack_executionSucceeds() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.startPrank(ADMIN);
        depositManager.setConfigOperator(CONFIG_OPERATOR);
        depositManager.setConfigOperator(address(_configTimelock));
        vm.stopPrank();
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "restored operator should permit queued execution"
        );
    }

    function test_givenTimelockIsReEnabled_queuesAndExecutes() public {
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();

        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        _warpReady();
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            100e18,
            "re-enabled timelock should remain operational"
        );
    }

    function test_givenQueuedAction_emergencyCancelsWhileDisabled() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.prank(EMERGENCY);
        _configTimelock.cancelQueuedAction(actionId);

        assertTrue(
            _configTimelock.getQueuedAction(actionId).cancelled,
            "emergency should cancel while disabled"
        );
    }

    function test_givenDepositManagerBecomesInactive_reEnableReverts() public {
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        vm.stopPrank();
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                address(depositManager)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
