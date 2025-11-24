// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

// Libraries
import {UniswapV3OracleHelper as OracleHelper} from "libraries/UniswapV3/Oracle.sol";
import {FullMath} from "libraries/FullMath.sol";

// Uniswap V3
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

// Bophades
import "modules/PRICE/PRICE.v2.sol";

/// @title      UniswapV3Price
/// @author     0xJem
/// @notice     Provides prices derived from the TWAP of a Uniswap V3 pool
contract UniswapV3Price is PriceSubmodule {
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice     The maximum number of decimals allowed for a token in order to prevent overflows
    uint8 internal constant BASE_10_MAX_EXPONENT = 30;

    /// @notice                         The parameters for a Uniswap V3 pool
    /// @param pool                     The address of the pool
    /// @param observationWindowSeconds The length of the TWAP observation window in seconds
    struct UniswapV3Params {
        IUniswapV3Pool pool;
        uint32 observationWindowSeconds;
    }

    /// @notice     The minimum tick that can be used in a pool, as defined by UniswapV3 libraries
    int24 internal constant MIN_TICK = -887272;
    /// @notice     The maximum tick that can be used in a pool, as defined by UniswapV3 libraries
    int24 internal constant MAX_TICK = -MIN_TICK;

    // ========== ERRORS ========== //

    /// @notice                 The decimals of the asset are out of bounds
    /// @param asset_           The address of the asset
    /// @param assetDecimals_   The number of decimals of the asset
    /// @param maxDecimals_     The maximum number of decimals allowed
    error UniswapV3_AssetDecimalsOutOfBounds(
        address asset_,
        uint8 assetDecimals_,
        uint8 maxDecimals_
    );

    /// @notice                 The lookup token was not found in the pool
    /// @param pool_            The address of the pool
    /// @param asset_           The address of the asset
    error UniswapV3_LookupTokenNotFound(address pool_, address asset_);

    /// @notice                 The output decimals are out of bounds
    /// @param outputDecimals_  The number of decimals of the output
    /// @param maxDecimals_     The maximum number of decimals allowed
    error UniswapV3_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);

    /// @notice                 The pool specified in the parameters is invalid
    /// @param paramsIndex_     The index of the parameter
    /// @param pool_            The address of the pool
    error UniswapV3_ParamsPoolInvalid(uint8 paramsIndex_, address pool_);

    /// @notice                 The pool tokens are invalid
    /// @param pool_            The address of the pool
    /// @param tokenIndex_      The index of the token
    /// @param token_           The address of the token
    error UniswapV3_PoolTokensInvalid(address pool_, uint8 tokenIndex_, address token_);

    /// @notice                 The pool is invalid
    /// @dev                    This is triggered if the pool reverted when called,
    ///                         and indicates that the feed address is not a UniswapV3 pool.
    ///
    /// @param pool_            The address of the pool
    error UniswapV3_PoolTypeInvalid(address pool_);

    /// @notice         Triggered if `pool_` is locked, which indicates re-entrancy
    ///
    /// @param pool_    The address of the affected Uniswap V3 pool
    error UniswapV3_PoolReentrancy(address pool_);

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    /// @inheritdoc      Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.UNIV3");
    }

    /// @inheritdoc      Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== TOKEN PRICE FUNCTIONS ========== //

    /// @notice                 Obtains the price of `lookupToken_` in USD, using the TWAP from the specified Uniswap V3 oracle.
    /// @dev                    This function will revert if:
    ///                         - The value of `params.observationWindowSeconds` is less than `UniswapV3OracleHelper.TWAP_MIN_OBSERVATION_WINDOW`
    ///                         - Any token decimals or `outputDecimals_` are high enough to cause an overflow
    ///                         - Any tokens in the pool are not set
    ///                         - `lookupToken_` is not in the pool
    ///                         - The calculated time-weighted tick is outside the bounds of int24
    ///
    ///                         NOTE: as a UniswapV3 pool can be manipulated using multi-block MEV, the TWAP values
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///                         See https://chainsecurity.com/oracle-manipulation-after-merge/
    ///
    /// @param lookupToken_     The token to determine the price of.
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Pool parameters of type `UniswapV3Params`
    /// @return                 Price in the scale of `outputDecimals_`
    function getTokenTWAP(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        UniswapV3Params memory params = abi.decode(params_, (UniswapV3Params));
        (
            address quoteToken,
            uint8 quoteTokenDecimals,
            uint8 lookupTokenDecimals
        ) = _checkPoolAndTokenParams(lookupToken_, outputDecimals_, params.pool);

        uint256 baseInQuotePrice = OracleHelper.getTWAPRatio(
            address(params.pool),
            params.observationWindowSeconds,
            lookupToken_,
            quoteToken,
            lookupTokenDecimals
        );

        // Get the price of {quoteToken} in USD
        // Decimals: outputDecimals_
        // PRICE will revert if the price cannot be determined or is 0.
        (uint256 quoteInUsdPrice, ) = _PRICE().getPrice(quoteToken, PRICEv2.Variant.CURRENT);

        // Calculate final price in USD
        // Decimals: outputDecimals_
        return baseInQuotePrice.mulDiv(quoteInUsdPrice, 10 ** quoteTokenDecimals);
    }

    /// @notice                 Obtains the price of `lookupToken_` in USD, using the current Slot0 price from the specified Uniswap V3 oracle.
    /// @dev                    This function will revert if:
    ///                         - The value of `params.observationWindowSeconds` is less than `UniswapV3OracleHelper.TWAP_MIN_OBSERVATION_WINDOW`
    ///                         - Any token decimals or `outputDecimals_` are high enough to cause an overflow
    ///                         - Any tokens in the pool are not set
    ///                         - `lookupToken_` is not in the pool
    ///                         - The calculated time-weighted tick is outside the bounds of int24
    ///
    ///                         NOTE: as a UniswapV3 pool can be manipulated using multi-block MEV, the TWAP values
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///                         See https://chainsecurity.com/oracle-manipulation-after-merge/
    ///
    /// @param lookupToken_     The token to determine the price of.
    /// @param outputDecimals_  The number of output decimals (assumed to be the same as PRICE decimals)
    /// @param params_          Pool parameters of type `UniswapV3Params`
    /// @return                 Price in the scale of `outputDecimals_`
    function getTokenPrice(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        UniswapV3Params memory params = abi.decode(params_, (UniswapV3Params));
        (
            address quoteToken,
            uint8 quoteTokenDecimals,
            uint8 lookupTokenDecimals
        ) = _checkPoolAndTokenParams(lookupToken_, outputDecimals_, params.pool);

        // Get the current price of the lookup token in terms of the quote token
        (, int24 currentTick, , , , , bool unlocked) = params.pool.slot0();

        // Check for re-entrancy
        if (unlocked == false) revert UniswapV3_PoolReentrancy(address(params.pool));

        uint256 baseInQuotePrice = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(10 ** lookupTokenDecimals),
            lookupToken_,
            quoteToken
        );

        // Get the price of {quoteToken} in USD
        // Decimals: outputDecimals_
        // PRICE will revert if the price cannot be determined or is 0.
        (uint256 quoteInUsdPrice, ) = _PRICE().getPrice(quoteToken, PRICEv2.Variant.CURRENT);

        // Calculate final price in USD
        // Decimals: outputDecimals_
        return baseInQuotePrice.mulDiv(quoteInUsdPrice, 10 ** quoteTokenDecimals);
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice  Performs checks to ensure that the pool, the tokens, and the decimals are valid.
    /// @dev                    This function will revert if:
    ///                         - Any token decimals or `outputDecimals_` are high enough to cause an overflow
    ///                         - Any tokens in the pool are not set
    ///                         - `lookupToken_` is not in the pool
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The decimals of `baseToken`
    /// @param pool_            The Uniswap V3 pool to use
    /// @return                 The `quoteToken`, its decimals, and the decimals of `lookupToken_`
    function _checkPoolAndTokenParams(
        address lookupToken_,
        uint8 outputDecimals_,
        IUniswapV3Pool pool_
    ) internal view returns (address, uint8, uint8) {
        if (address(pool_) == address(0)) revert UniswapV3_ParamsPoolInvalid(0, address(pool_));

        try pool_.slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
            // Do nothing
        } catch (bytes memory) {
            // Handle a non-UniswapV3 pool
            revert UniswapV3_PoolTypeInvalid(address(pool_));
        }

        address quoteToken;
        {
            bool lookupTokenFound;
            try pool_.token0() returns (address token) {
                // Check if token is zero address, revert if so
                if (token == address(0))
                    revert UniswapV3_PoolTokensInvalid(address(pool_), 0, token);

                // If token is the lookup token, set lookupTokenFound to true
                // Otherwise, it should be the quote token
                // If lookup token isn't found, quote token will be set twice,
                // but this is fine since the function will revert anyway
                if (token == lookupToken_) {
                    lookupTokenFound = true;
                } else {
                    quoteToken = token;
                }
            } catch (bytes memory) {
                // Handle a non-UniswapV3 pool
                revert UniswapV3_PoolTypeInvalid(address(pool_));
            }
            try pool_.token1() returns (address token) {
                // Check if token is zero address, revert if so
                if (token == address(0))
                    revert UniswapV3_PoolTokensInvalid(address(pool_), 1, token);

                // If token is the lookup token, set lookupTokenFound to true
                // Otherwise, it should be the quote token
                // If lookup token isn't found, quote token will be set twice,
                // but this is fine since the function will revert anyway
                if (token == lookupToken_) {
                    lookupTokenFound = true;
                } else {
                    quoteToken = token;
                }
            } catch (bytes memory) {
                // Handle a non-UniswapV3 pool
                revert UniswapV3_PoolTypeInvalid(address(pool_));
            }

            // If lookup token wasn't found, revert
            if (!lookupTokenFound)
                revert UniswapV3_LookupTokenNotFound(address(pool_), lookupToken_);
        }

        // Validate output decimals are not too high
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert UniswapV3_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

        uint8 quoteTokenDecimals = ERC20(quoteToken).decimals();
        uint8 lookupTokenDecimals = ERC20(lookupToken_).decimals();

        // Avoid overflows with decimal normalisation
        if (quoteTokenDecimals > BASE_10_MAX_EXPONENT)
            revert UniswapV3_AssetDecimalsOutOfBounds(
                quoteToken,
                quoteTokenDecimals,
                BASE_10_MAX_EXPONENT
            );

        // lookupTokenDecimals must be less than 38 to avoid overflow when cast to uint128
        // BASE_10_MAX_EXPONENT is less than 38, so this check is safe
        if (lookupTokenDecimals > BASE_10_MAX_EXPONENT)
            revert UniswapV3_AssetDecimalsOutOfBounds(
                lookupToken_,
                lookupTokenDecimals,
                BASE_10_MAX_EXPONENT
            );

        return (quoteToken, quoteTokenDecimals, lookupTokenDecimals);
    }
}
