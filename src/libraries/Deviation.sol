// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FullMath} from "src/libraries/FullMath.sol";

library Deviation {
    using FullMath for uint256;

    // ========== ERRORS ========== //

    /// @notice                 The provided deviation is greater than the maximum deviation
    /// @param deviationBps_    The accepted deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    error Deviation_InvalidDeviationBps(uint256 deviationBps_, uint256 deviationMax_);

    // ========== LIBRARY LOGIC ========== //

    /// @notice                 Checks if the deviation between two values is greater than the given deviation
    /// @dev                    This function will revert if:
    ///                         - `deviationBps_` is greater than `deviationMax_`
    ///
    /// @param value_           The value to be checked for deviation
    /// @param benchmark_       The reference value to check against
    /// @param deviationBps_    The accepted deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function isDeviatingWithBpsCheck(
        uint256 value_,
        uint256 benchmark_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal pure returns (bool) {
        if (deviationBps_ > deviationMax_)
            revert Deviation_InvalidDeviationBps(deviationBps_, deviationMax_);

        return isDeviating(value_, benchmark_, deviationBps_, deviationMax_);
    }

    /// @notice                 Checks if the deviation between two values is greater than the given deviation
    ///
    /// @param value_           The value to be checked for deviation
    /// @param benchmark_       The reference value to check against
    /// @param deviationBps_    The accepted deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function isDeviating(
        uint256 value_,
        uint256 benchmark_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal pure returns (bool) {
        uint256 diff = (value_ > benchmark_) ? value_ - benchmark_ : benchmark_ - value_;
        return _isDeviating(diff, benchmark_, deviationBps_, deviationMax_);
    }

    /// @notice                 Checks if the deviation between two values is greater than the given deviation
    /// @dev                    This function will revert if:
    ///                         - `benchmark_` is zero
    ///
    /// @param diff_            The difference between the two values
    /// @param benchmark_       The reference value to check against
    /// @param deviationBps_    The deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function _isDeviating(
        uint256 diff_,
        uint256 benchmark_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal pure returns (bool) {
        return diff_.mulDivUp(deviationMax_, benchmark_) > deviationBps_;
    }
}
