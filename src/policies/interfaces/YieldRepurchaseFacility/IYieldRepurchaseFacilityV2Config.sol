// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

/// @title IYieldRepurchaseFacilityV2Config
/// @notice The interface of the configuration policy of YieldRepurchaseFacilityV2: the only
///         caller the facility accepts for its configuration setters. The policy stores no
///         configuration of its own; every setter forwards to the bound facility, which
///         validates the call, stores the value, and emits the event.
/// @dev The facility is bound once through `setFacility`. An implementation is expected to
///      advertise this interface, `IConfigOperator`, and `IEnabler` through ERC165: the facility
///      checks this interface when the policy is bound as its configurator, and the config
///      timelock checks all three at construction.
///
///      The validation functions apply the value rules of the operator setters to the live
///      state of the bound facility, read through its getters, and revert with the error the
///      facility setter throws for the same values. They apply no authorization gate and no
///      enabled-state gate, and are intended to be called by the config timelock when an
///      action is queued; the facility setter applies the same rules again when the action
///      executes.
///
///      The setters form two groups. The operator setters are callable by the config operator
///      of `IConfigOperator`, meant to be the config timelock, or by the admin role; the admin
///      setters only by the admin role. Every setter requires this policy to be enabled and
///      forwards while the facility is disabled as well, so that a correction can be applied
///      before the facility is re-enabled. `setConfigOperator` of `IConfigOperator` is intended
///      to be callable only by the admin role while the policy is enabled.
///
///      The lifecycle is that of `IEnabler`, `IReEnabler`, and `IGracePeriod`: `enable` is
///      intended for the admin role, `disable` for the emergency or admin role, `reEnable` for
///      the yrf_admin role within the grace window after a disable, and `setGracePeriod` for the
///      admin role while the policy is enabled. The grace window must be strictly shorter than
///      `MAX_GRACE_PERIOD`. Enabling and re-enabling require the bound facility to be an active
///      policy of the same kernel, to report that kernel as its own, and to name this policy as
///      its configurator.
interface IYieldRepurchaseFacilityV2Config {
    // ============ EVENTS ============ //

    /// @notice Emitted when the policy is bound to its facility.
    /// @param facility The bound facility.
    event FacilitySet(address indexed facility);

    // ============ ERRORS ============ //

    /// @notice Thrown when the kernel supplied at construction is the zero address.
    error IYieldRepurchaseFacilityV2Config_ZeroAddress();

    /// @notice Thrown when `setFacility` is called while a facility is already bound.
    error IYieldRepurchaseFacilityV2Config_FacilityAlreadySet();

    /// @notice Thrown when the facility is unset, is not an active policy of the policy's kernel,
    ///         does not report that kernel as its own, does not advertise
    ///         `IYieldRepurchaseFacilityV2Write` and `IYieldRepurchaseFacilityV2View`, or does
    ///         not name this policy as its configurator.
    /// @param facility The rejected facility address.
    error IYieldRepurchaseFacilityV2Config_InvalidFacility(address facility);

    /// @notice Thrown when the re-enable grace window is configured with a length at or
    ///         above `MAX_GRACE_PERIOD`.
    error IYieldRepurchaseFacilityV2Config_GracePeriodTooLong();

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the facility the configuration policy is bound to.
    /// @return facility_ The facility address, or the zero address while no facility is bound.
    function facility() external view returns (address facility_);

    /// @notice Returns the exclusive upper bound of the re-enable grace window, in seconds:
    ///         the window must be strictly shorter than one weekly cycle of the facility.
    /// @return The bound, in seconds.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_GRACE_PERIOD() external view returns (uint32);

    // ============ VALIDATION ============ //

    /// @notice Validates the parameters of `setYieldBuybackShare` against the live facility
    ///         state, reverting when the facility setter's value checks would fail.
    /// @dev Intended to be called by the config timelock when a `setYieldBuybackShare`
    ///      action is queued.
    /// @param vault_ The registered vault.
    /// @param newShare_ The proposed share (`1e18` = 100%); must not exceed `1e18`.
    function validateSetYieldBuybackShare(address vault_, uint256 newShare_) external view;

