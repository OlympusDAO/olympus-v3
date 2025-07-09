// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

/// @title  IDepositRedemptionVault
/// @notice Interface for a contract that can manage the redemption of receipt tokens for their deposit
interface IDepositRedemptionVault {
    // ========== EVENTS ========== //

    event RedemptionStarted(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount,
        address facility
    );

    event RedemptionFinished(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event RedemptionCancelled(
        address indexed user,
        uint16 indexed redemptionId,
        address indexed depositToken,
        uint8 depositPeriod,
        uint256 amount
    );

    event RedemptionAmountDecreased(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 amount
    );

    // Borrowing Events
    event LoanCreated(
        address indexed user,
        uint16 indexed redemptionId,
        uint16 indexed loanId,
        uint256 amount,
        address facility
    );

    event LoanRepaid(
        address indexed user,
        uint16 indexed redemptionId,
        uint16 indexed loanId,
        uint256 amount
    );

    event LoanExtended(
        address indexed user,
        uint16 indexed redemptionId,
        uint16 indexed loanId,
        uint256 newDueDate
    );

    event LoanDefaulted(
        address indexed user,
        uint16 indexed redemptionId,
        uint16 indexed loanId,
        uint256 principal,
        uint256 interest,
        uint256 collateral
    );

    event FacilityAuthorized(address indexed facility);
    event FacilityDeauthorized(address indexed facility);

    // ========== ERRORS ========== //

    error RedemptionVault_InvalidDepositManager(address depositManager);

    error RedemptionVault_ZeroAmount();

    error RedemptionVault_InvalidRedemptionId(address user, uint16 redemptionId);

    error RedemptionVault_InvalidAmount(address user, uint16 redemptionId, uint256 amount);

    error RedemptionVault_TooEarly(address user, uint16 redemptionId, uint48 redeemableAt);

    error RedemptionVault_AlreadyRedeemed(address user, uint16 redemptionId);

    // Facility Authorization
    error RedemptionVault_InvalidFacility(address facility);
    error RedemptionVault_FacilityExists(address facility);
    error RedemptionVault_FacilityNotRegistered(address facility);

    // Borrowing Errors
    error RedemptionVault_BorrowLimitExceeded(uint256 requested, uint256 available);
    error RedemptionVault_NoActiveLoans(uint16 redemptionId);
    error RedemptionVault_LoanNotExpired(uint16 redemptionId, uint256 loanId);
    error RedemptionVault_InvalidLoanId(uint16 redemptionId, uint256 loanId);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data structure for a redemption of a receipt token
    ///
    /// @param  depositToken    The address of the deposit token
    /// @param  depositPeriod   The period of the deposit in months
    /// @param  redeemableAt    The timestamp at which the redemption can be finished
    /// @param  amount          The amount of deposit tokens to redeem
    /// @param  facility        The facility that handles this redemption
    struct UserRedemption {
        address depositToken;
        uint8 depositPeriod;
        uint48 redeemableAt;
        uint256 amount;
        address facility;
    }

    /// @notice Data structure for a loan against a redemption
    ///
    /// @param  principal       The principal amount borrowed
    /// @param  interest        The interest amount
    /// @param  dueDate         The timestamp when the loan is due
    /// @param  facility        The facility that handled this borrowing
    /// @param  isDefaulted     Whether the loan has defaulted
    struct Loan {
        uint256 principal;
        uint256 interest;
        uint48 dueDate;
        address facility;
        bool isDefaulted;
    }

    // ========== FACILITY MANAGEMENT ========== //

    /// @notice Authorize a facility
    /// @param facility_ The address of the facility to authorize
    function authorizeFacility(address facility_) external;

    /// @notice Deauthorize a facility
    /// @param facility_ The address of the facility to deauthorize
    function deauthorizeFacility(address facility_) external;

    /// @notice Check if a facility is registered
    /// @param facility_ The address of the facility to check
    /// @return True if the facility is registered
    function isRegisteredFacility(address facility_) external view returns (bool);

    /// @notice Get all registered facilities
    /// @return Array of registered facility addresses
    function getRegisteredFacilities() external view returns (address[] memory);

    // ========== REDEMPTION FLOW ========== //

    /// @notice Gets the details of a user's redemption
    ///
    /// @param  user_            The address of the user
    /// @param  redemptionId_    The ID of the redemption
    /// @return redemption       The details of the redemption
    function getUserRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (UserRedemption memory redemption);

    /// @notice Gets the number of redemptions a user has started
    ///
    /// @param  user_ The address of the user
    /// @return count The number of redemptions
    function getUserRedemptionCount(address user_) external view returns (uint16 count);

    /// @notice Starts a redemption of a quantity of deposit tokens
    ///
    /// @param  depositToken_   The address of the deposit token
    /// @param  depositPeriod_  The period of the deposit in months
    /// @param  amount_         The amount of deposit tokens to redeem
    /// @param  facility_       The facility to handle this redemption
    /// @return redemptionId    The ID of the user redemption
    function startRedemption(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address facility_
    ) external returns (uint16 redemptionId);

    /// @notice Cancels a redemption of a quantity of deposit tokens
    ///
    /// @param  redemptionId_ The ID of the user redemption
    /// @param  amount_       The amount of deposit tokens to cancel
    function cancelRedemption(uint16 redemptionId_, uint256 amount_) external;

    /// @notice Finishes a redemption of a quantity of deposit tokens
    /// @dev    This function does not take an amount as an argument, because the amount is determined by the redemption
    ///
    /// @param  redemptionId_   The ID of the user redemption
    function finishRedemption(uint16 redemptionId_) external;

    // ========== BORROWING FUNCTIONS ========== //

    /// @notice Borrow against an active redemption
    /// @param redemptionId_ The ID of the redemption to borrow against
    /// @param amount_ The amount to borrow
    /// @param facility_ The facility to handle this borrowing
    /// @return loanId The ID of the created loan
    function borrowAgainstRedemption(
        uint16 redemptionId_,
        uint256 amount_,
        address facility_
    ) external returns (uint256 loanId);

    /// @notice Repay a loan (FIFO order)
    /// @param redemptionId_ The ID of the redemption
    /// @param amount_ The amount to repay
    function repayBorrow(uint16 redemptionId_, uint256 amount_) external;

    /// @notice Extend a loan's due date
    /// @param redemptionId_ The ID of the redemption
    /// @param loanId_ The ID of the loan to extend
    /// @param newDueDate_ The new due date
    function extendLoan(uint16 redemptionId_, uint256 loanId_, uint48 newDueDate_) external;

    /// @notice Handle loan default
    /// @param redemptionId_ The ID of the redemption
    /// @param loanId_ The ID of the loan to default
    function handleLoanDefault(uint16 redemptionId_, uint256 loanId_) external;

    // ========== BORROWING VIEW FUNCTIONS ========== //

    /// @notice Get the available borrow amount for a redemption
    /// @param redemptionId_ The ID of the redemption
    /// @return The available borrow amount
    function getAvailableBorrowForRedemption(uint16 redemptionId_) external view returns (uint256);

    /// @notice Get all loans for a redemption
    /// @param redemptionId_ The ID of the redemption
    /// @return Array of loans
    function getRedemptionLoans(uint16 redemptionId_) external view returns (Loan[] memory);

    /// @notice Get the total borrowed amount for a redemption
    /// @param redemptionId_ The ID of the redemption
    /// @return The total borrowed amount
    function getTotalBorrowedForRedemption(uint16 redemptionId_) external view returns (uint256);
}
