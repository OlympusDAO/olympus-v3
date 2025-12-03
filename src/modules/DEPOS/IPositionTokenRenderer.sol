// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @title  IPositionTokenRenderer
/// @notice Interface for a contract that can render token URIs for deposit positions
interface IPositionTokenRenderer {
    // ========== ERRORS ========== //

    error PositionTokenRenderer_InvalidAddress();

    // ========== FUNCTIONS ========== //

    /// @notice Renders the token URI for a given position
    /// @dev    This function should return a valid JSON metadata string that follows the ERC721 metadata standard
    ///
    /// @param  positionManager_ The address of the position manager contract
    /// @param  positionId_      The ID of the position to render
    /// @return uri              The token URI as a string
    function tokenURI(
        address positionManager_,
        uint256 positionId_
    ) external view returns (string memory uri);
}
