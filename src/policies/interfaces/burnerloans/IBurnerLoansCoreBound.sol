// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Identifies the permanent accounting Core associated with a Burner Loans component.
/// @dev A shared binding does not grant settlement authority or imply that Core is operational.
interface IBurnerLoansCoreBound {
    /// @notice The proposed Core lacks required interfaces.
    /// @param core Invalid Core candidate.
    error BurnerLoansAction_InvalidCore(address core);

    /// @notice Returns the Core to which this component is permanently bound.
    /// @return core_ Core containing the authoritative custody and position identity.
    function core() external view returns (address core_);
}
