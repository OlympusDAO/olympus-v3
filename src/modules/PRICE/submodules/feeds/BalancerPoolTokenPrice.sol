// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {StableMath} from "src/libraries/Balancer/math/StableMath.sol";
import {IVault} from "src/libraries/Balancer/interfaces/IVault.sol";
import {VaultReentrancyLib} from "src/libraries/Balancer/contracts/VaultReentrancyLib.sol";
import {LogExpMath} from "src/libraries/Balancer/math/LogExpMath.sol";

interface IBasePool {
    function getPoolId() external view returns (bytes32);

    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);
}

interface IWeightedPool is IBasePool {
    function getNormalizedWeights() external view returns (uint256[] memory);

    function getInvariant() external view returns (uint256);
}

interface IStablePool is IBasePool {
    function getLastInvariant() external view returns (uint256, uint256);

    function getRate() external view returns (uint256);
}

contract BalancerPoolTokenPrice is PriceSubmodule {
    using FullMath for uint256;

    // 50 seems to be the maximum exponent that can be used without overflowing
    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    struct BalancerBasePoolParams {
        IBasePool pool;
    }

    struct BalancerWeightedPoolParams {
        IWeightedPool pool;
    }

    struct BalancerStablePoolParams {
        IStablePool pool;
    }

    // ========== ERRORS ========== //

    error Balancer_AssetDecimalsOutOfBounds(address asset_);
    error Balancer_LookupTokenNotFound(address asset_);
    error Balancer_OutputDecimalsOutOfBounds(uint8 outputDecimals_);
    error Balancer_PoolDecimalsOutOfBounds(bytes32 poolId_);
    error Balancer_PoolStableRateInvalid(bytes32 poolId_);
    error Balancer_PoolSupplyInvalid(bytes32 poolId_);
    error Balancer_PoolTokensInvalid(bytes32 poolId_);
    error Balancer_PoolTokenWeightMismatch(bytes32 poolId_);
    error Balancer_PoolTypeNotStable(bytes32 poolId_);
    error Balancer_PoolTypeNotWeighted(bytes32 poolId_);
    error Balancer_PoolWeightsInvalid(bytes32 poolId_);
    error Balancer_PriceNotFound(address asset_);

    // ========== STATE VARIABLES ========== //

    IVault public immutable balVault;

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_, IVault balVault_) Submodule(parent_) {
        balVault = balVault_;
    }

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.BPT");
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Converts the given value from the ERC20 token's decimals to the destination decimals
    ///
    /// @dev This function will revert if converting the token's decimals would result in an overflow.
    ///
    /// @param value value in native ERC20 token decimals
    /// @param token the address of the ERC20 token
    /// @param destinationDecimals the resulting number of decimals
    /// @return uint256 Number in the scale of destinationDecimals
    function _convertERC20Decimals(
        uint256 value,
        address token,
        uint8 destinationDecimals
    ) internal view returns (uint256) {
        uint8 tokenDecimals = ERC20(token).decimals();
        if (tokenDecimals > BASE_10_MAX_EXPONENT) revert Balancer_AssetDecimalsOutOfBounds(token);

        return value.mulDiv(10 ** destinationDecimals, 10 ** tokenDecimals);
    }

    /// @notice Obtains the balance of the token at the specified index in the pool
    ///
    /// @dev This function will revert if converting the token's balance would result in an overflow.
    ///
    /// As this function is accessing the balances of the pool, it is guarded by VaultReentrancyLib to
    /// prevent re-entrancy attacks.
    ///
    /// @param poolId id of the Balancer pool
    /// @param tokenIndex index of the token in the Balancer pool
    /// @param outputDecimals desired number of decimals
    /// @return uint256 Balance in the scale of outputDecimals
    function _getTokenBalance(
        bytes32 poolId,
        uint256 tokenIndex,
        uint8 outputDecimals
    ) internal returns (uint256) {
        // Prevent re-entrancy attacks
        VaultReentrancyLib.ensureNotInVaultContext(balVault);

        (address[] memory tokens_, uint256[] memory balances_, ) = balVault.getPoolTokens(poolId);

        // Balances are in the scale of the ERC20 token, so adjust those to outputDecimals
        return _convertERC20Decimals(balances_[tokenIndex], tokens_[tokenIndex], outputDecimals);
    }

    /// @notice Obtains the balance/weight ratio of token at the specified index in the pool
    ///
    /// @dev This function will revert if converting the pool's decimals would result in an overflow.
    ///
    /// As this function is accessing the balances of the pool, it is guarded by VaultReentrancyLib to
    /// prevent re-entrancy attacks.
    ///
    /// @param poolId_ id of the Balancer pool
    /// @param pool_ Balancer weighted pool
    /// @param index_ index of the token in the Balancer pool
    /// @param outputDecimals_ desired number of decimals
    /// @return uint256 Balance in the scale of outputDecimals_
    function _getTokenBalanceWeighting(
        bytes32 poolId_,
        IWeightedPool pool_,
        uint256 index_,
        uint8 outputDecimals_
    ) internal returns (uint256) {
        uint256 tokenBalance = _getTokenBalance(poolId_, index_, outputDecimals_);

        uint8 poolDecimals = pool_.decimals();
        uint256[] memory weights = pool_.getNormalizedWeights();
        uint256 tokenWeight = weights[index_].mulDiv(
            10 ** outputDecimals_,
            10 ** poolDecimals
        );

        return tokenBalance.mulDiv(10 ** outputDecimals_, tokenWeight);
    }

    function _getTokenValueInWeightedPool(
        address token_,
        uint256 weight_,
        uint8 poolDecimals_,
        uint8 outputDecimals_,
        uint8 powDecimals_,
        bytes32 poolId_
    ) internal view returns (uint256) {
        if (token_ == address(0)) revert Balancer_PoolTokensInvalid(poolId_);
        if (weight_ == 0) revert Balancer_PoolWeightsInvalid(poolId_);

        uint256 price; // powDecimals_
        {
            /**
             * PRICE will revert if there is an issue resolving the price, or if it is 0.
             *
             * As the value of the pool token is reliant on the price of every underlying token,
             * the revert from PRICE is not caught.
             */
            (uint256 price_, ) = _PRICE().getPrice(token_, PRICEv2.Variant.CURRENT); // outputDecimals_

            price = price_.mulDiv(10 ** powDecimals_, 10 ** outputDecimals_);
        }

        // powDecimals_
        uint256 weight = weight_.mulDiv(10 ** powDecimals_, 10 ** poolDecimals_);

        // All inputs to pow need to be in the scale of 1e18, so adjust for that
        return LogExpMath.pow(price.mulDiv(10 ** powDecimals_, weight), weight); // pow decimals
    }

    function _getWeightedPoolRawValue(
        address[] memory tokens_,
        uint256[] memory weights_,
        uint8 poolDecimals_,
        uint8 outputDecimals_,
        uint8 powDecimals_,
        bytes32 poolId_
    ) internal view returns (uint256) {
        uint256 len = tokens_.length;

        uint256 poolValue = 0; // pow decimals
        // PRICEv2 PRICE = _PRICE();
        for (uint256 i; i < len; ) {
            uint256 currentValue = _getTokenValueInWeightedPool(tokens_[i], weights_[i], poolDecimals_, outputDecimals_, powDecimals_, poolId_);

            if (poolValue == 0) {
                poolValue = currentValue;
            } else {
                poolValue = poolValue.mulDiv(currentValue, 10 ** powDecimals_);
            }

            unchecked {
                ++i;
            }
        }

        return poolValue;
    }

    // ========== POOL TOKEN PRICE FUNCTIONS ========== //

    /// @notice Determines the unit price of the pool token for the Balancer weighted pool specified in {params_}.
    ///
    /// @dev To avoid price manipulation, this function calculated the pool token price in the manner recommended by
    /// Balancer at https://docs.balancer.fi/concepts/advanced/valuing-bpt.html#on-chain-price-evaluation :
    /// - Obtains the prices of all tokens in the pool from PRICE (usually using price feeds)
    /// - Applies a guard to protect against re-entrancy attacks on the Balancer pool
    ///
    /// This function will revert if:
    /// - The scale of outputDecimals_ or the pool's decimals is too high
    /// - The pool is mis-configured
    /// - If the pool is not a weighted pool
    ///
    /// @param asset_ the token to determine the price of (unused)
    /// @param outputDecimals_ the number of output decimals
    /// @param params_ Balancer pool parameters of type BalancerWeightedPoolParams
    /// @return uint256 Price in the scale of outputDecimals_
    function getWeightedPoolTokenPrice(address asset_, uint8 outputDecimals_, bytes calldata params_) external returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_);

        address[] memory tokens;
        uint256[] memory weights;
        uint256 poolMultiplier; // outputDecimals_
        uint8 poolDecimals;
        bytes32 poolId;
        {
            // Decode params
            BalancerWeightedPoolParams memory params = abi.decode(
                params_,
                (BalancerWeightedPoolParams)
            );
            if (address(params.pool) == address(0)) revert Balancer_PoolTypeNotWeighted(bytes32(0));

            IWeightedPool pool = IWeightedPool(params.pool);

            // Get pool ID
            poolId = pool.getPoolId();

            // Prevent re-entrancy attacks
            VaultReentrancyLib.ensureNotInVaultContext(balVault);

            // Get tokens in the pool from vault
            (address[] memory tokens_, , ) = balVault.getPoolTokens(poolId);
            tokens = tokens_;

            // Get weights
            try pool.getNormalizedWeights() returns (uint256[] memory weights_) {
                weights = weights_;
            } catch {
                // Exit if it is not a weighted pool
                revert Balancer_PoolTypeNotWeighted(poolId);
            }

            uint256 poolSupply_ = pool.totalSupply(); // pool decimals
            if (poolSupply_ == 0) revert Balancer_PoolSupplyInvalid(poolId);

            uint256 poolInvariant_ = pool.getInvariant(); // pool decimals

            poolDecimals = pool.decimals();
            if (poolDecimals > BASE_10_MAX_EXPONENT)
                revert Balancer_PoolDecimalsOutOfBounds(poolId);

            // The invariant and supply have the same scale, so we can shift the result into outputDecimals_
            poolMultiplier = poolInvariant_.mulDiv(10 ** outputDecimals_, poolSupply_);
        }

        // Iterate through tokens, get prices, and determine pool value
        uint256 len = tokens.length;
        if (weights.length != len) revert Balancer_PoolTokenWeightMismatch(poolId);

        // Scale: powDecimals
        uint8 powDecimals = 18;
        uint256 poolValue = _getWeightedPoolRawValue(tokens, weights, poolDecimals, outputDecimals_, powDecimals, poolId);
        // No coins or balances
        if (poolValue == 0) revert Balancer_PoolTokensInvalid(poolId);

        // Calculate price of pool token in terms of outputDecimals_
        uint256 poolTokenPrice = poolMultiplier.mulDiv(poolValue, 10 ** powDecimals);

        return poolTokenPrice;
    }

    /// @notice Determines the unit price of the pool token for the Balancer stable pool specified in {params_}.
    ///
    /// @dev To avoid price manipulation, this function calculated the pool token price in the following manner:
    /// - Applies a guard to protect against re-entrancy attacks on the Balancer pool
    /// - Utilises the formula suggested by Balancer: https://docs.balancer.fi/concepts/advanced/valuing-bpt.html#on-chain-price-evaluation
    ///
    /// This function will revert if:
    /// - The scale of outputDecimals_ or the pool's decimals is too high
    /// - The pool is mis-configured
    /// - The pool is not a stable pool
    ///
    /// @param asset_ the token to determine the price of (unused)
    /// @param outputDecimals_ the number of output decimals
    /// @param params_ Balancer pool parameters of type BalancerStablePoolParams
    /// @return uint256 Price in the scale of outputDecimals_
    function getStablePoolTokenPrice(address asset_, uint8 outputDecimals_, bytes calldata params_) external returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_);

        address[] memory tokens;
        uint256 poolRate; // pool decimals
        uint8 poolDecimals;
        bytes32 poolId;
        {
            // Decode params
            BalancerStablePoolParams memory params = abi.decode(
                params_,
                (BalancerStablePoolParams)
            );
            if (address(params.pool) == address(0)) revert Balancer_PoolTypeNotStable(bytes32(0));

            IStablePool pool = IStablePool(params.pool);

            // Get pool ID
            poolId = pool.getPoolId();

            // Prevent re-entrancy attacks
            VaultReentrancyLib.ensureNotInVaultContext(balVault);

            // Get tokens in the pool from vault
            (address[] memory tokens_, , ) = balVault.getPoolTokens(poolId);
            tokens = tokens_;

            // Get rate
            try pool.getRate() returns (uint256 rate_) {
                if (rate_ == 0) {
                    revert Balancer_PoolStableRateInvalid(poolId);
                }

                poolRate = rate_;
            } catch {
                // Exit if it is not a stable pool
                revert Balancer_PoolTypeNotStable(poolId);
            }

            poolDecimals = pool.decimals();
            if (poolDecimals > BASE_10_MAX_EXPONENT)
                revert Balancer_PoolDecimalsOutOfBounds(poolId);
        }

        // Get the base token price
        PRICEv2 PRICE = _PRICE();
        uint256 len = tokens.length;
        if (len == 0) revert Balancer_PoolTokensInvalid(poolId);

        uint256 baseTokenPrice; // outputDecimals_
        {
            address token = tokens[0];
            if (token == address(0)) revert Balancer_PoolTokensInvalid(poolId);

            /**
             * PRICE will revert if there is an issue resolving the price, or if it is 0.
             *
             * As the value of the pool token is reliant on the price of every underlying token,
             * the revert from PRICE is not caught.
             */
            (uint256 price_, ) = PRICE.getPrice(tokens[0], PRICEv2.Variant.CURRENT); // outputDecimals_
            baseTokenPrice = price_;
        }

        uint256 poolValue = poolRate.mulDiv(baseTokenPrice, 10 ** poolDecimals); // outputDecimals_

        return poolValue;
    }

    // ========== TOKEN SPOT PRICE FUNCTIONS ========== //

    /// @notice Determines the spot price of the specified token from the Balancer pool specified in {params_}.
    ///
    /// @dev It does this by:
    /// - Determining the price and reserves of the token paired with {lookupToken_}
    /// - Determining the corresponding price of {lookupToken_}
    ///
    /// Will revert upon the following:
    /// - If outputDecimals_ or the pool's decimals are too high
    /// - If the transaction involves reentrancy on the Balancer pool
    /// - If the pool is not a weighted pool
    ///
    /// NOTE: as the reserves of Balancer pools can be manipulated using flash loans, the spot price
    /// can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_ the token to determine the price of
    /// @param outputDecimals_ the number of output decimals
    /// @param params_ Balancer pool parameters of type BalancerParams
    /// @return uint256 Price in the scale of outputDecimals_
    function getTokenPriceFromWeightedPool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        IWeightedPool pool;
        {
            BalancerWeightedPoolParams memory params = abi.decode(
                params_,
                (BalancerWeightedPoolParams)
            );
            if (address(params.pool) == address(0)) revert Balancer_PoolTypeNotWeighted(bytes32(0));

            pool = IWeightedPool(params.pool);
        }

        uint256 lookupTokenIndex = type(uint256).max;
        uint256 destinationTokenIndex = type(uint256).max;
        uint256 destinationTokenPrice; // Scale: outputDecimals_
        bytes32 poolId;
        {
            // Prevent re-entrancy attacks
            VaultReentrancyLib.ensureNotInVaultContext(balVault);

            // Get tokens in the pool from vault
            poolId = pool.getPoolId();
            (address[] memory tokens_, uint256[] memory balances_, ) = balVault.getPoolTokens(
                poolId
            );

            {
                uint8 poolDecimals = pool.decimals();
                if (poolDecimals > BASE_10_MAX_EXPONENT)
                    revert Balancer_PoolDecimalsOutOfBounds(poolId);
            }

            // Check that the pool is not mis-configured
            {
                uint256[] memory weights;
                {
                    // Test if the weights function exists, otherwise revert
                    try pool.getNormalizedWeights() returns (uint256[] memory weights_) {
                        weights = weights_;
                    } catch (bytes memory) {
                        revert Balancer_PoolTypeNotWeighted(poolId);
                    }
                }

                if (!(tokens_.length == balances_.length && balances_.length == weights.length))
                    revert Balancer_PoolTokensInvalid(poolId);
            }

            // Determine the index of the lookup token and an appropriate destination token
            {
                uint256 len = tokens_.length;
                address destinationToken;
                for (uint256 i; i < len; i++) {
                    // If address is zero, complain
                    if (tokens_[i] == address(0)) revert Balancer_PoolTokensInvalid(poolId);

                    // If lookup token
                    if (lookupToken_ == tokens_[i]) {
                        lookupTokenIndex = i;
                        continue;
                    }

                    // Don't set the destination token again
                    if (destinationTokenIndex != type(uint256).max) continue;

                    /**
                     * PRICE will revert if there is an issue resolving the price, or if it is 0.
                     *
                     * We catch this, so that other candidate tokens can be tested.
                     */
                    try _PRICE().getPrice(tokens_[i], PRICEv2.Variant.CURRENT) returns (
                        uint256 currentPrice,
                        uint48 timestamp
                    ) {
                        destinationTokenIndex = i;
                        destinationTokenPrice = currentPrice;
                        destinationToken = tokens_[i];
                    } catch (bytes memory) {
                        continue;
                    }
                }

                // Lookup token not found
                if (lookupTokenIndex == type(uint256).max)
                    revert Balancer_LookupTokenNotFound(lookupToken_);

                // No destination token found with a price
                if (
                    destinationTokenPrice == 0 ||
                    destinationTokenIndex == type(uint256).max ||
                    destinationToken == address(0)
                ) revert Balancer_PriceNotFound(lookupToken_);
            }
        }

        // Calculate the rate of the lookup token
        uint256 lookupTokenUsdPrice;
        {
            // Weightings
            // Scale: outputDecimals_
            uint256 lookupTokenWeighting = _getTokenBalanceWeighting(poolId, pool, lookupTokenIndex, outputDecimals_);
            uint256 destinationTokenWeighting = _getTokenBalanceWeighting(poolId, pool, destinationTokenIndex, outputDecimals_);

            // Get the lookupToken in terms of the destinationToken
            // Source: https://docs.balancer.fi/reference/math/weighted-math.html#spot-price
            lookupTokenUsdPrice = destinationTokenWeighting.mulDiv(
                    destinationTokenPrice,
                    lookupTokenWeighting
                );
        }

        return lookupTokenUsdPrice;
    }

    /// @notice Determines the spot price of the specified token from the Balancer pool specified in {params_}.
    ///
    /// @dev It does this by:
    /// - Using the Balancer StableMath library to determine the quantity of {lookupToken_} returned for 1 of
    /// any token paired with {lookupToken_} for which a price is available
    ///
    /// Will revert upon the following:
    /// - If the transaction involves reentrancy on the Balancer pool
    /// - If the pool is not a stable pool
    ///
    /// NOTE: as the reserves of Balancer pools can be manipulated using flash loans, the spot price
    /// can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_ the token to determine the price of
    /// @param outputDecimals_ the number of output decimals
    /// @param params_ Balancer pool parameters of type BalancerParams
    /// @return uint256 Price in the scale of outputDecimals_
    function getTokenPriceFromStablePool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_);

        // Decode params
        IStablePool pool;
        {
            BalancerStablePoolParams memory params = abi.decode(
                params_,
                (BalancerStablePoolParams)
            );
            if (address(params.pool) == address(0)) revert Balancer_PoolTypeNotStable(bytes32(0));

            pool = IStablePool(params.pool);
        }

        uint256 lookupTokenIndex = type(uint256).max;
        uint256 destinationTokenIndex = type(uint256).max;
        uint256 destinationTokenPrice; // Scale: outputDecimals_
        address destinationToken;
        bytes32 poolId;
        {
            // Prevent re-entrancy attacks
            VaultReentrancyLib.ensureNotInVaultContext(balVault);

            // Get tokens in the pool from vault
            poolId = pool.getPoolId();
            (address[] memory tokens_, uint256[] memory balances_, ) = balVault.getPoolTokens(
                poolId
            );

            if (!(tokens_.length == balances_.length)) revert Balancer_PoolTokensInvalid(poolId);

            // Determine the index of the lookup token and an appropriate destination token
            uint256 len = tokens_.length;
            for (uint256 i; i < len; i++) {
                // If address is zero, complain
                if (tokens_[i] == address(0)) revert Balancer_PoolTokensInvalid(poolId);

                // If lookup token
                if (lookupToken_ == tokens_[i]) {
                    lookupTokenIndex = i;
                    continue;
                }

                // Don't set the destination token again
                if (destinationTokenIndex != type(uint256).max) continue;

                /**
                 * PRICE will revert if there is an issue resolving the price, or if it is 0.
                 *
                 * We catch this, so that other candidate tokens can be tested.
                 */
                try _PRICE().getPrice(tokens_[i], PRICEv2.Variant.CURRENT) returns (
                    uint256 currentPrice,
                    uint48 timestamp
                ) {
                    destinationTokenIndex = i;
                    destinationTokenPrice = currentPrice;
                    destinationToken = tokens_[i];
                } catch (bytes memory) {
                    continue;
                }
            }

            // Lookup token not found
            if (lookupTokenIndex == type(uint256).max)
                revert Balancer_LookupTokenNotFound(lookupToken_);

            // No destination token found with a price
            if (
                destinationTokenPrice == 0 ||
                destinationTokenIndex == type(uint256).max ||
                destinationToken == address(0)
            ) revert Balancer_PriceNotFound(lookupToken_);
        }

        uint256 lookupTokenPrice;
        {
            (, uint256[] memory balances_, ) = balVault.getPoolTokens(pool.getPoolId());

            try pool.getLastInvariant() returns (uint256 invariant, uint256 ampFactor) {
                // Calculate the quantity of lookupTokens returned by swapping 1 destinationToken
                uint256 lookupTokensPerDestinationToken = StableMath._calcOutGivenIn(
                    ampFactor,
                    balances_,
                    destinationTokenIndex,
                    lookupTokenIndex,
                    1e18,
                    invariant
                );

                // Price per destinationToken / quantity
                lookupTokenPrice = destinationTokenPrice.mulDiv(
                    1e18,
                    lookupTokensPerDestinationToken
                );
            } catch (bytes memory) {
                // Revert if the pool is not a stable pool, and does not have the required function
                revert Balancer_PoolTypeNotStable(poolId);
            }
        }

        return lookupTokenPrice;
    }
}
