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

/// @title      BalancerPoolTokenPrice
/// @notice     Provides prices related to Balancer pools
contract BalancerPoolTokenPrice is PriceSubmodule {
    using FullMath for uint256;

    /// @notice     Any token or pool with a decimal scale greater than this would result in an overflow
    uint8 internal constant BASE_10_MAX_EXPONENT = 50;

    /// @notice     Used when calculating the value of a token in a weighted pool
    uint8 internal constant WEIGHTED_POOL_POW_DECIMALS = 18;

    /// @notice             Parameters for a Balancer weighted pool
    /// @param pool         Address of the Balancer pool
    struct BalancerWeightedPoolParams {
        IWeightedPool pool;
    }

    /// @notice             Parameters for a Balancer stable pool
    /// @param pool         Address of the Balancer pool
    struct BalancerStablePoolParams {
        IStablePool pool;
    }

    // ========== ERRORS ========== //

    /// @notice             The number of decimals of the asset is greater than the maximum allowed
    /// @param asset_       The address of the asset
    /// @param decimals_    The number of decimals of the asset
    /// @param maxDecimals_ The maximum number of decimals allowed
    error Balancer_AssetDecimalsOutOfBounds(address asset_, uint8 decimals_, uint8 maxDecimals_);

    /// @notice             The provided token was not found in the Balancer pool
    /// @param poolId_      The id of the Balancer pool
    /// @param asset_       The address of the token
    error Balancer_LookupTokenNotFound(bytes32 poolId_, address asset_);

    /// @notice                 The desired number of output decimals is greater than the maximum allowed
    /// @param outputDecimals_  The desired number of output decimals
    /// @param maxDecimals_     The maximum number of decimals allowed
    error Balancer_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);

    /// @notice                 The number of decimals of the pool is greater than the maximum allowed
    /// @param poolId_          The id of the Balancer pool
    /// @param poolDecimals_    The number of decimals of the pool
    /// @param maxDecimals_     The maximum number of decimals allowed
    error Balancer_PoolDecimalsOutOfBounds(
        bytes32 poolId_,
        uint8 poolDecimals_,
        uint8 maxDecimals_
    );

    /// @notice             The stable rate returned by the pool is invalid
    /// @dev                This currently only occurs if the rate is 0
    /// @param poolId_      The id of the Balancer pool
    /// @param rate_        The stable rate returned by the pool
    error Balancer_PoolStableRateInvalid(bytes32 poolId_, uint256 rate_);

    /// @notice             The total supply returned by the pool is invalid
    /// @dev                This currently only occurs if the total supply is 0
    /// @param poolId_      The id of the Balancer pool
    /// @param supply_      The total supply returned by the pool
    error Balancer_PoolSupplyInvalid(bytes32 poolId_, uint256 supply_);

    /// @notice             A token in the pool is invalid
    /// @dev                This currently only occurs if the token address is 0
    /// @param poolId_      The id of the Balancer pool
    /// @param index_       The index of the token in the pool
    /// @param token_       The address of the token
    error Balancer_PoolTokenInvalid(bytes32 poolId_, uint256 index_, address token_);

    /// @notice             The value of the Balancer pool is zero
    /// @dev                This currently only occurs if the number of tokens is 0
    /// @param poolId_      The id of the Balancer pool
    error Balancer_PoolValueZero(bytes32 poolId_);

    /// @notice             There is a mismatch between the number of tokens and weights
    /// @dev                This is unlikely to occur, but is in place to be defensive
    /// @param poolId_      The id of the Balancer pool
    /// @param tokenCount_  The number of tokens in the Balancer pool
    /// @param weightCount_ The number of weights in the Balancer pool
    error Balancer_PoolTokenWeightMismatch(
        bytes32 poolId_,
        uint256 tokenCount_,
        uint256 weightCount_
    );

    /// @notice                 There is a mismatch between the number of tokens and balances
    /// @dev                    This is unlikely to occur, but is in place to be defensive
    /// @param poolId_          The id of the Balancer pool
    /// @param tokenCount_      The number of tokens in the Balancer pool
    /// @param balanceCount_    The number of balances in the Balancer pool
    error Balancer_PoolTokenBalanceMismatch(
        bytes32 poolId_,
        uint256 tokenCount_,
        uint256 balanceCount_
    );

    /// @notice                 There is a mismatch between the number of tokens, balances and weights
    /// @dev                    This is unlikely to occur, but is in place to be defensive
    /// @param poolId_          The id of the Balancer pool
    /// @param tokenCount_      The number of tokens in the Balancer pool
    /// @param balanceCount_    The number of balances in the Balancer pool
    /// @param weightCount_     The number of weights in the Balancer pool
    error Balancer_PoolTokenBalanceWeightMismatch(
        bytes32 poolId_,
        uint256 tokenCount_,
        uint256 balanceCount_,
        uint256 weightCount_
    );

    /// @notice             The pool is not a stable pool
    /// @param poolId_      The id of the Balancer pool
    error Balancer_PoolTypeNotStable(bytes32 poolId_);

    /// @notice             The pool is not a weighted pool
    /// @param poolId_      The id of the Balancer pool
    error Balancer_PoolTypeNotWeighted(bytes32 poolId_);

    /// @notice             A weight in the pool is invalid
    /// @dev                This currently only occurs if the weight is 0
    /// @param poolId_      The id of the Balancer pool
    /// @param index_       The index of the weight in the pool
    /// @param weight_       The value of the weight
    error Balancer_PoolWeightInvalid(bytes32 poolId_, uint256 index_, uint256 weight_);

    /// @notice             The price of a corresponding token could not be found
    /// @dev                This occurs if there are no asset definitions in PRICE
    ///                     for the other tokens in the Balancer pool, and hence
    ///                     the price of the lookup token cannot be determined
    /// @param poolId_      The id of the Balancer pool
    /// @param lookupToken_ The token to determine the price of
    error Balancer_PriceNotFound(bytes32 poolId_, address lookupToken_);

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

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice                     Converts `value_` from the ERC20 token's decimals to `outputDecimals_`
    ///
    /// @dev                        This function will revert if converting the token's decimals would result in an overflow.
    ///
    /// @param value_               Value in native ERC20 token decimals
    /// @param token_               The address of the ERC20 token
    /// @param outputDecimals_      The desired number of decimals
    /// @return                     Number in the scale of `outputDecimals_`
    function _convertERC20Decimals(
        uint256 value_,
        address token_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        uint8 tokenDecimals = ERC20(token_).decimals();
        if (tokenDecimals > BASE_10_MAX_EXPONENT)
            revert Balancer_AssetDecimalsOutOfBounds(token_, tokenDecimals, BASE_10_MAX_EXPONENT);

        return value_.mulDiv(10 ** outputDecimals_, 10 ** tokenDecimals);
    }

    /// @notice                     Obtains the balance of the token at index `tokenIndex_` in the pool
    ///
    /// @dev                        This function will revert if converting the token's balance would result in an overflow.
    ///
    ///                             As this function is accessing the balances of the pool, it is guarded by VaultReentrancyLib to
    ///                             prevent re-entrancy attacks.
    ///
    /// @param poolId_              id of the Balancer pool
    /// @param tokenIndex_          Index of the token in the Balancer pool
    /// @param outputDecimals_      The desired number of decimals
    /// @return                     Balance in the scale of `outputDecimals_`
    function _getTokenBalance(
        bytes32 poolId_,
        uint256 tokenIndex_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        // Prevent re-entrancy attacks
        VaultReentrancyLib.ensureNotInVaultContext(balVault);

        (address[] memory tokens_, uint256[] memory balances_, ) = balVault.getPoolTokens(poolId_);

        // Balances are in the scale of the ERC20 token, so adjust those to `outputDecimals_`
        return _convertERC20Decimals(balances_[tokenIndex_], tokens_[tokenIndex_], outputDecimals_);
    }

    /// @notice                     Obtains the balance/weight ratio of the token at index `index_` in the pool
    ///
    /// @dev                        This function will revert if converting the pool's decimals would result in an overflow.
    ///
    ///                             As this function is accessing the balances of the pool, it is guarded by VaultReentrancyLib to
    ///                             prevent re-entrancy attacks.
    ///
    /// @param poolId_              Id of the Balancer pool
    /// @param pool_                Balancer weighted pool
    /// @param index_               Index of the token in the Balancer pool
    /// @param outputDecimals_      The desired number of decimals
    /// @return                     Balance in the scale of `outputDecimals_`
    function _getTokenBalanceWeighting(
        bytes32 poolId_,
        IWeightedPool pool_,
        uint256 index_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        uint256 tokenBalance = _getTokenBalance(poolId_, index_, outputDecimals_);

        uint8 poolDecimals = pool_.decimals();
        uint256[] memory weights = pool_.getNormalizedWeights();
        uint256 tokenWeight = weights[index_].mulDiv(10 ** outputDecimals_, 10 ** poolDecimals);

        return tokenBalance.mulDiv(10 ** outputDecimals_, tokenWeight);
    }

    /// @notice                     Calculates the value of a token in a Balancer weighted pool
    ///
    /// @dev                        This function will revert if:
    ///                             - The provided token is address(0)
    ///                             - The provided weight is 0
    ///
    /// @param token_               Address of the token
    /// @param weight_              Weight of the token in the Balancer pool
    /// @param poolDecimals_        The number of decimals of the Balancer pool
    /// @param outputDecimals_      The desired number of decimals
    /// @param poolId_              id of the Balancer pool
    /// @param index_               Index of the token in the Balancer pool
    /// @return                     Value in the scale of `outputDecimals_`
    function _getTokenValueInWeightedPool(
        address token_,
        uint256 weight_,
        uint8 poolDecimals_,
        uint8 outputDecimals_,
        bytes32 poolId_,
        uint256 index_
    ) internal view returns (uint256) {
        if (token_ == address(0)) revert Balancer_PoolTokenInvalid(poolId_, index_, token_);
        if (weight_ == 0) revert Balancer_PoolWeightInvalid(poolId_, index_, weight_);

        uint256 price; // Scale: `WEIGHTED_POOL_POW_DECIMALS`
        {
            /**
             * PRICE will revert if there is an issue resolving the price, or if it is 0.
             *
             * As the value of the pool token is reliant on the price of every underlying token,
             * the revert from PRICE is not caught.
             */
            (uint256 price_, ) = _PRICE().getPrice(token_, PRICEv2.Variant.CURRENT); // Scale: `outputDecimals_`

            price = price_.mulDiv(10 ** WEIGHTED_POOL_POW_DECIMALS, 10 ** outputDecimals_);
        }

        // Scale: `WEIGHTED_POOL_POW_DECIMALS`
        uint256 weight = weight_.mulDiv(10 ** WEIGHTED_POOL_POW_DECIMALS, 10 ** poolDecimals_);

        // All inputs to pow need to be in the scale of WEIGHTED_POOL_POW_DECIMALS, so adjust for that
        uint256 value = LogExpMath.pow(
            price.mulDiv(10 ** WEIGHTED_POOL_POW_DECIMALS, weight),
            weight
        ); // Scale: `WEIGHTED_POOL_POW_DECIMALS`

        // Adjust for `outputDecimals_`
        return value.mulDiv(10 ** outputDecimals_, 10 ** WEIGHTED_POOL_POW_DECIMALS);
    }

    /// @notice                     Calculates the value of a Balancer weighted pool
    ///
    /// @dev                        This function calculates the value of each token and returns the sum.
    ///
    /// @param tokens_              Array of tokens in the Balancer pool
    /// @param weights_             Array of weights of the tokens in the Balancer pool
    /// @param poolDecimals_        The number of decimals of the Balancer pool
    /// @param outputDecimals_      The desired number of decimals
    /// @return                     Value in the scale of `outputDecimals_`
    function _getWeightedPoolRawValue(
        address[] memory tokens_,
        uint256[] memory weights_,
        uint8 poolDecimals_,
        uint8 outputDecimals_,
        bytes32 poolId_
    ) internal view returns (uint256) {
        uint256 len = tokens_.length;

        uint256 poolValue = 0; // Scale: `outputDecimals_`
        for (uint256 i; i < len; ) {
            uint256 currentValue = _getTokenValueInWeightedPool(
                tokens_[i],
                weights_[i],
                poolDecimals_,
                outputDecimals_,
                poolId_,
                i
            );

            if (poolValue == 0) {
                poolValue = currentValue;
            } else {
                poolValue = poolValue.mulDiv(currentValue, 10 ** outputDecimals_);
            }

            unchecked {
                ++i;
            }
        }

        return poolValue;
    }

    // ========== POOL TOKEN PRICE FUNCTIONS ========== //

    /// @notice                 Determines the unit price of the pool token for the Balancer weighted pool specified in `params_`.
    ///
    /// @dev                    To avoid price manipulation, this function calculated the pool token price in the manner recommended by
    ///                         Balancer at https://docs.balancer.fi/concepts/advanced/valuing-bpt.html#on-chain-price-evaluation :
    ///                         - Obtains the prices of all tokens in the pool from PRICE (usually using price feeds)
    ///                         - Applies a guard to protect against re-entrancy attacks on the Balancer pool
    ///
    ///                         This function will revert if:
    ///                         - The scale of `outputDecimals_` or the pool's decimals is too high
    ///                         - The pool is mis-configured
    ///                         - If the pool is not a weighted pool
    ///
    /// @param asset_           Unused
    /// @param outputDecimals_  The number of output decimals
    /// @param params_          Balancer pool parameters of type `BalancerWeightedPoolParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getWeightedPoolTokenPrice(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

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
            if (poolSupply_ == 0) revert Balancer_PoolSupplyInvalid(poolId, 0);

            uint256 poolInvariant_ = pool.getInvariant(); // pool decimals

            poolDecimals = pool.decimals();
            if (poolDecimals > BASE_10_MAX_EXPONENT)
                revert Balancer_PoolDecimalsOutOfBounds(poolId, poolDecimals, BASE_10_MAX_EXPONENT);

            // The invariant and supply have the same scale, so we can shift the result into outputDecimals_
            poolMultiplier = poolInvariant_.mulDiv(10 ** outputDecimals_, poolSupply_);
        }

        // Iterate through tokens, get prices, and determine pool value
        uint256 len = tokens.length;
        if (weights.length != len)
            revert Balancer_PoolTokenWeightMismatch(poolId, len, weights.length);

        uint256 poolValue = _getWeightedPoolRawValue(
            tokens,
            weights,
            poolDecimals,
            outputDecimals_,
            poolId
        );
        // No coins or balances
        if (poolValue == 0) revert Balancer_PoolValueZero(poolId);

        // Calculate price of pool token in terms of outputDecimals_
        uint256 poolTokenPrice = poolMultiplier.mulDiv(poolValue, 10 ** outputDecimals_);

        return poolTokenPrice;
    }

    /// @notice                 Determines the unit price of the pool token for the Balancer stable pool specified in `params_`.
    ///
    /// @dev                    To avoid price manipulation, this function calculated the pool token price in the following manner:
    ///                         - Applies a guard to protect against re-entrancy attacks on the Balancer pool
    ///                         - Utilises the formula suggested by Balancer: https://docs.balancer.fi/concepts/advanced/valuing-bpt.html#on-chain-price-evaluation
    ///
    ///                         This function will revert if:
    ///                         - The scale of `outputDecimals_` or the pool's decimals is too high
    ///                         - The pool is mis-configured
    ///                         - The pool is not a stable pool
    ///
    /// @param asset_           Unused
    /// @param outputDecimals_  The number of output decimals
    /// @param params_          Balancer pool parameters of type `BalancerStablePoolParams`
    /// @return                 Price in the scale of outputDecimals_
    function getStablePoolTokenPrice(
        address asset_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

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
                    revert Balancer_PoolStableRateInvalid(poolId, 0);
                }

                poolRate = rate_;
            } catch {
                // Exit if it is not a stable pool
                revert Balancer_PoolTypeNotStable(poolId);
            }

            poolDecimals = pool.decimals();
            if (poolDecimals > BASE_10_MAX_EXPONENT)
                revert Balancer_PoolDecimalsOutOfBounds(poolId, poolDecimals, BASE_10_MAX_EXPONENT);
        }

        // Get the base token price
        uint256 len = tokens.length;
        if (len == 0) revert Balancer_PoolValueZero(poolId);

        uint256 baseTokenPrice; // outputDecimals_
        {
            address token = tokens[0];
            if (token == address(0)) revert Balancer_PoolTokenInvalid(poolId, 0, token);

            /**
             * PRICE will revert if there is an issue resolving the price, or if it is 0.
             *
             * As the value of the pool token is reliant on the price of every underlying token,
             * the revert from PRICE is not caught.
             */
            (uint256 price_, ) = _PRICE().getPrice(token, PRICEv2.Variant.CURRENT); // outputDecimals_
            baseTokenPrice = price_;
        }

        uint256 poolValue = poolRate.mulDiv(baseTokenPrice, 10 ** poolDecimals); // outputDecimals_

        return poolValue;
    }

    // ========== TOKEN SPOT PRICE FUNCTIONS ========== //

    /// @notice                 Determines the spot price of the specified token from the Balancer pool specified in `params_`.
    ///
    /// @dev                    It does this by:
    ///                         - Determining the price and reserves of the token paired with `lookupToken_`
    ///                         - Determining the corresponding price of `lookupToken_`
    ///
    ///                         Will revert upon the following:
    ///                         - If `outputDecimals_` or the pool's decimals are too high
    ///                         - If the transaction involves reentrancy on the Balancer pool
    ///                         - If the pool is not a weighted pool
    ///
    ///                         NOTE: as the reserves of Balancer pools can be manipulated using flash loans, the spot price
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The number of output decimals
    /// @param params_          Balancer pool parameters of type `BalancerWeightedPoolParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getTokenPriceFromWeightedPool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

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
            address[] memory tokens;
            {
                (address[] memory tokens_, uint256[] memory balances_, ) = balVault.getPoolTokens(
                    poolId
                );
                tokens = tokens_;

                uint8 poolDecimals = pool.decimals();
                if (poolDecimals > BASE_10_MAX_EXPONENT)
                    revert Balancer_PoolDecimalsOutOfBounds(
                        poolId,
                        poolDecimals,
                        BASE_10_MAX_EXPONENT
                    );

                // Check that the pool is not mis-configured
                uint256[] memory weights;
                // Test if the weights function exists, otherwise revert
                try pool.getNormalizedWeights() returns (uint256[] memory weights_) {
                    weights = weights_;
                } catch (bytes memory) {
                    revert Balancer_PoolTypeNotWeighted(poolId);
                }

                if (!(tokens.length == balances_.length && balances_.length == weights.length))
                    revert Balancer_PoolTokenBalanceWeightMismatch(
                        poolId,
                        tokens.length,
                        balances_.length,
                        weights.length
                    );
            }

            // Determine the index of the lookup token and an appropriate destination token
            {
                uint256 tokensLen = tokens.length;
                address destinationToken;
                for (uint256 i; i < tokensLen; i++) {
                    // If address is zero, complain
                    address currentToken = tokens[i];
                    if (currentToken == address(0))
                        revert Balancer_PoolTokenInvalid(poolId, i, currentToken);

                    // If lookup token
                    if (lookupToken_ == currentToken) {
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
                    try _PRICE().getPrice(currentToken, PRICEv2.Variant.CURRENT) returns (
                        uint256 currentPrice,
                        uint48 timestamp
                    ) {
                        destinationTokenIndex = i;
                        destinationTokenPrice = currentPrice;
                        destinationToken = currentToken;
                    } catch (bytes memory) {
                        continue;
                    }
                }

                // Lookup token not found
                if (lookupTokenIndex == type(uint256).max)
                    revert Balancer_LookupTokenNotFound(poolId, lookupToken_);

                // No destination token found with a price
                if (
                    destinationTokenPrice == 0 ||
                    destinationTokenIndex == type(uint256).max ||
                    destinationToken == address(0)
                ) revert Balancer_PriceNotFound(poolId, lookupToken_);
            }
        }

        // Calculate the rate of the lookup token
        uint256 lookupTokenUsdPrice;
        {
            // Weightings
            // Scale: outputDecimals_
            uint256 lookupTokenWeighting = _getTokenBalanceWeighting(
                poolId,
                pool,
                lookupTokenIndex,
                outputDecimals_
            );
            uint256 destinationTokenWeighting = _getTokenBalanceWeighting(
                poolId,
                pool,
                destinationTokenIndex,
                outputDecimals_
            );

            // Get the lookupToken in terms of the destinationToken
            // Source: https://docs.balancer.fi/reference/math/weighted-math.html#spot-price
            lookupTokenUsdPrice = destinationTokenWeighting.mulDiv(
                destinationTokenPrice,
                lookupTokenWeighting
            );
        }

        return lookupTokenUsdPrice;
    }

    /// @notice                 Determines the spot price of the specified token from the Balancer pool specified in `params_`.
    ///
    /// @dev                    It does this by:
    ///                         - Using the Balancer StableMath library to determine the quantity of `lookupToken_` returned for 1 of
    ///                         any token paired with `lookupToken_` for which a price is available
    ///
    ///                         Will revert upon the following:
    ///                         - If the transaction involves reentrancy on the Balancer pool
    ///                         - If the pool is not a stable pool
    ///
    ///                         NOTE: as the reserves of Balancer pools can be manipulated using flash loans, the spot price
    ///                         can also be manipulated. Price feeds are a preferred source of price data. Use this function with caution.
    ///
    /// @param lookupToken_     The token to determine the price of
    /// @param outputDecimals_  The number of output decimals
    /// @param params_          Balancer pool parameters of type `BalancerStablePoolParams`
    /// @return                 Price in the scale of `outputDecimals_`
    function getTokenPriceFromStablePool(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Prevent overflow
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert Balancer_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

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
            address[] memory tokens;
            {
                (address[] memory tokens_, uint256[] memory balances_, ) = balVault.getPoolTokens(
                    poolId
                );
                tokens = tokens_;

                uint256 tokensLen = tokens.length;
                uint256 balancesLen = balances_.length;
                if (!(tokensLen == balancesLen))
                    revert Balancer_PoolTokenBalanceMismatch(poolId, tokensLen, balancesLen);
            }

            // Determine the index of the lookup token and an appropriate destination token
            for (uint256 i; i < tokens.length; i++) {
                // If address is zero, complain
                address currentToken = tokens[i];
                if (currentToken == address(0))
                    revert Balancer_PoolTokenInvalid(poolId, i, currentToken);

                // If lookup token
                if (lookupToken_ == currentToken) {
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
                try _PRICE().getPrice(currentToken, PRICEv2.Variant.CURRENT) returns (
                    uint256 currentPrice,
                    uint48 timestamp
                ) {
                    destinationTokenIndex = i;
                    destinationTokenPrice = currentPrice;
                    destinationToken = currentToken;
                } catch (bytes memory) {
                    continue;
                }
            }

            // Lookup token not found
            if (lookupTokenIndex == type(uint256).max)
                revert Balancer_LookupTokenNotFound(poolId, lookupToken_);

            // No destination token found with a price
            if (
                destinationTokenPrice == 0 ||
                destinationTokenIndex == type(uint256).max ||
                destinationToken == address(0)
            ) revert Balancer_PriceNotFound(poolId, lookupToken_);
        }

        uint256 lookupTokenPrice;
        {
            (, uint256[] memory balances_, ) = balVault.getPoolTokens(poolId);

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
