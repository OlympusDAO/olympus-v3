// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Bophades modules
import {SPPLYv1, SupplySubmodule} from "modules/SPPLY/SPPLY.v1.sol";
import {Module} from "src/Kernel.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";

// Bunni contracts
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {IBunniHub} from "src/external/bunni/interfaces/IBunniHub.sol";

// Standard libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

/// Uniswap V3
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";

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

    error BunniSupply_Params_InvalidLastObservationTime(
        address token_,
        uint48 lastObservationTime_
    );

    error BunniSupply_Params_InvalidMovingAverageDuration(uint32 movingAverageDuration_);

    error BunniSupply_Params_InvalidObservationsLength(uint16 numObservations);

    error BunniSupply_Params_InvalidObservation(address token_, uint256 index_);

    error BunniSupply_MovingAverageStale(address token_, uint48 lastObservationTime_);

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
    }

    struct TokenMovingAverage {
        uint16 nextObservationIndex;
        uint16 numObservations;
        uint32 movingAverageDuration;
        uint48 lastObservationTime;
        uint256[] token0Observations;
        uint256[] token1Observations;
        uint256 token0CumulativeObservations;
        uint256 token1CumulativeObservations;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The BunniTokens that are being monitored
    TokenData[] public bunniTokens;

    /// @notice     The moving average data for each BunniToken
    mapping(address => TokenMovingAverage) public tokenMovingAverages;

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
    /// @dev        For this reason, the moving averages of the pool reserves are tracked.
    function getProtocolOwnedLiquidityOhm() external view override returns (uint256) {
        // Iterate through tokens and total up the pool OHM reserves as the POL supply
        uint256 len = bunniTokens.length;
        uint256 total;
        for (uint256 i; i < len; ) {
            TokenData storage tokenData = bunniTokens[i];
            BunniKey memory key = _getBunniKey(tokenData.token);
            TokenMovingAverage storage tokenMovingAverage = tokenMovingAverages[
                address(tokenData.token)
            ];

            // Check if the moving average is stale
            _revertIfMovingAverageStale(address(tokenData.token));

            total += _getOhmReserves(key, tokenMovingAverage);

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
    /// @dev        For this reason, the moving averages of the pool reserves are tracked.
    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        // Iterate through tokens and total up the reserves of each pool
        uint256 len = bunniTokens.length;
        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](len);
        for (uint256 i; i < len; ) {
            TokenData storage tokenData = bunniTokens[i];
            BunniKey memory key = _getBunniKey(tokenData.token);
            TokenMovingAverage storage tokenMovingAverage = tokenMovingAverages[
                address(tokenData.token)
            ];

            // Check if the moving average is stale
            _revertIfMovingAverageStale(address(tokenData.token));

            // Calculate the moving average of the reserves
            uint256 averageReserve0 = tokenMovingAverage.token0CumulativeObservations /
                tokenMovingAverage.numObservations;
            uint256 averageReserve1 = tokenMovingAverage.token1CumulativeObservations /
                tokenMovingAverage.numObservations;

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
    /// @dev                            - `_updateTokenMovingAverage` reverts
    ///
    /// @param token_                   The address of the BunniToken contract
    /// @param bunniLens_               The address of the BunniLens contract
    /// @param movingAverageDuration_   The duration of the moving average
    /// @param lastObservationTime_     The time of the last observation
    /// @param token0Observations_      The observations for token0
    /// @param token1Observations_      The observations for token1
    function addBunniToken(
        address token_,
        address bunniLens_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory token0Observations_,
        uint256[] memory token1Observations_
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

        bunniTokens.push(TokenData({token: token, lens: lens}));
        bunniTokenCount++;

        // Update asset moving average data
        _updateTokenMovingAverage(
            token_,
            movingAverageDuration_,
            lastObservationTime_,
            token0Observations_,
            token1Observations_
        );

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

        // Remove moving average configuration
        delete tokenMovingAverages[token_];

        emit BunniTokenRemoved(token_);
    }

    // ========== MOVING AVERAGE TRACKING ========== //

    /// @notice             Updates the moving average configuration of the token
    /// @dev                Reverts if:
    /// @dev                - The last observation time is in the future
    /// @dev                - The duration is not aligned with the observation frequency
    /// @dev                - The number of observations is not aligned with the duration
    /// @dev                - An zero-value observation is provided
    function _updateTokenMovingAverage(
        address token_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory token0Observations_,
        uint256[] memory token1Observations_
    ) internal {
        TokenMovingAverage storage movingAverage = tokenMovingAverages[token_];

        // Remove existing observations
        if (movingAverage.token0Observations.length > 0) delete movingAverage.token0Observations;
        if (movingAverage.token1Observations.length > 0) delete movingAverage.token1Observations;

        // Ensure the last observation time is not in the future
        if (lastObservationTime_ > block.timestamp)
            revert BunniSupply_Params_InvalidLastObservationTime(token_, lastObservationTime_);

        // Ensure the duration is aligned
        uint32 observationFrequency = SPPLYv1(address(parent)).observationFrequency();
        if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency != 0)
            revert BunniSupply_Params_InvalidMovingAverageDuration(movingAverageDuration_);

        // Ensure the number of observations is aligned
        uint16 numObservations = uint16(movingAverageDuration_ / observationFrequency);
        if (
            token0Observations_.length != numObservations ||
            token1Observations_.length != numObservations ||
            numObservations < 2
        ) revert BunniSupply_Params_InvalidObservationsLength(numObservations);

        // Update the moving average configuration
        movingAverage.movingAverageDuration = movingAverageDuration_;
        movingAverage.nextObservationIndex = 0;
        movingAverage.numObservations = numObservations;
        movingAverage.lastObservationTime = lastObservationTime_;
        movingAverage.token0CumulativeObservations = 0; // Reset to 0 before adding new observations
        movingAverage.token1CumulativeObservations = 0; // Reset to 0 before adding new observations

        // Add the new observations for token 0
        for (uint256 i; i < numObservations; ) {
            if (token0Observations_[i] == 0)
                revert BunniSupply_Params_InvalidObservation(token_, i);

            movingAverage.token0CumulativeObservations += token0Observations_[i];
            movingAverage.token0Observations.push(token0Observations_[i]);
            unchecked {
                ++i;
            }
        }

        // Add the new observations for token 1
        for (uint256 i; i < numObservations; ) {
            if (token1Observations_[i] == 0)
                revert BunniSupply_Params_InvalidObservation(token_, i);

            movingAverage.token1CumulativeObservations += token1Observations_[i];
            movingAverage.token1Observations.push(token1Observations_[i]);
            unchecked {
                ++i;
            }
        }

        // Emit event
        emit ReserveObservationUpdated(
            token_,
            movingAverage.token0Observations[numObservations - 1],
            movingAverage.token1Observations[numObservations - 1]
        );
    }

    /// @notice         Updates the moving average configuration of the token
    /// @dev            Reverts if the caller is not the parent module
    ///
    /// @param token_                   The address of the BunniToken contract
    /// @param movingAverageDuration_   The duration of the moving average
    /// @param lastObservationTime_     The time of the last observation
    /// @param token0Observations_      The observations for token0
    /// @param token1Observations_      The observations for token1
    function updateTokenMovingAverage(
        address token_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory token0Observations_,
        uint256[] memory token1Observations_
    ) external onlyParent {
        // Ensure that the token is already added
        uint256 tokenCount = bunniTokens.length;
        bool tokenFound;
        for (uint256 i; i < tokenCount; ) {
            if (address(bunniTokens[i].token) == token_) {
                tokenFound = true;
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (tokenFound == false) revert BunniSupply_Params_InvalidBunniToken(token_);

        _updateTokenMovingAverage(
            token_,
            movingAverageDuration_,
            lastObservationTime_,
            token0Observations_,
            token1Observations_
        );
    }

    /// @inheritdoc           SupplySubmodule
    function storeObservations() external override onlyParent {
        // Iterate over all tokens
        uint256 len = bunniTokens.length;
        for (uint256 i; i < len; ) {
            TokenData storage tokenData = bunniTokens[i];
            BunniLens lens = tokenData.lens;
            BunniKey memory key = _getBunniKey(tokenData.token);
            (, , uint256 reserve0, uint256 reserve1) = _getReservesWithFees(key, lens);

            TokenMovingAverage storage tokenMovingAverage = tokenMovingAverages[
                address(tokenData.token)
            ];

            // Get the oldest observation
            uint256 oldestReserve0 = tokenMovingAverage.token0Observations[
                tokenMovingAverage.nextObservationIndex
            ];
            uint256 oldestReserve1 = tokenMovingAverage.token1Observations[
                tokenMovingAverage.nextObservationIndex
            ];

            // Set the new observation
            tokenMovingAverage.token0Observations[
                tokenMovingAverage.nextObservationIndex
            ] = reserve0;
            tokenMovingAverage.token1Observations[
                tokenMovingAverage.nextObservationIndex
            ] = reserve1;

            // Update the observation time and index
            tokenMovingAverage.lastObservationTime = uint48(block.timestamp);
            tokenMovingAverage.nextObservationIndex =
                (tokenMovingAverage.nextObservationIndex + 1) %
                tokenMovingAverage.numObservations;

            // Update the cumulative observations (which makes it easy to calculate the average)
            tokenMovingAverage.token0CumulativeObservations =
                tokenMovingAverage.token0CumulativeObservations +
                reserve0 -
                oldestReserve0;
            tokenMovingAverage.token1CumulativeObservations =
                tokenMovingAverage.token1CumulativeObservations +
                reserve1 -
                oldestReserve1;

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
    /// @param  key_                The BunniKey for the pool
    /// @param  tokenMovingAverage_ The token moving average data for the pool
    /// @return uint256             The OHM reserves for the pool
    function _getOhmReserves(
        BunniKey memory key_,
        TokenMovingAverage memory tokenMovingAverage_
    ) internal view returns (uint256) {
        if (key_.pool.token0() == ohm) {
            return
                tokenMovingAverage_.token0CumulativeObservations /
                tokenMovingAverage_.numObservations;
        } else if (key_.pool.token1() == ohm) {
            return
                tokenMovingAverage_.token1CumulativeObservations /
                tokenMovingAverage_.numObservations;
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

    /// @notice     Reverts if the moving average is stale
    function _revertIfMovingAverageStale(address token_) internal view {
        TokenMovingAverage storage tokenMovingAverage = tokenMovingAverages[token_];
        if (
            tokenMovingAverage.lastObservationTime +
                SPPLYv1(address(parent)).observationFrequency() <=
            block.timestamp
        ) revert BunniSupply_MovingAverageStale(token_, tokenMovingAverage.lastObservationTime);
    }
}
