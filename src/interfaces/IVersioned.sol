// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.0;

/// @title IVersioned
/// @notice Interface for contracts that have a version
interface IVersioned {
    /// @notice Returns the version of the contract
    ///
    /// @return major - Major version upgrade indicates breaking change to the interface.
    /// @return minor - Minor version change retains backward-compatible interface.
    function VERSION() external view returns (uint8 major, uint8 minor);
}
/// forge-lint: disable-end(mixed-case-function)
