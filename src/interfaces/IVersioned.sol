// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity ^0.8.15;

/// @title  IVersioned
/// @notice Interface for contracts that have a version number.
interface IVersioned {
    /// @notice Returns the major and minor version of the contract
    ///
    /// @return major The major version of the contract
    /// @return minor The minor version of the contract
    function VERSION() external view returns (uint8 major, uint8 minor);
}
/// forge-lint: disable-end(mixed-case-function)
