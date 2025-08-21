// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC6909} from "@openzeppelin-5.3.0/interfaces/draft-IERC6909.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";

/// @title IReceiptTokenManager
/// @notice Interface for the contract that creates and manages receipt tokens
interface IReceiptTokenManager is IERC6909, IERC6909Wrappable {
    // ========== STRUCTS ========== //

    struct DepositTokenMetadata {
        address asset;
        uint8 depositPeriod;
        address operator;
    }

    // ========== EVENTS ========== //

    event TokenCreated(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed asset,
        uint8 depositPeriod,
        address operator
    );

    // ========== ERRORS ========== //

    error ReceiptTokenManager_TokenExists(uint256 tokenId);
    error ReceiptTokenManager_NotOwner(address caller, address owner);

    // ========== FUNCTIONS ========== //

    /// @notice Creates a new receipt token
    /// @dev    The caller (msg.sender) becomes the owner of the token for security
    ///
    /// @param  asset_          The underlying asset
    /// @param  depositPeriod_  The deposit period
    /// @param  operator_       The operator address
    /// @param  operatorName_   The operator name for token metadata
    /// @return tokenId         The created token ID
    function createToken(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        string memory operatorName_
    ) external returns (uint256 tokenId);

    /// @notice Mints tokens to a recipient
    /// @dev    Gated to the owner (creator) of the token
    ///
    /// @param  to_         The recipient
    /// @param  tokenId_    The token ID
    /// @param  amount_     The amount to mint
    /// @param  shouldWrap_ Whether to wrap as ERC20
    function mint(address to_, uint256 tokenId_, uint256 amount_, bool shouldWrap_) external;

    /// @notice Burns tokens from a holder
    /// @dev    Gated to the owner (creator) of the token
    ///
    /// @param  from_       The holder
    /// @param  tokenId_    The token ID
    /// @param  amount_     The amount to burn
    /// @param  isWrapped_  Whether the tokens are wrapped
    function burn(address from_, uint256 tokenId_, uint256 amount_, bool isWrapped_) external;

    /// @notice Generates a receipt token ID
    ///
    /// @param  owner_          The owner address
    /// @param  asset_          The asset
    /// @param  depositPeriod_  The deposit period
    /// @param  operator_       The operator
    /// @return tokenId         The generated token ID
    function getReceiptTokenId(
        address owner_,
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external pure returns (uint256 tokenId);

    /// @notice Returns the name of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return name        The name of the receipt token
    function getTokenName(uint256 tokenId_) external view returns (string memory name);

    /// @notice Returns the symbol of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return symbol      The symbol of the receipt token
    function getTokenSymbol(uint256 tokenId_) external view returns (string memory symbol);

    /// @notice Returns the decimals of a receipt token
    ///
    /// @param  tokenId_    The ID of the receipt token
    /// @return decimals    The decimals of the receipt token
    function getTokenDecimals(uint256 tokenId_) external view returns (uint8 decimals);

    /// @notice Gets the owner of a token
    ///
    /// @param  tokenId_    The token ID
    /// @return owner       The token owner
    function getTokenOwner(uint256 tokenId_) external view returns (address owner);

    /// @notice Gets the asset of a token
    ///
    /// @param  tokenId_    The token ID
    /// @return asset       The underlying asset
    function getTokenAsset(uint256 tokenId_) external view returns (IERC20 asset);

    /// @notice Gets the deposit period of a token
    ///
    /// @param  tokenId_        The token ID
    /// @return depositPeriod   The deposit period
    function getTokenDepositPeriod(uint256 tokenId_) external view returns (uint8 depositPeriod);

    /// @notice Gets the operator of a token
    ///
    /// @param  tokenId_    The token ID
    /// @return operator    The operator address
    function getTokenOperator(uint256 tokenId_) external view returns (address operator);
}
