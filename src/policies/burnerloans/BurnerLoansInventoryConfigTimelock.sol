// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
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
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigTimelockBatchQueue} from "src/policies/utils/ConfigTimelockBatchQueue.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";
import {TimelockBatchQueue} from "src/policies/utils/TimelockBatchQueue.sol";

/// @notice Delayed surplus recovery calling one directly bound Inventory.
/// @dev Core and BurnerLoansConfig replacement do not redirect this immutable target.
contract BurnerLoansInventoryConfigTimelock is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigTimelockBatchQueue,
    IBurnerLoansInventoryConfigTimelock,
    IVersioned
{
    using SafeCall for address;

    /// @notice Fixed notice before execution, in seconds.
    uint48 public constant MIN_TIMELOCK_DELAY = 1 days;
    /// @notice Maximum supported notice, in seconds.
    uint48 public constant MAX_TIMELOCK_DELAY = 30 days;
    /// @notice Inclusive execution window after the notice, in seconds.
    uint48 public constant EXECUTION_WINDOW = 3 days;
    /// @notice Immutable target for all queued configuration and recovery actions.
    IBurnerLoansInventory internal immutable _INVENTORY;

    /// @notice Binds this queue to one already-deployed same-Kernel Inventory.
    /// @dev Reverts if:
    ///      - Inventory lacks its interface or reports a different Kernel. Local activity is not required yet.
    /// @param kernel_ Kernel supplying governance roles.
    /// @param inventory_ Immutable routing/recovery target.
    constructor(
        Kernel kernel_,
        IBurnerLoansInventory inventory_
    )
        Policy(kernel_)
        ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD)
        ConfigTimelockBatchQueue(MIN_TIMELOCK_DELAY)
    {
        if (
            !ERC165Checker.supportsInterface(
                address(inventory_),
                type(IBurnerLoansInventory).interfaceId
            ) || !ERC165Checker.supportsInterface(address(inventory_), type(IEnabler).interfaceId)
        ) revert BurnerLoansInventoryTimelock_InvalidInventory(address(inventory_));
        PolicyDependency.requireSameKernel(address(inventory_), address(kernel_));
        _INVENTORY = inventory_;
    }

    /// @inheritdoc IBurnerLoansInventoryConfigTimelock
    /// @dev Returns the immutable target without external calls; does not revert.
    function inventory() external view override returns (IBurnerLoansInventory) {
        return _INVENTORY;
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

    /// @inheritdoc IBurnerLoansInventoryConfigTimelock
    /// @dev Reverts if:
    ///      - Queue admission fails, Inventory is disabled, or a surplus operation is pending.
    function queueBurnSurplus() external onlyActive givenEnabled onlyProposerRole returns (uint64) {
        return
            _queueAction(
                address(_INVENTORY),
                IBurnerLoansInventory.burnSurplus.selector,
                bytes("")
            );
    }

    /// @inheritdoc IBurnerLoansInventoryConfigTimelock
    /// @dev Reverts if:
    ///      - Queue admission fails or a surplus operation is pending. A paused Inventory is supported.
    function queueRescueSurplus()
        external
        onlyActive
        givenEnabled
        onlyProposerRole
        returns (uint64)
    {
        return
            _queueAction(
                address(_INVENTORY),
                IBurnerLoansInventory.rescueSurplus.selector,
                bytes("")
            );
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - Locally disabled/inactive, Inventory is inactive, the bound Kernel changed, proposer lacks both accepted roles, or controller selection changed.
    function _validateConfigQueue(address caller_) internal view override {
        _requireOwnActive();
        _requireEnabled();
        _requireProposerRole(caller_);
        _requireInventoryActive();
        if (IConfigOperator(address(_INVENTORY)).configOperator() != address(this))
            revert NotAuthorised();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Typed, argument-free queue functions construct the immutable target, selector and empty payload.
    ///      Only burn consumes an enabled-only service; paused rescue is intentionally supported.
    function _validateConfigSubAction(
        address,
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal view override {
        // Surplus rescue stays available while Inventory is paused; burning remains an enabled-only
        // operation. _requireReady supplies the shared same-Kernel and active-policy checks.
        if (action_.selector == IBurnerLoansInventory.burnSurplus.selector)
            _requireInventoryEnabled();
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    function _configDestination(
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (address) {
        return address(_INVENTORY);
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Both public operations consume the same surplus and share one pending key.
    function _configKeys(
        ITimelockBatchQueue.BatchAction memory
    ) internal pure override returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        // Burn and rescue consume the same surplus, so they share a conflict key even though their
        // selectors differ. Only one pending disposal of this Inventory's surplus is admitted.
        keys[0] = keccak256(abi.encode(IBurnerLoansInventory.burnSurplus.selector));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Controller changes invalidate queued recovery; surplus and Treasury remain live.
    function _currentConfigStateHash(
        uint64,
        uint256,
        bytes32,
        ITimelockBatchQueue.BatchAction memory
    ) internal view override returns (bytes32) {
        // Guard controller identity rather than a balance snapshot: donations, failed burns and
        // repayments can change surplus during the delay. Inventory computes the live amount on call.
        return keccak256(abi.encode(IConfigOperator(address(_INVENTORY)).configOperator()));
    }

    /// @inheritdoc ConfigTimelockBatchQueue
    /// @dev Reverts if:
    ///      - The admitted target fails. Propagates 1..255 revert bytes; empty/capped failures are wrapped.
    function _executeConfigSubAction(
        uint64,
        uint256,
        ITimelockBatchQueue.BatchAction memory action_
    ) internal override {
        // ConfigTimelockBatchQueue has already checked the stored controller commitment. Recheck
        // selector-specific enablement here; a paused Inventory can still execute rescueSurplus.
        if (action_.selector != IBurnerLoansInventory.rescueSurplus.selector)
            _requireInventoryEnabled();
        (bool ok, bytes memory data) = action_.target.safeCall(
            gasleft(),
            0,
            256,
            abi.encodePacked(action_.selector, action_.payload)
        );
        if (!ok) {
            if (data.length == 0 || data.length == 256)
                revert BurnerLoansInventoryTimelock_SubActionCallFailed(action_.selector);
            Address.verifyCallResult(ok, data);
        }
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Controller drift is rejected by each stored pre-state commitment before target dispatch.
    function _validateExecution(
        address,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireReady();
    }

    /// @inheritdoc TimelockBatchQueue
    /// @dev Reverts if:
    ///      - Local admission fails or caller lacks EMERGENCY. Broken targets do not prevent cancellation.
    function _validateCancellation(
        address caller_,
        uint64,
        ITimelockBatchQueue.QueuedAction storage
    ) internal view override {
        _requireOwnActive();
        _requireEnabled();
        _requireRole(caller_, EMERGENCY_ROLE);
    }

    /// @notice Validates this queue and its Inventory service, independent of Core lifecycle.
    /// @dev Reverts if:
    ///      - Locally disabled/inactive or Inventory is inactive or reports another Kernel.
    function _requireReady() private view {
        _requireOwnActive();
        _requireEnabled();
        _requireInventoryActive();
    }

    /// @notice Requires own policy membership with a product-owned error.
    /// @dev Reverts if:
    ///      - This timelock is Kernel-inactive.
    function _requireOwnActive() private view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @notice Checks the immutable Inventory's Kernel membership and binding.
    /// @dev Reverts if:
    ///      - Inventory reports another Kernel or is not active in this Kernel.
    function _requireInventoryActive() private view {
        PolicyDependency.requireActive(address(_INVENTORY), address(kernel));
    }

    /// @notice Requires the enabled-only burn service.
    /// @dev Reverts if:
    ///      - Inventory is locally disabled; rescue deliberately does not use this gate.
    function _requireInventoryEnabled() private view {
        if (!IEnabler(address(_INVENTORY)).isEnabled())
            revert PolicyDependency.PolicyDependency_NotActive(address(_INVENTORY));
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Payload is nonempty, own policy inactive, target Kernel changed or controller unselected.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
        _validateActivation();
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - Payload is nonempty. Inactive disable remains available.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - Initialization/grace or the identical enable prerequisites fail.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateActivation();
    }

    /// @notice Revalidates target identity and selection without requiring Core operation.
    /// @dev Reverts if:
    ///      - Own policy inactive, bound Kernel changed or controller unselected.
    function _validateActivation() private view {
        _requireOwnActive();
        _requireInventoryActive();
        if (IConfigOperator(address(_INVENTORY)).configOperator() != address(this))
            revert NotAuthorised();
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
            interfaceId_ == type(IBurnerLoansInventoryConfigTimelock).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
