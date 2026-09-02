// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(unwrapped-modifier-logic)
pragma solidity >=0.8.24;

import {Actions} from "src/Kernel.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";
import {MockYieldRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRecipient.sol";
import {BurnerLoansConfigTimelockHarness} from "src/test/policies/BurnerLoansConfigTimelock/fixtures/BurnerLoansConfigTimelockHarness.sol";

abstract contract BurnerLoansConfigTimelockTest is BurnerLoansTest {
    event AssetRiskConfigUpdateQueued(
        address indexed asset,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate update,
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection selection,
        IBurnerLoans.AssetRiskConfigInput resultingConfig
    );
    event AssetRiskConfigSet(address indexed asset, IBurnerLoans.AssetRiskConfigInput config);
    event AssetFeeConfigSet(address indexed asset, IBurnerLoans.AssetFeeConfig config);
    event TimelockActionQueued(
        uint64 indexed actionId,
        address indexed proposer,
        bytes32 batchHash,
        uint48 executableAt,
        uint48 expiresAt
    );
    event TimelockSubActionQueued(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        uint256 index,
        bytes32 payloadHash
    );
    event TimelockActionExecuted(uint64 indexed actionId, address indexed executor);
    event TimelockSubActionExecuted(
        uint64 indexed actionId,
        address indexed target,
        bytes4 indexed selector,
        uint256 index
    );
    event TimelockActionCancelled(uint64 indexed actionId, address indexed canceller);

    BurnerLoansConfigTimelockHarness internal configTimelockHarness;

    function setUp() public virtual override {
        super.setUp();
        _addDefaultUsdsAsset();
        vm.prank(admin);
        burnerLoansConfig.setAssetFeeConfig(address(usds), _defaultAssetFeeConfig());
        _setDefaultConfigOperator();
        _enableConfigTimelock();

        vm.startPrank(admin);
        configTimelockHarness = new BurnerLoansConfigTimelockHarness(kernel, burnerLoansConfig);
        kernel.executeAction(Actions.ActivatePolicy, address(configTimelockHarness));
        configTimelockHarness.enable("");
        vm.stopPrank();
    }

    function _singleAction(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory action) {
        action = ITimelockBatchQueue.BatchAction({
            target: address(burnerLoansConfig),
            selector: selector_,
            payload: payload_
        });
    }

    function _expectSingleActionQueued(
        uint64 actionId_,
        address proposer_,
        bytes4 selector_,
        bytes memory payload_
    ) internal {
        uint48 executableAt = uint48(block.timestamp + configTimelock.timelockDelay());
        uint48 expiresAt = executableAt + configTimelock.EXECUTION_WINDOW();
        ITimelockBatchQueue.BatchAction[] memory actions = new ITimelockBatchQueue.BatchAction[](1);
        actions[0] = _singleAction(selector_, payload_);

        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit TimelockSubActionQueued(
            actionId_,
            address(burnerLoansConfig),
            selector_,
            0,
            keccak256(payload_)
        );
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionQueued(
            actionId_,
            proposer_,
            keccak256(abi.encode(actions)),
            executableAt,
            expiresAt
        );
    }

    function _expectSingleActionExecuted(
        uint64 actionId_,
        bytes4 selector_,
        address executor_
    ) internal {
        vm.expectEmit(true, true, true, true, address(configTimelock));
        emit TimelockSubActionExecuted(actionId_, address(burnerLoansConfig), selector_, 0);
        vm.expectEmit(true, true, false, true, address(configTimelock));
        emit TimelockActionExecuted(actionId_, executor_);
    }

    function _maximumLtvConfig()
        internal
        pure
        returns (IBurnerLoans.AssetRiskConfigInput memory config)
    {
        config = IBurnerLoans.AssetRiskConfigInput({
            maxLtvBps: 8_500,
            backingMultiplierBps: 12_500,
            keeperRewardBps: 100,
            termLength: 30 days,
            maxMaturityHorizon: 90 days,
            maxKeeperReward: 1_000e6
        });
    }

    function _maxLtvUpdate()
        internal
        pure
        returns (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        )
    {
        update = IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
            maxLtvBps: 9_500,
            backingMultiplierBps: 0,
            keeperRewardBps: 0,
            termLength: 0,
            maxMaturityHorizon: 0,
            maxKeeperReward: 0
        });
        selection = IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
            maxLtvBps: true,
            backingMultiplierBps: false,
            keeperRewardBps: false,
            termLength: false,
            maxMaturityHorizon: false,
            maxKeeperReward: false
        });
    }

    function _selectAllFees()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection)
    {
        selection = IBurnerLoansConfigTimelock.FeeConfigUpdateSelection({
            baseFeeBps: true,
            kinkBps: true,
            preKinkSlopeBps: true,
            postKinkSlopeBps: true
        });
    }

    function _validRiskConfig()
        internal
        pure
        returns (IBurnerLoans.AssetRiskConfigInput memory config)
    {
        config = IBurnerLoans.AssetRiskConfigInput({
            maxLtvBps: 9_500,
            backingMultiplierBps: 11_000,
            keeperRewardBps: 500,
            termLength: 14 days,
            maxMaturityHorizon: 120 days,
            maxKeeperReward: 500e6
        });
    }

    function _selectAllRiskFields()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection)
    {
        selection = IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection({
            maxLtvBps: true,
            backingMultiplierBps: true,
            keeperRewardBps: true,
            termLength: true,
            maxMaturityHorizon: true,
            maxKeeperReward: true
        });
    }

    function _validRiskUpdate()
        internal
        pure
        returns (IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update)
    {
        update = IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
            maxLtvBps: 9_500,
            backingMultiplierBps: 11_000,
            keeperRewardBps: 500,
            termLength: 14 days,
            maxMaturityHorizon: 120 days,
            maxKeeperReward: 500e6
        });
    }

    function _queueMaximumLtvUpdate() internal returns (uint64 actionId) {
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _maxLtvUpdate();

        vm.prank(burnerLoansAdmin);
        actionId = configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    function _deployUsdsYieldRecipient() internal returns (MockYieldRecipient recipient) {
        vm.startPrank(admin);
        recipient = new MockYieldRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        vm.stopPrank();
        recipient.setVaultConfig(address(0), address(usds), true);
    }

    function _yieldAction(
        bytes4 selector_,
        bytes memory payload_
    ) internal view returns (ITimelockBatchQueue.BatchAction memory) {
        return _singleAction(selector_, payload_);
    }
}
/// forge-lint: disable-end(unwrapped-modifier-logic)
