// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";

/// @title  IBunniManager
/// @author 0xJem
/// @notice Bophades policy to manage Uniswap V3 positions
interface IBunniManager {
    // =========  EVENTS ========= //

    // =========  ERRORS ========= //

    // =========  CORE FUNCTIONS ========= //

    /// @notice                 Registers a Uniswap V3 position with the policy
    ///
    /// @notice                 This is useful when migrating to a new policy.
    ///
    /// @param pool_            The address of the Uniswap V3 pool
    /// @param prevManager_     The address of the previous BunniManager
    /// @param prevId_          The id of the Bunni position on the previous BunniManager
    /// @return token           The address of the ERC20-compatible BunniToken
    function registerPosition(
        address pool_,
        address prevManager_,
        uint256 prevId_
    ) external returns (IBunniToken token);

    /// @notice       Deploys a new ERC20 token for a full-range position of the given Uniswap V3 pool
    ///
    /// @notice       The BunniToken contract is used to wrap the Uniswap V3 position,
    /// @notice       as TRSRY cannot receive ERC721 Uniswap V3 positions.
    ///
    /// @notice       This method is used for full-range positions. Therefore, the token
    /// @notice       will be deployed with tickLower and tickUpper set to the pool's min and max.
    ///
    /// @param pool_  The address of the Uniswap V3 pool
    /// @return token The ERC20-compatible BunniToken
    function deployFullRangeToken(address pool_) external returns (IBunniToken token);

    /// @notice             Deploys a new ERC20 token for the concentrated position of the given Uniswap V3 pool
    ///
    /// @notice             The BunniToken contract is used to wrap the Uniswap V3 position,
    /// @notice             as TRSRY cannot receive ERC721 Uniswap V3 positions.
    ///
    /// @notice             This method is used for arbitrary (concentrated) position ranges.
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param tickLower_   The min tick of the position
    /// @param tickUpper_   The max tick of the position
    /// @return token       The ERC20-compatible BunniToken
    function deployConcentratedToken(
        address pool_,
        int24 tickLower_,
        int24 tickUpper_
    ) external returns (IBunniToken token);

    /// @notice         Activates the ERC20 token for the given Uniswap V3 pool
    ///
    /// @notice         This can only be called after `deployPositionToken` or `registerPool` has been called
    /// @notice         to deploy the ERC20 token for this pool.
    ///
    /// @notice         This function will register the pool token with TRSRY, PRICE and SPPLY.
    ///
    /// @param pool_                            The address of the Uniswap V3 pool
    /// @param id_                              The id of the Bunni position
    /// @param priceMovingAverageDuration_      The duration of the moving average for the pool price observations
    /// @param priceLastObservationTime_        The last observation time for the pool price observations
    /// @param priceObservations_               The observations for the pool price
    /// @param reserveMovingAverageDuration_    The duration of the moving average for the pool reserve observations
    /// @param reserveLastObservationTime_      The last observation time for the pool reserve observations
    /// @param reserveToken0Observations_       The observations for token0
    /// @param reserveToken1Observations_       The observations for token1
    function activatePositionToken(
        address pool_,
        uint256 id_,
        uint32 priceMovingAverageDuration_,
        uint48 priceLastObservationTime_,
        uint256[] memory priceObservations_,
        uint32 reserveMovingAverageDuration_,
        uint48 reserveLastObservationTime_,
        uint256[] memory reserveToken0Observations_,
        uint256[] memory reserveToken1Observations_
    ) external;

    /// @notice         Deactivates the ERC20 token for the given Uniswap V3 pool
    ///
    ///                 This function will de-register the pool token with TRSRY, PRICE and SPPLY.
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    function deactivatePositionToken(address pool_, uint256 id) external;

