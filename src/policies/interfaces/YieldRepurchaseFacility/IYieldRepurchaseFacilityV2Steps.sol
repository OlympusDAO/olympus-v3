// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IYieldRepurchaseFacilityV2Steps
/// @notice The self-call surface of the multi-asset Yield Repurchase Facility (YRF)
///         policy: the isolated steps of the heart beat and of the funds return, and the
///         checked vault interactions of the daily cycle.
/// @dev Every function is intended to be callable only by the facility itself, through
///      a call to its own address, and reverts with
///      `IYieldRepurchaseFacilityV2_InvalidCaller` for any other caller. The isolation
///      keeps a revert of one step from reverting the beat: the facility captures the
///      failure and emits the skip event of the step. The functions are declared here so
///      that the linked libraries of the facility can encode the calls. The surface is
///      not advertised through ERC165.
interface IYieldRepurchaseFacilityV2Steps {
    /// @notice Runs the weekly reset of a single vault: projects the yield of the coming
    ///         week, refreshes the yield snapshots, and withdraws the previously stored
    ///         projection from the treasury into the buyback pool.
    /// @dev Intended to be callable by the facility itself, with the gas limit returned
    ///      by `stepGasLimit`, during the weekly reset of `IPeriodicTask.execute`.
    /// @param vault_ The vault to reset.
    /// @param clearinghouseYield_ The weekly Clearinghouse interest credited to the
    ///        backing vault, in backing reserve units.
    function selfProcessVaultReset(address vault_, uint256 clearinghouseYield_) external;

    /// @notice Burns the purchased OHM against a backing withdrawal; the withdrawn
    ///         backing vault shares join the backing vault's buyback pool.
    /// @dev Intended to be callable by the facility itself, with the gas limit returned
    ///      by `stepGasLimit`, on each daily beat of `IPeriodicTask.execute`.
    function selfProcessOhmPurchases() external;

    /// @notice Runs the daily cycle of a single vault: sizes the daily bid from the
    ///         buyback pool and opens the vault's bond market, priced by the live OHM
    ///         price denominated in the vault's reserve.
    /// @dev Intended to be callable by the facility itself, with the gas limit returned
    ///      by `stepGasLimit`, on each daily beat of `IPeriodicTask.execute`.
    /// @param vault_ The vault to process.
    /// @param daysRemaining_ The number of daily cycles remaining in the week, including
    ///        this one.
    function selfProcessVaultDaily(address vault_, uint256 daysRemaining_) external;

    /// @notice Deposits the reserve into the vault and verifies the minted shares against
    ///         the preview.
    /// @dev Intended to be callable by the facility itself, during the daily cycle of a
    ///      sell-shares asset. Reverts when the received shares are below
    ///      `previewDeposit(amount_)` (`IYieldRepurchaseFacilityV2_InsufficientDeposit`).
    /// @param vault_ The vault to deposit into.
    /// @param amount_ The reserve amount to deposit.
    function selfWrapReserve(address vault_, uint256 amount_) external;

    /// @notice Redeems vault shares and verifies the received reserve against the
    ///         preview.
    /// @dev Intended to be callable by the facility itself, during the daily cycle of an
    ///      asset that pays out its reserve. Reverts when the redeem reverts or when the
    ///      received reserve is below `previewRedeem(shares_)`
    ///      (`IYieldRepurchaseFacilityV2_InsufficientRedeem`).
    /// @param vault_ The vault to redeem from.
    /// @param shares_ The share amount to redeem.
    /// @return received The reserve amount received.
    function selfRedeemChecked(address vault_, uint256 shares_) external returns (uint256 received);

    /// @notice Returns a vault's share and reserve balances to the treasury.
    /// @dev Intended to be callable by the facility itself, with the gas limit returned
    ///      by `stepGasLimit`, during `returnFundsToTreasury`.
    /// @param vault_ The vault to sweep.
    function selfReturnVaultFunds(address vault_) external;
}
