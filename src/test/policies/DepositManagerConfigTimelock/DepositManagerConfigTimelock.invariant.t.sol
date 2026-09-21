// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// The handler is co-located with its invariant test to keep the stateful harness self-contained.
// forge-lint: disable-start(multi-contract-file)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Contracts
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockHandler {
    uint256 internal constant _ACTION_SLOTS = 16;
    // Casting the deterministic Foundry cheat-code hash to an address intentionally takes its low
    // 160 bits, matching forge-std's Vm address derivation.
    // forge-lint: disable-next-line(unsafe-typecast)
    Vm internal constant _VM = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    DepositManagerConfigTimelock internal immutable _CONFIG_TIMELOCK;
    DepositManager internal immutable _DEPOSIT_MANAGER;
    IERC20 internal immutable _ASSET;
    uint8 internal immutable _DEPOSIT_PERIOD;
    uint8 internal immutable _ROUTE_CREATION_PERIOD;
    address internal immutable _OPERATOR;

    uint64[_ACTION_SLOTS] internal _actionIds;
    uint256 internal _nextActionSlot;

    // The invariant fixture always supplies its configured, nonzero deposit operator.
    // forge-lint: disable-start(missing-zero-check)
    constructor(
        DepositManagerConfigTimelock configTimelock_,
        DepositManager depositManager_,
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) {
        _CONFIG_TIMELOCK = configTimelock_;
        _DEPOSIT_MANAGER = depositManager_;
        _ASSET = asset_;
        _DEPOSIT_PERIOD = depositPeriod_;
        _ROUTE_CREATION_PERIOD = depositPeriod_ == type(uint8).max
            ? depositPeriod_ - 1
            : depositPeriod_ + 1;
        _OPERATOR = operator_;
    }

    // forge-lint: disable-end(missing-zero-check)

    function setDepositCapDirect(uint256 capSeed_) external {
        uint256 minimumDeposit = _DEPOSIT_MANAGER.getAssetConfiguration(_ASSET).minimumDeposit;
        uint256 depositCap = capSeed_ < minimumDeposit ? minimumDeposit : capSeed_;
        _DEPOSIT_MANAGER.setAssetDepositCap(_ASSET, depositCap);
    }

    function setMinimumDepositDirect(uint256 minimumSeed_) external {
        uint256 depositCap = _DEPOSIT_MANAGER.getAssetConfiguration(_ASSET).depositCap;
        uint256 minimumDeposit = depositCap == type(uint256).max
            ? minimumSeed_
            : minimumSeed_ % (depositCap + 1);
        _DEPOSIT_MANAGER.setAssetMinimumDeposit(_ASSET, minimumDeposit);
    }

    function toggleAssetPeriodDirect() external {
        if (_assetPeriodEnabled()) {
            _DEPOSIT_MANAGER.disableAssetPeriod(_ASSET, _DEPOSIT_PERIOD, _OPERATOR);
        } else {
            _DEPOSIT_MANAGER.enableAssetPeriod(_ASSET, _DEPOSIT_PERIOD, _OPERATOR);
        }
    }

    function queueDepositCap(uint256 capSeed_) external {
        uint256 minimumDeposit = _DEPOSIT_MANAGER.getAssetConfiguration(_ASSET).minimumDeposit;
        uint256 depositCap = capSeed_ < minimumDeposit ? minimumDeposit : capSeed_;
        try _CONFIG_TIMELOCK.queueSetAssetDepositCap(_ASSET, depositCap) returns (uint64 actionId) {
            _recordAction(actionId);
        } catch {}
    }

    function queueMinimumDeposit(uint256 minimumSeed_) external {
        uint256 depositCap = _DEPOSIT_MANAGER.getAssetConfiguration(_ASSET).depositCap;
        uint256 minimumDeposit = depositCap == type(uint256).max
            ? minimumSeed_
            : minimumSeed_ % (depositCap + 1);
        try _CONFIG_TIMELOCK.queueSetAssetMinimumDeposit(_ASSET, minimumDeposit) returns (
            uint64 actionId
        ) {
            _recordAction(actionId);
        } catch {}
    }

    function queueAssetPeriodToggle() external {
        if (_assetPeriodEnabled()) {
            try
                _CONFIG_TIMELOCK.queueDisableAssetPeriod(_ASSET, _DEPOSIT_PERIOD, _OPERATOR)
            returns (uint64 actionId) {
                _recordAction(actionId);
            } catch {}
        } else {
            try
                _CONFIG_TIMELOCK.queueEnableAssetPeriod(_ASSET, _DEPOSIT_PERIOD, _OPERATOR)
            returns (uint64 actionId) {
                _recordAction(actionId);
            } catch {}
        }
    }

    function queueAssetPeriodCreation() external {
        if (_DEPOSIT_MANAGER.isAssetPeriod(_ASSET, _ROUTE_CREATION_PERIOD, _OPERATOR).isConfigured)
            return;

        try
            _CONFIG_TIMELOCK.queueAddAssetPeriod(_ASSET, _ROUTE_CREATION_PERIOD, _OPERATOR)
        returns (uint64 actionId) {
            _recordAction(actionId);
        } catch {}
    }

    function queueShareWithdrawalRequirement(bool required_) external {
        try _CONFIG_TIMELOCK.queueSetAssetShareWithdrawalRequired(_ASSET, required_) returns (
            uint64 actionId
        ) {
            _recordAction(actionId);
        } catch {}
    }

    function executeQueuedAction(uint256 slotSeed_) external {
        uint64 actionId = _actionIds[slotSeed_ % _ACTION_SLOTS];
        if (actionId == 0) return;

        ITimelockBatchQueue.QueuedAction memory action = _CONFIG_TIMELOCK.getQueuedAction(actionId);
        if (action.executed || action.cancelled) return;
        // The invariant handler controls simulated time with vm.warp; validator influence is absent.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < action.executableAt) _VM.warp(action.executableAt);
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > action.expiresAt) {
            _CONFIG_TIMELOCK.cancelQueuedAction(actionId);
            return;
        }

        try _CONFIG_TIMELOCK.executeQueuedAction(actionId) {} catch {
            _CONFIG_TIMELOCK.cancelQueuedAction(actionId);
        }
    }

    function cancelQueuedAction(uint256 slotSeed_) external {
        uint64 actionId = _actionIds[slotSeed_ % _ACTION_SLOTS];
        if (actionId == 0) return;

        ITimelockBatchQueue.QueuedAction memory action = _CONFIG_TIMELOCK.getQueuedAction(actionId);
        if (action.executed || action.cancelled) return;
        _CONFIG_TIMELOCK.cancelQueuedAction(actionId);
    }

    function rotateConfigOperatorAwayAndBack() external {
        _DEPOSIT_MANAGER.setConfigOperator(address(this));
        _DEPOSIT_MANAGER.setConfigOperator(address(_CONFIG_TIMELOCK));
    }

    function cycleTimelockLifecycle() external {
        _CONFIG_TIMELOCK.disable("");
        _CONFIG_TIMELOCK.reEnable();
    }

    function cycleDepositManagerLifecycle() external {
        _DEPOSIT_MANAGER.disable("");
        _DEPOSIT_MANAGER.reEnable();
    }

    function routeCreationPeriod() external view returns (uint8) {
        return _ROUTE_CREATION_PERIOD;
    }

    function _assetPeriodEnabled() internal view returns (bool) {
        return _DEPOSIT_MANAGER.isAssetPeriod(_ASSET, _DEPOSIT_PERIOD, _OPERATOR).isEnabled;
    }

    function _recordAction(uint64 actionId_) internal {
        _actionIds[_nextActionSlot] = actionId_;
        _nextActionSlot = (_nextActionSlot + 1) % _ACTION_SLOTS;
    }
}

