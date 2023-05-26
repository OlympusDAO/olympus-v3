// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

/// @title Curve StableSwap Pool / 3Pool
/// @author Curve
/// @notice This interface is a simplified version of the Curve StableSwap pool and 3Pool contracts. e.g. 3pool, FRAX-USDC (FraxBP)
/// @dev https://github.com/curvefi/curve-contract/blob/b0bbf77f8f93c9c5f4e415bce9cd71f0cdee960e/contracts/pools/3pool/StableSwap3Pool.vy
interface ICurvePool {
    function get_virtual_price() external view returns (uint256);

    function coins(uint256 arg0) external view returns (address);

    function balances(uint256 arg0) external view returns (uint256);

    function get_dy(uint128, uint128, uint256) external view returns (uint256);

    function remove_liquidity(uint256, uint256[] calldata) external;
}

/// @title Curve Two-Crypto Pool
/// @author Curve
/// @notice This interface is a simplified version of the Curve Two-Crypto V2 pool contract. e.g. OHM-FraxBP
/// @dev https://github.com/curvefi/curve-factory-crypto/blob/7ed1011055682cef75ac2fa95d50407db33e7dfb/contracts/CurveCryptoSwap2ETH.vy
interface ICurvePoolTwoCrypto is ICurvePool {
    function price_oracle() external view returns (uint256);

    function token() external view returns (address);
}

/// @title Curve Tri-Crypto Pool
/// @author Curve
/// @notice This interface is a simplified version of the Curve Tri-Crypto V2 pool contract.
/// @dev https://github.com/curvefi/curve-crypto-contract/blob/d7d04cd9ae038970e40be850df99de8c1ff7241b/contracts/tricrypto/CurveCryptoSwap.vy
interface ICurvePoolTriCrypto is ICurvePool {
    function price_oracle(uint256 k) external view returns (uint256);

    function token() external view returns (address);
}