    /// @notice             Deposits liquidity into the given Uniswap V3 pool
    ///
    /// @notice             This can only be called after `deployPositionToken` has been called
    /// @notice             to deploy the ERC20 token for this pool.
    ///
    /// @notice             The ordering of tokenA and tokenB is irrelevant. The `deposit` function
    /// @notice             will handle the ordering of the tokens.
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param id_          The id of the Bunni position
    /// @param tokenA_      The address of a token (used to determine the orientation of pool tokens)
    /// @param amountA_     The amount of tokenA to deposit
    /// @param amountB_     The amount of tokenB to deposit
    /// @param slippageBps_ Maximum percentage slippage allowed in basis points (100 = 1%)
    /// @return shares      The amount of shares minted
    function deposit(
        address pool_,
        uint256 id_,
        address tokenA_,
        uint256 amountA_,
        uint256 amountB_,
        uint16 slippageBps_
    ) external returns (uint256 shares);

    /// @notice             Withdraws liquidity from the given Uniswap V3 pool
    ///
    /// @notice             This can only be called after `deployPositionToken` has been called
    /// @notice             to deploy the ERC20 token for this pool.
    ///
    /// @notice             The LP tokens will be withdrawn from TRSRY and burned.
    ///
    /// @param pool_        The address of the Uniswap V3 pool
    /// @param id_          The id of the Bunni position
    /// @param shares_      The amount of shares to withdraw
    /// @param slippageBps_ Maximum percentage slippage allowed in basis points (100 = 1%)
    function withdraw(address pool_, uint256 id_, uint256 shares_, uint16 slippageBps_) external;

    /// @notice             Updates the swap fees for the deployed Uniswap V3 pools
    function updateSwapFees() external;

    /// @notice             Harvests fees from the deployed Uniswap V3 pools
    ///
    /// @notice             The fees will be added back into the pool, and the caller will
    /// @notice             receive a reward in OHM.
    function harvest() external;

    // =========  VIEW FUNCTIONS ========= //

    /// @notice         Get the total number of Uniswap V3 positions for the given pool
    ///
    /// @param pool_            The address of the Uniswap V3 pool
    /// @return positionCount   The number of positions
    function positionCount(address pool_) external view returns (uint256 positionCount);

    /// @notice         Get the BunniKey for the given Uniswap V3 pool address and position ID
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @param id_      The id of the Bunni position
    /// @return key     The BunniKey
    function getPositionKey(address pool_, uint256 id_) external view returns (BunniKey memory key);

    /// @notice         Get the ERC20-compatible BunniToken for the given Uniswap V3 pool address
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @param id_      The id of the Bunni position
    /// @return token   The ERC20-compatible BunniToken
    function getPositionToken(address pool_, uint256 id_) external view returns (IBunniToken token);

    /// @notice         Gets the balance in TRSRY of the ERC20 token for the given Uniswap V3 pool address
    ///
    /// @param pool_    The address of the Uniswap V3 pool
    /// @param id_      The id of the Bunni position
    /// @return balance The balance of the ERC20 token, or 0
    function getPositionTokenBalance(
        address pool_,
        uint256 id_
    ) external view returns (uint256 balance);

    /// @notice         Returns the current reward amount that would be received from harvesting fees
    ///
    /// @return reward  The amount of OHM that would be rewarded from harvesting fees
    function getCurrentHarvestReward() external view returns (uint256 reward);

    // =========  ADMIN FUNCTIONS ========= //

    /// @notice             Sets the BunniLens and BunniHub contracts
    ///
    /// @param newBunniLens_ The new address to use
    function setBunniLens(address newBunniLens_) external;

    /// @notice             Sets the owner of the BunniHub contract
    /// @notice             This can be used when a new policy is deployed that needs to manage the
    /// @notice             Uniswap V3 positions through the BunniHub.
    ///
    /// @param newOwner_    The address of the new owner
    function setBunniOwner(address newOwner_) external;

    /// @notice             Resets the last harvest time so that `harvest` can be called immediately
    function resetLastHarvest() external;

    /// @notice                 Sets the minimum time between fee harvesting
    ///
    /// @param newFrequency_    The minimum time in seconds between fee harvests
    function setHarvestFrequency(uint48 newFrequency_) external;

    /// @notice                     Sets the parameters for the harvest auction
    ///
    /// @param newRewardMax_        The maximum reward amount for a harvest
    /// @param newRewardFee_        The multiplier applied to the pool fees to determine the reward amount (in basis points)
    function setHarvestRewardParameters(uint256 newRewardMax_, uint16 newRewardFee_) external;
}
