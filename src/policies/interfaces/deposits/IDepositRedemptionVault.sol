// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

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
        uint256 amount,
        uint256 remainingAmount
    );

    // Borrowing Events
    event LoanCreated(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 amount,
        address facility
    );

    event LoanRepaid(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 principal,
        uint256 interest
    );

    event LoanExtended(address indexed user, uint16 indexed redemptionId, uint256 newDueDate);

    event LoanDefaulted(
        address indexed user,
        uint16 indexed redemptionId,
        uint256 principal,
        uint256 interest,
        uint256 remainingCollateral
    );

    event FacilityAuthorized(address indexed facility);
    event FacilityDeauthorized(address indexed facility);

    event AnnualInterestRateSet(address indexed asset, uint16 rate);
    event MaxBorrowPercentageSet(address indexed asset, uint16 percent);
    event ClaimDefaultRewardPercentageSet(uint16 percent);

    // ========== ERRORS ========== //

    error RedemptionVault_InvalidDepositManager(address depositManager);

    error RedemptionVault_ZeroAmount();

    error RedemptionVault_InvalidRedemptionId(address user, uint16 redemptionId);

    error RedemptionVault_InvalidAmount(address user, uint16 redemptionId, uint256 amount);

    error RedemptionVault_TooEarly(address user, uint16 redemptionId, uint48 redeemableAt);

    error RedemptionVault_AlreadyRedeemed(address user, uint16 redemptionId);

    error RedemptionVault_OutOfBounds(uint16 rate);

    error RedemptionVault_UnpaidLoan(address user, uint16 redemptionId);

    // Facility Authorization
    error RedemptionVault_InvalidFacility(address facility);
    error RedemptionVault_FacilityExists(address facility);
    error RedemptionVault_FacilityNotRegistered(address facility);

    // Borrowing Errors
    error RedemptionVault_InterestRateNotSet(address asset);
    error RedemptionVault_MaxBorrowPercentageNotSet(address asset);
    error RedemptionVault_LoanAmountExceeded(address user, uint16 redemptionId, uint256 amount);

    error RedemptionVault_LoanIncorrectState(address user, uint16 redemptionId);
    error RedemptionVault_InvalidLoan(address user, uint16 redemptionId);

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
    /// @param  initialPrincipal    The initial principal amount borrowed
    /// @param  principal           The principal owed
    /// @param  interest            The interest owed
    /// @param  dueDate             The timestamp when the loan is due
    /// @param  isDefaulted         Whether the loan has defaulted
    struct Loan {
        uint256 initialPrincipal;
        uint256 principal;
        uint256 interest;
        uint48 dueDate;
        bool isDefaulted;
    }

    // ========== FACILITY MANAGEMENT ========== //

    /// @notice Authorize a facility
    ///
    /// @param facility_    The address of the facility to authorize
    function authorizeFacility(address facility_) external;

    /// @notice Deauthorize a facility
    ///
    /// @param facility_    The address of the facility to deauthorize
    function deauthorizeFacility(address facility_) external;

    /// @notice Check if a facility is authorized
    ///
    /// @param facility_        The address of the facility to check
    /// @return isAuthorized    True if the facility is authorized
    function isAuthorizedFacility(address facility_) external view returns (bool isAuthorized);

    /// @notice Get all authorized facilities
    ///
    /// @return facilities  Array of authorized facility addresses
    function getAuthorizedFacilities() external view returns (address[] memory facilities);

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

    /// @notice Borrow the maximum amount against an active redemption
    ///
    /// @param redemptionId_    The ID of the redemption to borrow against
    /// @return actualAmount    The quantity of underlying assets transferred to the recipient
    function borrowAgainstRedemption(uint16 redemptionId_) external returns (uint256 actualAmount);

    /// @notice Preview the maximum amount that can be borrowed against an active redemption
    ///
    /// @param user_            The address of the user
    /// @param redemptionId_    The ID of the redemption to borrow against
    /// @return principal       The principal amount that can be borrowed
    /// @return interest        The interest amount that will be charged
    /// @return dueDate         The due date of the loan
    function previewBorrowAgainstRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (uint256 principal, uint256 interest, uint48 dueDate);

    /// @notice Repay a loan
    ///
    /// @param redemptionId_    The ID of the redemption
    /// @param amount_          The amount to repay
    function repayLoan(uint16 redemptionId_, uint256 amount_) external;

    /// @notice Preview the interest payable for extending a loan
    ///
    /// @param user_            The address of the user
    /// @param redemptionId_    The ID of the redemption
    /// @param months_          The number of months to extend the loan
    /// @return newDueDate      The new due date
    /// @return interestPayable The interest payable upon extension
    function previewExtendLoan(
        address user_,
        uint16 redemptionId_,
        uint8 months_
    ) external view returns (uint48 newDueDate, uint256 interestPayable);

    /// @notice Extend a loan's due date
    ///
    /// @param redemptionId_    The ID of the redemption
    /// @param months_          The number of months to extend the loan
    function extendLoan(uint16 redemptionId_, uint8 months_) external;

    /// @notice Claim a defaulted loan and collect the reward
    ///
    /// @param user_            The address of the user
    /// @param redemptionId_    The ID of the redemption
    function claimDefaultedLoan(address user_, uint16 redemptionId_) external;

    // ========== BORROWING VIEW FUNCTIONS ========== //

    /// @notice Get all loans for a redemption
    ///
    /// @param user_            The address of the user
    /// @param redemptionId_    The ID of the redemption
    /// @return loan            The loan
    function getRedemptionLoan(
        address user_,
        uint16 redemptionId_
    ) external view returns (Loan memory loan);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Set the maximum borrow percentage for an asset
    ///
    /// @param asset_   The address of the asset
    /// @param percent_ The maximum borrow percentage
    function setMaxBorrowPercentage(IERC20 asset_, uint16 percent_) external;

    /// @notice Get the maximum borrow percentage for an asset
    ///
    /// @param asset_   The address of the asset
    /// @return percent The maximum borrow percentage, in terms of 100e2
    function getMaxBorrowPercentage(IERC20 asset_) external view returns (uint16 percent);

    /// @notice Set the annual interest rate for an asset
    ///
    /// @param asset_   The address of the asset
    /// @param rate_    The annual interest rate
    function setAnnualInterestRate(IERC20 asset_, uint16 rate_) external;

    /// @notice Get the annual interest rate for an asset
    ///
    /// @param asset_   The address of the asset
    /// @return rate    The annual interest rate, in terms of 100e2
    function getAnnualInterestRate(IERC20 asset_) external view returns (uint16 rate);

    /// @notice Set the reward percentage when a claiming a defaulted loan
    ///
    /// @param percent_  The claim default reward percentage
    function setClaimDefaultRewardPercentage(uint16 percent_) external;

    /// @notice Get the claim default reward percentage
    ///
    /// @return percent The claim default reward percentage, in terms of 100e2
    function getClaimDefaultRewardPercentage() external view returns (uint16 percent);
}
