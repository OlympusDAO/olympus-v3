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
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";
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
/// @dev Market updates and Core surplus rescue call Config through its delegated config operator.
///      Risk settings use BurnerLoansRiskConfigTimelock. This queue validates the proposer's role
///      and Config's current lifecycle, Kernel binding and operator selection.
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

    /// @dev Checks queue bounds with widened arithmetic before the shared queue stores them.
    /// @dev Reverts if:
    ///      - The next action ID exceeds uint64.
    ///      - The queue timestamp, executable timestamp or expiry exceeds uint48.
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
    /// @dev Construction does not query target activity, enablement or operator selection.
    /// @dev Reverts if:
    ///      - The target is zero or lacks a consumed Config, ConfigOperator or Enabler interface.
    ///      - The target Core binding is unreadable or Core lacks IBurnerLoansCore.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///
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
        _requireTargetInterfaces(address(burnerLoansConfig_));
        PolicyDependency.requireSameKernel(address(burnerLoansConfig_), address(kernel_));

        _BURNER_LOANS_CONFIG = burnerLoansConfig_;
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @notice Configures module dependencies for the policy.
    /// @dev Reverts if:
    ///      - The ROLES module is not installed.
    ///      - The installed ROLES module does not have major version 1.
    ///
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

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @notice Returns the Burner Loans Config policy targeted by this timelock.
    /// @dev Returns the immutable target without external calls.
    ///
    /// @return IBurnerLoansConfig The Burner Loans Config policy.
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

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @notice Queues an asset fee-curve update.
    /// @dev Execution revalidates the stored configuration commitment and the target's live checks.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Config reports a different Kernel or its Kernel metadata cannot be read.
    ///      - Config is Kernel-inactive.
    ///      - This timelock is not Config's selected operator or its operator metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The asset is not configured.
    ///      - The proposed fee curve violates Config's fee bounds.
    ///      - A conflicting configuration key is already reserved.
    ///      - The next action ID or a queue deadline exceeds its stored integer width.
    ///
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

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @notice Queues an asset active debt cap update.
    /// @dev Execution revalidates the stored configuration commitment and the target's live checks.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Config reports a different Kernel or its Kernel metadata cannot be read.
    ///      - Config is Kernel-inactive.
    ///      - This timelock is not Config's selected operator or its operator metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The asset is not configured.
    ///      - The proposed cap is below the asset's current active debt.
    ///      - A conflicting configuration key is already reserved.
    ///      - The next action ID or a queue deadline exceeds its stored integer width.
    ///
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
    /// @dev Execution revalidates the stored configuration commitment and the target's live checks.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Config reports a different Kernel or its Kernel metadata cannot be read.
    ///      - Config is Kernel-inactive.
    ///      - This timelock is not Config's selected operator or its operator metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The rescue preview rejects the token.
    ///      - The rescue preview rejects the destination.
    ///      - Config's Core binding, selected Core operator or settlement guard rejects rescue.
    ///      - A conflicting configuration key is already reserved.
    ///      - The next action ID or a queue deadline exceeds its stored integer width.
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
    /// @dev Execution revalidates the stored configuration commitment and the target's live checks.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Config reports a different Kernel or its Kernel metadata cannot be read.
    ///      - Config is Kernel-inactive.
    ///      - This timelock is not Config's selected operator or its operator metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The asset is not configured.
    ///      - DepositManager rejects the proposed withdrawal mode.
    ///      - A conflicting configuration key is already reserved.
    ///      - The next action ID or a queue deadline exceeds its stored integer width.
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

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @notice Queues a complete asset risk-configuration update.
    /// @dev Execution revalidates the stored configuration commitment and the target's live checks.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Config reports a different Kernel or its Kernel metadata cannot be read.
    ///      - Config is Kernel-inactive.
    ///      - This timelock is not Config's selected operator or its operator metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The asset is not configured.
    ///      - The proposed risk configuration violates Config's bounds.
    ///      - A conflicting configuration key is already reserved.
    ///      - The next action ID or a queue deadline exceeds its stored integer width.
    ///
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

    /// @inheritdoc IBurnerLoansConfigTimelock
    /// @notice Queues a batch of Burner Loans configuration updates.
    /// @dev Validation and later execution are atomic in array order.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Config reports a different Kernel or its Kernel metadata cannot be read.
    ///      - Config is Kernel-inactive.
    ///      - This timelock is not Config's selected operator or its operator metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The batch is empty or exceeds the shared action or key limits.
    ///      - A sub-action has an unsupported target, selector or noncanonical payload.
    ///      - A sub-action fails its typed queue helper's input or live-preview validation.
    ///      - The batch repeats a key or conflicts with a pending action.
    ///      - The next action ID or a queue deadline exceeds its stored integer width.
    ///
    /// @param actions_ Burner Loans configuration sub-actions.
    /// @return uint64 The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external onlyActive givenEnabled onlyProposerRole withinQueueBounds returns (uint64) {
        return _queueAction(actions_);
    }

    // ========== TIMELOCK HOOKS ========== //

    /// @notice Validates queue-wide authorization and lifecycle requirements.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requireProposerRole(caller_);
    }

    /// @notice Validates one product sub-action before shared key acquisition.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - Config's Kernel metadata is invalid or reports a different Kernel.
    ///      - Config is Kernel-inactive.
    ///      - Config's selected operator is different or its metadata is invalid.
    ///      - Config is locally disabled or its enabled-state getter fails.
    ///      - The target, selector or canonical payload validation fails.
    ///      - The asset configuration or target preview rejects the requested change.
    ///
    /// @param action_ Admitted queued configuration setter and payload.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        _requirePoliciesActive();
        _requireAuthorizedConfigOperator();
        _requireBurnerLoansConfigEnabled();
        _validateQueuedBurnerLoansAction(action_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Selectors define separate per-asset or per-token conflict domains.
    /// @dev Reverts if:
    ///      - The payload cannot be decoded as an asset or token address.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = keccak256(abi.encode(action_.selector, abi.decode(action_.payload, (address))));
    }

    /// @notice Selects the configuration contract that owns the guarded domains.
    /// @dev Returns the immutable Config target without external calls.
    ///
    /// @return address Bound Config policy receiving the queued setter.
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address) {
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
        address operator = _readConfigOperator();

        if (selector == IBurnerLoansConfig.rescue.selector)
            return
                keccak256(
                    abi.encode(facility, IConfigOperator(facility).configOperator(), operator)
                );
        address asset = abi.decode(action_.payload, (address));
        if (selector == IBurnerLoansConfig.setAssetFeeConfig.selector)
            return
                keccak256(
                    abi.encode(
                        facility,
                        asset,
                        _BURNER_LOANS_CONFIG.getAssetFeeConfig(asset),
                        operator
                    )
                );
        IBurnerLoansCore.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(asset);
        if (selector == IBurnerLoansConfig.setAssetRiskConfig.selector)
            return keccak256(abi.encode(facility, asset, _toRiskConfig(config), operator));
        if (selector == IBurnerLoansConfig.setAssetDebtCap.selector)
            return keccak256(abi.encode(facility, asset, config.debtCap, operator));
        if (selector == IBurnerLoansConfig.setAssetOriginationsEnabled.selector)
            return keccak256(abi.encode(facility, asset, config.originationsEnabled, operator));
        if (selector == IBurnerLoansConfig.setAssetWithdrawAsShares.selector)
            return keccak256(abi.encode(facility, asset, config.withdrawAsShares, operator));
        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - Config's Kernel metadata is invalid or reports a different Kernel.
    ///      - Config is Kernel-inactive.
    ///      - Config's enabled-state getter fails or reports false.
    ///      - Config's operator metadata is invalid or this timelock is no longer selected.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnPolicyActive();
        _requireEnabled();
        _requirePoliciesActive();
        _requireBurnerLoansConfigEnabled();
        _requireAuthorizedConfigOperator();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Local pause, target state and operator selection do not gate cancellation.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - The caller lacks EMERGENCY.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnPolicyActive();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev The inherited re-enable hook separately enforces the grace window.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
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

    /// @dev Target local enablement is neither read nor required.
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      - This timelock is Kernel-inactive.
    ///      - The target lacks a consumed interface.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///      - The target is Kernel-inactive.
    ///      - The target operator getter fails or returns malformed data.
    ///      - This timelock is not the target's selected config operator.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _requireBurnerLoansActive();
    }

    /// @dev Target local enablement is neither read nor required.
    /// @dev Reverts if:
    ///      - The inclusive grace deadline exceeds uint48.
    ///      - The inclusive grace deadline has expired.
    ///      - This timelock is Kernel-inactive.
    ///      - The target lacks a consumed interface.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///      - The target is Kernel-inactive.
    ///      - The target operator getter fails or returns malformed data.
    ///      - This timelock is not the target's selected config operator.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireBurnerLoansActive();
    }

    /// @dev A target pause does not block activation.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - The target lacks a consumed interface.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///      - The target is Kernel-inactive.
    ///      - The target operator getter fails or returns malformed data.
    ///      - This timelock is not the target's selected config operator.
    function _requireBurnerLoansActive() internal view {
        _requireOwnPolicyActive();
        address target = address(_BURNER_LOANS_CONFIG);
        _requireTargetInterfaces(target);
        PolicyDependency.requireActive(target, address(kernel));
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
    /// @dev Returns the constant window without external calls or arithmetic.
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

    /// @dev Reverts if:
    ///      - The target lacks Config, ConfigOperator or Enabler interface support.
    ///      - Its Core getter fails or returns a malformed address.
    ///      - Core lacks IBurnerLoansCore.
    function _requireTargetInterfaces(address target_) private view {
        if (
            !ERC165Checker.supportsInterface(target_, type(IBurnerLoansConfig).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IConfigOperator).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IEnabler).interfaceId)
        ) revert BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(target_);
        (bool validCore, address core) = SafeCallDecoder.safeReadAddress(
            target_,
            IBurnerLoansConfig.facility.selector
        );
        if (!validCore) revert BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(target_);
        // Queue validation reads Core.depositManager() directly for withdrawal-token changes.
        if (!ERC165Checker.supportsInterface(core, type(IBurnerLoansCore).interfaceId))
            revert BurnerLoansConfigTimelock_InvalidCore(core);
    }

    /// @dev Reverts if:
    ///      - Config's operator getter fails or returns a noncanonical address.
    function _readConfigOperator() private view returns (address operator) {
        bool success;
        (success, operator) = SafeCallDecoder.safeReadAddress(
            address(_BURNER_LOANS_CONFIG),
            IConfigOperator.configOperator.selector
        );
        if (!success)
            revert BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(
                address(_BURNER_LOANS_CONFIG)
            );
    }

    /// @notice Requires this timelock to remain the Config policy's authorized operator.
    /// @dev Reverts if:
    ///      - Config's operator getter fails or returns a noncanonical address.
    ///      - Config's selected operator is not this timelock.
    function _requireAuthorizedConfigOperator() internal view {
        // Each queued action revalidates its own policy binding and readiness.
        // forge-lint: disable-next-line(calls-loop)
        if (_readConfigOperator() != address(this)) {
            // Each queued action revalidates its own policy binding and readiness.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator(address(this));
        }
    }

    /// @notice Validates that the controlled BurnerLoansConfig policy is enabled.
    /// @dev Reverts if:
    ///      - Config's enabled-state getter fails or cannot be ABI-decoded.
    ///      - Config is locally disabled (PolicyDependency_NotActive).
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

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - Config's Kernel getter fails or returns malformed data.
    ///      - Config reports a different Kernel.
    ///      - Config is Kernel-inactive.
    function _requirePoliciesActive() internal view {
        _requireOwnPolicyActive();
        PolicyDependency.requireActive(address(_BURNER_LOANS_CONFIG), address(kernel));
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
    /// @dev Copies the mutable risk fields without external calls or arithmetic.
    ///
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
    /// @dev No target readiness is required.
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @notice Checks grace overflow without altering the shared ReEnabler.
    /// @dev Reverts if:
    ///      - The inclusive grace deadline exceeds uint48.
    ///      - The current timestamp exceeds the inclusive grace deadline.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
