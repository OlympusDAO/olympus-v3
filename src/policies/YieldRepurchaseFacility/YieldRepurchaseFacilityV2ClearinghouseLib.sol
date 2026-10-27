// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

// Interfaces
import {IClearinghouseReserve} from "src/policies/interfaces/IClearinghouseReserve.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {Errors} from "src/libraries/Errors.sol";
import {YieldRepurchaseFacilityV2MathLib} from "src/policies/YieldRepurchaseFacility/YieldRepurchaseFacilityV2MathLib.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";

/// @title YieldRepurchaseFacilityV2ClearinghouseLib
/// @notice An external library that owns the Clearinghouse configuration of the
///         YieldRepurchaseFacilityV2 (the receivables offsets and the inclusions) and
///         measures the Clearinghouse component of the backing yield.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      storage parameter references the calling facility's storage, and the events and
///      the errors belong to the facility interface. The interest arithmetic is that of
///      `YieldRepurchaseFacilityV2MathLib`, which the lens shares.
library YieldRepurchaseFacilityV2ClearinghouseLib {
    /// @notice The Clearinghouse configuration of the facility.
    /// @param offsets The cumulative offset applied to a Clearinghouse's
    ///        `principalReceivables`.
    /// @param included The Clearinghouses counted toward the backing yield regardless of
    ///        their reserve token.
    struct Clearinghouses {
        mapping(address clearinghouse => uint256 offset) offsets;
        mapping(address clearinghouse => bool included) included;
    }

    /// @notice Sets the cumulative receivables offset of a Clearinghouse.
    /// @dev Emits `ClearinghouseOffsetSet` for the facility.
    ///
    ///      Reverts if:
    ///      - `clearinghouse_` is the zero address (`Errors.BadInput`).
    ///      - `offset_` exceeds the current `principalReceivables`
    ///        (`IYieldRepurchaseFacilityV2_OffsetExceedsReceivables`).
    /// @param state_ The facility's Clearinghouse configuration storage.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param offset_ The new cumulative offset, in the receivables' units.
    function setOffset(
        Clearinghouses storage state_,
        address clearinghouse_,
        uint256 offset_
    ) external {
        validateOffset(clearinghouse_, offset_);

        state_.offsets[clearinghouse_] = offset_;
        emit IYieldRepurchaseFacilityV2.ClearinghouseOffsetSet(clearinghouse_, offset_);
    }

    /// @notice Validates a cumulative receivables offset against the Clearinghouse's live
    ///         `principalReceivables`.
    /// @dev Reverts if:
    ///      - `clearinghouse_` is the zero address (`Errors.BadInput`).
    ///      - `offset_` exceeds the current `principalReceivables`
    ///        (`IYieldRepurchaseFacilityV2_OffsetExceedsReceivables`).
    /// @param clearinghouse_ The Clearinghouse address.
    /// @param offset_ The cumulative offset to validate, in the receivables' units.
    function validateOffset(address clearinghouse_, uint256 offset_) public view {
        if (clearinghouse_ == address(0)) revert Errors.BadInput("clearinghouse");

        uint256 receivables = readPrincipalReceivables(clearinghouse_);
        if (offset_ > receivables)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_OffsetExceedsReceivables(
                clearinghouse_,
                offset_,
                receivables
            );
    }

    /// @notice Includes a Clearinghouse in the backing yield regardless of its reserve
    ///         token.
    /// @dev The inclusion is validated: the address must be present in the CHREG
    ///      registry, and its `principalReceivables()` must be readable (a zero value is
    ///      valid). Emits `ClearinghouseIncluded` for the facility.
    ///
    ///      Reverts if:
    ///      - The Clearinghouse is already included
    ///        (`IYieldRepurchaseFacilityV2_ClearinghouseIncluded`).
    ///      - `clearinghouse_` is not present in the CHREG registry
    ///        (`IYieldRepurchaseFacilityV2_ClearinghouseNotInRegistry`).
    ///      - The `principalReceivables()` read reverts
    ///        (`IYieldRepurchaseFacilityV2_ClearinghouseReceivablesNotReadable`).
    /// @param state_ The facility's Clearinghouse configuration storage.
    /// @param context_ The dependencies of the facility: the CHREG module.
    /// @param clearinghouse_ The Clearinghouse address.
    function include(
        Clearinghouses storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_,
        address clearinghouse_
    ) external {
        if (state_.included[clearinghouse_])
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseIncluded();

        _validateIncludable(context_, clearinghouse_);

        state_.included[clearinghouse_] = true;
        emit IYieldRepurchaseFacilityV2.ClearinghouseIncluded(clearinghouse_);
    }

    /// @notice Removes a Clearinghouse inclusion.
    /// @dev Emits `ClearinghouseExcluded` for the facility.
    ///
    ///      Reverts if the Clearinghouse is not included
    ///      (`IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded`).
    /// @param state_ The facility's Clearinghouse configuration storage.
    /// @param clearinghouse_ The Clearinghouse address.
    function exclude(Clearinghouses storage state_, address clearinghouse_) external {
        if (!state_.included[clearinghouse_])
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseNotIncluded();

        state_.included[clearinghouse_] = false;
        emit IYieldRepurchaseFacilityV2.ClearinghouseExcluded(clearinghouse_);
    }

    /// @notice Sums the weekly interest of every registry Clearinghouse that counts
    ///         toward the backing yield.
    /// @dev Zero when no backing vault is designated (the backing reserve of the context
    ///      is the zero address). The reads are tolerant, so an incompatible registry entry
    ///      contributes nothing.
    /// @param state_ The facility's Clearinghouse configuration storage.
    /// @param context_ The dependencies of the facility: the CHREG module and the backing
    ///        reserve.
    /// @return yield The weekly interest, in backing reserve units.
    function clearinghouseYield(
        Clearinghouses storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) external view returns (uint256 yield) {
        address backingReserve_ = context_.backingReserve;
        if (backingReserve_ == address(0)) return 0;

        CHREGv1 chreg = CHREGv1(context_.chreg);
        uint256 len = chreg.registryCount();
        for (uint256 i; i < len; ++i) {
            // The CHREG registry is append-only and grows only through permissioned activations
            // forge-lint: disable-next-line(calls-loop)
            address ch = chreg.registry(i);
            if (!_countsTowardBackingYield(state_, ch, backingReserve_)) continue;
            yield += YieldRepurchaseFacilityV2MathLib.clearinghouseInterest(
                readPrincipalReceivables(ch),
                state_.offsets[ch]
            );
        }
    }

    /// @notice Emits `ClearinghouseDebtTokenMismatch` for every registry Clearinghouse
    ///         that does not count toward the backing yield.
    /// @dev A no-op when no backing vault is designated (the backing reserve of the
    ///      context is the zero address). The event is emitted by the calling facility.
    /// @param state_ The facility's Clearinghouse configuration storage.
    /// @param context_ The dependencies of the facility: the CHREG module and the backing
    ///        reserve.
    function emitClearinghouseMismatches(
        Clearinghouses storage state_,
        IYieldRepurchaseFacilityV2.Context memory context_
    ) external {
        address backingReserve_ = context_.backingReserve;
        if (backingReserve_ == address(0)) return;

        CHREGv1 chreg = CHREGv1(context_.chreg);
        uint256 len = chreg.registryCount();
        for (uint256 i; i < len; ++i) {
            // The CHREG registry is append-only and grows only through permissioned activations
            // forge-lint: disable-next-line(calls-loop)
            address ch = chreg.registry(i);
            if (!_countsTowardBackingYield(state_, ch, backingReserve_))
                emit IYieldRepurchaseFacilityV2.ClearinghouseDebtTokenMismatch(ch);
        }
    }

    /// @notice Reads the Clearinghouse's `principalReceivables`, treating a revert as
    ///         zero.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return The current `principalReceivables`, or zero when the read reverts.
    function readPrincipalReceivables(address clearinghouse_) public view returns (uint256) {
        // Called once per entry of the governance-bounded registry scan
        // forge-lint: disable-next-line(calls-loop)
        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256 receivables
        ) {
            return receivables;
        } catch {
            return 0;
        }
    }

    /// @notice Validates that a Clearinghouse is includable into the backing yield: it is
    ///         present in the CHREG registry and its `principalReceivables()` is
    ///         readable.
    /// @dev A zero receivables value is valid; only a read that reverts is rejected.
    ///
    ///      Reverts if:
    ///      - `clearinghouse_` is not present in the CHREG registry.
    ///      - The `principalReceivables()` read reverts.
    function _validateIncludable(
        IYieldRepurchaseFacilityV2.Context memory context_,
        address clearinghouse_
    ) private view {
        bool registered;
        CHREGv1 chreg = CHREGv1(context_.chreg);
        uint256 len = chreg.registryCount();
        for (uint256 i; i < len; ++i) {
            // The CHREG registry is append-only and grows only through permissioned activations
            // forge-lint: disable-next-line(calls-loop)
            if (chreg.registry(i) == clearinghouse_) {
                registered = true;
                break;
            }
        }
        if (!registered)
            revert IYieldRepurchaseFacilityV2.IYieldRepurchaseFacilityV2_ClearinghouseNotInRegistry(
                clearinghouse_
            );

        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256
        ) {} catch {
            revert IYieldRepurchaseFacilityV2
                .IYieldRepurchaseFacilityV2_ClearinghouseReceivablesNotReadable(clearinghouse_);
        }
    }

    /// @notice Returns whether a Clearinghouse counts toward the backing yield: either
    ///         its reserve matches the backing reserve, or it has been explicitly
    ///         included.
    function _countsTowardBackingYield(
        Clearinghouses storage state_,
        address clearinghouse_,
        address backingReserve_
    ) private view returns (bool) {
        return
            state_.included[clearinghouse_] ||
            _readClearinghouseReserve(clearinghouse_) == backingReserve_;
    }

    /// @notice Reads the Clearinghouse's reserve token, treating a revert as the zero
    ///         address.
    function _readClearinghouseReserve(address clearinghouse_) private view returns (address) {
        // Called once per entry of the governance-bounded registry scans
        // forge-lint: disable-next-line(calls-loop)
        try IClearinghouseReserve(clearinghouse_).reserve() returns (address reserve) {
            return reserve;
        } catch {
            return address(0);
        }
    }
}