    /// @notice Validates the parameter of `setInitialDiscount`, reverting when the facility
    ///         setter's value check would fail.
    /// @dev Intended to be called by the config timelock when a `setInitialDiscount` action
    ///      is queued.
    /// @param initialDiscount_ The proposed discount (`1e18` = 100%); must be less than
    ///        `1e18`.
    function validateSetInitialDiscount(uint256 initialDiscount_) external view;

    /// @notice Validates the parameter of `setMaxPricePremium`, reverting when the facility
    ///         setter's value check would fail.
    /// @dev Intended to be called by the config timelock when a `setMaxPricePremium` action
    ///      is queued.
    /// @param maxPricePremium_ The proposed premium (`1e18` = 100%); must not exceed
    ///        `10e18`.
    function validateSetMaxPricePremium(uint256 maxPricePremium_) external view;

    /// @notice Validates the parameter of `enableAsset` against the live facility state,
    ///         reverting when the facility setter's value checks would fail.
    /// @dev Intended to be called by the config timelock when an `enableAsset` action is
    ///      queued.
    /// @param vault_ The vault to enable; must be registered and disabled.
    function validateEnableAsset(address vault_) external view;

    /// @notice Validates the parameter of `disableAsset` against the live facility state,
    ///         reverting when the facility setter's value checks would fail.
    /// @dev Intended to be called by the config timelock when a `disableAsset` action is
    ///      queued.
    /// @param vault_ The vault to disable; must be registered, enabled, and not the backing
    ///        vault.
    function validateDisableAsset(address vault_) external view;

    /// @notice Validates the parameter of `excludeClearinghouse` against the live facility
    ///         state, reverting when the facility setter's value check would fail.
    /// @dev Intended to be called by the config timelock when an `excludeClearinghouse`
    ///      action is queued.
    /// @param clearinghouse_ The Clearinghouse address; must be included.
    function validateExcludeClearinghouse(address clearinghouse_) external view;

    /// @notice Validates the parameters of `increaseClearinghouseOffset` against the live
    ///         facility state, reverting when the facility setter's value checks would fail.
    /// @dev The receivables are read live, so a validation that passes can be invalidated by
    ///      repayments before the setter runs. Intended to be called by the config timelock
    ///      when an `increaseClearinghouseOffset` action is queued.
    /// @param clearinghouse_ The Clearinghouse address; must not be the zero address
    ///        (`IYieldRepurchaseFacilityV2_ZeroAddress`).
    /// @param additionalOffset_ The amount added to the existing offset, in the receivables'
    ///        units; the resulting offset must not exceed the current `principalReceivables`.
    function validateIncreaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external view;

    /// @notice Validates the parameters of `decreaseNextYield` against the live facility
    ///         state, reverting when the facility setter's value checks would fail.
    /// @dev The stored next yield is read live, so a validation that passes can be invalidated
    ///      by a weekly reset before the setter runs. Intended to be called by the config
    ///      timelock when a `decreaseNextYield` action is queued.
    /// @param vault_ The registered vault.
    /// @param expectedNextYield_ The stored next yield the correction targets, in reserve
    ///        units.
    /// @param newNextYield_ The corrected next yield, in reserve units; must be lower than the
    ///        stored value.
    function validateDecreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external view;

    // ============ ADMIN FUNCTIONS ============ //

    /// @notice Binds the facility, once. Intended to be callable only by the admin role while the
    ///         policy is disabled.
    /// @dev The facility must be an active policy of the policy's kernel, report that kernel as
    ///      its own, and advertise `IYieldRepurchaseFacilityV2Write` and
    ///      `IYieldRepurchaseFacilityV2View` through ERC165. A bound facility cannot be replaced:
    ///      a replacement stack deploys a fresh configuration policy. Emits `FacilitySet`.
    /// @param facility_ The facility to bind.
    function setFacility(address facility_) external;

    /// @notice Forwards `addAsset` to the facility. Intended to be callable only by the admin
    ///         role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.addAsset` for the semantics and the parameter
    ///      requirements.
    /// @param params_ The registration inputs (see `IYieldRepurchaseFacilityV2.AddAssetParams`).
    function addAsset(IYieldRepurchaseFacilityV2.AddAssetParams calldata params_) external;

    /// @notice Forwards `removeAsset` to the facility. Intended to be callable only by the admin
    ///         role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.removeAsset` for the semantics.
    /// @param vault_ The vault to de-register.
    function removeAsset(address vault_) external;

