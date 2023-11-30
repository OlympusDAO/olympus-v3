// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library Deviation {
    /// @notice                 Checks if the deviation between two values is greater than the given deviation
    ///
    /// @param value0_          The first value
    /// @param value1_          The second value
    /// @param deviationBps_    The deviation in basis points (e.g. 100 = 1%)
    /// @param deviationMax_    The maximum deviation in basis points (e.g. 10000 = 100%)
    /// @return                 True if the deviation is greater than the given deviation, false otherwise
    function isDeviating(
        uint256 value0_,
        uint256 value1_,
        uint256 deviationBps_,
        uint256 deviationMax_
    ) internal view returns (bool) {
        if (value0_ < value1_) {
            return isDeviating(value1_, value0_, deviationBps_, deviationMax_);
        }

        return ((value0_ - value1_) * deviationMax_) / value0_ > deviationBps_;
    }
}