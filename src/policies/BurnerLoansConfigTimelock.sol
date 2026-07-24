// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {BurnerLoansConfigTimelockLib} from "src/policies/libraries/BurnerLoansConfigTimelockLib.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock
/// @notice External timelock for bounded Burner Loans risk-parameter updates.
/// @dev Queue functions validate that this policy and BurnerLoansConfig are enabled, caller role,
///      configurator wiring, target asset, payload shape, and resulting configuration at queue
///      time. Execution validates that this policy and BurnerLoansConfig are enabled, that this
///      policy is still the configured BurnerLoans
///      configurator, and that the queued sub-action's expected config pre-state still matches
///      live BurnerLoans state. Value invariants that can legitimately move during the delay,
///      such as active market debt, are rechecked by the BurnerLoansConfig setter at
///      execution rather than encoded into the pre-state hash.
contract BurnerLoansConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    TimelockBatchQueue,
    IBurnerLoansConfigTimelock,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @dev ABI-encoded byte length of an asset, fee config, and fee-field selection payload.
    uint256 internal constant _LEN_ADDRESS_FEE_CONFIG_SELECTION = 288;

    /// @dev ABI-encoded byte length of an asset, risk update, and risk-field selection payload.
    uint256 internal constant _LEN_ADDRESS_ASSET_RISK_CONFIG_SELECTION = 480;

    /// @dev ABI-encoded byte length of an address followed by one static value.
    uint256 internal constant _LEN_ADDRESS_UINT256 = 64;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    // ========== STATE ========== //

    /// @notice Identifies a projected config state stored for a queued sub-action.
    /// @param actionId Queued action containing the projection.
    /// @param index Sub-action index within the queued action.
    struct ProjectionKey {
        uint64 actionId;
        uint64 index;
    }

    /// @notice Projected fee config and the projection it superseded for an asset.
    /// @param previousActionId Queued action containing the preceding fee projection.
    /// @param previousIndex Sub-action index of the preceding fee projection.
    /// @param exists Whether this projection is populated.
    /// @param asset Collateral asset whose fee config is projected.
    /// @param config Projected fee config after applying the queued sub-action.
    struct FeeConfigPostState {
        uint64 previousActionId;
        uint64 previousIndex;
        bool exists;
        address asset;
        IBurnerLoans.AssetFeeConfig config;
    }

    /// @notice Projected asset config and the projection it superseded for an asset.
    /// @param previousActionId Queued action containing the preceding asset projection.
    /// @param previousIndex Sub-action index of the preceding asset projection.
    /// @param exists Whether this projection is populated.
    /// @param asset Collateral asset whose configuration is projected.
    /// @param config Projected asset config after applying the queued sub-action.
    struct AssetConfigPostState {
        uint64 previousActionId;
        uint64 previousIndex;
        bool exists;
        address asset;
        IBurnerLoans.AssetConfig config;
    }

    /// @notice Burner Loans Config policy controlled by this timelock.
    IBurnerLoansConfig internal immutable BURNER_LOANS;

    /// @notice Expected live config hash for each queued sub-action.
    mapping(uint64 actionId => mapping(uint256 index => bytes32 expectedHash))
        internal _expectedPreStateHashes;

    /// @notice Projected fee config stored for each queued sub-action.
    mapping(uint64 actionId => mapping(uint256 index => FeeConfigPostState state))
        internal _feeConfigPostStates;

    /// @notice Projected asset config stored for each queued sub-action.
    mapping(uint64 actionId => mapping(uint256 index => AssetConfigPostState state))
        internal _assetConfigPostStates;

    /// @notice Latest queued fee-config projection for each collateral asset.
    mapping(address asset => ProjectionKey key) internal _latestFeeConfigPostStateKeys;

    /// @notice Latest queued asset-config projection for each collateral asset.
    mapping(address asset => ProjectionKey key) internal _latestAssetConfigPostStateKeys;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys the Burner Loans config timelock.
    /// @dev Reverts if `burnerLoans_` is zero, does not advertise `IBurnerLoansConfig` and
    ///      `IEnabler` support through ERC165, or belongs to a different Kernel.
    /// @param kernel_ Kernel contract used by the policy.
    /// @param burnerLoans_ Same-Kernel Burner Loans Config policy that receives updates.
    constructor(
        Kernel kernel_,
        IBurnerLoansConfig burnerLoans_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(BurnerLoansConstants.REENABLE_GRACE_PERIOD)
        TimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        if (address(burnerLoans_) == address(0)) {
            revert BurnerLoansConfigTimelock_ZeroAddress();
        }
        address burnerLoansAddress = address(burnerLoans_);
        if (
            !ERC165Checker.supportsInterface(
                burnerLoansAddress,
                type(IBurnerLoansConfig).interfaceId
            ) || !ERC165Checker.supportsInterface(burnerLoansAddress, type(IEnabler).interfaceId)
        ) {
            revert BurnerLoansConfigTimelock_InvalidBurnerLoans(address(burnerLoans_));
        }
        address configKernel = address(Policy(address(burnerLoans_)).kernel());
        if (configKernel != address(kernel_)) {
            revert BurnerLoansConfigTimelock_KernelMismatch(configKernel);
        }

        BURNER_LOANS = burnerLoans_;
    }

    // ========== POLICY SETUP ========== //

    /// @notice Configures module dependencies for the policy.
    /// @dev Reverts if the installed ROLES module major version is not 1.
    /// @return dependencies Keycodes for required modules.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) {
            revert BurnerLoansConfigTimelock_InvalidModuleVersion();
        }
    }

    /// @notice Returns kernel permissions requested by the policy.
    /// @dev This policy does not request module permissions.
    /// @return requests Empty permission request array.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the Burner Loans Config policy controlled by this timelock.
    /// @return IBurnerLoansConfig The Burner Loans Config policy.
    function burnerLoans() external view override returns (IBurnerLoansConfig) {
        return BURNER_LOANS;
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @notice Queues an asset fee-curve update.
    /// @dev Reverts if:
    ///      - The timelock is disabled.
    ///      - BurnerLoansConfig is disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the BurnerLoans configurator.
    ///      - `asset_` is not configured in BurnerLoans.
    ///      - `selection_` selects no fields.
    ///      - Any unselected `config_` field is non-zero.
    ///      - The resulting fee curve violates BurnerLoans fee bounds.
    ///      Execution later reverts if the asset is disabled, config pre-state changed, the
    ///      timelock or BurnerLoans is disabled, the configurator changed, or the underlying
    ///      BurnerLoans setter rejects the resulting full fee curve.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Partial fee curve update.
    /// @param selection_ Fields to apply from `config_`.
    /// @return actionId The queued action ID.
    function queueSetAssetFeeConfig(
        address asset_,
        IBurnerLoans.AssetFeeConfig calldata config_,
        FeeConfigUpdateSelection calldata selection_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(BURNER_LOANS),
                IBurnerLoansConfig.setAssetFeeConfig.selector,
                abi.encode(asset_, config_, selection_)
            );
    }

    /// @notice Queues an asset active debt cap update.
    /// @dev Reverts if:
    ///      - The timelock is disabled.
    ///      - BurnerLoansConfig is disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the BurnerLoans configurator.
    ///      - `asset_` is not configured in BurnerLoans.
    ///      - `debtCapOhm_` is below current active debt for `asset_`.
    ///      - `debtCapOhm_` is above the current global Burner Loans debt cap.
    ///      Execution later reverts if the asset is disabled, config pre-state changed, the
    ///      timelock or BurnerLoans is disabled, the configurator changed, or the BurnerLoans
    ///      setter rejects the cap against live active debt/global cap state.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New active debt cap, in OHM decimals.
    /// @return actionId The queued action ID.
    function queueSetAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(BURNER_LOANS),
                IBurnerLoansConfig.setAssetDebtCap.selector,
                abi.encode(asset_, debtCapOhm_)
            );
    }

    /// @notice Queues a partial asset risk-configuration update.
    /// @dev Reverts if:
    ///      - The timelock is disabled.
    ///      - BurnerLoansConfig is disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the BurnerLoans configurator.
    ///      - `asset_` is not configured in BurnerLoans.
    ///      - `selection_` selects no fields.
    ///      - Any unselected `update_` field is non-zero.
    ///      - The resulting risk config violates BurnerLoans bps or maturity bounds.
    ///      Execution later reverts if the asset is disabled, config pre-state changed, the
    ///      timelock or BurnerLoans is disabled, the configurator changed, or the underlying
    ///      BurnerLoans setter rejects the resulting full risk config.
    /// @param asset_ Collateral asset to update.
    /// @param update_ Partial risk and term update.
    /// @param selection_ Fields to apply from `update_`.
    /// @return actionId The queued action ID.
    function queueSetAssetRiskConfig(
        address asset_,
        AssetRiskConfigUpdate calldata update_,
        AssetRiskConfigUpdateSelection calldata selection_
    ) external returns (uint64 actionId) {
        return
            _queueAction(
                address(BURNER_LOANS),
                IBurnerLoansConfig.setAssetRiskConfig.selector,
                abi.encode(asset_, update_, selection_)
            );
    }

    /// @notice Queues a batch of Burner Loans configuration updates.
    /// @dev Reverts if the timelock or BurnerLoansConfig is disabled, or if any sub-action fails
    ///      the same validation as the typed queue helpers. These lifecycle checks are enforced
    ///      for every queue entrypoint through `_onSubActionQueued`. The batch is stored and
    ///      executed atomically in array order.
    /// @param actions_ Burner Loans configuration sub-actions.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId) {
        return _queueAction(actions_);
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @notice Validates a sub-action before it is stored in a queued action.
    /// @dev Called by `TimelockBatchQueue._queueAction` for every typed queue helper and every
    ///      `queueBatch` sub-action. Batch-invariant lifecycle, role, and configurator checks run
    ///      once for the first sub-action; payload and resulting-config validation runs for every
    ///      sub-action. Reverts if either policy is disabled, if `caller_` lacks both admin and
    ///      burner_loans_admin roles, if this contract is not the configured Burner Loans
    ///      configurator, or if a sub-action target, selector, payload shape, or resulting config
    ///      is invalid.
    /// @param caller_ Account queueing the action.
    /// @param actionId_ Queued action ID being built.
    /// @param index_ Sub-action index inside the queued action.
    /// @param action_ Sub-action to validate.
    function _onSubActionQueued(
        address caller_,
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        if (index_ == 0) {
            _requireEnabled();
            _requireRiskConfigProposer(caller_);
            _requireAuthorizedConfigurator();
            _requireBurnerLoansConfigEnabled();
        }
        _validateQueuedBurnerLoansAction(actionId_, index_, action_);
    }

    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireEnabled();
        _requireBurnerLoansConfigEnabled();
        _requireAuthorizedConfigurator();
    }

    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts with `NotAuthorised` unless the caller has admin or burner_loans_admin
    ///      authority. The grace-period deadline is enforced by `ReEnablerGracePeriod`
    ///      before the policy is re-enabled.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @notice Authorizes a grace-period update.
    /// @dev Reverts with `ROLESv1.ROLES_RequireRole(ADMIN_ROLE)` when the caller lacks the
    ///      admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    function _onActionCancelled(uint64 actionId_, uint256 subActionCount_) internal override {
        for (uint256 i; i < subActionCount_; ++i) {
            delete _expectedPreStateHashes[actionId_][i];
            _clearFeeConfigPostState(actionId_, i);
            _clearAssetConfigPostState(actionId_, i);
        }
    }

    function _executeSubAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        _validatePreState(actionId_, index_, action_);
        BurnerLoansConfigTimelockLib.executeSubAction(BURNER_LOANS, action_);

        delete _expectedPreStateHashes[actionId_][index_];
        _clearFeeConfigPostState(actionId_, index_);
        _clearAssetConfigPostState(actionId_, index_);
    }

    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY) {
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
        }
    }

    function _executionWindow() internal pure override returns (uint48) {
        return EXECUTION_WINDOW;
    }

    // ========== VALIDATION ========== //

    function _validateQueuedBurnerLoansAction(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal {
        if (action_.target != address(BURNER_LOANS)) {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
        }

        bytes4 selector = action_.selector;
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS_FEE_CONFIG_SELECTION, selector);
            (
                address feeAsset,
                IBurnerLoans.AssetFeeConfig memory feeConfig,
                FeeConfigUpdateSelection memory feeSelection
            ) = abi.decode(
                    action_.payload,
                    (address, IBurnerLoans.AssetFeeConfig, FeeConfigUpdateSelection)
                );
            IBurnerLoans.AssetFeeConfig memory config = _projectFeeConfig(feeAsset);
            _expectedPreStateHashes[actionId_][index_] = _hashFeeConfig(feeAsset, config);
            config = BurnerLoansConfigTimelockLib.applyFeeConfigUpdate(
                config,
                feeConfig,
                feeSelection
            );
            BURNER_LOANS.validateFeeConfig(config);
            _storeFeeConfigPostState(actionId_, index_, feeAsset, config);
            return;
        }

        if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            _requirePayloadLength(
                action_.payload,
                _LEN_ADDRESS_ASSET_RISK_CONFIG_SELECTION,
                selector
            );
            (
                address asset,
                AssetRiskConfigUpdate memory update,
                AssetRiskConfigUpdateSelection memory selection
            ) = abi.decode(
                    action_.payload,
                    (address, AssetRiskConfigUpdate, AssetRiskConfigUpdateSelection)
                );
            IBurnerLoans.AssetConfig memory config = _projectAssetConfig(asset);
            _expectedPreStateHashes[actionId_][index_] = _hashAssetConfig(asset, config);
            config = BurnerLoansConfigTimelockLib.applyAssetRiskConfigUpdate(
                config,
                update,
                selection
            );
            BURNER_LOANS.validateAssetRiskConfig(BurnerLoansConfigTimelockLib.toRiskConfig(config));
            _storeAssetConfigPostState(actionId_, index_, asset, config);
            return;
        }

        if (selector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS_UINT256, selector);
            (address asset, uint128 debtCapOhm) = abi.decode(action_.payload, (address, uint128));
            IBurnerLoans.AssetConfig memory config = _projectAssetConfig(asset);
            _expectedPreStateHashes[actionId_][index_] = _hashAssetConfig(asset, config);
            BURNER_LOANS.validateAssetDebtCap(asset, debtCapOhm);
            config.debtCap = debtCapOhm;
            _storeAssetConfigPostState(actionId_, index_, asset, config);
            return;
        }

        if (selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector) {
            _requirePayloadLength(action_.payload, _LEN_ADDRESS_UINT256, selector);
            (address asset, bool enabled) = abi.decode(action_.payload, (address, bool));
            IBurnerLoans.AssetConfig memory config = _projectAssetConfig(asset);
            _expectedPreStateHashes[actionId_][index_] = _hashAssetConfig(asset, config);
            config.originationsEnabled = enabled;
            _storeAssetConfigPostState(actionId_, index_, asset, config);
            return;
        }

        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    function _requireAuthorizedConfigurator() internal view {
        if (BURNER_LOANS.configurator() != address(this)) {
            revert IBurnerLoans.BurnerLoans_UnauthorizedConfigurator(address(this));
        }
    }

    /// @notice Validates that the controlled BurnerLoansConfig policy is enabled.
    /// @dev Reverts with `IEnabler.NotEnabled` while BurnerLoansConfig is disabled.
    function _requireBurnerLoansConfigEnabled() internal view {
        if (!IEnabler(address(BURNER_LOANS)).isEnabled()) revert IEnabler.NotEnabled();
    }

    function _requirePayloadLength(
        bytes memory payload_,
        uint256 expectedLength_,
        bytes4 selector_
    ) internal pure {
        if (payload_.length != expectedLength_) {
            revert ITimelockBatchQueue_ActionInvalid(address(0), selector_);
        }
    }

    /// @notice Validates that an asset remains configured in Burner Loans Config.
    /// @dev Used before returning a stored projection, which otherwise would not read live market
    ///      state. Reverts with `BurnerLoans_AssetNotConfigured` when the asset is not configured.
    /// @param asset_ Collateral asset to validate.
    function _requireAssetConfigured(address asset_) internal view {
        if (!BURNER_LOANS.isAssetConfigured(asset_)) {
            revert IBurnerLoans.BurnerLoans_AssetNotConfigured(asset_);
        }
    }

    function _requireRiskConfigProposer(address caller_) internal view {
        if (!_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)) {
            revert ROLESv1.ROLES_RequireRole(BURNER_LOANS_ADMIN_ROLE);
        }
    }

    /// @notice Returns the latest projected fee config or the canonical live config.
    /// @dev A stored projection is returned only while its asset remains configured. The canonical
    ///      getter performs configuration validation when no stored projection is available.
    /// @param asset_ Collateral asset whose fee config is requested.
    /// @return config Latest projected or live fee config.
    function _projectFeeConfig(
        address asset_
    ) internal view returns (IBurnerLoans.AssetFeeConfig memory config) {
        ProjectionKey memory latest = _latestFeeConfigPostStateKeys[asset_];
        if (latest.actionId != 0) {
            FeeConfigPostState storage state = _feeConfigPostStates[latest.actionId][latest.index];
            if (state.exists && state.asset == asset_) {
                _requireAssetConfigured(asset_);
                return state.config;
            }
        }

        return BURNER_LOANS.getAssetFeeConfig(asset_);
    }

    /// @notice Returns the latest projected asset config or the canonical live config.
    /// @dev A stored projection is returned only while its asset remains configured. The canonical
    ///      getter performs configuration validation when no stored projection is available.
    /// @param asset_ Collateral asset whose configuration is requested.
    /// @return config Latest projected or live asset config.
    function _projectAssetConfig(
        address asset_
    ) internal view returns (IBurnerLoans.AssetConfig memory config) {
        ProjectionKey memory latest = _latestAssetConfigPostStateKeys[asset_];
        if (latest.actionId != 0) {
            AssetConfigPostState storage state = _assetConfigPostStates[latest.actionId][
                latest.index
            ];
            if (state.exists && state.asset == asset_) {
                _requireAssetConfigured(asset_);
                return state.config;
            }
        }

        return BURNER_LOANS.getAssetConfig(asset_);
    }

    function _storeFeeConfigPostState(
        uint64 actionId_,
        uint256 index_,
        address asset_,
        IBurnerLoans.AssetFeeConfig memory config_
    ) internal {
        ProjectionKey memory previousKey = _latestFeeConfigPostStateKeys[asset_];
        _feeConfigPostStates[actionId_][index_] = FeeConfigPostState({
            previousActionId: previousKey.actionId,
            previousIndex: previousKey.index,
            exists: true,
            asset: asset_,
            config: config_
        });
        // Casting is safe because TimelockBatchQueue caps batch length at 15 sub-actions.
        // forge-lint: disable-next-line(unsafe-typecast)
        _latestFeeConfigPostStateKeys[asset_] = ProjectionKey({
            actionId: actionId_,
            index: uint64(index_)
        });
    }

    function _storeAssetConfigPostState(
        uint64 actionId_,
        uint256 index_,
        address asset_,
        IBurnerLoans.AssetConfig memory config_
    ) internal {
        ProjectionKey memory previousKey = _latestAssetConfigPostStateKeys[asset_];
        _assetConfigPostStates[actionId_][index_] = AssetConfigPostState({
            previousActionId: previousKey.actionId,
            previousIndex: previousKey.index,
            exists: true,
            asset: asset_,
            config: config_
        });
        // Casting is safe because TimelockBatchQueue caps batch length at 15 sub-actions.
        // forge-lint: disable-next-line(unsafe-typecast)
        _latestAssetConfigPostStateKeys[asset_] = ProjectionKey({
            actionId: actionId_,
            index: uint64(index_)
        });
    }

    function _clearFeeConfigPostState(uint64 actionId_, uint256 index_) internal {
        FeeConfigPostState storage state = _feeConfigPostStates[actionId_][index_];
        if (!state.exists) return;

        address asset = state.asset;
        uint64 previousActionId = state.previousActionId;
        uint64 previousIndex = state.previousIndex;
        ProjectionKey storage latest = _latestFeeConfigPostStateKeys[asset];
        if (latest.actionId == actionId_ && latest.index == index_) {
            latest.actionId = previousActionId;
            latest.index = previousIndex;
        } else {
            _relinkFeeConfigPostState(asset, actionId_, index_, previousActionId, previousIndex);
        }

        delete _feeConfigPostStates[actionId_][index_];
    }

    function _clearAssetConfigPostState(uint64 actionId_, uint256 index_) internal {
        AssetConfigPostState storage state = _assetConfigPostStates[actionId_][index_];
        if (!state.exists) return;

        address asset = state.asset;
        uint64 previousActionId = state.previousActionId;
        uint64 previousIndex = state.previousIndex;
        ProjectionKey storage latest = _latestAssetConfigPostStateKeys[asset];
        if (latest.actionId == actionId_ && latest.index == index_) {
            latest.actionId = previousActionId;
            latest.index = previousIndex;
        } else {
            _relinkAssetConfigPostState(asset, actionId_, index_, previousActionId, previousIndex);
        }

        delete _assetConfigPostStates[actionId_][index_];
    }

    function _relinkFeeConfigPostState(
        address asset_,
        uint64 actionId_,
        uint256 index_,
        uint64 previousActionId_,
        uint64 previousIndex_
    ) internal {
        uint256 len = _maxBatchSize();
        for (uint256 i = index_ + 1; i < len; ++i) {
            FeeConfigPostState storage candidate = _feeConfigPostStates[actionId_][i];
            if (
                candidate.exists &&
                candidate.asset == asset_ &&
                candidate.previousActionId == actionId_ &&
                candidate.previousIndex == index_
            ) {
                candidate.previousActionId = previousActionId_;
                candidate.previousIndex = previousIndex_;
                return;
            }
        }
    }

    function _relinkAssetConfigPostState(
        address asset_,
        uint64 actionId_,
        uint256 index_,
        uint64 previousActionId_,
        uint64 previousIndex_
    ) internal {
        uint256 len = _maxBatchSize();
        for (uint256 i = index_ + 1; i < len; ++i) {
            AssetConfigPostState storage candidate = _assetConfigPostStates[actionId_][i];
            if (
                candidate.exists &&
                candidate.asset == asset_ &&
                candidate.previousActionId == actionId_ &&
                candidate.previousIndex == index_
            ) {
                candidate.previousActionId = previousActionId_;
                candidate.previousIndex = previousIndex_;
                return;
            }
        }
    }

    function _validatePreState(
        uint64 actionId_,
        uint256 index_,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view {
        BurnerLoansConfigTimelockLib.validatePreState(
            BURNER_LOANS,
            actionId_,
            index_,
            action_,
            _expectedPreStateHashes[actionId_][index_]
        );
    }

    function _hashFeeConfig(
        address asset_,
        IBurnerLoans.AssetFeeConfig memory config_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, config_));
    }

    function _hashAssetConfig(
        address asset_,
        IBurnerLoans.AssetConfig memory config_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, config_));
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @notice ERC165 interface support.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, TimelockBatchQueue) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
