// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Revert-path calls assert exact revert data instead of consuming return values.
// forge-lint: disable-start(unused-return)

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetAssetWithdrawAsSharesTest is
    BurnerLoansConfigTimelockTest
{
    event AssetWithdrawAsSharesSet(address indexed asset, bool withdrawAsShares);

    function _useAsyncMockVaultInShareMode() internal {
        _useMockDepositManager();
        _configureUsdsVaultDependencies();
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
        mockDepositManager.setAssetAsyncRedeem(IERC20(address(usds)), true);
        _setDefaultConfigOperator();
        _enableConfigTimelock();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansAdmin);

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        vm.prank(caller_);
        configTimelock.queueSetAssetWithdrawAsShares(address(usds), true);
    }

    function test_givenTimelockIsDisabled_reverts() public {
        vm.prank(admin);
        configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(burnerLoansAdmin);
        configTimelock.queueSetAssetWithdrawAsShares(address(usds), true);
    }

    function test_givenVaultAsset_queuesAndExecutesShareMode() public {
        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), true);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetWithdrawAsSharesSet(address(usds), true);
        configTimelock.executeQueuedAction(actionId);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "share withdrawals enabled"
        );
    }

    function test_givenTimelockIsReEnabled_queuesAndExecutesUnderlyingMode() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
        vm.prank(admin);
        configTimelock.disable("");
        vm.prank(admin);
        configTimelock.enable("");

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), false);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "underlying withdrawals restored after re-enable"
        );
    }

    function test_givenUnconfiguredAsset_reverts(address asset_) public {
        vm.assume(asset_ != address(usds));

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        configTimelock.queueSetAssetWithdrawAsShares(asset_, true);
    }

    function test_givenDirectCustody_whenEnabling_reverts() public {
        address asset = address(_addDirectAssetForTest());

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManagerV1_1.AssetManager_VaultRequired.selector, asset)
        );
        configTimelock.queueSetAssetWithdrawAsShares(asset, true);

        assertFalse(
            burnerLoansConfig.getAssetConfig(asset).withdrawAsShares,
            "share withdrawals remain disabled"
        );
    }

    function test_givenAssetOriginationsDisabled_queuesAndExecutesBothModes() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(burnerLoansAdmin);
        uint64 shareActionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), true);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(shareActionId);

        IBurnerLoans.AssetConfig memory shareConfig = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        assertFalse(shareConfig.originationsEnabled, "originations remain disabled");
        assertTrue(shareConfig.withdrawAsShares, "share output enabled while disabled");

        vm.prank(burnerLoansAdmin);
        uint64 assetActionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), false);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(assetActionId);

        IBurnerLoans.AssetConfig memory assetConfig = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        assertFalse(assetConfig.originationsEnabled, "originations still disabled");
        assertFalse(assetConfig.withdrawAsShares, "underlying output restored while disabled");
    }

    function test_givenOriginationsTransitionPending_queuesAndExecutesShareMode() public {
        vm.prank(burnerLoansAdmin);
        uint64 originationsActionId = _queueOriginationsEnabled(address(usds), false);

        vm.prank(burnerLoansAdmin);
        uint64 shareActionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), true);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        configTimelock.executeQueuedAction(shareActionId);
        configTimelock.executeQueuedAction(originationsActionId);

        IBurnerLoans.AssetConfig memory config = burnerLoansConfig.getAssetConfig(address(usds));
        assertFalse(config.originationsEnabled, "originations transition executed");
        assertTrue(config.withdrawAsShares, "share transition executed independently");
    }

    function test_givenShareOutputTransitionPending_queuesAndExecutesOriginationsChange() public {
        vm.prank(burnerLoansAdmin);
        uint64 shareActionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), true);

        vm.prank(burnerLoansAdmin);
        uint64 originationsActionId = _queueOriginationsEnabled(address(usds), false);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        configTimelock.executeQueuedAction(originationsActionId);
        configTimelock.executeQueuedAction(shareActionId);

        IBurnerLoans.AssetConfig memory config = burnerLoansConfig.getAssetConfig(address(usds));
        assertFalse(config.originationsEnabled, "originations transition executed independently");
        assertTrue(config.withdrawAsShares, "share transition executed while disabled");
    }

    function test_givenAsyncRedeem_whenQueueingUnderlyingMode_reverts() public {
        _useAsyncMockVaultInShareMode();
        address vault = depositManager.getAssetConfiguration(IERC20(address(usds))).vault;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(usds),
                vault
            )
        );
        vm.prank(burnerLoansAdmin);
        configTimelock.queueSetAssetWithdrawAsShares(address(usds), false);
    }

    function test_givenQueuedUnderlyingMode_whenVaultBecomesAsync_executeReverts() public {
        _useAsyncMockVaultInShareMode();
        mockDepositManager.setAssetAsyncRedeem(IERC20(address(usds)), false);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetWithdrawAsShares(address(usds), false);
        mockDepositManager.setAssetAsyncRedeem(IERC20(address(usds)), true);
        vm.warp(block.timestamp + configTimelock.timelockDelay());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(usds),
                depositManager.getAssetConfiguration(IERC20(address(usds))).vault
            )
        );
        configTimelock.executeQueuedAction(actionId);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "failed execution should preserve share output"
        );
    }
}

// forge-lint: disable-end(unused-return)
