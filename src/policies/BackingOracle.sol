// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

// Constants
import {ADMIN_ROLE, BACKING_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title BackingOracle
/// @notice	A policy that serves as the canonical OHM backing value (the reserve per OHM, 18 decimals).
/// @dev	ADMIN retains direct configuration authority; one replaceable config operator can
///      apply bounded updates. Delayed governance is provided by BackingOracleConfigTimelock.
contract BackingOracle is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    IBackingOracle,
    IVersioned
{
    // ========== CONSTANTS ========== //

    uint32 internal constant _DEFAULT_GRACE_PERIOD = 7 days;
    uint256 private constant _ENABLE_DATA_LENGTH = 32;
    uint256 private constant _MAX_BACKING_CHANGE_BPS = 1_000;
    uint256 private constant _BPS = 10_000;

    // ========== STATE ========== //

    /// @inheritdoc IBackingOracle
    uint256 public override backing;

    // ========== INITIALIZATION & POLICY SETUP ========== //

    /// @notice	Creates a disabled oracle with the default recovery grace period.
    /// @dev	Reverts if:
    ///      - `kernel_` is zero.
    ///
    /// @param	kernel_	Kernel supplying governance roles.
    constructor(Kernel kernel_) Policy(kernel_) ReEnablerGracePeriod(_DEFAULT_GRACE_PERIOD) {
        if (address(kernel_) == address(0)) revert BackingOracle_ZeroKernelAddress();
    }

    /// @inheritdoc Policy
    /// @dev	Reverts if:
    ///      - ROLES is not installed in the Kernel.
    ///      - The ROLES major version is not one.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // All minor versions are compatible; only the major version is constrained.
        // forge-lint: disable-next-line(unused-return)
        (uint8 m, ) = ROLES.VERSION();
        if (m != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev	No module-write permissions are required; backing is stored on this policy.
    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IBackingOracle
    /// @dev	The backing value is denominated in 18 decimals. Does not revert.
    function decimals() external pure override returns (uint8) {
        return 18;
    }

    // ========== ENABLE ========== //

    /// @inheritdoc EnablerV2
    /// @dev	Sets the `backing`. The value is applied without the timelock because `enable` is
    ///      already gated to the admin role.
    ///
    /// @dev	Reverts if:
    ///      - This policy is not active in its Kernel.
    ///      - The enable data is not the correct length.
    ///      - The initial backing value is zero.
    function _beforeEnable(bytes calldata data_) internal override {
        _requireActive();
        if (data_.length != _ENABLE_DATA_LENGTH) revert BackingOracle_InvalidEnableDataLength();
        uint256 initialBacking = abi.decode(data_, (uint256));
        _requireNonzeroBacking(initialBacking);

        _setBacking(initialBacking);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IBackingOracle
    /// @dev	ADMIN may update directly. The selected operator determines any additional notice.
    ///
    /// @dev	Reverts if:
    ///      - This policy is not active in its Kernel.
    ///      - The policy is not enabled.
    ///      - The caller is neither ADMIN nor the selected nonzero config operator.
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` changes the current backing beyond the allowed threshold.
    ///      - The computed upper backing bound exceeds uint256.
    function setBacking(uint256 newBacking_) external {
        _requireActive();
        _requireEnabled();
        _requireAuthorized(!_isAdmin(msg.sender) && !_isConfigOperator(msg.sender));
        _validateBackingChange(newBacking_);

        _setBacking(newBacking_);
    }

    /// @inheritdoc IBackingOracle
    /// @dev	Permissionless preflight using the same backing validation as setBacking.
    /// @dev	Reverts if:
    ///      - This policy is not active in its Kernel.
    ///      - The policy is not enabled.
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` is outside the current floor-rounded backing bounds.
    ///      - The computed upper backing bound exceeds uint256.
    function validateSetBacking(uint256 newBacking_) external view {
        _requireActive();
        _requireEnabled();
        _validateBackingChange(newBacking_);
    }

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev	Rotation or revocation is permitted while paused; no candidate metadata is read.
    /// @dev	Reverts if:
    ///      - This policy is not active in its Kernel.
    ///      - The caller does not hold ADMIN.
    function _authorizeSetConfigOperator() internal view override returns (bool) {
        _requireActive();
        _requireRole(msg.sender, ADMIN_ROLE);
        return true;
    }

    /// @inheritdoc EnablerV2
    /// @dev	Disable remains available while Kernel-inactive.
    /// @dev	Reverts if:
    ///      - `data_` is nonempty.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert BackingOracle_InvalidDisableDataLength();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Fast recovery preserves backing and operator state.
    /// @dev	Reverts if:
    ///      - The grace deadline exceeds uint48.
    ///      - The inclusive grace deadline has expired.
    ///      - This policy is not active in its Kernel.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireActive();
    }

    /// @notice	ADMIN or backing_admin may recover within the configured grace window.
    /// @dev	Reverts if:
    ///      - The caller holds neither ADMIN nor backing_admin.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BACKING_ADMIN_ROLE));
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Reverts if:
    ///      - This policy is not active in its Kernel.
    ///      - The policy is not enabled.
    ///      - The caller does not hold ADMIN.
    ///      - `period_` is zero.
    function setGracePeriod(uint32 period_) public override {
        _requireActive();
        super.setGracePeriod(period_);
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Reverts if:
    ///      - The caller does not hold ADMIN.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev	Widen before narrowing so deadline overflow returns the canonical SafeCast error.
    /// @dev	Reverts if:
    ///      - The grace deadline exceeds uint48.
    ///      - The inclusive grace deadline has expired.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice	Reject mutations after Kernel deactivation; disable and reads remain available.
    /// @dev	Reverts if:
    ///      - This policy is not active in its Kernel.
    function _requireActive() private view {
        if (!kernel.isPolicyActive(this)) revert BackingOracle_PolicyNotActive(address(this));
    }

    /// @notice	Validate a proposed backing change against the current backing value.
    /// @dev	The check runs at queue time as an early guard and again at execution time as the
    ///      authoritative check, because the current backing may change between the two.
    ///
    /// @dev	Reverts if:
    ///      - `newBacking_` is zero.
    ///      - `newBacking_` changes the current backing beyond the allowed threshold.
    ///      - The computed upper backing bound exceeds uint256.
    ///
    /// @param	newBacking_	The proposed backing value (18 decimals).
    function _validateBackingChange(uint256 newBacking_) internal view {
        _requireNonzeroBacking(newBacking_);

        uint256 currentBacking = backing;
        // Backing (18 decimals) * ratio (basis points) / 10,000 remains 18 decimals, rounded down.
        // Full precision avoids intermediate overflow; tiny-value lower-bound rounding is retained.
        uint256 minBacking = Math.mulDiv(currentBacking, _BPS - _MAX_BACKING_CHANGE_BPS, _BPS);
        uint256 maxBacking = Math.mulDiv(currentBacking, _BPS + _MAX_BACKING_CHANGE_BPS, _BPS);
        if (newBacking_ < minBacking || newBacking_ > maxBacking)
            revert BackingOracle_BackingChangeTooLarge(
                currentBacking,
                newBacking_,
                minBacking,
                maxBacking
            );
    }

    function _setBacking(uint256 backing_) private {
        backing = backing_;
        emit BackingSet(backing_);
    }

    /// @notice	Validates that backing has a nonzero value.
    /// @dev	Reverts if:
    ///      - `backing_` is zero.
    ///
    /// @param	backing_	Proposed backing value (18 decimals).
    function _requireNonzeroBacking(uint256 backing_) private pure {
        if (backing_ == 0) revert BackingOracle_ZeroBacking();
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBackingOracle).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
