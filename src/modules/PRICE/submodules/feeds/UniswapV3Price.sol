// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {IUniswapV3Pool} from "interfaces/UniswapV3/IUniswapV3Pool.sol";
import {OracleLibrary} from "libraries/UniswapV3/OracleLibrary.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "libraries/FullMath.sol";
import {TickMath} from "libraries/UniswapV3/TickMath.sol";

contract UniswapV3Price is PriceSubmodule {
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    // Sane amount to prevent overflows
    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    // Mandate the minimum length of the TWAP
    // From testing, a value under 19 seconds is rejected by OracleLibrary.getQuoteAtTick
    uint32 internal constant TWAP_MINIMUM_OBSERVATION_SECONDS = 19;

    struct UniswapV3Params {
        IUniswapV3Pool pool;
        uint32 observationWindowSeconds;
    }

    // Uniswap V3 ticks
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // ========== ERRORS ========== //

    error UniswapV3_AssetDecimalsOutOfBounds(address asset_);
    error UniswapV3_LookupTokenNotFound(address asset_);
    error UniswapV3_OutputDecimalsOutOfBounds(uint8 outputDecimals_);
    error UniswapV3_PoolTokensInvalid(address pool_);
    error UniswapV3_PoolTypeInvalid(address pool_);
    error UniswapV3_TickOutOfBounds(address pool_);
    error UniswapV3_TWAPObservationWindowTooShort(address pool_);

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.UNIV3");
    }

    // ========== TOKEN PRICE FUNCTIONS ========== //

    /// @notice Obtains the price of {lookupToken_} in USD, using the TWAP from the specified Uniswap V3 oracle.
    /// @dev This function will revert if:
    /// - The value of params.observationWindowSeconds is less than TWAP_MINIMUM_OBSERVATION_SECONDS
    /// - Any token decimals or outputDecimals_ are high enough to cause an overflow
    /// - Any tokens in the pool are not set
    /// - token_ is not in the pool
    /// - The calculated time-weighted tick is outside the bounds of int24
    ///
    /// @param lookupToken_ The token to determine the price of.
    /// @param outputDecimals_ The number of decimals to return the price in
    /// @param params_ Pool parameters of type UniswapV3Params
    /// @return uint256 Price in the scale of outputDecimals_
    function getTokenTWAP(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        UniswapV3Params memory params = abi.decode(params_, (UniswapV3Params));
        {
            if (address(params.pool) == address(0)) revert UniswapV3_PoolTypeInvalid(address(params.pool));
        }
        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);
        {
            try pool.token0() returns (address token) {
                // Do nothing
            } catch (bytes memory) {
                // Handle a non-UniswapV3 pool
                revert UniswapV3_PoolTypeInvalid(address(pool));
            }
        }

        // Revert if the observation window is less than the minimum (which would not give manipulation-resistant results)
        if (params.observationWindowSeconds < TWAP_MINIMUM_OBSERVATION_SECONDS)
            revert UniswapV3_TWAPObservationWindowTooShort(address(pool));

        // Revert if either of the tokens in the pool are not set (probably too paranoid)
        if (pool.token0() == address(0) || pool.token1() == address(0))
            revert UniswapV3_PoolTokensInvalid(address(pool));

        // Revert if token_ is not in the specified pool
        if (pool.token0() != lookupToken_ && pool.token1() != lookupToken_)
            revert UniswapV3_LookupTokenNotFound(lookupToken_);

        // Determine the tick over the observation window
        int56 timeWeightedTick;
        {
            uint32[] memory observationWindow = new uint32[](2);
            observationWindow[0] = params.observationWindowSeconds;
            observationWindow[1] = 0;

            try pool.observe(observationWindow) returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
                timeWeightedTick =
                    (tickCumulatives[1] - tickCumulatives[0]) /
                    int56(int32(params.observationWindowSeconds));
            } catch (bytes memory) {
                // Handle a non-UniswapV3 pool
                // A UniswapV2 pool could pass the above check, but would revert here
                revert UniswapV3_PoolTypeInvalid(address(pool));
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
                    revert UniswapV3_AssetDecimalsOutOfBounds(quoteToken);

                if (baseTokenDecimals > BASE_10_MAX_EXPONENT)
                    revert UniswapV3_AssetDecimalsOutOfBounds(lookupToken_);

                // Ensure the time-weighted tick is within the bounds of permissible ticks
                // Otherwise getQuoteAtTick will revert: https://docs.uniswap.org/contracts/v3/reference/error-codes
                if (timeWeightedTick > MAX_TICK || timeWeightedTick < MIN_TICK)
                    revert UniswapV3_TickOutOfBounds(address(pool));

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
                revert UniswapV3_OutputDecimalsOutOfBounds(outputDecimals_);

            // PRICE will revert if the price cannot be determined or is 0.
            (uint256 quoteInUsdPrice, ) = _PRICE().getPrice(
                quoteToken,
                PRICEv2.Variant.CURRENT
            );

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
