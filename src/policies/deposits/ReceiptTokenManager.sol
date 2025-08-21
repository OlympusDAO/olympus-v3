// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Libraries
import {ERC6909Wrappable} from "src/libraries/ERC6909Wrappable.sol";
import {CloneableReceiptToken} from "src/libraries/CloneableReceiptToken.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";
import {String} from "src/libraries/String.sol";

/// @title  ReceiptTokenManager
/// @notice Manager contract for creating and managing ERC6909 receipt tokens for deposits
/// @dev    This contract is extracted from DepositManager to reduce its size. Wrapped tokens will be clones of CloneableReceiptToken, but a future version could make the ERC20 wrapped token configurable.
contract ReceiptTokenManager is ERC6909Wrappable, IReceiptTokenManager {
    using String for string;

    // ========== STATE VARIABLES ========== //

    // ========== STORAGE STRUCTS ========== //

    struct TokenStorageData {
        address owner; // 20 bytes
        address asset; // 20 bytes
        address operator; // 20 bytes
        uint8 depositPeriod; // 1 byte
    }

    // ========== CONSTRUCTOR ========== //

    constructor() ERC6909Wrappable(address(new CloneableReceiptToken())) {}

    // ========== TOKEN CREATION ========== //

    /// @inheritdoc IReceiptTokenManager
    function createToken(
        address owner_,
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        string memory operatorName_
    ) external returns (uint256 tokenId) {
        // Generate token ID including owner in the hash
        tokenId = getReceiptTokenId(owner_, asset_, depositPeriod_, operator_);

        // Validate token doesn't already exist
        if (isValidTokenId(tokenId)) {
            revert ReceiptTokenManager_TokenExists(tokenId);
        }

        // Create the wrappable token with ABI-encoded struct
        _createWrappableToken(
            tokenId,
            string
                .concat(operatorName_, asset_.name(), " - ", uint2str(depositPeriod_), " months")
                .truncate32(),
            string
                .concat(operatorName_, asset_.symbol(), "-", uint2str(depositPeriod_), "m")
                .truncate32(),
            asset_.decimals(),
            abi.encode(
                TokenStorageData({
                    owner: owner_,
                    asset: address(asset_),
                    operator: operator_,
                    depositPeriod: depositPeriod_
                })
            ),
            false
        );

        emit TokenCreated(tokenId, owner_, address(asset_), depositPeriod_, operator_);
        return tokenId;
    }

    // ========== MINTING/BURNING ========== //

    modifier onlyTokenOwner(uint256 tokenId_) {
        address owner = getTokenOwner(tokenId_);
        if (msg.sender != owner) {
            revert ReceiptTokenManager_NotOwner(msg.sender, owner);
        }
        _;
    }

    /// @inheritdoc IReceiptTokenManager
    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool shouldWrap_
    ) external onlyTokenOwner(tokenId_) {
        _mint(to_, tokenId_, amount_, shouldWrap_);
    }

    /// @inheritdoc IReceiptTokenManager
    function burn(
        address from_,
        uint256 tokenId_,
        uint256 amount_,
        bool isWrapped_
    ) external onlyTokenOwner(tokenId_) {
        _burn(from_, tokenId_, amount_, isWrapped_);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice Decode the token storage data from _tokenMetadataAdditional
    /// @param tokenId_ The token ID
    /// @return data The decoded TokenStorageData struct
    function _getTokenStorageData(
        uint256 tokenId_
    ) internal view returns (TokenStorageData memory data) {
        // Access additional metadata directly from parent contract
        bytes memory encodedData = _getTokenAdditionalData(tokenId_);

        if (encodedData.length == 0) {
            return TokenStorageData(address(0), address(0), address(0), 0);
        }

        // Decode the ABI-encoded struct
        data = abi.decode(encodedData, (TokenStorageData));
        return data;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IReceiptTokenManager
    function getReceiptTokenId(
        address owner_,
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) public pure override returns (uint256) {
        return uint256(keccak256(abi.encode(owner_, asset_, depositPeriod_, operator_)));
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenName(uint256 tokenId_) public view override returns (string memory) {
        return name(tokenId_);
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenSymbol(uint256 tokenId_) public view override returns (string memory) {
        return symbol(tokenId_);
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenDecimals(uint256 tokenId_) public view override returns (uint8) {
        return decimals(tokenId_);
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenOwner(uint256 tokenId_) public view override returns (address) {
        TokenStorageData memory data = _getTokenStorageData(tokenId_);
        return data.owner;
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenAsset(uint256 tokenId_) external view override returns (IERC20) {
        TokenStorageData memory data = _getTokenStorageData(tokenId_);
        return IERC20(data.asset);
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenDepositPeriod(uint256 tokenId_) external view override returns (uint8) {
        TokenStorageData memory data = _getTokenStorageData(tokenId_);
        return data.depositPeriod;
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenOperator(uint256 tokenId_) external view override returns (address) {
        TokenStorageData memory data = _getTokenStorageData(tokenId_);
        return data.operator;
    }
}
