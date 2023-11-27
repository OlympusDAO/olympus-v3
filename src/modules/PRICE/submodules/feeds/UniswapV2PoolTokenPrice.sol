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

/// @title      UniswapV2PoolTokenPrice
/// @author     0xJem
/// @notice     Provides prices derived from a Uniswap V2 pool
contract UniswapV2PoolTokenPrice is PriceSubmodule {
    using FullMath for uint256;

    /// @notice     Any token or pool with a decimal scale greater than this would result in an overflow
    /// @notice     UniswapV2 uses uint112 to store token balances. Token decimals over this number will result in truncated balances.
    uint8 internal constant MAX_DECIMALS = 26;

    /// @notice     The number of balances expected to be in the pool
    uint256 internal constant BALANCES_COUNT = 2;

    /// @notice        UniswapV2 pool parameters
    ///
    /// @param pool    Address of the UniswapV2 pool
    struct UniswapV2PoolParams {
        IUniswapV2Pool pool;
    }

    // ========== ERRORS ========== //

    /// @notice                 The decimals of the asset are out of bounds
    ///
    /// @param asset_           The address of the asset
    /// @param assetDecimals_   The number of decimals of the asset
    /// @param maxDecimals_     The maximum number of decimals allowed
    error UniswapV2_AssetDecimalsOutOfBounds(
        address asset_,
        uint8 assetDecimals_,
        uint8 maxDecimals_
    );

    /// @notice                 The lookup token was not found in the pool
    ///
    /// @param pool_            The address of the pool
    /// @param asset_           The address of the asset
    error UniswapV2_LookupTokenNotFound(address pool_, address asset_);

    /// @notice                 The output decimals are out of bounds
    ///
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param maxDecimals_     The maximum number of decimals allowed
    error UniswapV2_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);

    /// @notice                 The token balance of a pool is invalid
    ///
    /// @param pool_            The address of the pool
    /// @param balanceIndex_    The index of the balance
    /// @param balance_         The balance of the token
    error UniswapV2_PoolTokenBalanceInvalid(address pool_, uint8 balanceIndex_, uint256 balance_);

    /// @notice                         The pool balances are invalid
    ///
    /// @param pool_                    The address of the pool
    /// @param balanceCount_            The number of balances returned by the pool
    /// @param expectedBalanceCount_    The number of balances expected
    error UniswapV2_PoolBalancesInvalid(
        address pool_,
        uint256 balanceCount_,
        uint256 expectedBalanceCount_
    );

    /// @notice                 The pool specified in the parameters is invalid
    ///
    /// @param paramsIndex_     The index of the parameter
    /// @param pool_            The address of the pool
    error UniswapV2_ParamsPoolInvalid(uint8 paramsIndex_, address pool_);

    /// @notice             The total supply returned by the pool is invalid
    /// @dev                This currently only occurs if the total supply is 0
    ///
    /// @param pool_        The address of the pool
    /// @param supply_      The total supply returned by the pool
    error UniswapV2_PoolSupplyInvalid(address pool_, uint256 supply_);

    /// @notice                 The pool tokens are invalid
    ///
    /// @param pool_            The address of the pool
    /// @param tokenIndex_      The index of the token
    /// @param token_           The address of the token
    error UniswapV2_PoolTokensInvalid(address pool_, uint256 tokenIndex_, address token_);

    /// @notice                 The pool is invalid
    /// @dev                    This is triggered if the pool reverted when called,
    /// @dev                    and indicates that the feed address is not a UniswapV2 pool.
    ///
    /// @param pool_            The address of the pool
    error UniswapV2_PoolTypeInvalid(address pool_);

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    /// @inheritdoc      Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.UNIV2");
    }

    /// @inheritdoc      Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice             Returns the tokens of a UniswapV2 pool in an array
    ///
    /// @param pool_        UniswapV2 pool
    /// @return             Array of length 2 containing token addresses
    function _getTokens(IUniswapV2Pool pool_) internal view returns (address[] memory) {
        address[] memory tokens = new address[](2);
        tokens[0] = pool_.token0();
        tokens[1] = pool_.token1();

        return tokens;
    }

    /// @notice             Returns the reserves of a UniswapV2 pool
    /// @dev                This function reverts if the pool does not have the `getReserves()` function.
    ///
    /// @param pool_        UniswapV2 pool
    /// @return             Reserves of the pool in their native decimals
    function _getReserves(IUniswapV2Pool pool_) internal view returns (uint112[] memory) {
        try pool_.getReserves() returns (uint112 token0Reserves, uint112 token1Reserves, uint32) {
            uint112[] memory balances = new uint112[](2);
            balances[0] = token0Reserves;
            balances[1] = token1Reserves;

            return balances;
        } catch (bytes memory) {
            revert UniswapV2_PoolTypeInvalid(address(pool_));
        }
    }

    /// @notice                     Converts the given value from the ERC20 token's decimals to `outputDecimals_`
    /// @dev                        This function will revert if:
    /// @dev                        - Converting the token's decimals would result in an overflow.
    ///
    /// @param value_               Value in native ERC20 token decimals
    /// @param token_               The address of the ERC20 token
    /// @param outputDecimals_      The resulting number of decimals
    /// @return                     Value in the scale of `outputDecimals_`
    function _convertERC20Decimals(
        uint112 value_,
        address token_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        uint8 tokenDecimals = ERC20(token_).decimals();
        if (tokenDecimals > MAX_DECIMALS)
            revert UniswapV2_AssetDecimalsOutOfBounds(token_, tokenDecimals, MAX_DECIMALS);

        return (uint256(value_)).mulDiv(10 ** outputDecimals_, 10 ** tokenDecimals);
    }

    // ========== POOL TOKEN PRICE FUNCTIONS ========== //

    /// @notice                 Determines the unit price of the pool token for the UniswapV2 pool specified in `params_`.
    /// @dev                    The pool token price is determined using the "fair LP pricing" described here: https://cmichel.io/pricing-lp-tokens/
    /// @dev                    This approach is implemented in order to reduce the susceptibility to manipulation of the pool token price
    /// @dev                    through the pool's reserves.
    ///
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          UniswapV2 pool parameters of type `UniswapV2PoolParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getPoolTokenPrice(
        address,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > MAX_DECIMALS)
            revert UniswapV2_OutputDecimalsOutOfBounds(outputDecimals_, MAX_DECIMALS);

        address token0;
        address token1;
        uint256 k; // outputDecimals_
        uint256 poolSupply; // outputDecimals_
        {
            IUniswapV2Pool pool;
            {
                // Decode params
                UniswapV2PoolParams memory params = abi.decode(params_, (UniswapV2PoolParams));
                if (address(params.pool) == address(0))
                    revert UniswapV2_ParamsPoolInvalid(0, address(params.pool));

                pool = IUniswapV2Pool(params.pool);
            }

            // Get balances
            // Call this first as it will check on whether the pool is valid, and exit
            uint112[] memory balances = _getReserves(pool);
            if (balances.length < BALANCES_COUNT)
                revert UniswapV2_PoolBalancesInvalid(
                    address(pool),
                    balances.length,
                    BALANCES_COUNT
                );

            // Get tokens
            token0 = pool.token0();
            token1 = pool.token1();
            if (token0 == address(0)) revert UniswapV2_PoolTokensInvalid(address(pool), 0, token0);
            if (token1 == address(0)) revert UniswapV2_PoolTokensInvalid(address(pool), 1, token1);

            // Convert balances to outputDecimals_
            uint256 balance0;
            {
                uint8 token0Decimals = ERC20(token0).decimals();
                if (token0Decimals > MAX_DECIMALS)
                    revert UniswapV2_AssetDecimalsOutOfBounds(token0, token0Decimals, MAX_DECIMALS);

                balance0 = uint256(balances[0]).mulDiv(10 ** outputDecimals_, 10 ** token0Decimals);
            }

            uint256 balance1;
            {
                uint8 token1Decimals = ERC20(token1).decimals();
                if (token1Decimals > MAX_DECIMALS)
                    revert UniswapV2_AssetDecimalsOutOfBounds(token1, token1Decimals, MAX_DECIMALS);

                balance1 = uint256(balances[1]).mulDiv(10 ** outputDecimals_, 10 ** token1Decimals);
            }

            if (balance0 == 0) revert UniswapV2_PoolTokenBalanceInvalid(address(pool), 0, balance0);
            if (balance1 == 0) revert UniswapV2_PoolTokenBalanceInvalid(address(pool), 1, balance1);

            // Determine balance0 * balance1 = k
            k = balance0.mulDiv(balance1, 10 ** outputDecimals_);

            uint256 poolSupply_ = pool.totalSupply();
            if (poolSupply_ == 0) revert UniswapV2_PoolSupplyInvalid(address(pool), poolSupply_);

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

    /// @notice                 Determines the spot price of the specified token from the UniswapV2 pool specified in `params_`
    /// @dev                    It does this by:
    /// @dev                    - Determining the price and reserves of the token paired with `lookupToken_`
    /// @dev                    - Determining the corresponding price of `lookupToken_`
    ///
    /// @dev                    NOTE: as the reserves of UniswapV2 pools can be manipulated using flash loans, the spot price
    /// @dev                    can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          UniswapV2 pool parameters of type `UniswapV2PoolParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getTokenPrice(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > MAX_DECIMALS)
            revert UniswapV2_OutputDecimalsOutOfBounds(outputDecimals_, MAX_DECIMALS);

        // Decode params
        IUniswapV2Pool pool;
        {
            UniswapV2PoolParams memory params = abi.decode(params_, (UniswapV2PoolParams));
            if (address(params.pool) == address(0))
                revert UniswapV2_ParamsPoolInvalid(0, address(params.pool));

            pool = IUniswapV2Pool(params.pool);
        }

        uint112[] memory balances_;
        address[] memory tokens_;
        {
            uint112[] memory balances = _getReserves(pool);
            if (balances.length < BALANCES_COUNT)
                revert UniswapV2_PoolBalancesInvalid(
                    address(pool),
                    balances.length,
                    BALANCES_COUNT
                );

            balances_ = balances;
            tokens_ = _getTokens(pool);
        }

        uint256 lookupTokenIndex = type(uint256).max;
        uint256 destinationTokenIndex = type(uint256).max;
        uint256 destinationTokenPrice; // Scale: outputDecimals_
        {
            address token0 = tokens_[0];
            address token1 = tokens_[1];

            if (token0 == address(0)) revert UniswapV2_PoolTokensInvalid(address(pool), 0, token0);
            if (token1 == address(0))
                revert UniswapV2_PoolTokensInvalid(address(pool), 1, tokens_[1]);
            if (lookupToken_ != token0 && lookupToken_ != token1)
                revert UniswapV2_LookupTokenNotFound(address(pool), lookupToken_);

            lookupTokenIndex = (lookupToken_ == token0) ? 0 : 1;
            destinationTokenIndex = 1 - lookupTokenIndex;
            (uint256 destinationTokenPrice_, ) = _PRICE().getPrice(
                tokens_[destinationTokenIndex],
                PRICEv2.Variant.CURRENT
            );
            destinationTokenPrice = destinationTokenPrice_;
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
