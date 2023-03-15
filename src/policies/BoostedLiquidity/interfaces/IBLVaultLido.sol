// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

struct RewardsData {
    address rewardToken;
    uint256 outstandingRewards;
}

interface IBLVaultLido {
    //============================================================================================//
    //                                      LIQUIDITY FUNCTIONS                                   //
    //============================================================================================//

    /// @notice                 Mints OHM against a wstETH deposit and uses the OHM and wstETH to add liquidity to a Balancer pool
    /// @dev                    Can only be called by the owner of the vault
    /// @param amount_          The amount of wstETH to deposit
    /// @param minLpAmount_     The minimum acceptable amount of LP tokens to receive back
    /// @return lpAmountOut     The amount of LP tokens received by the transaction
    function deposit(uint256 amount_, uint256 minLpAmount_) external returns (uint256 lpAmountOut);

    /// @notice                 Withdraws LP tokens from Balancer, burns the OHM side, and returns the wstETH side to the user
    /// @dev                    Can only be called by the owner of the vault
    /// @param lpAmount_        The amount of LP tokens to withdraw from Balancer
    /// @param minTokenAmounts_ The minimum acceptable amounts of OHM (first entry), and wstETH (second entry) to receive back from Balancer
    /// @return uint256         The amount of OHM received
    /// @return uint256         The amount of wstETH received
    function withdraw(
        uint256 lpAmount_,
        uint256[] calldata minTokenAmounts_
    ) external returns (uint256, uint256);

    //============================================================================================//
    //                                       REWARDS FUNCTIONS                                    //
    //============================================================================================//

    /// @notice                 Claims outstanding rewards from Aura
    /// @dev                    Can only be called by the owner of the vault
    function claimRewards() external;

    //============================================================================================//
    //                                        VIEW FUNCTIONS                                      //
    //============================================================================================//

    /// @notice                 Gets the LP balance of the contract based on its deposits to Aura
    /// @return uint256         LP balance deposited into Aura
    function getLpBalance() external view returns (uint256);

    /// @notice                 Gets the contract's claim on wstETH based on its LP balance deposited into Aura
    /// @return uint256         Claim on wstETH
    function getUserPairShare() external view returns (uint256);

    /// @notice                         Returns the vault's unclaimed rewards in Aura
    /// @return RewardsData[]           The vault's unclaimed rewards in Aura
    function getOutstandingRewards() external view returns (RewardsData[] memory);
}
