// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

// Based on Bond Protocol's `FixedStrikeOptionToken` and `OptionToken`:
// `https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/fixed-strike/FixedStrikeOptionToken.sol`
// `https://github.com/Bond-Protocol/option-contracts/blob/b8ce2ca2bae3bd06f0e7665c3aa8d827e4d8ca2c/src/bases/OptionToken.sol`

import {CloneERC20} from "src/policies/rewards/convertible/lib/clones/CloneERC20.sol";

/// @title Convertible OHM Token
/// @notice The ERC20-compatible token representing a call option on OHM with a fixed strike price.
/// @dev This contract uses Clones (https://github.com/wighawag/clones-with-immutable-args)
///      for gas-efficient deployment.
///      Tokens can only be minted/burned by the Convertible OHM Teller that created them.
///
///      Tokens can be exercised 1:1 for OHM by paying (amount * strike price) in the quote token.
///      Exercise is permitted any time between the eligible timestamp and the expiry timestamp.
///
///      Each token instance has immutable parameters.
///      Memory layout of immutable args (total: 169 bytes / 0xA9):
///      [0x00:0x20]  name (bytes32)
///      [0x20:0x40]  symbol (bytes32)
///      [0x40:0x41]  decimals (uint8)
///      [0x41:0x55]  quoteToken (address)
///      [0x55:0x5b]  eligible (uint48)
///      [0x5b:0x61]  expiry (uint48)
///      [0x61:0x75]  teller (address)
///      [0x75:0x89]  creator (address)
///      [0x89:0xA9]  strikePrice (uint256)
contract ConvertibleOHMToken is CloneERC20 {
    // ========== ERRORS ========== //

    error ConvertibleOHMToken_OnlyTeller();

    // ========== IMMUTABLE PARAMETERS ========== //

    // [0x00:0x20]  name (bytes32)
    // [0x20:0x40]  symbol (bytes32)
    // [0x40:0x41]  decimals (uint8)
    uint8 private constant _QUOTE_TOKEN_OFFSET = 0x41;
    uint8 private constant _ELIGIBLE_TIMESTAMP_OFFSET = 0x55;
    uint8 private constant _EXPIRATION_TIMESTAMP_OFFSET = 0x5b;
    uint8 private constant _TELLER_OFFSET = 0x61;
    uint8 private constant _CREATOR_OFFSET = 0x75;
    uint8 private constant _STRIKE_PRICE_OFFSET = 0x89;

    // ========== VIEW FUNCTIONS FOR IMMUTABLE PARAMETERS ========== //

    /// @notice Returns the token parameters: quote token, creator, eligible timestamp, expiration timestamp, strike price.
    function parameters() external pure returns (address, address, uint48, uint48, uint256) {
        return (quote(), creator(), eligible(), expiry(), strike());
    }

    /// @notice Returns the address of the quote token that this convertible token is quoted in.
    function quote() public pure returns (address) {
        return _getArgAddress(_QUOTE_TOKEN_OFFSET);
    }

    /// @notice Returns the timestamp when this convertible token can first be exercised.
    function eligible() public pure returns (uint48) {
        return _getArgUint48(_ELIGIBLE_TIMESTAMP_OFFSET);
    }

    /// @notice Returns the timestamp after which this convertible token can no longer be exercised.
    function expiry() public pure returns (uint48) {
        return _getArgUint48(_EXPIRATION_TIMESTAMP_OFFSET);
    }

    /// @notice Returns the address of the Convertible OHM Teller that created this convertible token.
    function teller() public pure returns (address) {
        return _getArgAddress(_TELLER_OFFSET);
    }

    /// @notice Returns the address of the contract that deployed this convertible token.
    function creator() public pure returns (address) {
        return _getArgAddress(_CREATOR_OFFSET);
    }

    /// @notice Returns the strike price specified in the amount of quote tokens per OHM.
    function strike() public pure returns (uint256) {
        return _getArgUint256(_STRIKE_PRICE_OFFSET);
    }

    // ========== MINT & BURN ========== //

    modifier onlyTeller() {
        if (msg.sender != teller()) revert ConvertibleOHMToken_OnlyTeller();
        _;
    }

    /// @notice Mints convertible tokens.
    /// @dev Only callable by the teller that created this token.
    ///      Implements IERC20BurnableMintable.mintFor interface.
    /// @param to_ The address to mint to.
    /// @param amount_ The amount to mint.
    function mintFor(address to_, uint256 amount_) external onlyTeller {
        _mint(to_, amount_);
    }

    /// @notice Burns convertible tokens.
    /// @dev Only callable by the teller that created this token.
    ///      Implements IERC20BurnableMintable.burnFrom interface.
    /// @param from_ The address to burn from.
    /// @param amount_ The amount to burn.
    function burnFrom(address from_, uint256 amount_) external onlyTeller {
        _burn(from_, amount_);
    }
}
