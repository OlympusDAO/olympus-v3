// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Libraries
import {DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueLimitsTest is DepositManagerConfigTimelockTest {
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
        vm.prank(caller_);
        _configTimelock.queueSetAssetDepositCap(iAsset, 100e18);
    }

    function test_givenUnconfiguredAsset_reverts(address asset_) public {
        vm.assume(asset_ != address(iAsset));

        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(IERC20(asset_), 100e18);
    }

    function test_whenDepositCapIsBelowMinimum_reverts() public {
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                2,
                1
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetDepositCap(iAsset, 1);
    }

    function test_whenMinimumDepositExceedsCap_reverts() public {
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                2,
                1
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetMinimumDeposit(iAsset, 2);
    }

    function test_givenDepositManagerAdmin_queuesAndExecutesDepositCap(
        address executor_,
        uint128 cap_
    ) public {
        uint64 actionId = _queueDepositCap(iAsset, cap_);
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            cap_,
            "permissionless execution should set deposit cap"
        );
    }

    function test_givenDepositManagerAdmin_queuesAndExecutesMinimumDeposit(
        address executor_,
        uint128 minimumDeposit_
    ) public {
        uint64 actionId = _queueMinimumDeposit(iAsset, minimumDeposit_);
        _warpReady();

        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).minimumDeposit,
            minimumDeposit_,
            "permissionless execution should set minimum deposit"
        );
    }

    function test_whenDepositCapIsUint256Max_queuesAndExecutes() public {
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 1);
        uint64 actionId = _queueDepositCap(iAsset, type(uint256).max);
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            type(uint256).max,
            "maximum deposit cap mismatch"
        );
    }

    function test_whenMinimumDepositIsUint256Max_queuesAndExecutes() public {
        uint64 actionId = _queueMinimumDeposit(iAsset, type(uint256).max);
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.getAssetConfiguration(iAsset).minimumDeposit,
            type(uint256).max,
            "maximum minimum deposit mismatch"
        );
    }

    function test_givenPendingCap_whenMinimumIsQueuedForSameAsset_reverts() public {
        uint64 owner = _queueDepositCap(iAsset, 100e18);

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetMinimumDeposit(iAsset, 1e18);

        assertEq(_configTimelock.nextActionId(), owner + 1, "failed queue should not consume id");
    }

    function test_givenPendingCap_whenMinimumIsQueuedForAnotherAsset_succeeds() public {
        MockERC20 secondAsset = new MockERC20("Second", "SECOND", 18);
        MockERC4626 secondVault = new MockERC4626(secondAsset, "Second Vault", "svSECOND");
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );

        uint64 first = _queueDepositCap(iAsset, 100e18);
        uint64 second = _queueMinimumDeposit(IERC20(address(secondAsset)), 1e18);

        assertEq(second, first + 1, "different assets should have independent limit keys");
    }

    function test_givenQueuedCap_whenMinimumChanges_executionRevertsAsStale() public {
        uint64 actionId = _queueDepositCap(iAsset, 100e18);
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, 1);
        _warpReady();

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        _configTimelock.executeQueuedAction(actionId);
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
