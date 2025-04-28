// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

/// @title Convertible Deposit Token Manager
/// @notice Defines an interface for a policy that manages convertible deposit tokens and their lifecycle
interface IConvertibleDepositTokenManager {
    // ========== EVENTS ========== //

    event Committed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    event Redeemed(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    event Uncommitted(
        address indexed user,
        uint16 indexed commitmentId,
        address indexed cdToken,
        uint256 amount
    );

    event Reclaimed(
        address indexed user,
        address indexed depositToken,
        uint256 reclaimedAmount,
        uint256 forfeitedAmount
    );

    event YieldSwept(
        address indexed vaultToken,
        address indexed receiver,
        uint256 reserveAmount,
        uint256 sReserveAmount
    );

    // ========== ERRORS ========== //

    error CDRedemptionVault_InvalidCDToken(address cdToken);

    error CDRedemptionVault_ZeroAmount(address user);

    error CDRedemptionVault_InvalidCommitmentId(address user, uint16 commitmentId);

    error CDRedemptionVault_InvalidAmount(address user, uint16 commitmentId, uint256 amount);

    error CDRedemptionVault_TooEarly(address user, uint16 commitmentId);

    error CDRedemptionVault_AlreadyRedeemed(address user, uint16 commitmentId);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for a user commitment to redeem a CD token
    ///
    /// @param  cdToken         The address of the CD token
    /// @param  amount          The amount of CD tokens committed
    /// @param  redeemableAt    The timestamp at which the commitment can be redeemed
    struct UserRedeemCommitment {
        IConvertibleDepositERC20 cdToken;
        uint256 amount;
        uint48 redeemableAt;
    }

    // ========== MINT/BURN ========== //

    /// @notice Mint CD tokens for the caller
    ///
    /// @param  cdToken_    The address of the CD token
    /// @param  amount_     The amount of CD tokens to mint
    function mint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external;

    /// @notice Mint CD tokens for `account_`
    ///
    /// @param  cdToken_    The address of the CD token
    /// @param  account_    The address of the account to mint the CD tokens to
    /// @param  amount_     The amount of CD tokens to mint
    function mintFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external;

    /// @notice Burn CD tokens from the caller
    ///
    /// @param  cdToken_    The address of the CD token
    /// @param  amount_     The amount of CD tokens to burn
    function burn(IConvertibleDepositERC20 cdToken_, uint256 amount_) external;

    /// @notice Burn CD tokens from `account_`
    ///
    /// @param  cdToken_    The address of the CD token
    /// @param  account_    The address of the account to burn the CD tokens from
    /// @param  amount_     The amount of CD tokens to burn
    function burnFrom(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external;

    // ========== REDEMPTION FLOW ========== //

    /// @notice Gets the details of a user's redeem commitment
    ///
    /// @param  user_            The address of the user
    /// @param  commitmentId_    The ID of the commitment
    /// @return commitment       The details of the commitment
    function getRedeemCommitment(
        address user_,
        uint16 commitmentId_
    ) external view returns (UserCommitment memory commitment);

    /// @notice Gets the number of redeem commitments a user has made
    ///
    /// @param  user_ The address of the user
    /// @return count The number of redeem commitments
    function getRedeemCommitmentCount(address user_) external view returns (uint16 count);

    /// @notice Commits to redeem a quantity of CD tokens
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of CD tokens to commit
    /// @return commitmentId    The ID of the user commitment
    function commitRedeem(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint16 commitmentId);

    /// @notice Revokes a commitment to redeem a quantity of CD tokens
    ///
    /// @param  commitmentId_ The ID of the user commitment
    /// @param  amount_       The amount of CD tokens to uncommit
    function uncommitRedeem(uint16 commitmentId_, uint256 amount_) external;

    /// @notice Redeems CD tokens that has been committed
    /// @dev    This function does not take an amount as an argument, because the amount is determined by the commitment
    ///
    /// @param  commitmentId_ The ID of the user commitment
    function redeem(uint16 commitmentId_) external;

    // ========== RECLAIM ========== //

    /// @notice Preview the amount of deposit token that would be reclaimed
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Returning the total amount of deposit tokens that would be reclaimed
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  amount_         The amount of CD tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    /// @return cdTokenSpender  The address that will spend the CD tokens. The caller must have approved this address to spend the total amount of CD tokens.
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view returns (uint256 reclaimed, address cdTokenSpender);

    /// @notice Reclaims CD tokens, after applying a discount
    ///         CD tokens can be reclaimed at any time.
    ///         The caller is not required to have a position in the facility.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Burning the CD tokens
    ///         - Transferring the deposit token to `account_`
    ///         - Emitting an event
    ///
    /// @param  cdToken_        The address of the CD token
    /// @param  account_        The address to reclaim the deposit token to
    /// @param  amount_         The amount of CD tokens to reclaim
    /// @return reclaimed       The amount of deposit token returned to the caller
    function reclaimFor(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    /// @notice Reclaims CD tokens, after applying a discount
    /// @dev    This variant reclaims the underlying asset to the caller
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 reclaimed);

    // ========== YIELD MANAGEMENT ========== //

    /// @notice Claim the yield accrued on all supported tokens
    /// @dev    The implementing function should perform the following:
    ///         - Iterate over all supported tokens
    ///         - Calls `sweepYield` for each token
    function sweepAllYield() external;

    /// @notice Claim the yield accrued for a CD token
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the CD token is supported
    ///         - Validates that the caller is permissioned
    ///         - Withdrawing the yield from the sReserve token
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  cdToken_        The CD token to sweep yield for
    /// @return yieldReserve    The amount of reserve token swept
    /// @return yieldSReserve   The amount of sReserve token swept
    function sweepYield(
        IConvertibleDepositERC20 cdToken_
    ) external returns (uint256 yieldReserve, uint256 yieldSReserve);

    /// @notice Preview the amount of yield that would be swept
    /// @dev    The implementing function should perform the following:
    ///         - Validates that the CD token is supported
    ///         - Computes the amount of yield that would be swept
    ///         - Returns the computed amount
    ///
    /// @param  cdToken_        The CD token to check
    /// @return yieldReserve    The amount of reserve token that would be swept
    /// @return yieldSReserve   The amount of sReserve token that would be swept
    function previewSweepYield(
        IConvertibleDepositERC20 cdToken_
    ) external view returns (uint256 yieldReserve, uint256 yieldSReserve);

    // ========== ADMIN ========== //

    /// @notice Creates a new CD token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new CD token
    ///         - Emitting an event
    ///
    /// @param  vault_          The address of the vault to use for the CD token
    /// @param  periodMonths_   The period of the CD token
    /// @param  reclaimRate_    The reclaim rate to set for the CD token
    /// @return cdToken         The address of the new CD token
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external returns (IConvertibleDepositERC20 cdToken);

    /// @notice Sets the reclaim rate for a CD token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the reclaim rate for the CD token
    ///
    /// @param  cdToken_      The address of the CD token
    /// @param  reclaimRate_  The reclaim rate to set
    function setReclaimRate(IConvertibleDepositERC20 cdToken_, uint16 reclaimRate_) external;

    /// @notice Gets the amount of vault shares deposited for a convertible deposit token
    ///
    /// @param  cdToken_ The address of the CD token
    /// @return shares   The amount of shares
    function getVaultShares(
        IConvertibleDepositERC20 cdToken_
    ) external view returns (uint256 shares);
}
