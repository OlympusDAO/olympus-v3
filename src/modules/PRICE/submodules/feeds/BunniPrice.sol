// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/PRICE/PRICE.v2.sol";

import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FullMath} from "libraries/FullMath.sol";

/// @title      BunniPrice
/// @notice     A PRICE submodule that provides data on OHM deployed into Uniswap V3 pools that
///             are managed by the BunniManager policy and its associated BunniHub.
contract BunniPrice is PriceSubmodule {
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    struct BunniParams {
        address bunniLens;
    }

    // ========== ERRORS ========== //

    error BunniPrice_Params_InvalidBunniToken(address bunniToken_);

    error BunniPrice_Params_InvalidBunniLens(address bunniLens_);

    error BunniPrice_Params_HubMismatch(address bunniTokenHub_, address bunniLensHub_);

    // ========== STATE VARIABLES ========== //

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_) Submodule(parent_) {}

    // ========== SUBMODULE FUNCTIONS =========== //

    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("PRICE.BNI");
    }

    function VERSION() public pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== TOKEN PRICE FUNCTIONS ========== //

    /// @notice                 Determines the price of `bunniToken_` (representing a Uniswap V3 pool) in USD
    /// @dev                    This function performs the following:
    ///                         - Decodes the parameters
    ///                         - Check that the token is a valid BunniToken
    ///                         - Check that the lens is a valid BunniLens
    ///                         - Check that the token and lens have the same BunniHub address
    ///                         - Fetches the reserves contained in the Uniswap V3 position
    ///                         - Determines the value of each reserve token in USD
    ///
    ///                         This function reverts if:
    ///                         - The token is not a valid BunniToken
    ///                         - The lens (from `params_`) is not a valid BunniLens
    ///                         - The token and lens do not have the same BunniHub address
    ///                         - Any of the reserve assets are not defined as assets in PRICE
    ///
    /// @param bunniToken_      The address of the BunniToken contract
    /// @param outputDecimals_  The number of decimals to use for the output price
    /// @param params_          The encoded parameters for the function call
    function getBunniTokenPrice(address bunniToken_, uint8 outputDecimals_, bytes calldata params_) external view returns (uint256) {
        // Decode the parameters
        address bunniLens;
        {
            BunniParams memory params = abi.decode(params_, (BunniParams));
            if (params.bunniLens == address(0)) {
                revert BunniPrice_Params_InvalidBunniLens(params.bunniLens);
            }

            bunniLens = params.bunniLens;

            // Check for invalid bunniToken_
            if (bunniToken_ == address(0)) {
                revert BunniPrice_Params_InvalidBunniToken(bunniToken_);
            }
        }

        // Validate the token
        BunniToken token = BunniToken(bunniToken_);
        BunniLens lens = BunniLens(bunniLens);
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
                revert BunniPrice_Params_InvalidBunniLens(bunniLens);
            }

            // Check that the hub matches
            if (tokenHub != lensHub) {
                revert BunniPrice_Params_HubMismatch(tokenHub, lensHub);
            }
        }

        // Fetch the reserves
        uint256 totalValue = _getTotalValue(token, lens, outputDecimals_);

        return totalValue;
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _getBunniKey(BunniToken token_) internal view returns (BunniKey memory) {
        return BunniKey({
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
    function _getBunniReserves(BunniToken token_, BunniLens lens_, uint8 outputDecimals_) internal view returns (address token0, uint256 reserve0, address token1, uint256 reserve1) {
        BunniKey memory key = _getBunniKey(token_);
        (uint112 reserve0_, uint112 reserve1_) = lens_.getReserves(key);

        // Get the token addresses
        token0 = key.pool.token0();
        token1 = key.pool.token1();
        uint8 token0Decimals = ERC20(token0).decimals();
        uint8 token1Decimals = ERC20(token1).decimals();
        reserve0 = uint256(reserve0_).mulDiv(10**outputDecimals_, 10**token0Decimals);
        reserve1 = uint256(reserve1_).mulDiv(10**outputDecimals_, 10**token1Decimals);
    }

    function _getTotalValue(BunniToken token_, BunniLens lens_, uint8 outputDecimals_) internal view returns (uint256) {
        (address token0, uint256 reserve0, address token1, uint256 reserve1) = _getBunniReserves(token_, lens_, outputDecimals_);
        uint256 outputScale = 10**outputDecimals_;

        // Determine the value of each reserve token in USD
        uint256 totalValue;
        totalValue += _PRICE().getPrice(token0, outputDecimals_).mulDiv(reserve0, outputScale);
        totalValue += _PRICE().getPrice(token1, outputDecimals_).mulDiv(reserve1, outputScale);

        return totalValue;
    }
}
