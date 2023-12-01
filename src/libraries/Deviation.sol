// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library Deviation {
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
    /// @param value0_          The first value
    /// @param value1_          The second value
    /// @param deviationBps_    The accepted deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function isDeviatingWithBpsCheck(
        uint256 value0_,
        uint256 value1_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal pure returns (bool) {
        if (deviationBps_ > deviationMax_)
            revert Deviation_InvalidDeviationBps(deviationBps_, deviationMax_);

        return isDeviating(value0_, value1_, deviationBps_, deviationMax_);
    }

    /// @notice                 Checks if the deviation between two values is greater than the given deviation
    ///
    /// @param value0_          The first value
    /// @param value1_          The second value
    /// @param deviationBps_    The accepted deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function isDeviating(
        uint256 value0_,
        uint256 value1_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal pure returns (bool) {
        return
            (value0_ < value1_)
                ? _isDeviating(value1_, value0_, deviationBps_, deviationMax_)
                : _isDeviating(value0_, value1_, deviationBps_, deviationMax_);
    }

    /// @notice                 Checks if the deviation between two values is greater than the given deviation
    /// @dev                    This function will revert if:
    ///                         - `value1_` is greater than `value0_`
    ///
    /// @param value0_          The biggest value
    /// @param value1_          The smallest value
    /// @param deviationBps_    The deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function _isDeviating(
        uint256 value0_,
        uint256 value1_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal pure returns (bool) {
        return ((value0_ - value1_) * deviationMax_) / value0_ > deviationBps_;
    }
}
