// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

interface IUniswapV2Pool {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);
}

contract UniswapV2PoolTokenPrice is PriceSubmodule {
    using FullMath for uint256;

    // UniswapV2 uses uint112 to store token balances. Token decimals over this number will result in truncated balances.
    uint8 internal constant MAX_DECIMALS = 26;

    struct UniswapV2PoolParams {
        IUniswapV2Pool pool;
    }

    // ========== ERRORS ========== //

    error UniswapV2_AssetDecimalsOutOfBounds(address asset_);
    error UniswapV2_LookupTokenNotFound(address asset_);
    error UniswapV2_OutputDecimalsOutOfBounds(uint8 outputDecimals_);
    error UniswapV2_PoolBalancesInvalid(address pool_);
    error UniswapV2_PoolSupplyInvalid(address pool_);
    error UniswapV2_PoolTokensInvalid(address pool_);
    error UniswapV2_PoolTypeInvalid(address pool_);
    error UniswapV2_PriceNotFound(address asset_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.UNIV2");
    }

    // ========== HELPER FUNCTIONS ========== //

    function _getTokens(IUniswapV2Pool pool) internal view returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = pool.token0();
        tokens[1] = pool.token1();

        return tokens;
    }

    /// @notice Returns the reserves of a UniswapV2 pool
    /// @dev This function reverts if the pool does not have the getReserves() function.
    ///
    /// @param pool_ UniswapV2 pool
    /// @return uint112[] Reserves of the pool in their native decimals
    function _getReserves(IUniswapV2Pool pool_) internal view returns (uint112[] memory) {
        try pool_.getReserves() returns (
            uint112 token0Reserves,
            uint112 token1Reserves,
            uint32 blockTimestampLast
        ) {
            uint112[] memory balances = new uint112[](2);
            balances[0] = token0Reserves;
            balances[1] = token1Reserves;

            return balances;
        } catch (bytes memory) {
            revert UniswapV2_PoolTypeInvalid(address(pool_));
        }
    }

    /// @notice Converts the given value from the ERC20 token's decimals to the destination decimals
    ///
    /// @dev This function will revert if converting the token's decimals would result in an overflow.
    ///
    /// @param value_ value in native ERC20 token decimals
    /// @param token_ the address of the ERC20 token
    /// @param destinationDecimals_ the resulting number of decimals
    /// @return uint256 Value in the scale of destinationDecimals
    function _convertERC20Decimals(
        uint112 value_,
        address token_,
        uint8 destinationDecimals_
    ) internal view returns (uint256) {
        uint8 tokenDecimals = ERC20(token_).decimals();
        if (tokenDecimals > MAX_DECIMALS) revert UniswapV2_AssetDecimalsOutOfBounds(token_);

        return (uint256(value_)).mulDiv(10 ** destinationDecimals_, 10 ** tokenDecimals);
    }

    // ========== POOL TOKEN PRICE FUNCTIONS ========== //

    /// @notice Determines the unit price of the pool token for the UniswapV2 pool specified in {params_}.
    ///
    /// @dev The pool token price is determined using the "fair LP pricing" described here: https://cmichel.io/pricing-lp-tokens/
    /// This approach is implemented in order to reduce the succeptibility to manipulation of the pool token price
    /// through the pool's reserves.
    ///
    /// @param asset_ The asset to get the price of (unused)
    /// @param outputDecimals_ The number of decimals to return the price in
    /// @param params_ UniswapV2 pool parameters of type UniswapV2PoolParams
    /// @return uint256 Price in the scale of outputDecimals_
    function getPoolTokenPrice(address asset_, uint8 outputDecimals_, bytes calldata params_) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > MAX_DECIMALS)
            revert UniswapV2_OutputDecimalsOutOfBounds(outputDecimals_);

        address token0;
        address token1;
        uint256 k; // outputDecimals_
        uint256 poolSupply; // outputDecimals_
        {
            IUniswapV2Pool pool;
            {
                // Decode params
                UniswapV2PoolParams memory params = abi.decode(params_, (UniswapV2PoolParams));
                if (address(params.pool) == address(0)) revert UniswapV2_PoolTypeInvalid(address(params.pool));

                pool = IUniswapV2Pool(params.pool);
            }

            // Get balances
            // Call this first as it will check on whether the pool is valid, and exit
            uint112[] memory balances = _getReserves(pool);
            if (balances.length == 0) revert UniswapV2_PoolBalancesInvalid(address(pool));

            // Get tokens
            token0 = pool.token0();
            token1 = pool.token1();
            if (token0 == address(0) || token1 == address(0))
                revert UniswapV2_PoolTokensInvalid(address(pool));

            // Convert balances to outputDecimals_
            uint256 balance0;
            {
                uint8 token0Decimals = ERC20(token0).decimals();
                if (token0Decimals > MAX_DECIMALS) revert UniswapV2_AssetDecimalsOutOfBounds(token0);

                balance0 = uint256(balances[0]).mulDiv(
                    10 ** outputDecimals_,
                    10 ** token0Decimals
                );
            }

            uint256 balance1;
            {
                uint8 token1Decimals = ERC20(token1).decimals();
                if (token1Decimals > MAX_DECIMALS) revert UniswapV2_AssetDecimalsOutOfBounds(token1);

                balance1 = uint256(balances[1]).mulDiv(
                    10 ** outputDecimals_,
                    10 ** token1Decimals
                );
            }

            if (balance0 == 0 || balance1 == 0) revert UniswapV2_PoolBalancesInvalid(address(pool));

            // Determine balance0 * balance1 = k
            k = balance0.mulDiv(balance1, 10 ** outputDecimals_);

            uint256 poolSupply_ = pool.totalSupply();
            if (poolSupply_ == 0) revert UniswapV2_PoolSupplyInvalid(address(pool));

            // Shift the pool supply into outputDecimals_
            uint8 poolDecimals = pool.decimals(); // Always 18
            poolSupply = poolSupply_.mulDiv(10 ** outputDecimals_, 10 ** poolDecimals);
        }

        uint256 price0; // outputDecimals_
        uint256 price1; // outputDecimals_
        {
            PRICEv2 PRICE = _PRICE();

            // PRICE will revert if the price cannot be determined or is 0.
            // If ANY price cannot be determined, then the LP token value cannot be determined. So we don't catch the error.
            (uint256 price0_, ) = PRICE.getPrice(token0, PRICEv2.Variant.CURRENT);
            (uint256 price1_, ) = PRICE.getPrice(token1, PRICEv2.Variant.CURRENT);

            price0 = price0_;
            price1 = price1_;
        }

        uint256 poolValue; // outputDecimals_
        {
            uint256 priceMultiple = FixedPointMathLib.sqrt(
                price0.mulDiv(price1, 10 ** outputDecimals_) * k
            ); // sqrt(price * price) = outputDecimals_

            uint256 two = 2 * 10 ** outputDecimals_;
            poolValue = two.mulDiv(priceMultiple, poolSupply);
        }

        return poolValue;
    }

    // ========== TOKEN SPOT PRICE FUNCTIONS ========== //

    /// Determines the spot price of the specified token from the UniswapV2 pool specified in {params_}.
    ///
    /// It does this by:
    /// - Determining the price and reserves of the token paired with {lookupToken_}
    /// - Determining the corresponding price of {lookupToken_}
    ///
    /// NOTE: as the reserves of UniswapV2 pools can be manipulated using flash loans, the spot price
    /// can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_ the token to determine the price of
    /// @param outputDecimals_ The number of decimals to return the price in
    /// @param params_ UniswapV2 pool parameters of type UniswapV2PoolParams
    /// @return uint256 Price in the scale of outputDecimals_
    function getTokenPrice(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > MAX_DECIMALS)
            revert UniswapV2_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        IUniswapV2Pool pool;
        {
            UniswapV2PoolParams memory params = abi.decode(params_, (UniswapV2PoolParams));
            if (address(params.pool) == address(0)) revert UniswapV2_PoolTypeInvalid(address(params.pool));

            pool = IUniswapV2Pool(params.pool);
        }

        uint112[] memory balances_;
        address[] memory tokens_;
        {
            uint112[] memory balances = _getReserves(pool);
            if (balances.length == 0) revert UniswapV2_PoolBalancesInvalid(address(pool));

            balances_ = balances;
            tokens_ = _getTokens(pool);
        }

        uint256 lookupTokenIndex = type(uint256).max;
        uint256 destinationTokenIndex = type(uint256).max;
        uint256 destinationTokenPrice; // Scale: outputDecimals_
        {
            address destinationToken;

            // Determine the index of the lookup token and an appropriate destination token
            uint256 len = tokens_.length;
            for (uint256 i; i < len; i++) {
                // If address is zero, complain
                if (tokens_[i] == address(0)) revert UniswapV2_PoolTokensInvalid(address(pool));

                // If lookup token
                if (lookupToken_ == tokens_[i]) {
                    lookupTokenIndex = i;
                    continue;
                }

                // Don't set the destination token again
                if (destinationTokenIndex != type(uint256).max) {
                    continue;
                }

                // PRICE will revert if the price cannot be determined or is 0.
                (uint256 currentPrice, ) = _PRICE().getPrice(tokens_[i], PRICEv2.Variant.CURRENT);

                destinationTokenIndex = i;
                destinationTokenPrice = currentPrice;
                destinationToken = tokens_[i];
            }

            // Lookup token not found
            if (lookupTokenIndex == type(uint256).max)
                revert UniswapV2_LookupTokenNotFound(lookupToken_);

            // No destination token found with a price
            if (
                destinationTokenPrice == 0 ||
                destinationTokenIndex == type(uint256).max ||
                destinationToken == address(0)
            ) revert UniswapV2_PriceNotFound(address(pool));
        }

        // Calculate the rate of the lookup token
        uint256 lookupTokenUsdPrice;
        {
            uint256 lookupTokenBalance = _convertERC20Decimals(
                balances_[lookupTokenIndex],
                tokens_[lookupTokenIndex],
                outputDecimals_
            );
            uint256 destinationTokenBalance = _convertERC20Decimals(
                balances_[destinationTokenIndex],
                tokens_[destinationTokenIndex],
                outputDecimals_
            );

            // Get the lookupToken in terms of the destinationToken
            lookupTokenUsdPrice = destinationTokenBalance.mulDiv(
                destinationTokenPrice,
                lookupTokenBalance
            );
        }

        return lookupTokenUsdPrice;
    }
}