contract DepositManagerConfigTimelockInvariantTest is
    StdInvariant,
    DepositManagerConfigTimelockTest
{
    DepositManagerConfigTimelockHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _handler = new DepositManagerConfigTimelockHandler(
            _configTimelock,
            depositManager,
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("admin", address(_handler));
        rolesAdmin.grantRole("deposit_manager_admin", address(_handler));
        rolesAdmin.grantRole("emergency", address(_handler));
        vm.stopPrank();

        targetContract(address(_handler));
    }

    function invariant_minimumDepositNeverExceedsDepositCap() public view {
        IDepositManager.AssetConfiguration memory configuration = depositManager
            .getAssetConfiguration(iAsset);
        assertLe(
            configuration.minimumDeposit,
            configuration.depositCap,
            "minimum deposit exceeds cap"
        );
    }

    function invariant_authorityBindingsAndLifecycleRemainRestored() public view {
        assertEq(
            depositManager.configOperator(),
            address(_configTimelock),
            "config operator should remain bound"
        );
        assertTrue(depositManager.isEnabled(), "DepositManager should remain enabled");
        assertTrue(_configTimelock.isEnabled(), "config timelock should remain enabled");
    }

    function invariant_createdRouteRetainsGovernancePrerequisites() public view {
        IDepositManager.AssetPeriodStatus memory status = depositManager.isAssetPeriod(
            iAsset,
            _handler.routeCreationPeriod(),
            DEPOSIT_OPERATOR
        );
        if (!status.isConfigured) return;

        assertTrue(status.isEnabled, "timelocked route should start enabled");
        assertTrue(
            depositManager.getAssetConfiguration(iAsset).isConfigured,
            "timelocked route should reference a configured asset"
        );
        assertGt(
            bytes(depositManager.getOperatorName(DEPOSIT_OPERATOR)).length,
            0,
            "timelocked route should reference a registered operator"
        );
        assertTrue(
            roles.hasRole(DEPOSIT_OPERATOR, "deposit_operator"),
            "timelocked route operator should hold deposit_operator"
        );
    }
}

// forge-lint: disable-end(multi-contract-file)
