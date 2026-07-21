// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IClearinghouseReserve} from "src/policies/interfaces/IClearinghouseReserve.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {IYieldRepurchaseFacilityV2} from "src/policies/interfaces/YieldRepurchaseFacility/IYieldRepurchaseFacilityV2.sol";

// Libraries
import {Math} from "@openzeppelin-5.3.0/utils/math/Math.sol";

// Modules
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";

/// @title YRFClearinghouseLib
/// @notice An external library that measures the Clearinghouse component of the backing
///         yield of the YieldRepurchaseFacilityV2.
/// @dev The library is deployed separately and reached through `DELEGATECALL`, so the
///      mapping parameters reference the calling facility's storage and the mismatch
///      event is emitted by the facility.
library YRFClearinghouseLib {
    /// @notice Numerator of the Clearinghouse annual interest rate (0.5%).
    uint256 internal constant CH_RATE_NUMERATOR = 5;

    /// @notice Denominator of the Clearinghouse annual interest rate (`5 / 1000` = 0.5%).
    uint256 internal constant CH_RATE_DENOMINATOR = 1000;

    /// @notice Number of weeks per year used for the Clearinghouse annual rate.
    uint256 internal constant WEEKS_PER_YEAR = 52;

    /// @notice Sums the weekly interest of every registry Clearinghouse that counts
    ///         toward the backing yield.
    /// @dev Zero when `backingReserve_` is the zero address. The reads are tolerant, so
    ///      an incompatible registry entry contributes nothing.
    /// @param chreg_ The Clearinghouse registry module.
    /// @param backingReserve_ The reserve token of the backing vault, or the zero
    ///        address when no backing vault is designated.
    /// @param receivablesOffsets_ The caller's per-Clearinghouse receivables offsets.
    /// @param includedClearinghouses_ The caller's per-Clearinghouse inclusion flags.
    /// @return yield The weekly interest, in backing reserve units.
    function clearinghouseYield(
        CHREGv1 chreg_,
        address backingReserve_,
        mapping(address => uint256) storage receivablesOffsets_,
        mapping(address => bool) storage includedClearinghouses_
    ) external view returns (uint256 yield) {
        if (backingReserve_ == address(0)) return 0;

        uint256 len = chreg_.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            address ch = chreg_.registry(i);
            if (!_countsTowardBackingYield(ch, backingReserve_, includedClearinghouses_)) continue;
            yield += _clearinghouseInterest(readPrincipalReceivables(ch), receivablesOffsets_[ch]);
        }
    }

    /// @notice Emits `ClearinghouseDebtTokenMismatch` for every registry Clearinghouse
    ///         that does not count toward the backing yield.
    /// @dev A no-op when `backingReserve_` is the zero address. The event is emitted by
    ///      the calling facility.
    /// @param chreg_ The Clearinghouse registry module.
    /// @param backingReserve_ The reserve token of the backing vault, or the zero
    ///        address when no backing vault is designated.
    /// @param includedClearinghouses_ The caller's per-Clearinghouse inclusion flags.
    function emitClearinghouseMismatches(
        CHREGv1 chreg_,
        address backingReserve_,
        mapping(address => bool) storage includedClearinghouses_
    ) external {
        if (backingReserve_ == address(0)) return;

        uint256 len = chreg_.registryCount();
        for (uint256 i = 0; i < len; ++i) {
            address ch = chreg_.registry(i);
            if (!_countsTowardBackingYield(ch, backingReserve_, includedClearinghouses_))
                emit IYieldRepurchaseFacilityV2.ClearinghouseDebtTokenMismatch(ch);
        }
    }

    /// @notice Reads the Clearinghouse's `principalReceivables`, treating a revert as
    ///         zero.
    /// @param clearinghouse_ The Clearinghouse address.
    /// @return The current `principalReceivables`, or zero when the read reverts.
    function readPrincipalReceivables(address clearinghouse_) public view returns (uint256) {
        try IGenericClearinghouse(clearinghouse_).principalReceivables() returns (
            uint256 receivables
        ) {
            return receivables;
        } catch {
            return 0;
        }
    }

    /// @notice Returns whether a Clearinghouse counts toward the backing yield: either
    ///         its reserve matches the backing reserve, or it has been explicitly
    ///         included.
    function _countsTowardBackingYield(
        address clearinghouse_,
        address backingReserve_,
        mapping(address => bool) storage includedClearinghouses_
    ) private view returns (bool) {
        return
            includedClearinghouses_[clearinghouse_] ||
            _readClearinghouseReserve(clearinghouse_) == backingReserve_;
    }

    /// @notice Returns one week of interest on the effective receivables.
    /// @dev The offset is subtracted with saturation; the rate is 0.5% per year divided
    ///      over 52 weeks, floored at each division.
    function _clearinghouseInterest(
        uint256 receivables_,
        uint256 offset_
    ) private pure returns (uint256) {
        uint256 effective = Math.saturatingSub(receivables_, offset_);
        return (effective * CH_RATE_NUMERATOR) / CH_RATE_DENOMINATOR / WEEKS_PER_YEAR;
    }

    /// @notice Reads the Clearinghouse's reserve token, treating a revert as the zero
    ///         address.
    function _readClearinghouseReserve(address clearinghouse_) private view returns (address) {
        try IClearinghouseReserve(clearinghouse_).reserve() returns (address reserve) {
            return reserve;
        } catch {
            return address(0);
        }
    }
}
