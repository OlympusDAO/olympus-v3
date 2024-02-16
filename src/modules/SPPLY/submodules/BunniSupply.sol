// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Bophades modules
import "modules/SPPLY/SPPLY.v1.sol";

// Bunni contracts
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

// Standard libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

/// Uniswap V3
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {Deviation} from "libraries/Deviation.sol";
import {UniswapV3OracleHelper} from "libraries/UniswapV3/Oracle.sol";
import {BunniHelper} from "libraries/UniswapV3/BunniHelper.sol";

/// @title      BunniSupply
/// @author     0xJem
/// @notice     A SPPLY submodule that provides data on OHM deployed into Uniswap V3 pools that
/// @notice     are managed by the BunniManager policy and its associated BunniHub.
contract BunniSupply is SupplySubmodule {
    using FullMath for uint256;

    // ========== ERRORS ========== //

    /// @notice             The specified token is not a valid BunniToken
    ///
    /// @param token_       The address of the token
    error BunniSupply_Params_InvalidBunniToken(address token_);

    /// @notice             The specified lens is not a valid BunniLens
    ///
    /// @param lens_        The address of the lens
    error BunniSupply_Params_InvalidBunniLens(address lens_);

    /// @notice             The token and lens do not have the same BunniHub address
    ///
    /// @param tokenHub_    The BunniHub address of the token
    /// @param lensHub_     The BunniHub address of the lens
    error BunniSupply_Params_HubMismatch(address tokenHub_, address lensHub_);

    // ========== EVENTS ========== //

    /// @notice             Emitted when a new BunniToken is added
    /// @param token_       The address of the BunniToken contract
    /// @param bunniLens_   The address of the BunniLens contract
    event BunniTokenAdded(address token_, address bunniLens_);

    /// @notice             Emitted when a BunniToken is removed
    /// @param token_       The address of the BunniToken contract
    event BunniTokenRemoved(address token_);

    /// @notice             Emitted when the reserve observation is updated
    event ReserveObservationUpdated(address token, uint256 reserve0, uint256 reserve1);

    // ========== DATA STRUCTURES ========== //

    struct TokenData {
        BunniToken token;
        BunniLens lens;
        uint16 nextObservationIndex;
        uint16 numObservations;
        uint48 lastObservationTime;
        uint256[] token0Observations;
        uint256[] token1Observations;
        uint256 token0CumulativeObservations;
        uint256 token1CumulativeObservations;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The BunniTokens that are being monitored
    TokenData[] public bunniTokens;

    /// @notice     The number of BunniTokens that are being monitored
    uint256 public bunniTokenCount;

    /// @notice     The address of the OHM token
    /// @dev        Set at deployment-time
    address internal immutable ohm;

    // ========== CONSTRUCTOR ========== //

    /// @notice                 Initialize the submodule
    ///
    /// @param parent_          The parent module (SPPLY)
    constructor(Module parent_) Submodule(parent_) {
        ohm = address(SPPLYv1(address(parent_)).ohm());
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.BNI");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========== DATA FUNCTIONS ========== //

    /// @inheritdoc SupplySubmodule
    function getSourceCount() external view override returns (uint256) {
        return bunniTokens.length;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable for Uniswap V3 pools managed by BunniHub
    function getCollateralizedOhm() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable for Uniswap V3 pools managed by BunniHub
    function getProtocolOwnedBorrowableOhm() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Returns the total of OHM in all of the registered tokens representing Uniswap V3 pools
    ///
    /// @dev        This function accesses the reserves of the registered
    /// @dev        Uniswap V3 pools, and can be susceptible to re-entrancy attacks.
    /// @dev        The BunniLens contract used by this Submodule performs a re-entrancy check.
    ///
    /// @dev        Additionally, the reserves and TWAP are compared to ensure that the reserves
    /// @dev        have not been manipulated.
    function getProtocolOwnedLiquidityOhm() external view override returns (uint256) {
        // TODO revert if last observation is stale

        // Iterate through tokens and total up the pool OHM reserves as the POL supply
        uint256 len = bunniTokens.length;
        uint256 total;
        for (uint256 i; i < len; ) {
            TokenData storage tokenData = bunniTokens[i];
            BunniKey memory key = _getBunniKey(tokenData.token);

            total += _getOhmReserves(key, tokenData);

            unchecked {
                ++i;
            }
        }

        return total;
    }

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedTreasuryOhm() external pure override returns (uint256) {
        // POTO is always zero for BunniTokens
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Returns the total of OHM and non-OHM reserves in the submodule
    /// @dev        This includes both the reserves and uncollected fees belonging to the position.
    ///
    /// @dev        This function accesses the reserves of the registered
    /// @dev        Uniswap V3 pools, and can be susceptible to re-entrancy attacks.
    /// @dev        The BunniLens contract used by this Submodule performs a re-entrancy check.
    ///
    /// @dev        Additionally, the reserves and TWAP are compared to ensure that the reserves
    /// @dev        have not been manipulated.
    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        // TODO revert if last observation is stale

        // Iterate through tokens and total up the reserves of each pool
        uint256 len = bunniTokens.length;
        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](len);
        for (uint256 i; i < len; ) {
            TokenData storage tokenData = bunniTokens[i];
            BunniKey memory key = _getBunniKey(tokenData.token);

            // Calculate the moving average of the reserves
            uint256 averageReserve0 = tokenData.token0CumulativeObservations /
                tokenData.numObservations;
            uint256 averageReserve1 = tokenData.token1CumulativeObservations /
                tokenData.numObservations;

            address[] memory underlyingTokens = new address[](2);
            underlyingTokens[0] = key.pool.token0();
            underlyingTokens[1] = key.pool.token1();
            uint256[] memory underlyingReserves = new uint256[](2);
            underlyingReserves[0] = averageReserve0;
            underlyingReserves[1] = averageReserve1;

            reserves[i] = SPPLYv1.Reserves({
                source: address(tokenData.token),
                tokens: underlyingTokens,
                balances: underlyingReserves
            });

            unchecked {
                ++i;
            }
        }

        return reserves;
    }

    /// @notice         Determines whether `token_` has been registered
    ///
    /// @param token_   The address of the token
    /// @return         True if the token has been registered, otherwise false
    function hasBunniToken(address token_) external view returns (bool) {
        if (token_ == address(0) || !_inTokenArray(token_)) return false;

        return true;
    }

    // =========== ADMIN FUNCTIONS =========== //

    /// @notice                         Adds a deployed BunniToken address to the list of monitored tokens
    /// @dev                            Reverts if:
    /// @dev                            - The address is the zero address
    /// @dev                            - The address is already managed
    /// @dev                            - The caller is not the parent module
    /// @dev                            - `token_` does not adhere to the IBunniToken interface
    /// @dev                            - `bunniLens_` does not adhere to the IBunniLens interface
    /// @dev                            - `token_` and `bunniLens_` do not have the same BunniHub address
    ///
    /// @param token_                   The address of the BunniToken contract
    /// @param bunniLens_               The address of the BunniLens contract
    /// @param twapMaxDeviationBps_     The maximum deviation from the TWAP in basis points
    /// @param twapObservationWindow_   The TWAP observation window in seconds
    function addBunniToken(
        address token_,
        address bunniLens_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external onlyParent {
        if (token_ == address(0) || _inTokenArray(token_))
            revert BunniSupply_Params_InvalidBunniToken(token_);

        if (bunniLens_ == address(0)) revert BunniSupply_Params_InvalidBunniLens(bunniLens_);

        // Validate the token
        BunniToken token = BunniToken(token_);
        address tokenHub;
        try token.hub() returns (IBunniHub tokenHub_) {
            tokenHub = address(tokenHub_);
        } catch (bytes memory) {
            revert BunniSupply_Params_InvalidBunniToken(token_);
        }

        // Validate the lens
        BunniLens lens = BunniLens(bunniLens_);
        address lensHub;
        try lens.hub() returns (IBunniHub lensHub_) {
            lensHub = address(lensHub_);
        } catch (bytes memory) {
            revert BunniSupply_Params_InvalidBunniLens(bunniLens_);
        }

        // Check that the hub matches
        if (tokenHub != lensHub) revert BunniSupply_Params_HubMismatch(tokenHub, lensHub);

        uint256[] memory token0Observations = new uint256[](0);
        uint256[] memory token1Observations = new uint256[](0);

        // TODO handle moving average input

        bunniTokens.push(
            TokenData({
                token: token,
                lens: lens,
                nextObservationIndex: 0,
                numObservations: 0,
                lastObservationTime: 0,
                token0Observations: token0Observations,
                token1Observations: token1Observations,
                token0CumulativeObservations: 0,
                token1CumulativeObservations: 0
            })
        );
        bunniTokenCount++;

        emit BunniTokenAdded(token_, bunniLens_);
    }

    /// @notice                 Remove a deployed BunniToken address from the list of monitored tokens
    /// @dev                    Reverts if:
    /// @dev                    - The address is the zero address
    /// @dev                    - The address is not managed
    /// @dev                    - The caller is not the parent module
    ///
    /// @param token_           The address of the BunniToken contract
    function removeBunniToken(address token_) external onlyParent {
        if (token_ == address(0) || !_inTokenArray(token_))
            revert BunniSupply_Params_InvalidBunniToken(token_);

        uint256 len = bunniTokens.length;
        uint256 bunniTokenIndex = type(uint256).max;
        // Remove the token first
        for (uint256 i; i < len; ) {
            address tokenAddress = address(bunniTokens[i].token);
            if (token_ == tokenAddress) {
                bunniTokens[i] = bunniTokens[len - 1];
                bunniTokens.pop();
                bunniTokenIndex = i;
                break;
            }

            unchecked {
                ++i;
            }
        }

        bunniTokenCount--;

        emit BunniTokenRemoved(token_);
    }

    // ========== MOVING AVERAGE TRACKING ========== //

    /// @notice             Updates the moving average configuration of the token
    /// @dev                Reverts if:
    /// @dev                -
    function _updateTokenMovingAverage(
        BunniKey memory key_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory token0Observations_,
        uint256[] memory token1Observations_
    ) internal {
        // TODO
    }

    function updateTokenMovingAverage() external onlyParent {
        // TODO
    }

    /// @notice             Store the reserves of all the monitored tokens
    /// @dev                Assumptions:
    ///                     - The parent module has checked if sufficient time has passed since the last observation
    function storeReserveObservations() external onlyParent {
        // Iterate over all tokens
        uint256 len = bunniTokens.length;
        for (uint256 i; i < len; ) {
            TokenData storage tokenData = bunniTokens[i];
            BunniLens lens = tokenData.lens;
            BunniKey memory key = _getBunniKey(tokenData.token);
            (
                address token0,
                address token1,
                uint256 reserve0,
                uint256 reserve1
            ) = _getReservesWithFees(key, lens);

            // Get the oldest observation
            uint256 oldestReserve0 = tokenData.token0Observations[tokenData.nextObservationIndex];
            uint256 oldestReserve1 = tokenData.token1Observations[tokenData.nextObservationIndex];

            // Set the new observation
            tokenData.token0Observations[tokenData.nextObservationIndex] = reserve0;
            tokenData.token1Observations[tokenData.nextObservationIndex] = reserve1;

            // Update the observation time and index
            tokenData.lastObservationTime = uint48(block.timestamp);
            tokenData.nextObservationIndex =
                (tokenData.nextObservationIndex + 1) %
                tokenData.numObservations;

            // Update the cumulative observations (which makes it easy to calculate the average)
            tokenData.token0CumulativeObservations += reserve0 - oldestReserve0;
            tokenData.token1CumulativeObservations += reserve1 - oldestReserve1;

            emit ReserveObservationUpdated(address(tokenData.token), reserve0, reserve1);

            unchecked {
                ++i;
            }
        }
    }

    // =========== INTERNAL FUNCTIONS =========== //

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

    /// @notice             Returns the OHM reserves for the pool represented by `key_`
    ///
    /// @param key_         The BunniKey for the pool
    /// @param tokenData_   The TokenData for the pool
    /// @return         The OHM reserves for the pool
    function _getOhmReserves(
        BunniKey memory key_,
        TokenData memory tokenData_
    ) internal view returns (uint256) {
        if (key_.pool.token0() == ohm) {
            return tokenData_.token0CumulativeObservations / tokenData_.numObservations;
        } else if (key_.pool.token1() == ohm) {
            return tokenData_.token1CumulativeObservations / tokenData_.numObservations;
        } else {
            return 0;
        }
    }

    /// @notice         Returns the reserves for the pool represented by `key_`
    /// @dev            Includes uncollected fees
    ///
    /// @param key_     The BunniKey for the pool
    /// @param lens_    The BunniLens contract
    /// @return         The reserves for the pool in the order of (token0, token1, reserve0, reserv1)
    function _getReservesWithFees(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (address, address, uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        (uint256 fee0, uint256 fee1) = lens_.getUncollectedFees(key_);

        return (key_.pool.token0(), key_.pool.token1(), reserve0 + fee0, reserve1 + fee1);
    }

    /// @notice         Determines whether `token_` is in the `bunniTokens` array
    ///
    /// @param token_   The address of the token
    /// @return         True if the token is in the array, otherwise false
    function _inTokenArray(address token_) internal view returns (bool) {
        uint256 len = bunniTokens.length;
        for (uint256 i; i < len; ) {
            address tokenAddress = address(bunniTokens[i].token);
            if (token_ == tokenAddress) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }
}
