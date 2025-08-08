// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IERC6909Wrappable
/// @notice Declares interface for an ERC6909 implementation that allows for wrapping and unwrapping ERC6909 tokens to and from ERC20 tokens
interface IERC6909Wrappable {
    // ========== EVENTS ========== //

    event Wrapped(
        uint256 indexed tokenId,
        address indexed wrappedToken,
        address indexed account,
        uint256 amount
    );

    event Unwrapped(
        uint256 indexed tokenId,
        address indexed wrappedToken,
        address indexed account,
        uint256 amount
    );

    // ========== ERRORS ========== //

    error ERC6909Wrappable_TokenIdAlreadyExists(uint256 tokenId);
    error ERC6909Wrappable_InvalidTokenId(uint256 tokenId);
    error ERC6909Wrappable_InvalidERC20Implementation(address erc20Implementation);
    error ERC6909Wrappable_ZeroAmount();

    // ========== WRAP/UNWRAP FUNCTIONS ========== //

    /// @notice Wraps an ERC6909 token to an ERC20 token
    ///
    /// @param tokenId_      The ID of the ERC6909 token
    /// @param amount_       The amount of tokens to wrap
    /// @return wrappedToken The address of the wrapped ERC20 token
    function wrap(uint256 tokenId_, uint256 amount_) external returns (address wrappedToken);

    /// @notice Unwraps an ERC20 token to an ERC6909 token
    ///
    /// @param tokenId_      The ID of the ERC6909 token
    /// @param amount_       The amount of tokens to unwrap
    function unwrap(uint256 tokenId_, uint256 amount_) external;

    /// @notice Returns the address of the wrapped ERC20 token for a given token ID
    ///
    /// @param  tokenId_        The ID of the ERC6909 token
    /// @return wrappedToken    The address of the wrapped ERC20 token (or zero address)
    function getWrappedToken(uint256 tokenId_) external view returns (address wrappedToken);

    // ========== TOKEN FUNCTIONS ========== //

    /// @notice Returns whether a token ID is valid
    ///
    /// @param  tokenId_        The ID of the ERC6909 token
    /// @return isValid         Whether the token ID is valid
    function isValidTokenId(uint256 tokenId_) external view returns (bool isValid);

    /// @notice Returns the token IDs and wrapped token addresses of all tokens
    ///
    /// @return tokenIds        The IDs of all tokens
    /// @return wrappedTokens   The wrapped token addresses of all tokens
    function getWrappableTokens()
        external
        view
        returns (uint256[] memory tokenIds, address[] memory wrappedTokens);
}
