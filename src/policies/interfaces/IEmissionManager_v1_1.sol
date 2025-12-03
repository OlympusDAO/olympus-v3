// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

/// @dev Interface for the EmissionManager policy as of v1.1
interface IEmissionManager {
    /// @notice Whether the contract is locally active
    function locallyActive() external view returns (bool);
}
