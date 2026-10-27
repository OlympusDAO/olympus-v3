// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {YieldRepurchaseFacilityV2Constants} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2Constants.sol";

/// @title YieldRepurchaseFacilityV2ValidationLib
/// @notice An internal library of the value rules of the YieldRepurchaseFacilityV2
///         configuration: the bounds of the market parameters and of the yield buyback
///         share, the receivables bound of a Clearinghouse offset, the compare-and-set
///         rule of a next-yield correction, and the status conditions of an asset and
///         of a Clearinghouse.
/// @dev The functions are internal and take values, so they are compiled into the
///      facility, into its linked libraries, and into the configuration policy: each
///      value rule is defined once, and the setters of the facility and the validation
///      functions of the configuration policy reject the same values with the same
///      errors, which belong to the facility interface. The tolerant read of the
///      Clearinghouse receivables is a private helper of this library; the
///      Clearinghouse library and the lens read the receivables the same way.
library YieldRepurchaseFacilityV2ValidationLib {
    /// @notice Reverts unless the share is at most 100% (`1e18`).
    /// @param share_ The yield buyback share (`1e18` = 100%).
    function requireValidYieldBuybackShare(uint256 share_) internal pure {
        if (share_ > YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_YieldBuybackShareTooHigh();
    }

    /// @notice Reverts unless the discount is less than 100% (`1e18`).
    /// @param initialDiscount_ The initial discount (`1e18` = 100%).
    function requireValidInitialDiscount(uint256 initialDiscount_) internal pure {
        if (initialDiscount_ >= YieldRepurchaseFacilityV2Constants.ONE_HUNDRED_PERCENT)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_InitialDiscountTooHigh();
    }

    /// @notice Reverts unless the premium is at or below 1,000% (`10e18`).
    /// @param maxPricePremium_ The max price premium (`1e18` = 100%).
    function requireValidMaxPricePremium(uint256 maxPricePremium_) internal pure {
        if (maxPricePremium_ > YieldRepurchaseFacilityV2Constants.MAX_PRICE_PREMIUM_LIMIT)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_MaxPricePremiumTooHigh();
    }

    /// @notice Reverts unless a cumulative receivables offset is within the live
    ///         `principalReceivables` of a Clearinghouse.
    /// @dev The receivables are read tolerantly: a read that reverts counts as zero, so
    ///      such a Clearinghouse accepts only a zero offset.
    ///
    ///      Reverts if:
    ///      - `clearinghouse_` is the zero address
    ///        (`IYieldRepurchaseFacilityV2_ZeroAddress`).
    ///      - `offset_` exceeds the current `principalReceivables`
    ///        (`IYieldRepurchaseFacilityV2_OffsetExceedsReceivables`).
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param offset_ The cumulative offset to validate, in the receivables' units.
    function requireOffsetWithinReceivables(address clearinghouse_, uint256 offset_) internal view {
        if (clearinghouse_ == address(0))
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ZeroAddress();

        uint256 receivables = _readPrincipalReceivables(clearinghouse_);
        if (offset_ > receivables)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
                clearinghouse_,
                offset_,
                receivables
            );
    }

    /// @notice Reverts unless a next-yield correction targets the stored value and lowers
    ///         it.
    /// @dev Reverts if:
    ///      - `current_` does not equal `expected_`
    ///        (`IYieldRepurchaseFacilityV2_NextYieldMismatch`).
    ///      - `newValue_` is not lower than `current_`
    ///        (`IYieldRepurchaseFacilityV2_NextYieldNotDecreased`).
    /// @param vault_ The vault whose next yield is corrected, for the errors.
    /// @param expected_ The stored next yield the correction targets, in reserve units.
    /// @param current_ The stored next yield, in reserve units.
    /// @param newValue_ The corrected next yield, in reserve units.
    function requireNextYieldDecrease(
        address vault_,
        uint256 expected_,
        uint256 current_,
        uint256 newValue_
    ) internal pure {
        if (current_ != expected_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldMismatch(
                vault_,
                expected_,
                current_
            );
        if (newValue_ >= current_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_NextYieldNotDecreased(
                vault_,
                newValue_,
                current_
            );
    }

    /// @notice Reverts unless the asset is enabled.
    /// @param isAssetEnabled_ The stored `isAssetEnabled` flag of the asset.
    // Reached from loops over admin-supplied seeds, where an invalid entry must reject the
    // whole call.
    // forge-lint: disable-next-item(require-revert-in-loop)
    function requireAssetEnabled(bool isAssetEnabled_) internal pure {
        if (!isAssetEnabled_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetDisabled();
    }

    /// @notice Reverts unless the asset is disabled.
    /// @param isAssetEnabled_ The stored `isAssetEnabled` flag of the asset.
    function requireAssetDisabled(bool isAssetEnabled_) internal pure {
        if (isAssetEnabled_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_AssetEnabled();
    }

    /// @notice Reverts when the vault is the backing vault.
    /// @param vault_ The vault.
    /// @param backingVault_ The designated backing vault, or the zero address when none is
    ///        designated.
    function requireNotBackingVault(address vault_, address backingVault_) internal pure {
        if (vault_ == backingVault_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_VaultIsBackingVault();
    }

    /// @notice Reverts unless the Clearinghouse is included in the backing yield.
    /// @param included_ The stored inclusion flag of the Clearinghouse.
    function requireClearinghouseIncluded(bool included_) internal pure {
        if (!included_)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded();
    }

    /// @notice Reads the Clearinghouse's `principalReceivables`, treating a revert as
    ///         zero.
    function _readPrincipalReceivables(address clearinghouse_) private view returns (uint256) {
        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256 receivables
        ) {
            return receivables;
        } catch {
            return 0;
        }
    }
}
