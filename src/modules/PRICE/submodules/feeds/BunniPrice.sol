// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Bophades modules
import "modules/PRICE/PRICE.v2.sol";

// Bunni contracts
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

// Standard libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {Deviation} from "libraries/Deviation.sol";
import {UniswapV3OracleHelper} from "libraries/UniswapV3/Oracle.sol";
import {BunniHelper} from "libraries/UniswapV3/BunniHelper.sol";

/// @title      BunniPrice
/// @author     0xJem
/// @notice     A PRICE submodule that provides data on OHM deployed into Uniswap V3 pools that
/// @notice     are managed by the BunniManager policy and its associated BunniHub.
contract BunniPrice is PriceSubmodule {
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice     Struct containing parameters for the submodule
    struct BunniParams {
        address bunniLens;
        uint16 twapMaxDeviationsBps;
        uint32 twapObservationWindow;
    }

    // ========== ERRORS ========== //

    /// @notice             `bunniToken_` is not a valid BunniToken
    /// @param bunniToken_  The invalid token
    error BunniPrice_Params_InvalidBunniToken(address bunniToken_);

    /// @notice             `bunniLens_` is not a valid BunniLens
    /// @param bunniLens_   The invalid BunniLens
    error BunniPrice_Params_InvalidBunniLens(address bunniLens_);

    /// @notice                 The BunniHub does not match between the BunniToken and BunniLens
    /// @param bunniTokenHub_   The address of the BunniHub configured in the BunniToken
    /// @param bunniLensHub_    The address of the BunniHub configured in the BunniLens
    error BunniPrice_Params_HubMismatch(address bunniTokenHub_, address bunniLensHub_);

    /// @notice                   The calculated pool price deviates from the TWAP by more than the maximum deviation.
    ///
    /// @param pool_              The address of the pool
    /// @param baseInQuoteTWAP_   The calculated TWAP price in terms of the quote token
    /// @param baseInQuotePrice_  The calculated current price in terms of the quote token
    error BunniPrice_PriceMismatch(
        address pool_,
        uint256 baseInQuoteTWAP_,
        uint256 baseInQuotePrice_
    );

    // ========== STATE VARIABLES ========== //

    uint16 internal constant TWAP_MAX_DEVIATION_BASE = 10_000; // 100%

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    /// @inheritdoc     Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.BNI");
    }

    /// @inheritdoc     Submodule
    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== TOKEN PRICE FUNCTIONS ========== //

    /// @notice                 Determines the price of `bunniToken_` (representing a Uniswap V3 pool) in USD
    /// @dev                    This function performs the following:
    /// @dev                    - Decodes the parameters
    /// @dev                    - Check that the token is a valid BunniToken
    /// @dev                    - Check that the lens is a valid BunniLens
    /// @dev                    - Check that the token and lens have the same BunniHub address
    /// @dev                    - Fetches the reserves contained in the Uniswap V3 position
    /// @dev                    - Determines the value of each reserve token in USD
    ///
    /// @dev                    This function accesses the reserves of the registered
    /// @dev                    Uniswap V3 pools, and can be susceptible to re-entrancy attacks.
    /// @dev                    The BunniLens contract used by this Submodule performs a re-entrancy check.
    ///
    /// @dev                    This function reverts if:
    /// @dev                    - The token is not a valid BunniToken
    /// @dev                    - The lens (from `params_`) is not a valid BunniLens
    /// @dev                    - The token and lens do not have the same BunniHub address
    /// @dev                    - The reserves of the pool deviate from the TWAP by more than the maximum deviation
    /// @dev                    - Any of the reserve assets are not defined as assets in PRICE
    ///
    /// @param bunniToken_      The address of the BunniToken contract
    /// @param outputDecimals_  The number of decimals to use for the output price
    /// @param params_          The encoded parameters for the function call
    function getBunniTokenPrice(
        address bunniToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        // Decode the parameters
        BunniParams memory params;
        {
            params = abi.decode(params_, (BunniParams));
            if (params.bunniLens == address(0)) {
                revert BunniPrice_Params_InvalidBunniLens(params.bunniLens);
            }

            // Check for invalid bunniToken_
            if (bunniToken_ == address(0)) {
                revert BunniPrice_Params_InvalidBunniToken(bunniToken_);
            }
        }

        // Validate the token
        BunniToken token = BunniToken(bunniToken_);
        BunniLens lens = BunniLens(params.bunniLens);
        {
            address tokenHub;
            try token.hub() returns (IBunniHub tokenHub_) {
                tokenHub = address(tokenHub_);
            } catch (bytes memory) {
                revert BunniPrice_Params_InvalidBunniToken(bunniToken_);
            }

            // Validate the lens
            address lensHub;
            try lens.hub() returns (IBunniHub lensHub_) {
                lensHub = address(lensHub_);
            } catch (bytes memory) {
                revert BunniPrice_Params_InvalidBunniLens(params.bunniLens);
            }

            // Check that the hub matches
            if (tokenHub != lensHub) {
                revert BunniPrice_Params_HubMismatch(tokenHub, lensHub);
            }
        }

        // Validate reserves
        _validateReserves(
            _getBunniKey(token),
            lens,
            params.twapMaxDeviationsBps,
            params.twapObservationWindow
        );

        // Fetch the reserves
        uint256 totalValue = _getTotalValue(token, lens, outputDecimals_);

        return totalValue;
    }

    // ========== INTERNAL FUNCTIONS ========== //

    /// @notice         Returns the BunniKey for the pool repesented by `token_` and the full-range ticks
    ///
    /// @param token_   The address of the BunniToken contract
    /// @return         The BunniKey for the pool
    function _getBunniKey(BunniToken token_) internal view returns (BunniKey memory) {
        return
            BunniKey({
                pool: token_.pool(),
                tickLower: token_.tickLower(),
                tickUpper: token_.tickUpper()
            });
    }

    /// @notice                 Fetches the reserves of a Uniswap V3 position
    ///
    /// @param token_           The address of the BunniToken contract
    /// @param lens_            The address of the BunniLens contract
    /// @param outputDecimals_  The number of decimals to use for the output price
    /// @return token0          The address of the first reserve token
    /// @return reserve0        The amount of the first reserve token (in `outputDecimals_`)
    /// @return token1          The address of the second reserve token
    /// @return reserve1        The amount of the second reserve token (in `outputDecimals_`)
    function _getBunniReserves(
        BunniToken token_,
        BunniLens lens_,
        uint8 outputDecimals_
    ) internal view returns (address token0, uint256 reserve0, address token1, uint256 reserve1) {
        BunniKey memory key = _getBunniKey(token_);
        (uint112 reserve0_, uint112 reserve1_) = lens_.getReserves(key);

        // Get the token addresses
        token0 = key.pool.token0();
        token1 = key.pool.token1();
        uint8 token0Decimals = ERC20(token0).decimals();
        uint8 token1Decimals = ERC20(token1).decimals();
        reserve0 = uint256(reserve0_).mulDiv(10 ** outputDecimals_, 10 ** token0Decimals);
        reserve1 = uint256(reserve1_).mulDiv(10 ** outputDecimals_, 10 ** token1Decimals);
    }

    /// @notice                 Determines the total value of the Uniswap V3 position represented by `token_`
    ///
    /// @param token_           The BunniToken representing the Uniswap V3 position
    /// @param lens_            The BunniLens to use for determining reserves
    /// @param outputDecimals_  The decimal scale to use
    /// @return                 The total value of the position in USD in the scale of `outputDecimals_`
    function _getTotalValue(
        BunniToken token_,
        BunniLens lens_,
        uint8 outputDecimals_
    ) internal view returns (uint256) {
        (address token0, uint256 reserve0, address token1, uint256 reserve1) = _getBunniReserves(
            token_,
            lens_,
            outputDecimals_
        );
        uint256 outputScale = 10 ** outputDecimals_;

        // Determine the value of each reserve token in USD
        uint256 totalValue;
        totalValue += _PRICE().getPrice(token0).mulDiv(reserve0, outputScale);
        totalValue += _PRICE().getPrice(token1).mulDiv(reserve1, outputScale);

        return totalValue;
    }

    /// @notice                         Validates that the reserves of the pool represented by `key_` are within
    /// @notice                         the maximum deviation from the pool's TWAP.
    ///
    /// @param key_                     The BunniKey for the pool
    /// @param lens_                    The BunniLens contract
    /// @param twapMaxDeviationBps_     The maximum deviation from the TWAP in basis points
    /// @param twapObservationWindow_   The TWAP observation window in seconds
    function _validateReserves(
        BunniKey memory key_,
        BunniLens lens_,
        uint16 twapMaxDeviationBps_,
        uint32 twapObservationWindow_
    ) internal view {
        uint256 reservesTokenRatio = BunniHelper.getReservesRatio(key_, lens_);
        uint256 twapTokenRatio = UniswapV3OracleHelper.getTWAPRatio(
            address(key_.pool),
            twapObservationWindow_
        );

        // Revert if the relative deviation is greater than the maximum.
        if (
            // `isDeviatingWithBpsCheck()` will revert if `deviationBps` is invalid.
            Deviation.isDeviatingWithBpsCheck(
                reservesTokenRatio,
                twapTokenRatio,
                twapMaxDeviationBps_,
                TWAP_MAX_DEVIATION_BASE
            )
        ) {
            revert BunniPrice_PriceMismatch(address(key_.pool), twapTokenRatio, reservesTokenRatio);
        }
    }
}