    /// @notice Forwards `setSellShares` to the facility. Intended to be callable only by the
    ///         admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.setSellShares` for the semantics.
    /// @param vault_ The registered vault.
    /// @param sellShares_ Whether bond markets pay out the vault shares; must differ from the
    ///        stored mode.
    function setSellShares(address vault_, bool sellShares_) external;

    /// @notice Forwards `refreshAsyncRedeem` to the facility. Intended to be callable only by
    ///         the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.refreshAsyncRedeem` for the semantics.
    /// @param vault_ The registered vault.
    function refreshAsyncRedeem(address vault_) external;

    /// @notice Forwards `setBackingVault` to the facility. Intended to be callable only by the
    ///         admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.setBackingVault` for the semantics.
    /// @param vault_ The vault to designate.
    function setBackingVault(address vault_) external;

    /// @notice Forwards `setClearinghouseOffset` to the facility. Intended to be callable only by
    ///         the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.setClearinghouseOffset` for the semantics.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param offset_ The new cumulative offset, in the receivables' units.
    function setClearinghouseOffset(address clearinghouse_, uint256 offset_) external;

    /// @notice Forwards `includeClearinghouse` to the facility. Intended to be callable only by
    ///         the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.includeClearinghouse` for the semantics.
    /// @param clearinghouse_ The Clearinghouse address.
    function includeClearinghouse(address clearinghouse_) external;

    // ============ OPERATOR FUNCTIONS ============ //

    /// @notice Forwards `setYieldBuybackShare` to the facility. Intended to be callable only by
    ///         the config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.setYieldBuybackShare` for the semantics.
    /// @param vault_ The registered vault.
    /// @param newShare_ The new share (`1e18` = 100%); must not exceed `1e18`.
    function setYieldBuybackShare(address vault_, uint256 newShare_) external;

    /// @notice Forwards `setInitialDiscount` to the facility. Intended to be callable only by the
    ///         config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.setInitialDiscount` for the semantics.
    /// @param initialDiscount_ The new discount (`1e18` = 100%); must be less than `1e18`.
    function setInitialDiscount(uint256 initialDiscount_) external;

    /// @notice Forwards `setMaxPricePremium` to the facility. Intended to be callable only by the
    ///         config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.setMaxPricePremium` for the semantics.
    /// @param maxPricePremium_ The new premium (`1e18` = 100%); must not exceed `10e18`.
    function setMaxPricePremium(uint256 maxPricePremium_) external;

    /// @notice Forwards `increaseClearinghouseOffset` to the facility. Intended to be callable
    ///         only by the config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.increaseClearinghouseOffset` for the semantics.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param additionalOffset_ The amount added to the existing offset, in the receivables'
    ///        units.
    function increaseClearinghouseOffset(
        address clearinghouse_,
        uint256 additionalOffset_
    ) external;

    /// @notice Forwards `decreaseNextYield` to the facility. Intended to be callable only by the
    ///         config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.decreaseNextYield` for the semantics.
    /// @param vault_ The registered vault.
    /// @param expectedNextYield_ The stored next yield the correction targets, in reserve units.
    /// @param newNextYield_ The corrected next yield, in reserve units; must be lower than the
    ///        stored value.
    function decreaseNextYield(
        address vault_,
        uint256 expectedNextYield_,
        uint256 newNextYield_
    ) external;

    /// @notice Forwards `excludeClearinghouse` to the facility. Intended to be callable only by
    ///         the config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.excludeClearinghouse` for the semantics.
    /// @param clearinghouse_ The included Clearinghouse address.
    function excludeClearinghouse(address clearinghouse_) external;

    /// @notice Forwards `enableAsset` to the facility. Intended to be callable only by the config
    ///         operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.enableAsset` for the semantics.
    /// @param vault_ The vault to enable.
    function enableAsset(address vault_) external;

    /// @notice Forwards `disableAsset` to the facility. Intended to be callable only by the
    ///         config operator or the admin role while the policy is enabled.
    /// @dev See `IYieldRepurchaseFacilityV2Write.disableAsset` for the semantics.
    /// @param vault_ The vault to disable.
    function disableAsset(address vault_) external;
}
