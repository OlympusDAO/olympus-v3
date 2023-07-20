// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {IUniswapV3Pool} from "interfaces/UniswapV3/IUniswapV3Pool.sol";
import {OracleLibrary} from "libraries/UniswapV3/OracleLibrary.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "libraries/FullMath.sol";
import {TickMath} from "libraries/UniswapV3/TickMath.sol";

/// @title      UniswapV3Price
/// @notice     Provides prices derived from the TWAP of a Uniswap V3 pool
contract UniswapV3Price is PriceSubmodule {
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice     The maximum number of decimals allowed for a token in order to prevent overflows
    uint8 internal constant BASE_10_MAX_EXPONENT = 30;

    /// @notice     The minimum length of the TWAP observation window in seconds
    ///             From testing, a value under 19 seconds is rejected by `OracleLibrary.getQuoteAtTick()`
    uint32 internal constant TWAP_MINIMUM_OBSERVATION_SECONDS = 19;

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

    /// @notice                                 The observation window specified in the parameters is too short
    /// @param paramsIndex_                     The index of the parameter
    /// @param observationWindowSeconds_        The observation window in seconds
    /// @param minimumObservationWindowSeconds_ The minimum observation window in seconds
    error UniswapV3_ParamsObservationWindowTooShort(
        uint8 paramsIndex_,
        uint32 observationWindowSeconds_,
        uint32 minimumObservationWindowSeconds_
    );

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

    /// @notice                             The pool is invalid or the observation window is too long.
    /// @dev                                This is triggered if the pool reverted when called,
    ///                                     and indicates that the feed address is not a UniswapV3 pool
    ///                                     or that the observation window is too long.
    ///
    /// @param pool_                        The address of the pool
    /// @param observationWindowSeconds_    The observation window in seconds
    error UniswapV3_InvalidObservation(address pool_, uint32 observationWindowSeconds_);

    /// @notice                 The calculated tick is out of bounds
    /// @dev                    The tick is calculated as the average of the ticks over the observation window.
    ///
    /// @param pool_            The address of the pool
    /// @param calculatedTick_  The calculated tick
    /// @param minTick_         The minimum tick
    /// @param maxTick_         The maximum tick
    error UniswapV3_TickOutOfBounds(
        address pool_,
        int56 calculatedTick_,
        int24 minTick_,
        int24 maxTick_
    );

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.UNIV3");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== TOKEN PRICE FUNCTIONS ========== //

    /// @notice                 Obtains the price of `lookupToken_` in USD, using the TWAP from the specified Uniswap V3 oracle.
    /// @dev                    This function will revert if:
    ///                         - The value of `params.observationWindowSeconds` is less than `TWAP_MINIMUM_OBSERVATION_SECONDS`
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
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          Pool parameters of type `UniswapV3Params`
    /// @return                 Price in the scale of `outputDecimals_`
    function getTokenTWAP(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        UniswapV3Params memory params = abi.decode(params_, (UniswapV3Params));
        if (address(params.pool) == address(0))
            revert UniswapV3_ParamsPoolInvalid(0, address(params.pool));

        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);
        try pool.slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
            // Do nothing
        } catch (bytes memory) {
            // Handle a non-UniswapV3 pool
            revert UniswapV3_PoolTypeInvalid(address(pool));
        }

        // Revert if the observation window is less than the minimum (which would not give manipulation-resistant results)
        if (params.observationWindowSeconds < TWAP_MINIMUM_OBSERVATION_SECONDS)
            revert UniswapV3_ParamsObservationWindowTooShort(
                1,
                params.observationWindowSeconds,
                TWAP_MINIMUM_OBSERVATION_SECONDS
            );

        // Revert if either of the tokens in the pool are not set (probably too paranoid)
        if (pool.token0() == address(0))
            revert UniswapV3_PoolTokensInvalid(address(pool), 0, pool.token0());
        if (pool.token1() == address(0))
            revert UniswapV3_PoolTokensInvalid(address(pool), 1, pool.token1());

        // Revert if token_ is not in the specified pool
        if (pool.token0() != lookupToken_ && pool.token1() != lookupToken_)
            revert UniswapV3_LookupTokenNotFound(address(pool), lookupToken_);

        // Determine the tick over the observation window
        int56 timeWeightedTick;
        {
            uint32[] memory observationWindow = new uint32[](2);
            observationWindow[0] = params.observationWindowSeconds;
            observationWindow[1] = 0;

            try pool.observe(observationWindow) returns (
                int56[] memory tickCumulatives,
                uint160[] memory secondsPerLiquidityCumulativeX128s
            ) {
                timeWeightedTick =
                    (tickCumulatives[1] - tickCumulatives[0]) /
                    int56(int32(params.observationWindowSeconds));
            } catch (bytes memory) {
                // This function will revert if the observation window is longer than the oldest observation in the pool
                // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/Oracle.sol#L226C30-L226C30
                revert UniswapV3_InvalidObservation(address(pool), params.observationWindowSeconds);
            }
        }

        uint256 tokenPrice;
        {
            uint8 quoteTokenDecimals;
            address quoteToken;
            uint256 baseInQuotePrice;
            {
                // Convert the tick to a price in terms of the other token
                quoteToken = pool.token0() == lookupToken_ ? pool.token1() : pool.token0();
                quoteTokenDecimals = ERC20(quoteToken).decimals();
                uint8 baseTokenDecimals = ERC20(lookupToken_).decimals();

                // Avoid overflows with decimal normalisation
                if (quoteTokenDecimals > BASE_10_MAX_EXPONENT)
                    revert UniswapV3_AssetDecimalsOutOfBounds(
                        quoteToken,
                        quoteTokenDecimals,
                        BASE_10_MAX_EXPONENT
                    );

                // baseTokenDecimals must be less than 38 to avoid overflow when cast to uint128
                // BASE_10_MAX_EXPONENT is less than 38, so this check is safe
                if (baseTokenDecimals > BASE_10_MAX_EXPONENT)
                    revert UniswapV3_AssetDecimalsOutOfBounds(
                        lookupToken_,
                        baseTokenDecimals,
                        BASE_10_MAX_EXPONENT
                    );

                // Ensure the time-weighted tick is within the bounds of permissible ticks
                // Otherwise getQuoteAtTick will revert: https://docs.uniswap.org/contracts/v3/reference/error-codes
                if (timeWeightedTick > MAX_TICK || timeWeightedTick < MIN_TICK)
                    revert UniswapV3_TickOutOfBounds(
                        address(pool),
                        timeWeightedTick,
                        MIN_TICK,
                        MAX_TICK
                    );

                // Decimals: quoteTokenDecimals
                baseInQuotePrice = OracleLibrary.getQuoteAtTick(
                    int24(timeWeightedTick),
                    uint128(10 ** baseTokenDecimals),
                    lookupToken_,
                    quoteToken
                );
            }

            // Get the price of {quoteToken} in USD
            // Decimals: outputDecimals_
            if (outputDecimals_ > BASE_10_MAX_EXPONENT)
                revert UniswapV3_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

            // PRICE will revert if the price cannot be determined or is 0.
            (uint256 quoteInUsdPrice, ) = _PRICE().getPrice(quoteToken, PRICEv2.Variant.CURRENT);

            // Decimals: outputDecimals_
            tokenPrice = baseInQuotePrice.mulDiv(quoteInUsdPrice, 10 ** quoteTokenDecimals);
        }

        return tokenPrice;
    }

    /**
     * Due to the way that Uniswap V3 is structured, there is no
     * standard unit price that can be calculated for a pool token.
     *
     * However, given the token id of a Uniswap V3 position (stored as an NFT),
     * the underlying token balances can be retrieved and the value
     * of that position calculated.
     */
}
