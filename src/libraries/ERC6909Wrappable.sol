// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Interfaces
import {IERC20BurnableMintable} from "src/interfaces/IERC20BurnableMintable.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC6909Metadata, IERC6909TokenSupply} from "@openzeppelin-5.3.0/interfaces/draft-IERC6909.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";

// Libraries
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";
import {ERC6909Metadata} from "@openzeppelin-5.3.0/token/ERC6909/extensions/draft-ERC6909Metadata.sol";
import {ClonesWithImmutableArgs} from "@clones-with-immutable-args-1.1.2/ClonesWithImmutableArgs.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

/// @title ERC6909Wrappable
/// @notice This abstract contract extends ERC6909 to allow for wrapping and unwrapping of the token to an ERC20 token.
///         It extends the ERC6909Metadata contract, and additionally implements the IERC6909TokenSupply interface.
abstract contract ERC6909Wrappable is ERC6909Metadata, IERC6909Wrappable, IERC6909TokenSupply {
    using ClonesWithImmutableArgs for address;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice The address of the implementation of the ERC20 contract
    address private immutable _ERC20_IMPLEMENTATION;

    /// @notice The set of all token IDs
    EnumerableSet.UintSet internal _wrappableTokenIds;

    /// @notice The total supply of each token
    mapping(uint256 tokenId => uint256) private _totalSupplies;

    /// @notice Additional metadata for each token
    mapping(uint256 tokenId => bytes) private _tokenMetadataAdditional;

    /// @notice The address of the wrapped ERC20 token for each token
    mapping(uint256 tokenId => address) internal _wrappedTokens;

    constructor(address erc20Implementation_) {
        // Validate that the ERC20 implementation implements the required interface
        if (
            !IERC165(erc20Implementation_).supportsInterface(
                type(IERC20BurnableMintable).interfaceId
            )
        ) revert ERC6909Wrappable_InvalidERC20Implementation(erc20Implementation_);

        _ERC20_IMPLEMENTATION = erc20Implementation_;
    }

    /// @notice Returns the clone initialisation data for a given token ID
    function _getTokenData(uint256 tokenId_) internal view returns (bytes memory) {
        bytes memory additionalMetadata = _tokenMetadataAdditional[tokenId_];

        return
            abi.encodePacked(
                bytes32(bytes(name(tokenId_))),
                bytes32(bytes(symbol(tokenId_))),
                decimals(tokenId_),
                additionalMetadata
            );
    }

    // ========== MINT/BURN FUNCTIONS ========== //

    /// @notice Mints the ERC6909 or ERC20 wrapped token to the recipient
    ///
    /// @param onBehalfOf_   The address to mint the token to
    /// @param tokenId_      The ID of the ERC6909 token
    /// @param amount_       The amount of tokens to mint
    /// @param shouldWrap_   Whether to wrap the token to an ERC20 token
    function _mint(
        address onBehalfOf_,
        uint256 tokenId_,
        uint256 amount_,
        bool shouldWrap_
    ) internal onlyValidTokenId(tokenId_) {
        if (amount_ == 0) revert ERC6909Wrappable_ZeroAmount();
        if (onBehalfOf_ == address(0)) revert ERC6909InvalidReceiver(onBehalfOf_);

        if (shouldWrap_) {
            _getWrappedToken(tokenId_).mintFor(onBehalfOf_, amount_);
        } else {
            _mint(onBehalfOf_, tokenId_, amount_);
        }
    }

    /// @notice Burns the ERC6909 or ERC20 wrapped token from the recipient
    ///
    /// @param onBehalfOf_   The address to burn the token from
    /// @param tokenId_      The ID of the ERC6909 token
    /// @param amount_       The amount of tokens to burn
    /// @param wrapped_      Whether the token is wrapped
    function _burn(
        address onBehalfOf_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) internal onlyValidTokenId(tokenId_) {
        if (amount_ == 0) revert ERC6909Wrappable_ZeroAmount();
        if (onBehalfOf_ == address(0)) revert ERC6909InvalidSender(onBehalfOf_);

        if (wrapped_) {
            // Will revert if the caller has not approved spending
            _getWrappedToken(tokenId_).burnFrom(onBehalfOf_, amount_);
        } else {
            // Spend allowance (since it is not implemented in _burn())
            _spendAllowance(onBehalfOf_, address(this), tokenId_, amount_);

            // Burn the ERC6909 token
            _burn(onBehalfOf_, tokenId_, amount_);
        }
    }

    // ========== TOTAL SUPPLY EXTENSION ========== //

    /// @inheritdoc IERC6909TokenSupply
    function totalSupply(uint256 tokenId_) public view virtual override returns (uint256) {
        return _totalSupplies[tokenId_];
    }

    /// @dev Copied from draft-ERC6909TokenSupply.sol
    function _update(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal virtual override {
        // Calls ERC6909Metadata._update()
        super._update(from, to, id, amount);

        if (from == address(0)) {
            _totalSupplies[id] += amount;
        }
        if (to == address(0)) {
            unchecked {
                // amount <= _balances[from][id] <= _totalSupplies[id]
                _totalSupplies[id] -= amount;
            }
        }
    }

    // ========== WRAP/UNWRAP FUNCTIONS ========== //

    /// @dev Returns the address of the wrapped ERC20 token for a given token ID, or creates a new one if it does not exist
    function _getWrappedToken(
        uint256 tokenId_
    ) internal returns (IERC20BurnableMintable wrappedToken) {
        // Validate that the token id exists
        if (decimals(tokenId_) == 0) revert ERC6909Wrappable_InvalidTokenId(tokenId_);

        // If the wrapped token exists, return it
        if (_wrappedTokens[tokenId_] != address(0))
            return IERC20BurnableMintable(_wrappedTokens[tokenId_]);

        // Otherwise, create a new wrapped token
        bytes memory tokenData = _getTokenData(tokenId_);
        wrappedToken = IERC20BurnableMintable(_ERC20_IMPLEMENTATION.clone(tokenData));
        _wrappedTokens[tokenId_] = address(wrappedToken);
        return wrappedToken;
    }

    /// @inheritdoc IERC6909Wrappable
    function getWrappedToken(uint256 tokenId_) public view returns (address wrappedToken) {
        return _wrappedTokens[tokenId_];
    }

    /// @inheritdoc IERC6909Wrappable
    function wrap(uint256 tokenId_, uint256 amount_) public returns (address wrappedToken) {
        // Burn the ERC6909 token
        _burn(msg.sender, tokenId_, amount_, false);

        // Mint the wrapped ERC20 token to the recipient
        IERC20BurnableMintable wrappedToken_ = _getWrappedToken(tokenId_);
        wrappedToken_.mintFor(msg.sender, amount_);
        return address(wrappedToken_);
    }

    /// @inheritdoc IERC6909Wrappable
    function unwrap(uint256 tokenId_, uint256 amount_) public {
        // Burn the wrapped ERC20 token
        _burn(msg.sender, tokenId_, amount_, true);

        // Mint the ERC6909 token
        _mint(msg.sender, tokenId_, amount_);
    }

    // ========== TOKEN FUNCTIONS ========== //

    /// @inheritdoc IERC6909Wrappable
    function isValidTokenId(uint256 tokenId_) public view returns (bool) {
        return decimals(tokenId_) > 0;
    }

    modifier onlyValidTokenId(uint256 tokenId_) {
        if (!isValidTokenId(tokenId_)) revert ERC6909Wrappable_InvalidTokenId(tokenId_);
        _;
    }

    /// @notice Creates a new wrappable token
    /// @dev    Reverts if the token ID already exists
    function _createWrappableToken(
        uint256 tokenId_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        bytes memory additionalMetadata_,
        bool createWrappedToken_
    ) internal {
        // If the token ID already exists, revert
        if (_wrappableTokenIds.contains(tokenId_))
            revert ERC6909Wrappable_TokenIdAlreadyExists(tokenId_);

        _setName(tokenId_, name_);
        _setSymbol(tokenId_, symbol_);
        _setDecimals(tokenId_, decimals_);
        _tokenMetadataAdditional[tokenId_] = additionalMetadata_;

        if (createWrappedToken_) {
            _getWrappedToken(tokenId_);
        }

        // Record the token ID
        _wrappableTokenIds.add(tokenId_);
    }

    /// @inheritdoc IERC6909Wrappable
    function getWrappableTokens()
        public
        view
        override
        returns (uint256[] memory tokenIds, address[] memory wrappedTokens)
    {
        tokenIds = _wrappableTokenIds.values();
        wrappedTokens = new address[](tokenIds.length);
        for (uint256 i; i < tokenIds.length; ++i) {
            wrappedTokens[i] = _wrappedTokens[tokenIds[i]];
        }

        return (tokenIds, wrappedTokens);
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override(ERC6909, IERC165) returns (bool) {
        return
            interfaceId_ == type(IERC6909Wrappable).interfaceId ||
            interfaceId_ == type(IERC6909Metadata).interfaceId ||
            interfaceId_ == type(IERC6909TokenSupply).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
