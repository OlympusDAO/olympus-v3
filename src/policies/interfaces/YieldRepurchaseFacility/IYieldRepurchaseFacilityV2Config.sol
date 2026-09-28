// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IYieldRepurchaseFacilityV2Config
/// @notice The interface for the configuration policy of YieldRepurchaseFacilityV2: the only
///         caller the facility accepts for its configuration setters.
/// @dev An implementation is expected to advertise this interface through ERC165: the
///      facility checks it when the policy is bound as the configurator.
interface IYieldRepurchaseFacilityV2Config {
    /// @notice Returns the facility the configuration policy is bound to.
    /// @return facility_ The facility address, or the zero address while no facility is bound.
    function facility() external view returns (address facility_);
}
