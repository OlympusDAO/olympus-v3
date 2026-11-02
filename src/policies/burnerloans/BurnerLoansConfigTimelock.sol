// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansConfigTimelock.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {Address} from "@openzeppelin-5.7.0/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock
/// @notice Timelock implementation for bounded Burner Loans Config updates.
/// @dev Market updates call Config through its delegated config operator. Cache-age updates instead
///      call Core's selected Risk through Risk's independently delegated operator, so Config/Core
///      pauses do not block that route. Both routes validate the proposer's role and target readiness.
///      ConfigTimelockBatchQueue owns delay handling, conflict-key reservations and checks of the
///      recorded configuration state before each dispatch. This contract defines admitted selectors,
///      canonical payloads and the live settings protected by those checks. Debt and balances may move
///      during the delay; the target setter or rescue rechecks those quantities at execution.
contract BurnerLoansConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IBurnerLoansConfigTimelock,
    IVersioned
{
    using SafeCall for address;

    // ========== CONSTANTS ========== //

    uint16 internal constant _MAX_REVERT_DATA_BYTES = 256;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override MIN_TIMELOCK_DELAY = 1 days;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override MAX_TIMELOCK_DELAY = 30 days;

    /// @inheritdoc IBurnerLoansConfigTimelock
    uint48 public constant override EXECUTION_WINDOW = 3 days;

    // ========== STATE ========== //

    /// @dev Product boundary errors use widened arithmetic before the shared queue narrows values.
    modifier withinQueueBounds() {
        // Each conversion intentionally validates the bound; the base stores the same values.

        SafeCast.toUint64(uint256(nextActionId) + 1);
        uint48 queuedAt = SafeCast.toUint48(block.timestamp);
        uint48 executableAt = SafeCast.toUint48(uint256(queuedAt) + timelockDelay);
        SafeCast.toUint48(uint256(executableAt) + EXECUTION_WINDOW);

        _;
    }

    /// @notice Burner Loans Config policy for which this contract may act as config operator.
    IBurnerLoansConfig internal immutable _BURNER_LOANS_CONFIG;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys the Burner Loans config timelock.
    /// @dev Reverts if:
    ///      - `burnerLoansConfig_` is zero, does not advertise `IBurnerLoansConfig`,
    ///      `IConfigOperator`, and `IEnabler` support through ERC165, or belongs to a different
    ///      Kernel.
    /// @param kernel_ Kernel contract used by the policy.
    /// @param burnerLoansConfig_ Same-Kernel Burner Loans Config policy that receives updates.
    constructor(
        Kernel kernel_,
        IBurnerLoansConfig burnerLoansConfig_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        address burnerLoansConfigAddress = address(burnerLoansConfig_);
        if (
            !ERC165Checker.supportsInterface(
                burnerLoansConfigAddress,
                type(IBurnerLoansConfig).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(
                burnerLoansConfigAddress,
                type(IConfigOperator).interfaceId
            ) ||
            !ERC165Checker.supportsInterface(burnerLoansConfigAddress, type(IEnabler).interfaceId)
        ) {
            revert BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(address(burnerLoansConfig_));
        }
        PolicyDependency.requireSameKernel(address(burnerLoansConfig_), address(kernel_));

        _BURNER_LOANS_CONFIG = burnerLoansConfig_;
    }

    // ========== POLICY SETUP ========== //

    /// @notice Configures module dependencies for the policy.
    /// @dev Reverts if:
    ///      - the installed ROLES module major version is not 1.
    /// @return dependencies Keycodes for required modules.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
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

    /// @notice Returns the Burner Loans Config policy targeted by this timelock.
    /// @return IBurnerLoansConfig The Burner Loans Config policy.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function burnerLoans() external view override returns (IBurnerLoansConfig) {
        return _BURNER_LOANS_CONFIG;
    }

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    modifier onlyActive() {
        _requireOwnPolicyActive();
        _;
    }

    /// @dev Reverts if:
    ///      - The caller holds neither accepted queue-proposer role.
    modifier onlyProposerRole() {
        _requireProposerRole(msg.sender);
        _;
    }

    // ========== QUEUE FUNCTIONS ========== //

    /// @notice Queues an asset fee-curve update.
    /// @dev Reverts if:
    ///      - The timelock or BurnerLoansConfig is Kernel-inactive or disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the configured config operator.
    ///      - `asset_` is not configured in Burner Loans Config.
    ///      - The resulting fee curve violates Burner Loans Config fee bounds.
    ///
    /// @dev Execution later reverts if:
    ///      - The asset is disabled.
    ///      - The recorded configuration pre-state changed.
    ///      - The timelock or Burner Loans Config is Kernel-inactive or disabled.
    ///      - The selected config operator changed.
    ///      - The downstream setter rejects the fee curve against live state.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee curve.
    /// @return uint64 The queued action ID.
    function queueSetAssetFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig calldata config_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetFeeConfig.selector,
                abi.encode(asset_, config_)
            );
    }

    /// @notice Queues an asset active debt cap update.
    /// @dev Reverts if:
    ///      - The timelock or BurnerLoansConfig is Kernel-inactive or disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the configured config operator.
    ///      - `asset_` is not configured in Burner Loans Config.
    ///      - `debtCapOhm_` is below current active debt for `asset_`.
    ///
    /// @dev Execution later reverts if:
    ///      - The asset is disabled.
    ///      - The recorded configuration pre-state changed.
    ///      - The timelock or Burner Loans Config is Kernel-inactive or disabled.
    ///      - The selected config operator changed.
    ///      - The downstream setter rejects the debt cap against live state.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New active debt cap, in OHM decimals.
    /// @return uint64 The queued action ID.
    function queueSetAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetDebtCap.selector,
                abi.encode(asset_, debtCapOhm_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @dev Reverts if:
    ///      - The timelock or Config is disabled or Kernel-inactive.
    ///      - The caller lacks ADMIN and burner_loans_admin.
    ///      - Config’s selected operator is not this timelock.
    ///      - The scoped configuration key is already pending, or queue ID/time arithmetic overflows.
    function queueSetPriceCacheMaxAge(
        uint48 priceCacheMaxAge_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return
            _queueAction(
                IBurnerLoansCore(_BURNER_LOANS_CONFIG.facility()).risk(),
                IBurnerLoansRisk.setPriceCacheMaxAge.selector,
                abi.encode(priceCacheMaxAge_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @dev Reverts if:
    ///      - The caller lacks admin or burner_loans_admin authority.
    ///      - This timelock or Config is disabled, either policy is inactive, or this operator is no longer selected.
    ///      - The preview rejects the token or destination, or a surplus rescue for the token is
    ///        already queued.
    function queueRescue(
        address token_,
        address destination_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.rescue.selector,
                abi.encode(token_, destination_)
            );
    }

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @dev Reverts if:
    ///      - queue validation fails or another output-mode transition is already pending
    ///      for the asset. Originations transitions use an independent configuration key.
    function queueSetAssetWithdrawAsShares(
        address asset_,
        bool withdrawAsShares_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetWithdrawAsShares.selector,
                abi.encode(asset_, withdrawAsShares_)
            );
    }

    /// @notice Queues a complete asset risk-configuration update.
    /// @dev Reverts if:
    ///      - The timelock or BurnerLoansConfig is Kernel-inactive or disabled.
    ///      - The caller lacks both `admin` and `burner_loans_admin`.
    ///      - This contract is not the configured config operator.
    ///      - `asset_` is not configured in Burner Loans Config.
    ///      - The resulting risk config violates Burner Loans Config bps or maturity bounds.
    ///
    /// @dev Execution later reverts if:
    ///      - The asset is disabled.
    ///      - The recorded configuration pre-state changed.
    ///      - The timelock or Burner Loans Config is Kernel-inactive or disabled.
    ///      - The selected config operator changed.
    ///      - The downstream setter rejects the risk configuration against live state.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk and term configuration.
    /// @return uint64 The queued action ID.
    function queueSetAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return
            _queueAction(
                address(_BURNER_LOANS_CONFIG),
                IBurnerLoansConfig.setAssetRiskConfig.selector,
                abi.encode(asset_, config_)
            );
    }

    /// @notice Queues a batch of Burner Loans configuration updates.
    /// @dev Reverts if:
    ///      - the timelock or BurnerLoansConfig is Kernel-inactive or disabled, or if any
    ///      sub-action fails the same validation as the typed queue helpers. These lifecycle checks
    ///      are enforced for every queue entrypoint through `_onSubActionQueued`. The batch is
    ///      stored and executed atomically in array order.
    /// @param actions_ Burner Loans configuration sub-actions.
    /// @return uint64 The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return _queueAction(actions_);
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @notice Validates queue-wide authorization and lifecycle requirements.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requireProposerRole(caller_);
    }

    /// @notice Validates one product sub-action before shared key acquisition.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param action_ Admitted queued configuration setter and payload.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        if (action_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector) {
            // _validateConfigQueue checks this timelock's lifecycle; _requireRiskReady checks
            // Risk's Kernel, lifecycle and config operator. Config and Core may be paused.
            if (action_.target != IBurnerLoansCore(_BURNER_LOANS_CONFIG.facility()).risk())
                revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
            _requireRiskReady(action_.target);
        } else {
            _requirePoliciesActive();
            _requireAuthorizedConfigOperator();
            _requireBurnerLoansConfigEnabled();
        }
        _validateQueuedBurnerLoansAction(action_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Queue validation admits selectors before key acquisition. Each selector owns a
    ///      separate conflict domain: global, per asset/token, or per token/recipient for pending rescue.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        bytes32 key = action_.selector == IBurnerLoansConfig.setPriceCacheMaxAge.selector
            ? keccak256(abi.encode(action_.selector))
            : keccak256(abi.encode(action_.selector, abi.decode(action_.payload, (address))));
        keys = new bytes32[](1);
        keys[0] = key;
    }

    /// @notice Selects the configuration contract that owns the guarded domains.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @return address Bound Config policy receiving the queued setter.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (address) {
        if (action_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector)
            return action_.target;
        return address(_BURNER_LOANS_CONFIG);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The queued selector is unsupported.
    ///      - A canonical configuration or custody getter fails.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32) {
        // Hash only the setting being changed and identities needed to interpret it. Unrelated
        // parameter updates should not invalidate a queued action that owns a different conflict key.
        bytes4 selector = action_.selector;
        address facility = _BURNER_LOANS_CONFIG.facility();
        if (selector == IBurnerLoansConfig.setPriceCacheMaxAge.selector) {
            // Bind the quote to this Risk instance as well as its age. Replacing Risk requires
            // a new notice period rather than applying an old queued change to the replacement.
            IBurnerLoansRisk evaluator = IBurnerLoansRisk(IBurnerLoansCore(facility).risk());
            return
                keccak256(abi.encode(facility, address(evaluator), evaluator.priceCacheMaxAge()));
        }
        if (selector == IBurnerLoansConfig.rescue.selector)
            return keccak256(abi.encode(facility, IConfigOperator(facility).configOperator()));
        address asset = abi.decode(action_.payload, (address));
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector)
            return
                keccak256(
                    abi.encode(facility, asset, _BURNER_LOANS_CONFIG.getAssetFeeConfig(asset))
                );
        IBurnerLoansCore.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(asset);
        if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector)
            return keccak256(abi.encode(facility, asset, _toRiskConfig(config)));
        if (selector == IBurnerLoansConfig.setAssetDebtCap.selector)
            return keccak256(abi.encode(facility, asset, config.debtCap));
        if (selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector)
            return keccak256(abi.encode(facility, asset, config.originationsEnabled));
        if (selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector)
            return keccak256(abi.encode(facility, asset, config.withdrawAsShares));
        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage action_
    ) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        bool configValidated;
        for (uint256 i; i < action_.actions.length; ++i) {
            if (action_.actions[i].selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector) {
                // Repeat Risk's own readiness and operator checks at execution, independently
                // of Config/Core lifecycle. Risk.setPriceCacheMaxAge rechecks its lifecycle
                // and caller authorization.
                _requireRiskReady(action_.actions[i].target);
            } else if (!configValidated) {
                _requireBurnerLoansConfigEnabled();
                _requirePoliciesActive();
                _requireAuthorizedConfigOperator();
                configValidated = true;
            }
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller lacks the emergency role.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev The grace-period deadline is enforced by `ReEnablerGracePeriod` before re-enablement.
    ///      Reverts if:
    ///      - The caller lacks admin or burner_loans_admin authority (`NotAuthorised`).
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireOwnPolicyActive();
        super.setGracePeriod(period_);
    }

    /// @notice Authorizes a grace-period update.
    /// @dev Reverts if:
    ///      - The caller lacks admin authority (`ROLESv1.ROLES_RequireRole(ADMIN_ROLE)`).
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Revalidates the constructor-bound Config policy before operational enablement.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _requireBurnerLoansActive();
    }

    /// @dev Preserves the grace-period gate and revalidates Config before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireBurnerLoansActive();
    }

    /// @dev Reverts if:
    ///      - The constructor-bound Config is inactive in this policy's Kernel.
    function _requireBurnerLoansActive() internal view {
        _requireOwnPolicyActive();
        PolicyDependency.requireActiveAndEnabled(address(_BURNER_LOANS_CONFIG), address(kernel));
        _requireAuthorizedConfigOperator();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The queued configuration payload cannot be rebuilt.
    ///      - The downstream Config setter fails; bounded revert bytes are propagated or wrapped.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        bytes memory callData = abi.encodePacked(action_.selector, action_.payload);
        (bool ok, bytes memory result) = action_.target.safeCall(
            gasleft(),
            0,
            _MAX_REVERT_DATA_BYTES,
            callData
        );
        if (!ok) {
            // A capped response may be truncated and cannot safely stand in for the original error.
            // Wrap empty/capped failures; preserve complete smaller errors for precise diagnostics.
            if (result.length == 0 || result.length == _MAX_REVERT_DATA_BYTES)
                revert BurnerLoansConfigTimelock_SubActionCallFailed(
                    action_.target,
                    action_.selector
                );
            Address.verifyCallResult(ok, result);
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Reverts if:
    ///      - The delay is below MIN_TIMELOCK_DELAY or above MAX_TIMELOCK_DELAY.
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY) {
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev No external state or token calls; checked arithmetic errors propagate.
    function _executionWindow() internal pure override returns (uint48) {
        return EXECUTION_WINDOW;
    }

    // ========== VALIDATION ========== //

    /// @notice Validates a Burner Loans configuration sub-action before key acquisition.
    /// @dev Reverts if:
    ///      - The target or selector is unsupported.
    ///      - The payload has an invalid ABI shape.
    ///      - Asset or resulting-configuration validation fails.
    ///
    /// @param action_ Burner Loans configuration sub-action to validate.
    function _validateQueuedBurnerLoansAction(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view {
        // Inspect full ABI words before decoding narrow types. This rejects dirty address bits,
        // out-of-range integers and noncanonical booleans with this timelock's admission error.
        bytes4 selector = action_.selector;
        if (selector == IBurnerLoansConfig.setPriceCacheMaxAge.selector) {
            if (action_.target != IBurnerLoansCore(_BURNER_LOANS_CONFIG.facility()).risk())
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            _requirePayloadLength(action_, 32);
            if (abi.decode(action_.payload, (uint256)) > type(uint48).max)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            return;
        }
        if (action_.target != address(_BURNER_LOANS_CONFIG))
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector) {
            _requirePayloadLength(action_, 160);
            uint256[5] memory feeWords = abi.decode(action_.payload, (uint256[5]));
            if (
                feeWords[0] > type(uint160).max ||
                feeWords[1] > type(uint16).max ||
                feeWords[2] > type(uint16).max ||
                feeWords[3] > type(uint16).max ||
                feeWords[4] > type(uint16).max
            ) revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address asset, IBurnerLoansRisk.AssetFeeConfig memory config) = abi.decode(
                action_.payload,
                (address, IBurnerLoansRisk.AssetFeeConfig)
            );
            _BURNER_LOANS_CONFIG.validateFeeConfig(asset, config);
            return;
        }
        if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector) {
            _requirePayloadLength(action_, 224);
            uint256[7] memory riskWords = abi.decode(action_.payload, (uint256[7]));
            if (
                riskWords[0] > type(uint160).max ||
                riskWords[1] > type(uint16).max ||
                riskWords[2] > type(uint16).max ||
                riskWords[3] > type(uint16).max ||
                riskWords[4] > type(uint48).max ||
                riskWords[5] > type(uint48).max ||
                riskWords[6] > type(uint128).max
            ) revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address asset, IBurnerLoansRisk.AssetRiskConfigInput memory config) = abi.decode(
                action_.payload,
                (address, IBurnerLoansRisk.AssetRiskConfigInput)
            );
            _BURNER_LOANS_CONFIG.validateAssetRiskConfig(asset, config);
            return;
        }
        _requirePayloadLength(action_, 64);
        uint256[2] memory words = abi.decode(action_.payload, (uint256[2]));
        if (words[0] > type(uint160).max)
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        if (selector == IBurnerLoansConfig.rescue.selector) {
            if (words[1] > type(uint160).max)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address token, address destination) = abi.decode(action_.payload, (address, address));
            // This validates admission; the result does not commit a balance or replace execution-time checks.
            // forge-lint: disable-next-line(unused-return)
            _BURNER_LOANS_CONFIG.previewRescue(token, destination);
            return;
        }
        if (selector == IBurnerLoansConfig.setAssetDebtCap.selector) {
            if (words[1] > type(uint128).max)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address asset, uint128 cap) = abi.decode(action_.payload, (address, uint128));
            _BURNER_LOANS_CONFIG.validateAssetDebtCap(asset, cap);
            return;
        }
        if (
            selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector ||
            selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector
        ) {
            if (words[1] > 1) revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address asset, bool enabled) = abi.decode(action_.payload, (address, bool));
            // This validates admission; the result does not commit a balance or replace execution-time checks.
            // forge-lint: disable-next-line(unused-return)
            _BURNER_LOANS_CONFIG.getAssetConfig(asset);
            if (selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector)
                IAssetManagerV1_1(
                    IBurnerLoansCore(_BURNER_LOANS_CONFIG.facility()).depositManager()
                ).validateAssetWithdrawAsShares(IERC20(asset), enabled);
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @notice Requires this timelock to remain the Config policy's authorized operator.
    /// @dev Reverts if:
    ///      - Config's selected operator is no longer this timelock.
    function _requireAuthorizedConfigOperator() internal view {
        // Each queued action revalidates its own policy binding and readiness.
        // forge-lint: disable-next-line(calls-loop)
        if (IConfigOperator(address(_BURNER_LOANS_CONFIG)).configOperator() != address(this)) {
            // Each queued action revalidates its own policy binding and readiness.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator(address(this));
        }
    }

    /// @notice Validates that the controlled BurnerLoansConfig policy is enabled.
    /// @dev Reverts if:
    ///      - BurnerLoansConfig is disabled (`IEnabler.NotEnabled`).
    function _requireBurnerLoansConfigEnabled() internal view {
        // Each queued action revalidates its own policy binding and readiness.
        // forge-lint: disable-next-line(calls-loop)
        if (!IEnabler(address(_BURNER_LOANS_CONFIG)).isEnabled())
            // Each queued action revalidates its own policy binding and readiness.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert PolicyDependency.PolicyDependency_NotActive(address(_BURNER_LOANS_CONFIG));
    }

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    function _requireOwnPolicyActive() internal view {
        address timelock = address(this);
        // Each queued action revalidates its own policy binding and readiness.
        // forge-lint: disable-next-line(calls-loop)
        if (!kernel.isPolicyActive(Policy(timelock))) {
            // Each queued action revalidates its own policy binding and readiness.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(timelock);
        }
    }

    /// @dev Both policies must retain Kernel membership for queueing and execution.
    function _requirePoliciesActive() internal view {
        _requireOwnPolicyActive();
        PolicyDependency.requireActive(address(_BURNER_LOANS_CONFIG), address(kernel));
    }

    /// @dev Risk age has its own controller and readiness; Config and Core may be paused.
    ///      Reverts if:
    ///      - Risk reports another Kernel or is inactive or disabled.
    ///      - This timelock is not Risk's selected config operator.
    function _requireRiskReady(address risk_) private view {
        // Kernel membership can survive migration, so it does not replace the live binding check.
        PolicyDependency.requireActiveAndEnabled(risk_, address(kernel));
        // Each queued action revalidates its own policy binding and readiness.
        // forge-lint: disable-next-line(calls-loop,require-revert-in-loop)
        if (IConfigOperator(risk_).configOperator() != address(this)) revert NotAuthorised();
    }

    /// @notice Requires an action payload to match the ABI length for its selector.
    /// @dev Reverts if:
    ///      - The payload length differs from the selector's expected ABI length.
    /// @param action_ Admitted queued configuration setter and payload.
    /// @param expectedLength_ Exact admitted payload byte length.
    function _requirePayloadLength(
        ITimelockBatchQueue.BatchAction memory action_,
        uint256 expectedLength_
    ) internal pure {
        if (action_.payload.length != expectedLength_) {
            revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
        }
    }

    /// @dev Reverts if:
    ///      - The caller has neither accepted queue-proposer role (NotAuthorised).
    /// @param caller_ Actual caller whose governance role is checked.
    function _requireProposerRole(address caller_) internal view {
        _requireAuthorized(
            !_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, BURNER_LOANS_ADMIN_ROLE)
        );
    }

    // ========== VERSION ========== //

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    // ========== ERC165 ========== //

    /// @notice ERC165 interface support.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param interfaceId_ ERC-165 interface identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(EnablerV2, ReEnablerGracePeriod, ConfigTimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IBurnerLoansConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ========== QUEUED CONFIGURATION TRANSFORMATIONS ========== //

    /// @notice Projects a complete asset configuration into the risk setter's input shape.
    /// @dev No external state or token calls; checked arithmetic errors propagate.
    /// @param config_ Canonical market or proposed parameter configuration.
    /// @return IBurnerLoansRisk.AssetRiskConfigInput Mutable risk fields extracted from the complete market configuration.
    function _toRiskConfig(
        IBurnerLoansCore.AssetConfig memory config_
    ) private pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return
            IBurnerLoansRisk.AssetRiskConfigInput({
                maxLtvBps: config_.maxLtvBps,
                backingMultiplierBps: config_.backingMultiplierBps,
                keeperRewardBps: config_.keeperRewardBps,
                termLength: config_.termLength,
                maxMaturityHorizon: config_.maxMaturityHorizon,
                maxKeeperReward: config_.maxKeeperReward
            });
    }

    /// @notice Rejects unused pause payloads while preserving inactive disable.
    /// @dev Reverts if:
    ///      - Data is nonempty; no dependency readiness is required.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @notice Checks grace overflow without altering the shared ReEnabler.
    /// @dev Reverts if:
    ///      - The inclusive deadline overflows uint48 or expired.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
