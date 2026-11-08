// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";
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
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @notice Delayed routing and recovery calling a directly bound Payout.
/// @dev Retired Payout remains a valid target. No ADMIN grant or general Config layer is needed.
contract BurnerLoansPayoutConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IBurnerLoansPayoutConfigTimelock,
    IVersioned
{
    using SafeCall for address;

    /// @notice Length of one ABI-encoded address, boolean or integer, in bytes.
    uint256 private constant _ABI_WORD_BYTES = 32;
    /// @notice Payload length of rescue(address,address), in bytes.
    uint256 private constant _RESCUE_PAYLOAD_BYTES = 2 * _ABI_WORD_BYTES;
    /// @notice Payload length of rescuePendingPayout(address,address,address,uint256), in bytes.
    uint256 private constant _RESCUE_PENDING_PAYOUT_PAYLOAD_BYTES = 4 * _ABI_WORD_BYTES;

    /// @notice Fixed notice before execution, in seconds.
    uint48 public constant MIN_TIMELOCK_DELAY = 1 days;
    /// @notice Maximum supported notice, in seconds.
    uint48 public constant MAX_TIMELOCK_DELAY = 30 days;
    /// @notice Inclusive execution window after the notice, in seconds.
    uint48 public constant EXECUTION_WINDOW = 3 days;
    /// @notice Immutable target for all queued configuration and recovery actions.
    IBurnerLoansPayout internal immutable _PAYOUT;

    /// @notice Binds this queue to one already-deployed same-Kernel Payout.
    /// @dev Construction does not query target activity, local enablement or operator selection.
    /// @dev Reverts if:
    ///      - The target lacks a consumed domain, ConfigOperator or Enabler interface.
    ///      - The target Kernel getter fails or returns malformed data.
    ///      - The target reports a different Kernel.
    ///
    /// @param kernel_ Kernel supplying governance roles.
    /// @param payout_ Immutable routing/recovery target.
    constructor(
        Kernel kernel_,
        IBurnerLoansPayout payout_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        _requireTargetInterfaces(address(payout_));
        PolicyDependency.requireSameKernel(address(payout_), address(kernel_));
        _PAYOUT = payout_;
    }

    /// @inheritdoc IBurnerLoansPayoutConfigTimelock
    /// @dev Returns the immutable target without external calls; does not revert.
    function payout() external view override returns (IBurnerLoansPayout) {
        return _PAYOUT;
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

    /// @inheritdoc IBurnerLoansPayoutConfigTimelock
    /// @dev Reverts if:
    ///      - Admission, distributor validation or scoped-key acquisition fails. True revalidates the distributor even when already true.
    function queueSetSendFeesToDistributor(
        bool enabled_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_PAYOUT),
                IBurnerLoansPayout.setSendFeesToDistributor.selector,
                abi.encode(enabled_)
            );
    }

    /// @inheritdoc IBurnerLoansPayoutConfigTimelock
    /// @dev Reverts if:
    ///      - Admission, distributor validation or scoped-key acquisition fails. False requires no distributor.
    function queueSetSendYieldToDistributor(
        bool enabled_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_PAYOUT),
                IBurnerLoansPayout.setSendYieldToDistributor.selector,
                abi.encode(enabled_)
            );
    }

    /// @inheritdoc IBurnerLoansPayoutConfigTimelock
    /// @dev Reverts if:
    ///      - Admission, token/destination validation or scoped-key acquisition fails. No balance is reserved at queue time.
    function queueRescue(
        address token_,
        address destination_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_PAYOUT),
                IBurnerLoansPayout.rescue.selector,
                abi.encode(token_, destination_)
            );
    }

    /// @inheritdoc IBurnerLoansPayoutConfigTimelock
    /// @dev Reverts if:
    ///      - Admission or live entitlement validation fails. Execution recomputes entitlement rather than reserving the quote.
    function queueRescuePendingPayout(
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_PAYOUT),
                IBurnerLoansPayout.rescuePendingPayout.selector,
                abi.encode(token_, recipient_, destination_, amount_)
            );
    }

    /// @inheritdoc IBurnerLoansPayoutConfigTimelock
    /// @dev Reverts if:
    ///      - Batch bounds or any operation fails validation. Distributor replacement is not an admitted selector.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external override onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return _queueAction(actions_);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - Locally disabled/inactive, the bound Kernel changed, proposer lacks both accepted roles, or controller selection changed.
    ///      - Payout is Kernel-inactive. A local Payout pause does not block admission.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnActive();
        _requireEnabled();
        _requireProposerRole(caller_);
        PolicyDependency.requireSameKernel(address(_PAYOUT), address(kernel));
        if (IConfigOperator(address(_PAYOUT)).configOperator() != address(this))
            revert NotAuthorised();
        if (!kernel.isPolicyActive(Policy(address(_PAYOUT))))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(_PAYOUT));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The target or selector is unsupported, or the payload is noncanonical.
    ///      - The live routing or recovery request is invalid.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        bytes4 selector = action_.selector;
        if (action_.target != address(_PAYOUT))
            revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
        if (
            selector == IBurnerLoansPayout.setSendFeesToDistributor.selector ||
            selector == IBurnerLoansPayout.setSendYieldToDistributor.selector
        ) {
            _requireLength(action_, _ABI_WORD_BYTES);
            uint256 value = abi.decode(action_.payload, (uint256));
            if (value > 1) revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            if (value == 1) _PAYOUT.validateRevenueDistributor(_PAYOUT.revenueDistributor());
            return;
        }
        if (selector == IBurnerLoansPayout.rescue.selector) {
            _requireLength(action_, _RESCUE_PAYLOAD_BYTES);
            uint256[2] memory words = abi.decode(action_.payload, (uint256[2]));
            if (words[0] > type(uint160).max || words[1] > type(uint160).max)
                revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address token, address destination) = abi.decode(action_.payload, (address, address));
            // This validates admission; the result does not commit a balance or replace execution-time checks.
            // forge-lint: disable-next-line(unused-return)
            _PAYOUT.previewRescue(token, destination);
            return;
        }
        if (selector == IBurnerLoansPayout.rescuePendingPayout.selector) {
            _requireLength(action_, _RESCUE_PENDING_PAYOUT_PAYLOAD_BYTES);
            uint256[4] memory words = abi.decode(action_.payload, (uint256[4]));
            if (
                words[0] > type(uint160).max ||
                words[1] > type(uint160).max ||
                words[2] > type(uint160).max
            ) revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
            (address token, address recipient, address destination, uint256 amount) = abi.decode(
                action_.payload,
                (address, address, address, uint256)
            );
            // This validates admission; the result does not commit a balance or replace execution-time checks.
            // forge-lint: disable-next-line(unused-return)
            _PAYOUT.previewRescuePendingPayout(token, recipient, destination, amount);
            return;
        }
        revert ITimelockBatchQueue_ActionInvalid(action_.target, selector);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address) {
        return address(_PAYOUT);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Separate fee/yield keys permit their independent disable commands in one batch.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory action_
    ) internal pure override returns (bytes32[] memory keys) {
        // Global routing flags conflict per selector; surplus recovery conflicts per token; pending
        // recovery conflicts per token and recipient. Independent obligations can be queued together.
        bytes32 key;
        if (action_.selector == IBurnerLoansPayout.rescuePendingPayout.selector) {
            (address token, address recipient, , ) = abi.decode(
                action_.payload,
                (address, address, address, uint256)
            );
            key = keccak256(abi.encode(action_.selector, token, recipient));
        } else if (action_.selector == IBurnerLoansPayout.rescue.selector)
            key = keccak256(abi.encode(action_.selector, abi.decode(action_.payload, (address))));
        else key = keccak256(abi.encode(action_.selector));
        keys = new bytes32[](1);
        keys[0] = key;
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Commits the operator and relevant routing identities; balances and entitlements remain live.
    /// @dev Reverts if:
    ///      - A consumed target getter fails or cannot be ABI-decoded.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override returns (bytes32) {
        // Pending amounts may be paid or credited while notice runs. Commit to the controller and
        // routing that define the entitlement; Payout checks the still-available amount at execution.
        address controller = IConfigOperator(address(_PAYOUT)).configOperator();
        if (action_.selector == IBurnerLoansPayout.setSendFeesToDistributor.selector)
            return
                keccak256(
                    abi.encode(
                        controller,
                        _PAYOUT.sendFeesToDistributor(),
                        _PAYOUT.revenueDistributor()
                    )
                );
        if (action_.selector == IBurnerLoansPayout.setSendYieldToDistributor.selector)
            return
                keccak256(
                    abi.encode(
                        controller,
                        _PAYOUT.sendYieldToDistributor(),
                        _PAYOUT.revenueDistributor()
                    )
                );
        if (action_.selector == IBurnerLoansPayout.rescuePendingPayout.selector)
            return
                keccak256(
                    abi.encode(
                        controller,
                        _PAYOUT.sendFeesToDistributor(),
                        _PAYOUT.revenueDistributor(),
                        _PAYOUT.treasury()
                    )
                );
        return keccak256(abi.encode(controller));
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
                revert BurnerLoansPayoutTimelock_SubActionCallFailed(action_.selector);
            Address.verifyCallResult(ok, data);
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev The shared base separately checks stored operator commitments.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - Payout's Kernel getter fails or returns malformed data.
    ///      - Payout reports a different Kernel.
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

    /// @notice Validates only this queue's lifecycle and the bound target's Kernel.
    /// @dev Target actions enforce their operation-specific lifecycle checks.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    ///      - This timelock is locally disabled.
    ///      - Payout's Kernel getter fails or returns malformed data.
    ///      - Payout reports a different Kernel.
    function _requireReady() private view {
        _requireOwnActive();
        _requireEnabled();
        // Each Payout preview/mutation enforces target activity. Active paused or deselected
        // Payouts retain routing and recovery access.
        PolicyDependency.requireSameKernel(address(_PAYOUT), address(kernel));
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

    /// @dev Construction and activation share this compatibility predicate.
    /// @dev Reverts if:
    ///      - The target lacks a consumed domain, ConfigOperator or Enabler interface.
    function _requireTargetInterfaces(address target_) private view {
        if (
            !ERC165Checker.supportsInterface(target_, type(IBurnerLoansPayout).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IConfigOperator).interfaceId) ||
            !ERC165Checker.supportsInterface(target_, type(IEnabler).interfaceId)
        ) revert BurnerLoansPayoutTimelock_InvalidPayout(target_);
    }

    /// @notice Revalidates target identity and selection without requiring Core operation.
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
        address target = address(_PAYOUT);
        _requireTargetInterfaces(target);
        PolicyDependency.requireActive(target, address(kernel));
        if (_payoutAddress(IConfigOperator.configOperator.selector) != address(this))
            revert BurnerLoansPayoutTimelock_NotController();
    }

    /// @dev Reverts if:
    ///      - The target address getter fails or returns a noncanonical address.
    function _payoutAddress(bytes4 selector_) private view returns (address result) {
        bool success;
        (success, result) = SafeCallDecoder.safeReadAddress(address(_PAYOUT), selector_);
        if (!success) revert BurnerLoansPayoutTimelock_InvalidPayout(address(_PAYOUT));
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
            interfaceId_ == type(IBurnerLoansPayoutConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