contract CurvePoolTokenPrice is PriceSubmodule {
    using FullMath for uint256;

    struct CurveParams {
        ICurvePool pool;
    }

    struct CurveTwoCryptoParams {
        ICurvePoolTwoCrypto pool;
    }

    struct CurveTriCryptoParams {
        ICurvePoolTriCrypto pool;
    }

    // ========== ERRORS ========== //

    error Curve_AssetDecimalsOutOfBounds(address asset_);
    error Curve_LookupTokenNotFound(address asset_);
    error Curve_OutputDecimalsOutOfBounds(uint8 outputDecimals_);
    error Curve_PoolBalancesInvalid(address pool_);
    error Curve_PoolPriceOracleInvalid(address pool_);
    error Curve_PoolSupplyInvalid(address poolToken_);
    error Curve_PoolTokenBalancesMismatch(address pool_);
    error Curve_PoolTokenDecimalsOutOfBounds(address asset_);
    error Curve_PoolTokenNotSet(address pool_);
    error Curve_PoolTokensInvalid(address pool_);
    error Curve_PoolTypeNotStable(address pool_);
    error Curve_PoolTypeNotTriCrypto(address pool_);
    error Curve_PoolTypeNotTwoCrypto(address pool_);
    error Curve_PriceNotFound(address asset_);

    // ========== CONSTANTS ========== //

    // This is not configurable in the contract code, so we hard-code it.
    uint8 internal constant POOL_DECIMALS = 18;
    uint8 internal constant BASE_10_MAX_EXPONENT = 60;

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.CRV");
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice     Activates a reentrancy lock on the Curve pool contract
    /// @dev        This uses the same method as MakerDAO:
    ///             https://github.com/makerdao/curve-lp-oracle/blob/302f5e6966fdbfebe0f7063c9d6f6bc1f6470f28/src/CurveLPOracle.sol#L228-L231
    function _reentrancyLock(ICurvePool pool_, uint8 numCoins_) internal {
        uint256[] memory amounts = new uint256[](numCoins_);
        pool_.remove_liquidity(0, amounts);

        // Attempts to make this a staticcall will fail since the function returns data
        // and state is manipulated in the function. TODO: come up with a different view fix
        // (, bytes memory revertData) = address(pool_).staticcall{gas: 1_000}(
        //     abi.encodeWithSelector(pool_.remove_liquidity.selector, 0, amounts)
        // );

        // require(revertData.length == 0, "reentrancy detected");
    }

    function _getERC20Decimals(address token_) internal view returns (uint8) {
        return ERC20(token_).decimals();
    }

    /// @notice                     Converts the given value from the ERC20 token's decimals to the destination decimals
    ///
    /// @dev                        This function will revert if:
    ///                             - converting the token's decimals would result in an overflow.
    ///
    /// @param value_               Value in native ERC20 token decimals
    /// @param token_               The address of the ERC20 token
    /// @param destinationDecimals_ The resulting number of decimals
    /// @return uint256             Value in the scale of destinationDecimals
    function _convertERC20Decimals(
        uint256 value_,
        address token_,
        uint8 destinationDecimals_
    ) internal view returns (uint256) {
        uint8 tokenDecimals = _getERC20Decimals(token_);
        if (tokenDecimals > BASE_10_MAX_EXPONENT) revert Curve_AssetDecimalsOutOfBounds(token_);

        return value_.mulDiv(10 ** destinationDecimals_, 10 ** tokenDecimals);
    }

    // ========== POOL TOKEN PRICE FUNCTIONS ========== //

    /// @notice                     Determines the price of the pool token for the Curve stable pool specified in {params_}.
    ///
    ///                             @dev Will revert upon the following:
    ///                             - Decimal exponent too high
    ///                             - 0x0 addresses in the pool
    ///                             - Unable to find a price for the tokens that are part of the pool
    ///                             - If the transaction involves reentrancy on the Curve pool
    ///
    ///                             NOTE: if a non-stable Curve pool is passed in the parameters, an incorrect price will be
    ///                             pool token price returned. Use the pool-specified pool token price function instead.
    ///
    /// @param asset_               The asset to get the price of (unused)
    /// @param outputDecimals_      The number of decimals to return the price in
    /// @param params_              Curve pool parameters of type ICurvePool
    /// @return uint256             Price in the scale of outputDecimals_
    function getPoolTokenPriceFromStablePool(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Curve_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        CurveParams memory params = abi.decode(params_, (CurveParams));
        {
            if (address(params.pool) == address(0))
                revert Curve_PoolTypeNotStable(address(params.pool));
        }
        ICurvePool pool = ICurvePool(params.pool);
        uint256 poolVirtualPrice;
        {
            // Ensure the pool is of the correct type
            try pool.get_virtual_price() returns (uint256 _virtualPrice) {
                poolVirtualPrice = _virtualPrice;
            } catch (bytes memory) {
                revert Curve_PoolTypeNotStable(address(pool));
            }
        }
        uint256 minimumPrice = type(uint256).max; // outputDecimals_

        /**
         * Iterate through all coins until the function reverts.
         *
         * The Curve pool contract does not offer a way to obtain the number of coins,
         * so this crude approach is required.
         */
        uint8 numCoins = 0;
        for (uint256 i = 0; i < 10; i++) {
            address currentCoin;
            try pool.coins(i) returns (address currentCoin_) {
                if (currentCoin_ == address(0)) revert Curve_PoolTokensInvalid(address(pool));

                currentCoin = currentCoin_;
                numCoins++;
            } catch (bytes memory) {
                // Hit the last element of the array, so exit
                break;
            }

            /**
             * PRICE will revert if the price cannot be determined or is 0.
             *
             * If ANY price cannot be determined, then the pool token value cannot be determined. So we don't catch the error.
             */
            (uint256 currentCoinPrice, ) = _PRICE().getPrice(currentCoin, PRICEv2.Variant.CURRENT);

            // We track the minimum price of all of the coins, as the pool token price is derived from that
            if (currentCoinPrice < minimumPrice) {
                minimumPrice = currentCoinPrice;
            }
        }

        // Trigger the re-entrancy lock
        _reentrancyLock(pool, numCoins);

        // If the minimumPrice is still max, there were no coins in the pool
        if (minimumPrice == type(uint256).max) revert Curve_PoolTokensInvalid(address(pool));

        /**
         * Pool price is minimum of coin price * virtual price, adjusted for decimals.
         *
         * As the prices returned from PRICE have a consistent number of decimal places,
         * we just need to adjust for the potentially-different number of decimal places
         * for the value returned from the Curve pool. The resulting number will
         * have the same decimal places as prices returned by PRICE.
         */
        uint256 adjustedVirtualPrice = minimumPrice.mulDiv(poolVirtualPrice, 10 ** POOL_DECIMALS);
        return adjustedVirtualPrice;
    }

    /// @notice                         Determines the price of the pool token for the Curve two- or three-crypto pool specified in {params_}.
    ///
    /// @dev                            Will revert upon the following:
    ///                                 - Pool balance is 0
    ///                                 - This function is called on an unsupported pool type
    ///                                 - 0x0 addresses in the pool
    ///                                 - Unable to find a price for the tokens that are part of the pool
    ///                                 - If the transaction involves reentrancy on the Curve pool
    ///
    ///                                 Assumes the following have already been checked:
    ///                                 - outputDecimals_ is within bounds
    ///                                 - Pool token total supply is not 0
    ///
    /// @param poolTokenTotalSupply_    Total supply of the pool token
    /// @param outputDecimals_          The number of decimals to return the price in
    /// @param params_                  Curve pool parameters of type ICurvePoolTriCrypto
    /// @return uint256                 Price in the scale of outputDecimals_
    function _getPoolTokenPriceCrypto(
        uint256 poolTokenTotalSupply_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) internal returns (uint256) {
        // Decode params
        ICurvePoolTriCrypto pool;
        {
            CurveTriCryptoParams memory params = abi.decode(params_, (CurveTriCryptoParams));
            pool = ICurvePoolTriCrypto(params.pool);
        }

        // Total value of the pool
        // Decimals: outputDecimals_
        uint256 poolValue = 0;

        uint8 numCoins = 0;

        /**
         * Iterate through all coins until the function reverts.
         *
         * The Curve pool contract does not offer a way to obtain the number of coins,
         * so this crude approach is required.
         *
         * For each coin:
         * - Get the price
         * - Get the balance
         * - Calculate the value of the reserves
         */
        for (uint256 i = 0; i < 10; i++) {
            address currentCoin;
            try pool.coins(i) returns (address currentCoin_) {
                if (currentCoin_ == address(0)) revert Curve_PoolTokensInvalid(address(pool));

                currentCoin = currentCoin_;
                numCoins++;
            } catch (bytes memory) {
                // Hit the last element of the array, so exit
                break;
            }

            /**
             * PRICE will revert if the price cannot be determined or is 0.
             *
             * If ANY price cannot be determined, then the pool token value cannot be determined. So we don't catch the error.
             */
            (uint256 lookupCoinPrice, ) = _PRICE().getPrice(currentCoin, PRICEv2.Variant.CURRENT);

            try pool.balances(i) returns (uint256 currentBalance) {
                // Under no circumstances should this be 0
                if (currentBalance == 0) revert Curve_PoolBalancesInvalid(address(pool));

                // Adjust to outputDecimals_
                uint256 currentBalanceConsistentDecimals;
                {
                    currentBalanceConsistentDecimals = currentBalance.mulDiv(
                        10 ** outputDecimals_,
                        10 ** ERC20(currentCoin).decimals()
                    );
                }

                // Multiply and adjust to outputDecimals_
                uint256 currentCoinValue = lookupCoinPrice.mulDiv(
                    currentBalanceConsistentDecimals,
                    10 ** outputDecimals_
                );

                poolValue += currentCoinValue;
            } catch (bytes memory) {
                // If calling pool.balances() reverts, then the number of coins and balances is different
                revert Curve_PoolTokenBalancesMismatch(address(pool));
            }
        }

        // Trigger the re-entrancy lock
        _reentrancyLock(pool, numCoins);

        // No coins or balances
        if (poolValue == 0) revert Curve_PoolTokensInvalid(address(pool));

        // Calculate per-token price
        uint256 poolTokenPrice = poolValue.mulDiv(10 ** outputDecimals_, poolTokenTotalSupply_);
        return poolTokenPrice;
    }

    /// @notice                 Determines the price of the pool token for the Curve two-crypto pool specified in {params_}.
    ///
    /// @dev                    Will revert upon the following:
    ///                         - Decimal exponent too high
    ///                         - Pool token is not set or is 0x0
    ///                         - Pool token total supply is 0
    ///                         - Pool balance is 0
    ///                         - Incorrect pool type
    ///                         - 0x0 addresses in the pool
    ///                         - Unable to find a price for the tokens that are part of the pool
    ///                         - If the transaction involves reentrancy on the Curve pool
    ///
    /// @param asset_           The asset to get the price of (unused)
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          Curve pool parameters of type ICurvePoolTwoCrypto
    /// @return uint256         Price in the scale of outputDecimals_
    function getPoolTokenPriceFromTwoCryptoPool(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Curve_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        CurveTwoCryptoParams memory params = abi.decode(params_, (CurveTwoCryptoParams));
        {
            if (address(params.pool) == address(0))
                revert Curve_PoolTypeNotTwoCrypto(address(params.pool));
        }
        ICurvePoolTwoCrypto pool = ICurvePoolTwoCrypto(params.pool);

        // Get pool total supply
        // Decimals: outputDecimals_
        uint256 poolTokenTotalSupply;
        address poolTokenAddress;
        {
            try pool.token() returns (address tokenAddress) {
                poolTokenAddress = tokenAddress;
            } catch (
                bytes memory // If the function is not present on the pool, give an error that makes sense
                // This would fail if a different pool type is given as a parameter
            ) {
                revert Curve_PoolTypeNotTwoCrypto(address(pool));
            }

            // Complain if the pool token is not set
            if (poolTokenAddress == address(0)) revert Curve_PoolTokenNotSet(address(pool));

            // Total supply will be checked in the internal function
            uint256 poolTotalSupplyRaw = ERC20(poolTokenAddress).totalSupply();
            uint8 decimals = ERC20(poolTokenAddress).decimals();
            if (decimals > BASE_10_MAX_EXPONENT)
                revert Curve_PoolTokenDecimalsOutOfBounds(address(poolTokenAddress));

            poolTokenTotalSupply = poolTotalSupplyRaw.mulDiv(10 ** outputDecimals_, 10 ** decimals);
            // Prevent divide by zero
            if (poolTokenTotalSupply == 0) revert Curve_PoolSupplyInvalid(poolTokenAddress);
        }

        return _getPoolTokenPriceCrypto(poolTokenTotalSupply, outputDecimals_, params_);
    }

    /// @notice                 Determines the price of the pool token for the Curve tri-crypto pool specified in {params_}.
    ///
    /// @dev                    Will revert upon the following:
    ///                         - Decimal exponent too high
    ///                         - Pool token is not set or is 0x0
    ///                         - Pool token total supply is 0
    ///                         - Pool balance is 0
    ///                         - Incorrect pool type
    ///                         - 0x0 addresses in the pool
    ///                         - Unable to find a price for the tokens that are part of the pool
    ///                         - If the transaction involves reentrancy on the Curve pool
    ///
    /// @param asset_           The asset to get the price of (unused)
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          Curve pool parameters of type ICurvePoolTriCrypto
    /// @return uint256         Price in the scale of outputDecimals_
    function getPoolTokenPriceFromTriCryptoPool(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Curve_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        CurveTriCryptoParams memory params = abi.decode(params_, (CurveTriCryptoParams));
        {
            if (address(params.pool) == address(0))
                revert Curve_PoolTypeNotTriCrypto(address(params.pool));
        }
        ICurvePoolTriCrypto pool = ICurvePoolTriCrypto(params.pool);

        // Get pool total supply
        // Decimals: outputDecimals_
        uint256 poolTokenTotalSupply;
        address poolTokenAddress;
        {
            try pool.token() returns (address tokenAddress) {
                poolTokenAddress = tokenAddress;
            } catch (
                bytes memory // If the function is not present on the pool, give an error that makes sense
                // This would fail if a different pool type is given as a parameter
            ) {
                revert Curve_PoolTypeNotTriCrypto(address(pool));
            }

            // Complain if the pool token is not set
            if (poolTokenAddress == address(0)) revert Curve_PoolTokenNotSet(address(pool));

            // Total supply will be checked in the internal function
            uint256 poolTotalSupplyRaw = ERC20(poolTokenAddress).totalSupply();
            uint8 decimals = ERC20(poolTokenAddress).decimals();
            if (decimals > BASE_10_MAX_EXPONENT)
                revert Curve_PoolTokenDecimalsOutOfBounds(address(poolTokenAddress));

            poolTokenTotalSupply = poolTotalSupplyRaw.mulDiv(10 ** outputDecimals_, 10 ** decimals);
            // Prevent divide by zero
            if (poolTokenTotalSupply == 0) revert Curve_PoolSupplyInvalid(poolTokenAddress);
        }

        return _getPoolTokenPriceCrypto(poolTokenTotalSupply, outputDecimals_, params_);
    }

    // ========== TOKEN SPOT PRICE FUNCTIONS ========== //

    /// @notice                 Determines the price of the specified token, using the two-crypto Curve pool specified in {params_}.
    ///
    /// @dev                    Will revert upon the following:
    ///                         - Decimal exponent too high
    ///                         - 0x0 addresses in the pool
    ///                         - Incorrect pool type
    ///                         - The price_oracle() function on the Curve pool returns 0
    ///                         - Unable to find the price of a second token in the pool
    ///                         - If the transaction involves reentrancy on the Curve pool
    ///
    ///                         This function utilises the price_oracle() function on the Curve pool to provide resistance to price manipulation.
    ///
    ///                         NOTE: as the reserves of Curve pools can be manipulated using flash loans, the spot price
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          Curve pool parameters of type ICurvePoolTwoCrypto
    /// @return uint256         Price in the scale of outputDecimals_
    function getTokenPriceFromTwoCryptoPool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Curve_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        CurveTwoCryptoParams memory params = abi.decode(params_, (CurveTwoCryptoParams));
        {
            if (address(params.pool) == address(0))
                revert Curve_PoolTypeNotTwoCrypto(address(params.pool));
        }
        ICurvePoolTwoCrypto pool = ICurvePoolTwoCrypto(params.pool);

        uint256 price_oracle;
        {
            // Get the ratio of lookupToken_ : destToken
            // price_oracle() provides a moving average that is updated upon exchange and add/remove liquidity, so is resistant to price manipulation
            // Decimals: POOL_DECIMALS
            try pool.price_oracle() returns (uint256 price_oracle_value) {
                price_oracle = price_oracle_value;
            } catch (
                bytes memory // If the function is not present on the pool, give an error that makes sense
                // This would fail if a stable or tri-crypto pool is given as a parameter
            ) {
                revert Curve_PoolTypeNotTwoCrypto(address(pool));
            }

            // Avoid divide by 0
            if (price_oracle == 0) revert Curve_PoolPriceOracleInvalid(address(pool));
        }

        // Check that pool tokens are valid
        uint8 numCoins = 2;
        bool lookupTokenIsToken0 = false;
        uint256 destTokenPrice = 0; // Decimals: outputDecimals_
        {
            uint128 lookupTokenIndex = type(uint128).max;
            uint128 destTokenIndex = type(uint128).max;

            for (uint8 i = 0; i < numCoins; i++) {
                address currentCoin = pool.coins(uint256(i));

                if (currentCoin == address(0)) revert Curve_PoolTokensInvalid(address(pool));

                if (currentCoin == lookupToken_) {
                    lookupTokenIndex = i;
                    continue;
                }

                // Check if the price of currentCoin can be resolved
                // Skip if not
                try _PRICE().getPrice(currentCoin, PRICEv2.Variant.CURRENT) returns (
                    uint256 currentCoinPrice,
                    uint48 timestamp
                ) {
                    destTokenIndex = i;
                    destTokenPrice = currentCoinPrice;
                } catch (bytes memory) {
                    continue;
                }
            }

            // Unable to find the lookup token
            if (lookupTokenIndex == type(uint128).max)
                revert Curve_LookupTokenNotFound(lookupToken_);

            // Unable to find a second token with a price configured
            if (destTokenIndex == type(uint128).max) revert Curve_PriceNotFound(address(pool));

            // Unable to resolve the price of the destination token
            if (destTokenPrice == 0) revert Curve_PriceNotFound(address(pool));

            lookupTokenIsToken0 = lookupTokenIndex == 0;
        }

        // Trigger the re-entrancy lock
        _reentrancyLock(pool, numCoins);

        uint256 tokenInUsdPrice;
        {
            // Make the orientation of the ratio consistent, and adjust for decimals
            // price_oracle is validated above to be non-zero
            uint256 lookupTokenInDestToken = lookupTokenIsToken0
                ? (10 ** POOL_DECIMALS).mulDiv(10 ** POOL_DECIMALS, price_oracle)
                : price_oracle;

            // Get the price in USD
            // Decimals: outputDecimals_
            tokenInUsdPrice = lookupTokenInDestToken.mulDiv(destTokenPrice, 10 ** POOL_DECIMALS);
        }

        return tokenInUsdPrice;
    }

    /// @notice                 Determines the price of the specified token, using the tri-crypto Curve pool specified in {params_}.
    ///
    /// @dev                    Will revert upon the following:
    ///                         - Decimal exponent too high
    ///                         - 0x0 addresses in the pool
    ///                         - Incorrect pool type
    ///                         - The price_oracle() function on the Curve pool returns 0
    ///                         - Unable to find the price of a second token in the pool
    ///                         - If the transaction involves reentrancy on the Curve pool
    ///
    ///                         This function utilises the price_oracle() function on the Curve pool to provide resistance to price manipulation.
    ///
    ///                         NOTE: as the reserves of Curve pools can be manipulated using flash loans, the spot price
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          Curve pool parameters of type ICurvePoolTriCrypto
    /// @return uint256         Price in the scale of outputDecimals_
    function getTokenPriceFromTriCryptoPool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Curve_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        CurveTriCryptoParams memory params = abi.decode(params_, (CurveTriCryptoParams));
        {
            if (address(params.pool) == address(0))
                revert Curve_PoolTypeNotTriCrypto(address(params.pool));
        }
        ICurvePoolTriCrypto pool = ICurvePoolTriCrypto(params.pool);

        // Determine which tokens we are dealing with
        uint8 numCoins = 3;
        uint128 lookupTokenIndex = type(uint128).max;
        uint128 destTokenIndex = type(uint128).max;
        uint256 destTokenPrice = 0; // Decimals: outputDecimals_
        {
            // Iterate over all coins
            for (uint128 i = 0; i < numCoins; i++) {
                address currentCoin = pool.coins(uint256(i));

                // Check for 0 address
                if (currentCoin == address(0)) revert Curve_PoolTokensInvalid(address(pool));

                // Note the index of the lookupToken_
                if (currentCoin == lookupToken_) {
                    lookupTokenIndex = i;
                    continue;
                }

                // Skip if the destTokenIndex has already been determined
                // Otherwise the destination token could end up being a non-base token
                if (destTokenIndex < type(uint128).max) {
                    continue;
                }

                // Check if the price of currentCoin can be resolved
                // Skip if not
                try _PRICE().getPrice(currentCoin, PRICEv2.Variant.CURRENT) returns (
                    uint256 currentCoinPrice,
                    uint48 timestamp
                ) {
                    destTokenIndex = i;
                    destTokenPrice = currentCoinPrice;
                } catch (bytes memory) {
                    continue;
                }
            }

            // Unable to find the lookup token
            if (lookupTokenIndex == type(uint128).max)
                revert Curve_LookupTokenNotFound(lookupToken_);

            // Unable to find a second token with a price configured
            if (destTokenIndex == type(uint128).max) revert Curve_PriceNotFound(address(pool));

            // Unable to resolve the price of the destination token
            if (destTokenPrice == 0) revert Curve_PriceNotFound(address(pool));

            // If neither the lookup nor destination token are the base token, that will prevent determining the price.
            // This is because the price oracle values are in reference to the base token at index 0.
            if (lookupTokenIndex > 0 && destTokenIndex > 0)
                revert Curve_PriceNotFound(address(pool));
        }

        // Trigger the re-entrancy lock
        _reentrancyLock(pool, numCoins);

        uint256 price_oracle;
        {
            // The price_oracle array has 2 (N_COINS - 1) elements for the potential pairings of coins(1) and coins(2) with coins(0)
            uint128 oracleIndex = lookupTokenIndex == 0 ? destTokenIndex - 1 : lookupTokenIndex - 1;

            // Get the ratio of lookupToken_ : destToken
            // price_oracle() provides a moving average that is updated upon exchange and add/remove liquidity, so is resistant to price manipulation
            // Decimals: POOL_DECIMALS
            try pool.price_oracle(oracleIndex) returns (uint256 price_oracle_value) {
                price_oracle = price_oracle_value;
            } catch (
                bytes memory // If the function is not present on the pool, give an error that makes sense
                // This would fail if a stable or tri-crypto pool is given as a parameter
            ) {
                revert Curve_PoolTypeNotTriCrypto(address(pool));
            }

            // Avoid divide by 0
            if (price_oracle == 0) revert Curve_PoolPriceOracleInvalid(address(pool));
        }

        uint256 tokenInUsdPrice;
        {
            // Make the orientation of the ratio consistent, and adjust for decimals
            // price_oracle is validated above to be non-zero
            uint256 lookupTokenInDestToken = lookupTokenIndex == 0
                ? (10 ** POOL_DECIMALS).mulDiv(10 ** POOL_DECIMALS, price_oracle)
                : price_oracle;

            // Get the price in USD
            // Decimals: outputDecimals_
            tokenInUsdPrice = lookupTokenInDestToken.mulDiv(destTokenPrice, 10 ** POOL_DECIMALS);
        }

        return tokenInUsdPrice;
    }

    /// @notice                 Determine the quantity of t2 received in return for 1 unit of t1
    /// @dev                    Uses get_dy in the Curve pool
    ///
    /// @param pool_            The Curve pool
    /// @param t1Index_         The index of the first token
    /// @param t2Index_         The index of the second token
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @return uint256         Quantity in terms of outputDecimals_, or 0
    function _getStablePoolSwapQuantity(
        ICurvePool pool_,
        uint128 t1Index_,
        uint128 t2Index_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        address t1 = pool_.coins(t1Index_);
        address t2 = pool_.coins(t2Index_);

        // Returned in terms of t2's ERC20 decimals
        uint256 dyResult = pool_.get_dy(t1Index_, t2Index_, 10 ** _getERC20Decimals(t1));
        uint256 swapResult = _convertERC20Decimals(dyResult, t2, outputDecimals_);

        return swapResult;
    }

    /// @notice                 Determines the price of the specified token, using the stable Curve pool specified in {params_}.
    ///
    /// @dev                    Will revert upon the following:
    ///                         - Decimal exponent too high
    ///                         - 0x0 addresses in the pool
    ///                         - Incorrect pool type
    ///                         - Unable to find the price of a second token in the pool
    ///                         - If the transaction involves reentrancy on the Curve pool
    ///
    ///                         To determine the price of the lookupToken_ (t1), this function uses the following process:
    ///                         - Determine the price of a second token (t2) in the pool
    ///                         - Use get_dy to determine the quantity (q2) of t2 received in return for 1 unit of t1
    ///                         - Multiply q2 * t2 to determine the price of t1 in USD
    ///
    ///                         NOTE: as the reserves of Curve pools can be manipulated using flash loans, the spot price
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The number of decimals to return the price in
    /// @param params_          Curve pool parameters of type ICurvePool
    /// @return uint256         Price in the scale of outputDecimals_
    function getTokenPriceFromStablePool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        // Decode params
        ICurvePool pool;
        {
            CurveParams memory params = abi.decode(params_, (CurveParams));
            {
                if (address(params.pool) == address(0))
                    revert Curve_PoolTypeNotStable(address(params.pool));
            }
            pool = ICurvePool(params.pool);
            {
                // Ensure the pool is of the correct type
                try pool.get_virtual_price() returns (uint256 _virtualPrice) {
                    // Do nothing
                } catch (bytes memory) {
                    revert Curve_PoolTypeNotStable(address(pool));
                }
            }
        }

        // Find the index of the lookup token
        uint128 lookupTokenIndex = type(uint128).max;
        {
            uint8 numCoins;
            for (uint128 i = 0; i < 10; i++) {
                address currentCoin;

                /**
                 * Iterate through all coins until the function reverts.
                 *
                 * The Curve pool contract does not offer a way to obtain the number of coins,
                 * so this crude approach is required.
                 */
                try pool.coins(i) returns (address currentCoin_) {
                    if (currentCoin_ == address(0)) revert Curve_PoolTokensInvalid(address(pool));

                    currentCoin = currentCoin_;
                    numCoins++;
                } catch (bytes memory) {
                    // Hit the last element of the array, so exit
                    break;
                }

                // Note the index of the lookupToken_
                if (currentCoin == lookupToken_) {
                    lookupTokenIndex = i;
                    continue;
                }
            }

            // Unable to find the lookup token
            if (lookupTokenIndex == type(uint128).max)
                revert Curve_LookupTokenNotFound(lookupToken_);

            // Trigger the re-entrancy lock
            _reentrancyLock(pool, numCoins);
        }

        uint256 lookupTokenPrice = 0; // Decimals: outputDecimals_
        {
            for (uint128 i = 0; i < 10; i++) {
                /**
                 * Iterate through all coins until the function reverts.
                 *
                 * The Curve pool contract does not offer a way to obtain the number of coins,
                 * so this crude approach is required.
                 */
                address currentCoin;
                try pool.coins(i) returns (address currentCoin_) {
                    currentCoin = currentCoin_;
                } catch (bytes memory) {
                    // Hit the last element of the array, so exit
                    break;
                }

                /**
                 * Use get_dy to determine the quantity of destToken received in return
                 * for 1 unit of lookupToken.
                 *
                 * Input value is in the lookup token's ERC20 decimals.
                 * Output value is in the destination token's ERC20 decimals.
                 */
                uint256 swapQuantity = _getStablePoolSwapQuantity(
                    pool,
                    lookupTokenIndex,
                    i,
                    outputDecimals_
                );
                if (swapQuantity == 0) continue;

                // Check if the price of the destination token can be resolved
                // Skip if not
                try _PRICE().getPrice(currentCoin, PRICEv2.Variant.CURRENT) returns (
                    uint256 destTokenPrice,
                    uint48 _timestamp
                ) {
                    if (destTokenPrice == 0) continue;

                    lookupTokenPrice = swapQuantity.mulDiv(destTokenPrice, 10 ** outputDecimals_);
                    break;
                } catch (bytes memory) {
                    continue;
                }
            }
        }

        if (lookupTokenPrice == 0) revert Curve_PriceNotFound(address(pool));

        return lookupTokenPrice;
    }
}
