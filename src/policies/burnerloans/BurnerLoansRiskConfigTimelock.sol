// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansRiskConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansRiskConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {Address} from "@openzeppelin-5.7.0/utils/Address.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @notice Delayed referral and cache-age configuration for one directly bound Risk.
/// @dev Independent setting keys permit concurrent intents. Direct target ADMIN access is retained.
contract BurnerLoansRiskConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IBurnerLoansRiskConfigTimelock,
    IVersioned
{
    using SafeCall for address;

    /// @notice Length of one ABI-encoded address, boolean or integer, in bytes.
    uint256 private constant _ABI_WORD_BYTES = 32;
    /// @notice Copies one word plus one byte to reject oversized status responses.
    uint16 private constant _MAX_SETTING_RETURN_BYTES = 33;

    /// @notice Fixed notice before execution, in seconds.
    uint48 public constant MIN_TIMELOCK_DELAY = 1 days;
    /// @notice Maximum supported notice, in seconds.
    uint48 public constant MAX_TIMELOCK_DELAY = 30 days;
    /// @notice Inclusive execution window after the notice, in seconds.
    uint48 public constant EXECUTION_WINDOW = 3 days;
    IBurnerLoansRisk internal immutable _RISK;

    /// @notice Binds this queue to one already-deployed same-Kernel Risk.
    /// @dev Reverts if:
    ///      - Risk lacks its interface or reports a different Kernel. Local activity is not required yet.
    /// @param kernel_ Kernel supplying governance roles.
    /// @param risk_ Immutable Risk settings target.
    constructor(
        Kernel kernel_,
        IBurnerLoansRisk risk_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        _requireRiskInterfaces(address(risk_));
        PolicyDependency.requireSameKernel(address(risk_), address(kernel_));
        _RISK = risk_;
    }

    /// @inheritdoc IBurnerLoansRiskConfigTimelock
    /// @dev Returns the immutable target without external calls; does not revert.
    function risk() external view override returns (IBurnerLoansRisk) {
        return _RISK;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - ROLES is missing or has an unsupported major version.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // Only the module major version determines compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 major, ) = ROLES.VERSION();
        if (major != 1) revert IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion();
    }

    /// @inheritdoc Policy
    /// @dev Requests no module-write permissions.
    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    modifier onlyActive() {
        _requireOwnActive();
        _;
    }

    /// @dev Reverts if:
    ///      - The caller holds neither accepted queue-proposer role.
    modifier onlyProposerRole() {
        _requireProposerRole(msg.sender);
        _;
    }

    /// @dev Reverts if:
    ///      - The caller holds neither accepted queue-proposer role (NotAuthorised).
    /// @param caller_ Actual caller whose governance role is checked.
    function _requireProposerRole(address caller_) private view {
        if (!_hasRole(caller_, ADMIN_ROLE) && !_hasRole(caller_, BURNER_LOANS_ADMIN_ROLE))
            revert NotAuthorised();
    }

    /// @inheritdoc IBurnerLoansRiskConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Risk's Kernel or enabled-state metadata is invalid.
    ///      - Risk reports a different Kernel.
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - Risk's operator getter is invalid or this timelock is not selected.
    ///      - The referral share exceeds 10,000 basis points.
    ///      - The referral-share key is reserved.
    ///      - The shared queue action-ID or deadline bounds are exceeded.
    function queueSetReferralFeeBps(
        uint16 bps_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_RISK),
                IBurnerLoansRisk.setReferralFeeBps.selector,
                abi.encode(bps_)
            );
    }

    /// @inheritdoc IBurnerLoansRiskConfigTimelock
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Risk's Kernel or enabled-state metadata is invalid.
    ///      - Risk reports a different Kernel.
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - Risk's operator getter is invalid or this timelock is not selected.
    ///      - The referrer is zero.
    ///      - The membership key for this referrer is reserved.
    ///      - The shared queue action-ID or deadline bounds are exceeded.
    function queueSetReferrerAllowed(
        address referrer_,
        bool allowed_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_RISK),
                IBurnerLoansRisk.setReferrerAllowed.selector,
                abi.encode(referrer_, allowed_)
            );
    }

    /// @inheritdoc IBurnerLoansRiskConfigTimelock
    /// @dev All uint48 cache ages are valid.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - The caller holds neither ADMIN nor BURNER_LOANS_ADMIN.
    ///      - Risk's Kernel or enabled-state metadata is invalid.
    ///      - Risk reports a different Kernel.
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - Risk's operator getter is invalid or this timelock is not selected.
    ///      - The cache-age key is reserved.
    ///      - The shared queue action-ID or deadline bounds are exceeded.
    function queueSetPriceCacheMaxAge(
        uint48 age_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_RISK),
                IBurnerLoansRisk.setPriceCacheMaxAge.selector,
                abi.encode(age_)
            );
    }

    /// @inheritdoc IBurnerLoansRiskConfigTimelock
    /// @dev Reverts if:
    ///      - Batch bounds, target admission, payload validation, or key acquisition fails.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return _queueAction(actions_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - Local/target admission fails, proposer lacks both accepted roles, or controller selection changed.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnActive();
        _requireEnabled();
        _requireProposerRole(caller_);
        _requireTargetReady();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The target or selector is unsupported, or the payload is noncanonical.
    ///      - A setting value is invalid.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        bytes4 selector = action_.selector;
        if (action_.target != address(_RISK))
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        if (selector == IBurnerLoansRisk.setReferralFeeBps.selector) {
            _requireLength(action_, _ABI_WORD_BYTES);
            uint256 value = abi.decode(action_.payload, (uint256));
            if (value > type(uint16).max)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            if (value > LoanParameters._MAX_BPS)
                revert IBurnerLoansRisk.BurnerLoansRisk_InvalidReferralFeeBps(
                    SafeCast.toUint16(value)
                );
            return;
        }
        if (selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector) {
            _requireLength(action_, _ABI_WORD_BYTES);
            if (abi.decode(action_.payload, (uint256)) > type(uint48).max)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            return;
        }
        if (selector == IBurnerLoansRisk.setReferrerAllowed.selector) {
            _requireLength(action_, 2 * _ABI_WORD_BYTES);
            (uint256 referrer, uint256 allowed) = abi.decode(action_.payload, (uint256, uint256));
            if (referrer > type(uint160).max || allowed > 1)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            if (referrer == 0) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address) {
        return address(_RISK);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Independent global settings and per-referrer membership have separate keys.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = action_.selector == IBurnerLoansRisk.setReferrerAllowed.selector
            ? keccak256(abi.encode(action_.selector, abi.decode(action_.payload, (address))))
            : keccak256(abi.encode(action_.selector));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Commits only the selected operator and the setting affected by this action.
    /// @dev Reverts if:
    ///      - The current operator or setting getter fails or returns malformed data.
    ///      - The setting getter returns a noncanonical narrow value.
    ///      - A referrer payload cannot be decoded.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32) {
        address controller = _riskAddress(IConfigOperator.configOperator.selector);
        if (action_.selector == IBurnerLoansRisk.setReferralFeeBps.selector) {
            uint16 bps = SafeCast.toUint16(
                _riskWord(
                    abi.encodeWithSelector(IBurnerLoansRisk.referralFeeBps.selector),
                    type(uint16).max
                )
            );
            return keccak256(abi.encode(controller, bps));
        }
        if (action_.selector == IBurnerLoansRisk.setPriceCacheMaxAge.selector) {
            uint48 age = SafeCast.toUint48(
                _riskWord(
                    abi.encodeWithSelector(IBurnerLoansRisk.priceCacheMaxAge.selector),
                    type(uint48).max
                )
            );
            return keccak256(abi.encode(controller, age));
        }
        address referrer = abi.decode(action_.payload, (address));
        bool value = _riskWord(abi.encodeCall(IBurnerLoansRisk.isReferrerAllowed, (referrer)), 1) ==
            1;
        return keccak256(abi.encode(controller, value));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The admitted target fails. Propagates 1..255 revert bytes; empty/capped failures are wrapped.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        (bool ok, bytes memory data) = action_.target.safeCall(
            gasleft(),
            0,
            256,
            abi.encodePacked(action_.selector, action_.payload)
        );
        if (!ok) {
            if (data.length == 0 || data.length == 256)
                revert BurnerLoansRiskTimelock_SubActionCallFailed(action_.selector);
            Address.verifyCallResult(ok, data);
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev The shared base separately checks stored pre-state commitments.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - Risk's Kernel or enabled-state metadata is invalid.
    ///      - Risk reports a different Kernel.
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - Risk's operator getter is invalid or this timelock is not selected.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireReady();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Local pause, broken targets and operator selection do not prevent cancellation.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - The caller lacks EMERGENCY.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnActive();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Validates local lifecycle and the bound Risk target.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - Risk's Kernel or enabled-state metadata is invalid.
    ///      - Risk reports a different Kernel.
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - Risk's operator getter is invalid or this timelock is not selected.
    function _requireReady() private view {
        _requireOwnActive();
        _requireEnabled();
        _requireTargetReady();
    }

    /// @notice Revalidates Risk's independent lifecycle and this queue's delegated authority.
    /// @dev Reverts if:
    ///      - Risk's Kernel or enabled-state metadata is invalid.
    ///      - Risk reports a different Kernel.
    ///      - Risk is Kernel-inactive.
    ///      - Risk is locally disabled.
    ///      - Risk's operator getter is invalid or this timelock is not selected.
    function _requireTargetReady() private view {
        PolicyDependency.requireActiveAndEnabled(address(_RISK), address(kernel));
        if (_riskAddress(IConfigOperator.configOperator.selector) != address(this))
            revert BurnerLoansRiskTimelock_NotController();
    }

    /// @notice Requires own policy membership with a product-owned error.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    function _requireOwnActive() private view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @notice Requires the canonical static payload length.
    /// @dev Reverts if:
    ///      - Payload length differs from the operation's ABI.
    /// @param action_ Proposed operation.
    /// @param length_ Required payload length in bytes.
    function _requireLength(
        ITimelockBatchQueue.BatchAction memory action_,
        uint256 length_
    ) private pure {
        if (action_.payload.length != length_)
            revert ITimelockBatchQueue_ActionInvalid(action_.target, action_.selector);
    }

    /// @inheritdoc EnablerV2
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
        _validateActivation();
    }

    /// @inheritdoc EnablerV2
    /// @dev Kernel inactivity does not prevent disable.
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @inheritdoc ReEnablerGracePeriod
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
        _validateActivation();
    }

    /// @notice Revalidates target compatibility, activity and controller selection.
    /// @dev Target local enablement is neither read nor required.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - The target lacks a consumed interface.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///      - The target is Kernel-inactive.
    ///      - The target operator getter fails or returns malformed data.
    ///      - This timelock is not the target's selected config operator.
    function _validateActivation() private view {
        _requireOwnActive();
        _requireRiskInterfaces(address(_RISK));
        PolicyDependency.requireActive(address(_RISK), address(kernel));
        if (_riskAddress(IConfigOperator.configOperator.selector) != address(this))
            revert BurnerLoansRiskTimelock_NotController();
    }

    /// @notice Checks every interface consumed by this queue without requiring target enablement.
    /// @dev Checks compatibility without reading target enablement.
    /// @dev Reverts if:
    ///      - An ERC165 probe fails or returns noncanonical data.
    ///      - A consumed interface is unsupported or the invalid interface ID is advertised.
    function _requireRiskInterfaces(address target_) private view {
        if (
            !_supportsInterface(target_, type(IERC165).interfaceId, true) ||
            !_supportsInterface(target_, 0xffffffff, false) ||
            !_supportsInterface(target_, type(IBurnerLoansRisk).interfaceId, true) ||
            !_supportsInterface(target_, type(IConfigOperator).interfaceId, true) ||
            !_supportsInterface(target_, type(IEnabler).interfaceId, true)
        ) revert BurnerLoansRiskTimelock_InvalidRisk(target_);
    }

    /// @dev Reverts if:
    ///      - The target address getter fails or returns a noncanonical address.
    function _riskAddress(bytes4 selector_) private view returns (address result) {
        bool success;
        (success, result) = SafeCallDecoder.safeReadAddress(address(_RISK), selector_);
        if (!success) revert BurnerLoansRiskTimelock_InvalidRisk(address(_RISK));
    }

    /// @notice Reads canonical ERC165 advertisement with the standard gas allowance.
    /// @dev Returns false on failed calls, dirty booleans or non-word return data.
    function _supportsInterface(
        address target_,
        bytes4 id_,
        bool expected_
    ) private view returns (bool) {
        (bool ok, bytes memory data) = target_.safeStaticCall(
            30000,
            _MAX_SETTING_RETURN_BYTES,
            abi.encodeCall(IERC165.supportsInterface, (id_))
        );
        if (!ok || data.length != _ABI_WORD_BYTES) return false;
        uint256 word = abi.decode(data, (uint256));
        return word <= 1 && (word == 1) == expected_;
    }

    /// @notice Reads one canonical setting word with a bounded return buffer.
    /// @dev Reverts if:
    ///      - The setting getter fails or returns a non-word response.
    ///      - The returned value exceeds the admitted maximum.
    function _riskWord(bytes memory call_, uint256 maximum_) private view returns (uint256 value) {
        (bool ok, bytes memory data) = address(_RISK).safeStaticCall(
            gasleft(),
            _MAX_SETTING_RETURN_BYTES,
            call_
        );
        if (!ok || data.length != _ABI_WORD_BYTES)
            revert BurnerLoansRiskTimelock_InvalidRisk(address(_RISK));
        value = abi.decode(data, (uint256));
        if (value > maximum_) revert BurnerLoansRiskTimelock_InvalidRisk(address(_RISK));
    }

    /// @notice Authorizes a fast re-enable transition.
    /// @dev Reverts if:
    ///      - Caller holds neither ADMIN nor Burner Loans admin.
    function _authorizeReEnable() internal view override {
        if (!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE))
            revert NotAuthorised();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireOwnActive();
        super.setGracePeriod(period_);
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    ///      - This policy is inactive.
    ///      Unchanged periods still emit the inherited event.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - There is uint48 deadline overflow or an expired inclusive grace window.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Reverts if:
    ///      - The delay is outside the supported notice interval.
    function _validateTimelockDelay(uint48 delay_) internal pure override {
        if (delay_ < MIN_TIMELOCK_DELAY || delay_ > MAX_TIMELOCK_DELAY)
            revert ITimelockBatchQueue_TimelockDelayInvalid(
                delay_,
                MIN_TIMELOCK_DELAY,
                MAX_TIMELOCK_DELAY
            );
    }

    /// @inheritdoc TimelockBatchQueue
    function _executionWindow() internal pure override returns (uint48) {
        return EXECUTION_WINDOW;
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @notice Advertises the narrow queue and inherited framework interfaces.
    /// @param interfaceId_ Interface selector to inspect.
    /// @return bool Whether this implementation supports that interface.
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(EnablerV2, ReEnablerGracePeriod, ConfigTimelockBatchQueue)
        returns (bool)
    {
        return
            interfaceId_ == type(IBurnerLoansRiskConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
