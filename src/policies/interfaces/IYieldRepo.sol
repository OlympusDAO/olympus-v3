// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IYieldRepo {
    // =========  CORE FUNCTIONS ========= //

    /// @notice Triggers the yield repurchase facility functionality
    ///         Access controlled to the "heart" role
    /// @dev    Increments the epoch and triggers various actions depending on the new epoch number
    ///         When epoch == epochLength (21), withdraws the last week's yield and interest from the treasury
    ///         When epoch % 3 == 0 (once a day), triggers the creation of a bond market with the currently bid amount
    ///         Otherwise, does nothing.
    ///         The contract can be shutdown and this function will still work, but executes no logic.
    function endEpoch() external;

    /// ========== VIEWS ========== //

    /// @notice Returns the current epoch
    function epoch() external view returns (uint48);

    /// @notice Returns whether the contract is shutdown
    function isShutdown() external view returns (bool);

    /// @notice Returns the current balance of yield generating reserves in the treasury and clearinghouse
    function getReserveBalance() external view returns (uint256);

    /// @notice Returns the next yield amount which is converted to the bid budget
    /// @dev    This value uses the current sDAI balance, but always assumes a week's worth of interest for the clearinghouse
    ///         Therefore, it's only accurate when called close to the end of the epoch
    function getNextYield() external view returns (uint256);
}
