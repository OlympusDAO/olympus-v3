// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

// Libraries
import {ERC6909Wrappable} from "src/libraries/ERC6909Wrappable.sol";
import {CloneableReceiptToken} from "src/libraries/CloneableReceiptToken.sol";
import {uint2str} from "src/libraries/Uint2Str.sol";
import {String} from "src/libraries/String.sol";
import {IDepositReceiptToken} from "src/interfaces/IDepositReceiptToken.sol";

/// @title  ReceiptTokenManager
/// @notice Manager contract for creating and managing ERC6909 receipt tokens for deposits
/// @dev    Extracted from DepositManager to reduce contract size.
///
///         Key Features:
///         - Creator-only minting/burning: Only the contract that creates a token can mint/burn it
///         - ERC6909 compatibility with optional ERC20 wrapping via CloneableReceiptToken clones
///         - Deterministic token ID generation based on owner, asset, deposit period, and operator
///         - Automatic wrapped token creation for seamless DeFi integration
///
///         Security Model:
///         - Token ownership is immutable and set to msg.sender during creation
///         - All mint/burn operations are gated by onlyTokenOwner modifier
///         - Token IDs include owner address to prevent collision attacks
contract ReceiptTokenManager is ERC6909Wrappable, IReceiptTokenManager {
    using String for string;

    // ========== STATE VARIABLES ========== //

    /// @notice Maps token ID to the authorized owner (for mint/burn operations)
    mapping(uint256 tokenId => address authorizedOwner) internal _tokenOwners;

    // ========== CONSTRUCTOR ========== //

    constructor() ERC6909Wrappable(address(new CloneableReceiptToken())) {}

    // ========== TOKEN CREATION ========== //

    /// @inheritdoc IReceiptTokenManager
    /// @dev        This function reverts if:
    ///             - The asset is the zero address
    ///             - The deposit period is 0
    ///             - The operator is the zero address
    ///             - A token with the same parameters already exists
    function createToken(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_,
        string memory operatorName_
    ) external returns (uint256 tokenId) {
        // Validate parameters
        if (address(asset_) == address(0)) {
            revert ReceiptTokenManager_InvalidParams("asset");
        }
        if (depositPeriod_ == 0) {
            revert ReceiptTokenManager_InvalidParams("depositPeriod");
        }
        if (operator_ == address(0)) {
            revert ReceiptTokenManager_InvalidParams("operator");
        }

        // Use msg.sender as the owner for security
        address owner = msg.sender;

        // Generate token ID including owner in the hash
        tokenId = getReceiptTokenId(owner, asset_, depositPeriod_, operator_);

        // Validate token doesn't already exist
        if (isValidTokenId(tokenId)) {
            revert ReceiptTokenManager_TokenExists(tokenId);
        }

        // Store the authorized owner for this token
        _tokenOwners[tokenId] = owner;

        // Create the wrappable token with proper metadata layout for CloneableReceiptToken
        string memory tokenName = string
            .concat(operatorName_, asset_.name(), " - ", uint2str(depositPeriod_), " months")
            .truncate32();
        string memory tokenSymbol = string
            .concat(operatorName_, asset_.symbol(), "-", uint2str(depositPeriod_), "m")
            .truncate32();

        _createWrappableToken(
            tokenId,
            tokenName,
            tokenSymbol,
            asset_.decimals(),
            abi.encodePacked(
                address(this), // Owner at 0x41
                address(asset_), // Asset at 0x55
                depositPeriod_, // Deposit Period at 0x69
                operator_ // Operator at 0x6A
            ),
            true // Automatically create the wrapped token
        );

        emit TokenCreated(tokenId, owner, address(asset_), depositPeriod_, operator_);
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
    /// @dev        This function reverts if:
    ///             - The token ID is invalid (not created)
    ///             - The caller is not the token owner
    ///             - The recipient is the zero address
    ///             - The amount is 0
    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool shouldWrap_
    ) external onlyValidTokenId(tokenId_) onlyTokenOwner(tokenId_) {
        _mint(to_, tokenId_, amount_, shouldWrap_);
    }

    /// @inheritdoc IReceiptTokenManager
    /// @dev        This function reverts if:
    ///             - The token ID is invalid (not created)
    ///             - The caller is not the token owner
    ///             - The account is the zero address
    ///             - The amount is 0
    ///             - For wrapped tokens: account has not approved ReceiptTokenManager to spend the wrapped ERC20 token
    ///             - For unwrapped tokens: account has not approved the caller to spend ERC6909 tokens
    ///             - The account has insufficient token balance
    function burn(
        address from_,
        uint256 tokenId_,
        uint256 amount_,
        bool isWrapped_
    ) external onlyValidTokenId(tokenId_) onlyTokenOwner(tokenId_) {
        _burn(from_, tokenId_, amount_, isWrapped_);
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
        return _tokenOwners[tokenId_];
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenAsset(uint256 tokenId_) external view override returns (IERC20) {
        address wrappedToken = getWrappedToken(tokenId_);
        if (wrappedToken == address(0)) return IERC20(address(0));
        return IDepositReceiptToken(wrappedToken).asset();
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenDepositPeriod(uint256 tokenId_) external view override returns (uint8) {
        address wrappedToken = getWrappedToken(tokenId_);
        if (wrappedToken == address(0)) return 0;
        return IDepositReceiptToken(wrappedToken).depositPeriod();
    }

    /// @inheritdoc IReceiptTokenManager
    function getTokenOperator(uint256 tokenId_) external view override returns (address) {
        address wrappedToken = getWrappedToken(tokenId_);
        if (wrappedToken == address(0)) return address(0);
        return IDepositReceiptToken(wrappedToken).operator();
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC6909Wrappable, IERC165) returns (bool) {
        return
            interfaceId == type(IReceiptTokenManager).interfaceId ||
            ERC6909Wrappable.supportsInterface(interfaceId);
    }
}
