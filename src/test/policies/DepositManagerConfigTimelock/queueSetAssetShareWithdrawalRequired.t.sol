// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Revert-path calls deliberately ignore return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

// Libraries
import {DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockQueueSetAssetShareWithdrawalRequiredTest is
    DepositManagerConfigTimelockTest
{
    uint8 internal constant _TOKEN_DECIMALS = 18;

    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, DEPOSIT_MANAGER_ADMIN_ROLE)
        );
        vm.prank(caller_);
        _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);
    }

    function test_givenAdmin_whenCallingDepositManagerDirectly() public {
        vm.prank(ADMIN);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "direct admin requirement mismatch"
        );
    }

    function test_givenAdmin_whenRequirementIsQueued_executesAfterDelay() public {
        vm.prank(ADMIN);
        uint64 actionId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);
        _warpReady();

        _configTimelock.executeQueuedAction(actionId);

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "admin-queued requirement mismatch"
        );
    }

    function test_givenUnconfiguredAsset_reverts(address asset_, bool required_) public {
        vm.assume(asset_ != address(iAsset));

        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(IERC20(asset_), required_);
    }

    function test_givenIdleAsset_whenRequiredIsTrue_reverts() public {
        MockERC20 idleAsset = new MockERC20("Idle", "IDLE", _TOKEN_DECIMALS);
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(idleAsset)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(idleAsset)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(IERC20(address(idleAsset)), true);
    }

    function test_givenAsyncRedeemVault_whenRequiredIsFalse_reverts() public {
        MockERC20 asyncAsset = new MockERC20("Async", "ASYNC", _TOKEN_DECIMALS);
        MockERC7540ExternalShareVault asyncVault = new MockERC7540ExternalShareVault(
            asyncAsset,
            false,
            true,
            true
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(asyncAsset)),
            IERC4626(address(asyncVault)),
            type(uint256).max,
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(asyncAsset),
                address(asyncVault)
            )
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(IERC20(address(asyncAsset)), false);
    }

    function test_whenRequirementIsQueued_executesAfterDelay(
        bool required_,
        address executor_
    ) public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, required_);

        assertFalse(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "requirement changed before execution"
        );
        _warpReady();
        vm.prank(executor_);
        _configTimelock.executeQueuedAction(actionId);

        assertEq(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            required_,
            "executed requirement mismatch"
        );
    }

    function test_givenPendingRequirement_whenSameAssetIsQueuedAgain_reverts() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 owner = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, false);

        assertEq(_configTimelock.nextActionId(), owner + 1, "failed queue consumed action ID");
    }

    function test_givenQueuedRequirement_whenRequirementChanges_executionRevertsAsStale() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 actionId = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);

        vm.prank(address(_configTimelock));
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
        _warpReady();

        vm.expectPartialRevert(
            IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigStateChanged.selector
        );
        _configTimelock.executeQueuedAction(actionId);
    }

    function test_givenPendingRequirement_whenAssetPeriodChangeIsQueued_succeeds() public {
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 requirementActionId = _configTimelock.queueSetAssetShareWithdrawalRequired(
            iAsset,
            true
        );
        uint64 periodActionId = _queuePeriod(false);

        assertEq(
            periodActionId,
            requirementActionId + 1,
            "independent setting should use a separate key"
        );
    }

    function test_givenSecondAsset_requirementKeysAreIndependent() public {
        MockERC20 secondAsset = new MockERC20("Second", "SECOND", _TOKEN_DECIMALS);
        MockERC4626 secondVault = new MockERC4626(secondAsset, "Second Vault", "svSECOND");
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );

        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 first = _configTimelock.queueSetAssetShareWithdrawalRequired(iAsset, true);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        uint64 second = _configTimelock.queueSetAssetShareWithdrawalRequired(
            IERC20(address(secondAsset)),
            true
        );

        assertEq(second, first + 1, "different assets should have independent keys");
    }
}

// forge-lint: disable-end(unused-return)
