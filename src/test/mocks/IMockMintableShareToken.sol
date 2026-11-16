// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice Mint and burn surface used by the ERC-7575 share-token fixtures.
interface IMockMintableShareToken {
    /// @notice Mints fixture shares to a recipient.
    /// @param recipient_ Address receiving the shares.
    /// @param amount_ Number of shares to mint.
    function mint(address recipient_, uint256 amount_) external;

    /// @notice Burns fixture shares from an owner.
    /// @param owner_ Address whose shares are burned.
    /// @param amount_ Number of shares to burn.
    function burn(address owner_, uint256 amount_) external;
}
