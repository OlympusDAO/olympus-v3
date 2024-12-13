// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @title  IConvertibleDepositFacility
/// @notice Interface for a contract that can perform functions related to convertible deposit tokens
interface IConvertibleDepositFacility {
    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Converts convertible deposit tokens to OHM before expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` has an active convertible deposit position
    ///         - Validating that `account_` has the required amount of convertible deposit tokens
    ///         - Validating that all of the positions have not expired
    ///         - Burning the convertible deposit tokens
    ///         - Minting OHM to `account_`
    ///         - Transferring the reserve token to the treasury
    ///         - Emitting an event
    ///
    /// @param  account_        The address to convert for
    /// @param  positionIds_    An array of position ids that will be converted
    /// @param  amounts_        An array of amounts of convertible deposit tokens to convert
    /// @return converted       The amount of OHM minted to `account_`
    function convertFor(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 converted);

    /// @notice Reclaims convertible deposit tokens after expiry
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` has an active convertible deposit position
    ///         - Validating that `account_` has the required amount of convertible deposit tokens
    ///         - Validating that all of the positions have expired
    ///         - Burning the convertible deposit tokens
    ///         - Transferring the reserve token to `account_`
    ///         - Emitting an event
    ///
    /// @param  account_        The address to reclaim for
    /// @param  positionIds_    An array of position ids that will be reclaimed
    /// @param  amounts_        An array of amounts of convertible deposit tokens to reclaim
    /// @return reclaimed       The amount of reserve token returned to `account_`
    function reclaimFor(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 reclaimed);

    // TODO decide in the depositFor and withdrawTo functions should be in the ERC20 contract (aka ERC20Wrapper)

    /// @notice Deposits the reserve token in exchange for convertible deposit tokens
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the required amount of reserve tokens
    ///         - Minting the convertible deposit tokens to the caller
    ///         - Emitting an event
    ///
    /// @param  account_  The address to mint to
    /// @param  amount_   The amount of reserve token to mint
    /// @return minted    The amount of convertible deposit tokens minted to the caller
    function depositFor(address account_, uint256 amount_) external returns (uint256 minted);

    /// @notice Preview the amount of convertible deposit tokens that would be minted for a given amount of reserve token
    ///
    /// @param  account_  The address to mint to
    /// @param  amount_   The amount of reserve token to mint
    /// @return minted    The amount of convertible deposit tokens that would be minted
    function previewDepositFor(
        address account_,
        uint256 amount_
    ) external view returns (uint256 minted);

    /// @notice Withdraws the reserve token in exchange for convertible deposit tokens
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the required amount of convertible deposit tokens
    ///         - Burning the convertible deposit tokens
    ///         - Transferring the reserve token to the caller
    ///         - Emitting an event
    ///
    /// @param  account_    The address to withdraw to
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return withdrawn   The amount of reserve tokens returned to the caller
    function withdrawTo(address account_, uint256 amount_) external returns (uint256 withdrawn);

    /// @notice Preview the amount of reserve token that would be returned for a given amount of convertible deposit tokens
    ///
    /// @param  account_    The address to withdraw to
    /// @param  amount_     The amount of convertible deposit tokens to burn
    /// @return withdrawn   The amount of reserve tokens that would be returned
    function previewWithdrawTo(
        address account_,
        uint256 amount_
    ) external view returns (uint256 withdrawn);

    // ========== YIELD MANAGEMENT ========== //

    /// @notice Claim the yield accrued on the reserve token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Withdrawing the yield from the sReserve token
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @return yieldReserve  The amount of reserve token that was swept
    /// @return yieldSReserve The amount of sReserve token that was swept
    function sweepYield() external returns (uint256 yieldReserve, uint256 yieldSReserve);

    /// @notice Preview the amount of yield that would be swept
    ///
    /// @return yieldReserve  The amount of reserve token that would be swept
    /// @return yieldSReserve The amount of sReserve token that would be swept
    function previewSweepYield()
        external
        view
        returns (uint256 yieldReserve, uint256 yieldSReserve);

    // ========== ADMIN ========== /

    /// @notice Set the withdraw rate when withdrawing the convertible deposit token, where withdraw rate = reserve token output / convertible deposit token input
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Validating that the new rate is within bounds
    ///         - Setting the new redeem rate
    ///         - Emitting an event
    ///
    /// @param  newRate_    The new withdraw rate
    function setWithdrawRate(uint256 newRate_) external;

    // ========== STATE VARIABLES ========== //

    /// @notice The reserve token that is exchanged for the convertible deposit token
    function reserveToken() external view returns (IERC20);

    /// @notice The sReserve token that the reserve token is deposited into
    function sReserveToken() external view returns (IERC4626);

    /// @notice The convertible deposit token that is minted to the user
    function convertibleDepositToken() external view returns (IERC20);

    /// @notice The withdraw rate when withdrawing the convertible deposit token
    function withdrawRate() external view returns (uint256);
}
