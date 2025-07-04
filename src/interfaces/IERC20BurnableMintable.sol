// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

interface IERC20BurnableMintable {
    /// @notice Mints tokens to the specified address
    ///
    /// @param to_      The address to mint tokens to
    /// @param amount_  The amount of tokens to mint
    function mintFor(address to_, uint256 amount_) external;

    /// @notice Burns tokens from the specified address
    ///
    /// @param from_    The address to burn tokens from
    /// @param amount_  The amount of tokens to burn
    function burnFrom(address from_, uint256 amount_) external;
}
