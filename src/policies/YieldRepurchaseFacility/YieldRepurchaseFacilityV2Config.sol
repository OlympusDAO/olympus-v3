// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {ERC165Checker} from "@openzeppelin-5.3.0/utils/introspection/ERC165Checker.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IYieldRepurchaseFacilityV2Config} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Config.sol";
import {IYieldRepurchaseFacilityV2View} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2View.sol";
import {IYieldRepurchaseFacilityV2Write} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2Write.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

// Contracts
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

// Constants
import {ADMIN_ROLE, YRF_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title YieldRepurchaseFacilityV2Config
/// @notice The configuration policy of YieldRepurchaseFacilityV2: the configurator the facility
///         accepts for its configuration setters.
/// @dev The policy stores only the facility binding. Every setter forwards to the facility,
///      which validates the call, stores the value, and emits the event. The operator setters
///      accept the config operator of `ConfigOperatorSingleStep`, meant to be
///      `YieldRepurchaseFacilityV2ConfigTimelock`, and the admin role; the admin setters accept
///      the admin role only. Every setter requires this policy to be enabled, and none requires
///      the facility to be enabled: the facility applies its configuration setters while
///      disabled, so a correction can be applied before the facility is re-enabled.
///
///      Lifecycle: `enable` (admin) and `reEnable` (yrf_admin, within the grace window) require
///      the bound facility to be an active policy of this policy's kernel, to report that kernel
///      as its own, and to name this policy as its configurator; `disable` (emergency or admin)
///      leaves the binding and the config operator in place. The grace window is strictly
///      shorter than one weekly cycle of the facility (`MAX_GRACE_PERIOD`). The facility is
///      bound once through `setFacility`, while this policy is disabled.
///
///      The admin role is expected to be held only by the OCG timelock, so every admin-gated
///      function of this contract is de-facto timelocked.
contract YieldRepurchaseFacilityV2Config is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    IYieldRepurchaseFacilityV2Config,
    IVersioned
{
    // ========== CONSTANTS ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    uint32 public constant override MAX_GRACE_PERIOD =
        YieldRepurchaseFacilityV2Constants.MAX_GRACE_PERIOD;

    /// @notice The number of interfaces `setFacility` requires the facility to advertise:
    ///         `IYieldRepurchaseFacilityV2Write` and `IYieldRepurchaseFacilityV2View`.
    uint256 internal constant _FACILITY_INTERFACE_COUNT = 2;

    /// @notice Keycode for the ROLES module dependency.
    /// @dev Pre-computed to avoid the runtime cost of `toKeycode("ROLES")`.
    Keycode internal constant _KEYCODE_ROLES = Keycode.wrap(0x524f4c4553); // toKeycode("ROLES")

    // ========== STATE ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    address public override facility;

    // ========== CONSTRUCTOR ========== //

    /// @notice Deploys an unbound configuration policy.
    /// @dev The facility is bound once after deployment through `setFacility`. The policy
    ///      starts disabled.
    ///
    ///      Reverts if:
    ///      - `kernel_` is the zero address.
    ///      - `gracePeriod_` is zero or not less than `MAX_GRACE_PERIOD`.
    /// @param kernel_ The Olympus Kernel.
    /// @param gracePeriod_ The initial re-enable grace window, in seconds.
    constructor(
        Kernel kernel_,
        uint32 gracePeriod_
    ) Policy(kernel_) ReEnablerGracePeriod(gracePeriod_) {
        if (address(kernel_) == address(0)) revert Errors.BadInput("kernel");
        _requireValidGracePeriod(gracePeriod_);

        // Disabled by default by EnablerV2
    }

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The ROLES module does not report major version 1.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = _KEYCODE_ROLES;

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // ROLES compatibility depends only on its major version
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev The policy does not request module permissions.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== ROLE GATES ========== //

    /// @notice Reverts with `NotAuthorised` unless the caller is the config operator or holds
    ///         the admin role.
    modifier onlyConfigOperatorOrAdmin() {
        _requireAuthorized(!_isConfigOperator(msg.sender) && !_isAdmin(msg.sender));
        _;
    }

    // ========== FACILITY BINDING ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev The binding is revalidated by `enable` and `reEnable`, together with the reverse
    ///      link `configurator()` of the facility, which the facility only sets once this
    ///      policy reports it as its `facility()`.
    ///
    ///      Reverts if:
    ///      - The contract is enabled.
    ///      - The caller does not hold the admin role.
    ///      - A facility is already bound.
    ///      - `facility_` is the zero address, is not an active policy of this policy's
    ///        kernel, or does not report that kernel as its own.
    ///      - `facility_` does not advertise `IYieldRepurchaseFacilityV2Write` and
    ///        `IYieldRepurchaseFacilityV2View` through ERC165.
    function setFacility(address facility_) external override givenDisabled onlyAdminRole {
        if (facility != address(0)) revert IYieldRepurchaseFacilityV2Config_FacilityAlreadySet();
        _requireFacilityActive(facility_);

        bytes4[] memory interfaceIds = new bytes4[](_FACILITY_INTERFACE_COUNT);
        interfaceIds[0] = type(IYieldRepurchaseFacilityV2Write).interfaceId;
        interfaceIds[1] = type(IYieldRepurchaseFacilityV2View).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(facility_, interfaceIds))
            revert IYieldRepurchaseFacilityV2Config_InvalidFacility(facility_);

        facility = facility_;
        // The calls above are static reads of the kernel and of the candidate facility, and
        // the binding is admin-gated and one-shot
        // forge-lint: disable-next-line(reentrancy-events)
        emit FacilitySet(facility_);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The facility rejects the call (see
    ///        `YieldRepurchaseFacilityV2.addAsset`).
    function addAsset(
        address vault_,
        uint256 yieldBuybackShare_,
        uint256 initialReserveBalance_,
        uint256 initialConversionRate_,
        uint256 nextYield_,
        bool sellShares_,
        bool setAsBackingVault_
    ) external override givenEnabled onlyAdminRole {
        _facility().addAsset(
            vault_,
            yieldBuybackShare_,
            initialReserveBalance_,
            initialConversionRate_,
            nextYield_,
            sellShares_,
            setAsBackingVault_
        );
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.removeAsset`).
    function removeAsset(address vault_) external override givenEnabled onlyAdminRole {
        _facility().removeAsset(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.setSellShares`).
    function setSellShares(
        address vault_,
        bool sellShares_
    ) external override givenEnabled onlyAdminRole {
        _facility().setSellShares(vault_, sellShares_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.setBackingVault`).
    function setBackingVault(address vault_) external override givenEnabled onlyAdminRole {
        _facility().setBackingVault(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The facility rejects the call (see
    ///        `YieldRepurchaseFacilityV2.setClearinghouseOffset`).
    function setClearinghouseOffset(
        address clearinghouse_,
        uint256 offset_
    ) external override givenEnabled onlyAdminRole {
        _facility().setClearinghouseOffset(clearinghouse_, offset_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - The facility rejects the call (see
    ///        `YieldRepurchaseFacilityV2.includeClearinghouse`).
    function includeClearinghouse(
        address clearinghouse_
    ) external override givenEnabled onlyAdminRole {
        _facility().includeClearinghouse(clearinghouse_);
    }

    // ========== OPERATOR FUNCTIONS ========== //

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see
    ///        `YieldRepurchaseFacilityV2.setYieldBuybackShare`).
    function setYieldBuybackShare(
        address vault_,
        uint256 newShare_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().setYieldBuybackShare(vault_, newShare_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.setInitialDiscount`).
    function setInitialDiscount(
        uint256 initialDiscount_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().setInitialDiscount(initialDiscount_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.setMaxPricePremium`).
    function setMaxPricePremium(
        uint256 maxPricePremium_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().setMaxPricePremium(maxPricePremium_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see
    ///        `YieldRepurchaseFacilityV2.increaseClearinghouseOffset`).
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().increaseClearinghouseOffset(clearinghouse_, additionalOffset_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.decreaseNextYield`).
    function decreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().decreaseNextYield(vault_, expectedNextYield_, newNextYield_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see
    ///        `YieldRepurchaseFacilityV2.excludeClearinghouse`).
    function excludeClearinghouse(
        address clearinghouse_
    ) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().excludeClearinghouse(clearinghouse_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.enableAsset`).
    function enableAsset(address vault_) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().enableAsset(vault_);
    }

    /// @inheritdoc IYieldRepurchaseFacilityV2Config
    /// @dev Reverts if:
    ///      - The contract is disabled.
    ///      - The caller is neither the config operator nor an admin.
    ///      - The facility rejects the call (see `YieldRepurchaseFacilityV2.disableAsset`).
    function disableAsset(address vault_) external override givenEnabled onlyConfigOperatorOrAdmin {
        _facility().disableAsset(vault_);
    }

    // ========== CONFIG OPERATOR HOOKS ========== //

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev The hook reverts on failure, so the mix-in never reports
    ///      `ConfigOperator_Unauthorized` through this policy; the mix-in then rejects the
    ///      operator already set, the zero address included, with `ConfigOperator_Unchanged`.
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    function _authorizeSetConfigOperator() internal view override returns (bool authorized) {
        _requireEnabled();
        _requireRole(msg.sender, ADMIN_ROLE);
        return true;
    }

    // ========== ENABLE / DISABLE ========== //

    /// @inheritdoc EnablerV2
    /// @dev The payload is not used.
    ///
    ///      Reverts if:
    ///      - The facility is unset, is not an active policy of this policy's kernel, or does
    ///        not report that kernel as its own.
    ///      - The facility does not name this policy as its configurator.
    function _beforeEnable(bytes calldata) internal view override {
        _validateConfiguration();
    }

    /// @notice Authorizes a re-enable transition during the grace window.
    /// @dev The admin role is not accepted here: it restarts the policy through `enable`.
    ///
    ///      Reverts if:
    ///      - The caller does not hold the yrf_admin role.
    function _authorizeReEnable() internal view override {
        _requireRole(msg.sender, YRF_ADMIN_ROLE);
    }

    /// @notice Validates the grace window and the facility binding before the policy is
    ///         re-enabled.
    /// @dev Reverts if:
    ///      - The grace window since the last transition has elapsed (`GracePeriod_Expired`).
    ///      - The facility is unset, is not an active policy of this policy's kernel, or does
    ///        not report that kernel as its own.
    ///      - The facility does not name this policy as its configurator.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateConfiguration();
    }

    /// @notice Authorizes a grace window update.
    /// @dev Reverts if:
    ///      - The caller does not hold the admin role.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Bounds the window: the grace period must be strictly shorter than one weekly
    ///      cycle of the facility (`MAX_GRACE_PERIOD`).
    ///
    ///      Reverts if:
    ///      - The contract is disabled.
    ///      - The caller does not hold the admin role.
    ///      - `period_` is zero.
    ///      - `period_` is not less than `MAX_GRACE_PERIOD`.
    function setGracePeriod(uint32 period_) public override givenEnabled {
        _requireValidGracePeriod(period_);
        super.setGracePeriod(period_);
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Returns the bound facility as its state-changing surface.
    function _facility() internal view returns (IYieldRepurchaseFacilityV2Write) {
        return IYieldRepurchaseFacilityV2Write(facility);
    }

    /// @notice Validates the facility binding before the policy is enabled or re-enabled.
    /// @dev Reverts with `IYieldRepurchaseFacilityV2Config_InvalidFacility` if:
    ///      - The facility is unset, is not an active policy of this policy's kernel, or does
    ///        not report that kernel as its own.
    ///      - The facility does not name this policy as its configurator.
    function _validateConfiguration() internal view {
        address facility_ = facility;
        _requireFacilityActive(facility_);
        if (IYieldRepurchaseFacilityV2View(facility_).configurator() != address(this))
            revert IYieldRepurchaseFacilityV2Config_InvalidFacility(facility_);
    }

    /// @notice Reverts with `IYieldRepurchaseFacilityV2Config_InvalidFacility` unless
    ///         `facility_` is a non-zero active policy of this policy's kernel that reports
    ///         that kernel as its own.
    function _requireFacilityActive(address facility_) internal view {
        if (
            facility_ == address(0) ||
            !kernel.isPolicyActive(Policy(facility_)) ||
            !_reportsKernel(facility_)
        ) revert IYieldRepurchaseFacilityV2Config_InvalidFacility(facility_);
    }

    /// @notice Returns whether `policy_` reports this policy's kernel as its own.
    /// @dev A `kernel()` read that reverts is reported as a mismatch.
    function _reportsKernel(address policy_) internal view returns (bool) {
        try Policy(policy_).kernel() returns (Kernel reportedKernel) {
            return address(reportedKernel) == address(kernel);
        } catch {
            return false;
        }
    }

    /// @notice Reverts unless the grace window is strictly shorter than `MAX_GRACE_PERIOD`.
    function _requireValidGracePeriod(uint32 period_) private pure {
        if (period_ >= MAX_GRACE_PERIOD)
            revert IYieldRepurchaseFacilityV2Config_GracePeriodTooLong();
    }

    // ========== ERC165 ========== //

    /// @inheritdoc EnablerV2
    /// @dev Adds `IYieldRepurchaseFacilityV2Config`, `IConfigOperator`, and `IVersioned` to
    ///      the interfaces advertised by the bases.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IYieldRepurchaseFacilityV2Config).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
