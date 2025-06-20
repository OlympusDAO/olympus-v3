// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IPositionTokenRenderer
/// @notice Interface for a contract that can render token URIs for deposit positions
interface IPositionTokenRenderer {
    // ========== ERRORS ========== //

    error PositionTokenRenderer_ZeroAddress();

    // ========== FUNCTIONS ========== //

    /// @notice Get the address of the position manager contract
    /// @dev    This function should return the address of the position manager contract
    ///
    /// @return positionManager_    The address of the position manager contract
    function getPositionManager() external view returns (address positionManager_);

    /// @notice Renders the token URI for a given position
    /// @dev    This function should return a valid JSON metadata string that follows the ERC721 metadata standard
    ///
    /// @param  positionId_      The ID of the position to render
    /// @return uri              The token URI as a string
    function tokenURI(uint256 positionId_) external view returns (string memory uri);
}
