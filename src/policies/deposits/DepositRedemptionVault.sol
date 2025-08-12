// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC6909} from "@openzeppelin-5.3.0/interfaces/draft-IERC6909.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Bophades
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title  DepositRedemptionVault
/// @notice A contract that manages the redemption of receipt tokens with facility coordination and borrowing
contract DepositRedemptionVault is Policy, IDepositRedemptionVault, PolicyEnabler, ReentrancyGuard {
    using TransferHelper for ERC20;
    using FullMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice The number of months in a year
    uint8 internal constant _MONTHS_IN_YEAR = 12;

    /// @notice Constant for one month
    uint48 internal constant _ONE_MONTH = 30 days;

    // ========== CONFIGURABLE PARAMETERS ========== //

    /// @notice Per-asset max borrow percentage (in 100e2, e.g. 8500 = 85%)
    mapping(address => uint16) internal _assetMaxBorrowPercentages;

    /// @notice Per-asset interest rate (annual, in 100e2, e.g. 500 = 5%)
    mapping(address => uint16) internal _assetAnnualInterestRates;

    /// @notice Keeper reward percentage (in 100e2, e.g. 500 = 5%)
    uint16 internal _claimDefaultRewardPercentage;

    // ========== STATE VARIABLES ========== //

    /// @notice The address of the token manager
    IDepositManager public immutable DEPOSIT_MANAGER;

    /// @notice The TRSRY module.
    TRSRYv1 public TRSRY;

    /// @notice The number of redemptions per user
    mapping(address => uint16) internal _userRedemptionCount;

    /// @notice The redemption for each user and redemption ID
    /// @dev    Use `_getUserRedemptionKey()` to calculate the key for the mapping.
    ///         A complex key is used to save gas compared to a nested mapping.
    mapping(bytes32 => UserRedemption) internal _userRedemptions;

    /// @notice Registered facilities
    EnumerableSet.AddressSet internal _authorizedFacilities;

    /// @notice Loan for each redemption
    /// @dev    Use `_getUserRedemptionKey()` to calculate the key for the mapping.
    ///         A complex key is used to save gas compared to a nested mapping.
    mapping(bytes32 => Loan) internal _redemptionLoan;

    // ========== CONSTRUCTOR ========== //

    constructor(address kernel_, address depositManager_) Policy(Kernel(kernel_)) {
        // Validate that the DepositManager implements IDepositManager
        if (!IERC165(depositManager_).supportsInterface(type(IDepositManager).interfaceId)) {
            revert RedemptionVault_InvalidDepositManager(depositManager_);
        }
        // Validate that the DepositManager implements IERC6909
        if (!IERC165(depositManager_).supportsInterface(type(IERC6909).interfaceId)) {
            revert RedemptionVault_InvalidDepositManager(depositManager_);
        }

        DEPOSIT_MANAGER = IDepositManager(depositManager_);
    }

    // ========== SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {}

    // ========== FACILITY MANAGEMENT ========== //

    /// @inheritdoc IDepositRedemptionVault
    function authorizeFacility(address facility_) external onlyAdminRole {
        if (facility_ == address(0)) revert RedemptionVault_InvalidFacility(facility_);
        if (_authorizedFacilities.contains(facility_))
            revert RedemptionVault_FacilityExists(facility_);

        // Validate that the facility implements IDepositFacility (even if it doesn't have the function)
        {
            (bool success, bytes memory data) = facility_.staticcall(
                abi.encodeWithSelector(
                    IERC165.supportsInterface.selector,
                    type(IDepositFacility).interfaceId
                )
            );
            if (!success || abi.decode(data, (bool)) == false)
                revert RedemptionVault_InvalidFacility(facility_);
        }

        _authorizedFacilities.add(facility_);

        emit FacilityAuthorized(facility_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function deauthorizeFacility(address facility_) external onlyEmergencyOrAdminRole {
        if (!_authorizedFacilities.contains(facility_))
            revert RedemptionVault_FacilityNotRegistered(facility_);

        _authorizedFacilities.remove(facility_);

        emit FacilityDeauthorized(facility_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function isAuthorizedFacility(address facility_) external view returns (bool) {
        return _authorizedFacilities.contains(facility_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function getAuthorizedFacilities() external view returns (address[] memory) {
        return _authorizedFacilities.values();
    }

    // ========== ASSETS ========== //

    /// @notice Pull the receipt tokens from the caller
    function _pullReceiptToken(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        address facility_,
        uint256 amount_
    ) internal {
        // Transfer the receipt tokens from the caller to this contract
        IERC6909(address(DEPOSIT_MANAGER)).transferFrom(
            msg.sender,
            address(this),
            DEPOSIT_MANAGER.getReceiptTokenId(depositToken_, depositPeriod_, facility_),
            amount_
        );
    }

    // ========== USER REDEMPTIONS ========== //

    function _getUserRedemptionKey(
        address user_,
        uint16 redemptionId_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(user_, redemptionId_));
    }

    /// @inheritdoc IDepositRedemptionVault
    function getUserRedemptionCount(address user_) external view returns (uint16 count) {
        return _userRedemptionCount[user_];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getUserRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (UserRedemption memory redemption) {
        redemption = _userRedemptions[_getUserRedemptionKey(user_, redemptionId_)];
        if (redemption.depositToken == address(0))
            revert RedemptionVault_InvalidRedemptionId(user_, redemptionId_);

        return redemption;
    }

    // ========== REDEMPTION FLOW ========== //

    modifier onlyValidRedemptionId(address user_, uint16 redemptionId_) {
        // If the deposit token is the zero address, the redemption is invalid
        if (
            _userRedemptions[_getUserRedemptionKey(user_, redemptionId_)].depositToken == address(0)
        ) revert RedemptionVault_InvalidRedemptionId(user_, redemptionId_);
        _;
    }

    function _validateFacility(address facility_) internal view {
        if (!_authorizedFacilities.contains(facility_))
            revert RedemptionVault_FacilityNotRegistered(facility_);
    }

    modifier onlyValidFacility(address facility_) {
        _validateFacility(facility_);
        _;
    }

    /// @inheritdoc IDepositRedemptionVault
    function startRedemption(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_,
        address facility_
    ) external nonReentrant onlyEnabled onlyValidFacility(facility_) returns (uint16 redemptionId) {
        // Validate that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Create a User Redemption
        redemptionId = _userRedemptionCount[msg.sender]++;
        _userRedemptions[_getUserRedemptionKey(msg.sender, redemptionId)] = UserRedemption({
            depositToken: address(depositToken_),
            depositPeriod: depositPeriod_,
            redeemableAt: uint48(block.timestamp) + uint48(depositPeriod_) * _ONE_MONTH,
            amount: amount_,
            facility: facility_
        });

        // Mark the funds as committed
        IDepositFacility(facility_).handleCommit(depositToken_, depositPeriod_, amount_);

        // Pull the receipt tokens from the caller
        _pullReceiptToken(depositToken_, depositPeriod_, facility_, amount_);

        // Emit events
        emit RedemptionStarted(
            msg.sender,
            redemptionId,
            address(depositToken_),
            depositPeriod_,
            amount_,
            facility_
        );

        return redemptionId;
    }

    /// @inheritdoc IDepositRedemptionVault
    function cancelRedemption(
        uint16 redemptionId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption storage redemption = _userRedemptions[redemptionKey];

        // Check that the facility is authorized
        _validateFacility(redemption.facility);

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Check that the amount is not greater than the redemption
        if (amount_ > redemption.amount)
            revert RedemptionVault_InvalidAmount(msg.sender, redemptionId_, amount_);

        // Check that there isn't an unpaid loan
        if (_redemptionLoan[redemptionKey].principal > 0)
            revert RedemptionVault_UnpaidLoan(msg.sender, redemptionId_);

        // Update the redemption
        redemption.amount -= amount_;

        // Reduce the committed funds
        IDepositFacility(redemption.facility).handleCommitCancel(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            amount_
        );

        // Transfer the quantity of receipt tokens to the caller
        // Redemptions are only accessible to the owner, so msg.sender is safe here
        IERC6909(address(DEPOSIT_MANAGER)).transfer(
            msg.sender,
            DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod,
                redemption.facility
            ),
            amount_
        );

        // Emit the cancelled event
        emit RedemptionCancelled(
            msg.sender,
            redemptionId_,
            redemption.depositToken,
            redemption.depositPeriod,
            amount_,
            redemption.amount
        );
    }

    /// @inheritdoc IDepositRedemptionVault
    function finishRedemption(
        uint16 redemptionId_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption storage redemption = _userRedemptions[redemptionKey];

        // Validate that the facility is authorized
        _validateFacility(redemption.facility);

        // Check that the redemption is not already redeemed
        if (redemption.amount == 0)
            revert RedemptionVault_AlreadyRedeemed(msg.sender, redemptionId_);

        // Check that the redemption is redeemable
        if (block.timestamp < redemption.redeemableAt)
            revert RedemptionVault_TooEarly(msg.sender, redemptionId_, redemption.redeemableAt);

        // Check that there isn't an unpaid loan
        if (_redemptionLoan[redemptionKey].principal > 0)
            revert RedemptionVault_UnpaidLoan(msg.sender, redemptionId_);

        // Update the redemption
        uint256 redemptionAmount = redemption.amount;
        redemption.amount = 0;

        // Handle the withdrawal
        // Redemptions are only accessible to the owner, so msg.sender is safe here
        IERC6909(address(DEPOSIT_MANAGER)).approve(
            address(DEPOSIT_MANAGER),
            DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod,
                redemption.facility
            ),
            redemptionAmount
        );
        IDepositFacility(redemption.facility).handleCommitWithdraw(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            redemptionAmount,
            msg.sender
        );

        // Emit the redeemed event
        emit RedemptionFinished(
            msg.sender,
            redemptionId_,
            redemption.depositToken,
            redemption.depositPeriod,
            redemptionAmount
        );
    }

    // ========== BORROWING FUNCTIONS ========== //

    function _calculateInterest(
        uint256 principal_,
        uint256 interestRate_,
        uint256 depositPeriod_
    ) internal pure returns (uint256) {
        // Rounded up, in favour of the protocol
        return
            principal_.mulDivUp(
                interestRate_ * depositPeriod_,
                uint256(_MONTHS_IN_YEAR) * uint256(ONE_HUNDRED_PERCENT)
            );
    }

    function _previewBorrowAgainstRedemption(
        address user_,
        uint16 redemptionId_
    ) internal view returns (uint256, uint256, uint48) {
        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(user_, redemptionId_);
        UserRedemption memory redemption = _userRedemptions[redemptionKey];

        // Validate that the facility is still authorized
        _validateFacility(redemption.facility);

        // Determine the amount to borrow
        // This deliberately does not revert. That will be handled in the borrowAgainstRedemption() function
        uint256 principal = redemption.amount.mulDiv(
            _assetMaxBorrowPercentages[redemption.depositToken],
            ONE_HUNDRED_PERCENT
        );

        // Interest: annualized, prorated for period
        uint256 interest = _calculateInterest(
            principal,
            _assetAnnualInterestRates[redemption.depositToken],
            redemption.depositPeriod
        );

        // Due date: now + deposit period
        uint48 dueDate = uint48(block.timestamp) + uint48(redemption.depositPeriod) * _ONE_MONTH;

        return (principal, interest, dueDate);
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        Notes:
    ///             - The calculated amount may differ from the actual amount borrowed (using `borrowAgainstRedemption()`) by a few wei, due to rounding behaviour in ERC4626 vaults.
    function previewBorrowAgainstRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (uint256, uint256, uint48) {
        return _previewBorrowAgainstRedemption(user_, redemptionId_);
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The facility is not authorized
    ///             - The amount is 0
    ///             - The interest rate is not set
    function borrowAgainstRedemption(
        uint16 redemptionId_
    )
        external
        nonReentrant
        onlyEnabled
        onlyValidRedemptionId(msg.sender, redemptionId_)
        returns (uint256)
    {
        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption storage redemption = _userRedemptions[redemptionKey];

        // Check that the facility is still authorized
        _validateFacility(redemption.facility);

        // Validate that the redemption is not already borrowed against
        if (_redemptionLoan[redemptionKey].dueDate != 0)
            revert RedemptionVault_LoanIncorrectState(msg.sender, redemptionId_);

        (uint256 principal, , uint48 dueDate) = _previewBorrowAgainstRedemption(
            msg.sender,
            redemptionId_
        );

        if (principal == 0)
            revert RedemptionVault_MaxBorrowPercentageNotSet(redemption.depositToken);

        // Ensure a non-zero interest rate is configured
        uint16 interestRate = _assetAnnualInterestRates[redemption.depositToken];
        if (interestRate == 0) revert RedemptionVault_InterestRateNotSet(redemption.depositToken);

        // Delegate to the facility for borrowing
        uint256 principalActual = IDepositFacility(redemption.facility).handleBorrow(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            principal,
            msg.sender
        );

        // Compute interest on the actual amount
        uint256 interestActual = _calculateInterest(
            principalActual,
            interestRate,
            redemption.depositPeriod
        );

        // Create loan
        // Values are actuals, which prevents future issues with repayment
        Loan memory newLoan = Loan({
            initialPrincipal: principalActual,
            principal: principalActual,
            interest: interestActual,
            dueDate: dueDate,
            isDefaulted: false
        });
        _redemptionLoan[redemptionKey] = newLoan;

        // Emit event
        emit LoanCreated(msg.sender, redemptionId_, principalActual, redemption.facility);

        return principalActual;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The redemption has no loan
    ///             - The amount is 0
    ///             - The loan is expired, defaulted or fully repaid
    function repayLoan(
        uint16 redemptionId_,
        uint256 amount_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Validate that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption memory redemption = _userRedemptions[redemptionKey];

        // Check that the facility is still authorized
        _validateFacility(redemption.facility);

        // Get the loan
        Loan storage loan = _redemptionLoan[redemptionKey];

        // Validate that the redemption has a loan
        if (loan.dueDate == 0) revert RedemptionVault_InvalidLoan(msg.sender, redemptionId_);

        // Validate that the loan is not:
        // - expired
        // - defaulted
        // - fully repaid
        if (block.timestamp >= loan.dueDate || loan.isDefaulted == true || loan.principal == 0)
            revert RedemptionVault_LoanIncorrectState(msg.sender, redemptionId_);

        // Update loan state
        // Partial repayment (pay interest first, then principal)
        uint256 principalRepaid;
        uint256 interestRepaid;
        if (amount_ <= loan.interest) {
            loan.interest -= amount_;

            // Update loan data
            interestRepaid = amount_;
        } else {
            interestRepaid = loan.interest;
            principalRepaid = amount_ - loan.interest;

            if (principalRepaid > loan.principal)
                revert RedemptionVault_LoanAmountExceeded(
                    msg.sender,
                    redemptionId_,
                    loan.principal
                );

            // Update loan data
            loan.interest = 0;
            loan.principal -= principalRepaid;
        }

        // Pull in the deposit tokens from the caller
        ERC20(redemption.depositToken).safeTransferFrom(msg.sender, address(this), amount_);

        // Delegate to the facility for repayment of principal
        // This will revert if there is an over-payment
        if (principalRepaid > 0) {
            ERC20(redemption.depositToken).safeApprove(address(DEPOSIT_MANAGER), principalRepaid);

            IDepositFacility(redemption.facility).handleLoanRepay(
                IERC20(redemption.depositToken),
                redemption.depositPeriod,
                principalRepaid,
                address(this)
            );
        }

        // Transfer interest to the TRSRY
        ERC20(redemption.depositToken).safeTransfer(address(TRSRY), interestRepaid);

        // Receipt tokens are not returned here.
        // They are only returned through cancelRedemption() or finishRedemption().

        emit LoanRepaid(msg.sender, redemptionId_, principalRepaid, interestRepaid);
    }

    function _previewExtendLoan(
        address asset_,
        uint256 principal_,
        uint48 dueDate_,
        uint8 extensionMonths_
    ) internal view returns (uint48, uint256) {
        uint16 interestRate = _assetAnnualInterestRates[asset_];
        if (interestRate == 0) revert RedemptionVault_InterestRateNotSet(asset_);

        uint256 interestPayable = _calculateInterest(principal_, interestRate, extensionMonths_);

        uint48 newDueDate = dueDate_ + uint48(extensionMonths_) * _ONE_MONTH;

        return (newDueDate, interestPayable);
    }

    /// @inheritdoc IDepositRedemptionVault
    function previewExtendLoan(
        address user_,
        uint16 redemptionId_,
        uint8 months_
    ) external view returns (uint48, uint256) {
        // Validate that the months is not 0
        if (months_ == 0) revert RedemptionVault_ZeroAmount();

        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(user_, redemptionId_);
        UserRedemption memory redemption = _userRedemptions[redemptionKey];

        // Get the loan
        Loan memory loan = _redemptionLoan[redemptionKey];

        // Preview the new due date and interest payable
        (uint48 newDueDate, uint256 interestPayable) = _previewExtendLoan(
            redemption.depositToken,
            loan.principal,
            loan.dueDate,
            months_
        );

        return (newDueDate, interestPayable);
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The loan is invalid
    ///             - The loan is expired, defaulted or fully repaid
    ///             - The months is 0
    function extendLoan(
        uint16 redemptionId_,
        uint8 months_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Validate that the months is not 0
        if (months_ == 0) revert RedemptionVault_ZeroAmount();

        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption memory redemption = _userRedemptions[redemptionKey];

        // Check that the facility is still authorized
        _validateFacility(redemption.facility);

        // Get the loan
        Loan storage loan = _redemptionLoan[redemptionKey];

        // Validate that the redemption has a loan
        if (loan.dueDate == 0) revert RedemptionVault_InvalidLoan(msg.sender, redemptionId_);

        // Validate that the loan is not:
        // - expired
        // - defaulted
        // - fully repaid
        if (block.timestamp >= loan.dueDate || loan.isDefaulted == true || loan.principal == 0)
            revert RedemptionVault_LoanIncorrectState(msg.sender, redemptionId_);

        (uint48 newDueDate, uint256 interestPayable) = _previewExtendLoan(
            redemption.depositToken,
            loan.principal,
            loan.dueDate,
            months_
        );

        // Update due date by the number of months
        loan.dueDate = newDueDate;

        // No need to update the interest payable, as it is collected immediately

        // Transfer the interest from the caller to the TRSRY
        ERC20(redemption.depositToken).safeTransferFrom(
            msg.sender,
            address(TRSRY),
            interestPayable
        );

        emit LoanExtended(msg.sender, redemptionId_, loan.dueDate);
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The loan is invalid
    ///             - The loan is not expired
    ///             - The loan is already defaulted
    function claimDefaultedLoan(
        address user_,
        uint16 redemptionId_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(user_, redemptionId_) {
        // Get the redemption and loan
        UserRedemption storage redemption;
        Loan storage loan;
        {
            bytes32 redemptionKey = _getUserRedemptionKey(user_, redemptionId_);
            redemption = _userRedemptions[redemptionKey];
            loan = _redemptionLoan[redemptionKey];
        }

        // Validate that the facility is still authorized
        _validateFacility(redemption.facility);

        // Validate that the redemption has a loan
        if (loan.dueDate == 0) revert RedemptionVault_InvalidLoan(user_, redemptionId_);

        // Validate that the loan is:
        // - expired
        // - not defaulted
        // - not fully repaid
        if (block.timestamp < loan.dueDate || loan.isDefaulted == true || loan.principal == 0)
            revert RedemptionVault_LoanIncorrectState(user_, redemptionId_);

        // Determine how much collateral to confiscate
        // Any principal that has been paid off will be retained by the borrower
        // The remainder, including the buffer, will be confiscated
        // e.g. the borrower has a redemption amount of 100, the borrower has borrowed 80, and paid off 20,
        // the borrower has an outstanding principal of 60.
        // The borrower will retain a redemption amount of 20 (due to the payment).
        // The protocol will burn the custodied receipt tokens for the unpaid principal: 80 - 20 = 60.
        // The remainder (20) will be sent to the treasury.
        uint256 previousPrincipal = loan.principal;
        uint256 previousInterest = loan.interest;
        uint256 retainedCollateral = redemption.amount - loan.initialPrincipal; // Buffer amount

        // Mark loan as defaulted
        loan.isDefaulted = true;
        loan.principal = 0;
        loan.interest = 0;

        IERC6909(address(DEPOSIT_MANAGER)).approve(
            address(DEPOSIT_MANAGER),
            DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod,
                redemption.facility
            ),
            retainedCollateral + previousPrincipal
        );
        // Burn the receipt tokens for the principal
        if (previousPrincipal > 0) {
            IDepositFacility(redemption.facility).handleLoanDefault(
                IERC20(redemption.depositToken),
                redemption.depositPeriod,
                previousPrincipal,
                address(this)
            );
        }
        // Withdraw deposit for retained collateral
        uint256 retainedCollateralActual;
        if (retainedCollateral > 0) {
            retainedCollateralActual = IDepositFacility(redemption.facility).handleCommitWithdraw(
                IERC20(redemption.depositToken),
                redemption.depositPeriod,
                retainedCollateral,
                address(this)
            );
        }

        // Reduce redemption amount by the burned and retained collateral
        // Use the calculated amount (retainedCollateral + previousPrincipal) to adjust redemption.
        // This leaves redemption.amount equal to (initialPrincipal - previousPrincipal), i.e.,
        // any principal already repaid remains redeemable by the borrower. Using calculated amounts
        // avoids inconsistencies from ERC4626 rounding in actual transfers.
        redemption.amount -= retainedCollateral + previousPrincipal;

        // Distribute residual value (keeper reward + treasury)
        uint256 keeperReward = retainedCollateralActual.mulDiv(
            _claimDefaultRewardPercentage,
            ONE_HUNDRED_PERCENT
        );
        uint256 treasuryAmount = retainedCollateralActual - keeperReward;

        if (keeperReward > 0) {
            ERC20(redemption.depositToken).safeTransfer(msg.sender, keeperReward);
        }

        if (treasuryAmount > 0) {
            ERC20(redemption.depositToken).safeTransfer(address(TRSRY), treasuryAmount);
        }

        emit LoanDefaulted(
            user_,
            redemptionId_,
            previousPrincipal,
            previousInterest,
            retainedCollateral + previousPrincipal // Calculated amount
        );
        emit RedemptionCancelled(
            user_,
            redemptionId_,
            address(redemption.depositToken),
            redemption.depositPeriod,
            retainedCollateral + previousPrincipal, // Calculated amount
            redemption.amount
        );
    }

    // ========== BORROWING VIEW FUNCTIONS ========== //

    /// @inheritdoc IDepositRedemptionVault
    function getRedemptionLoan(
        address user_,
        uint16 redemptionId_
    ) external view returns (Loan memory) {
        return _redemptionLoan[_getUserRedemptionKey(user_, redemptionId_)];
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IDepositRedemptionVault
    /// @dev    Notes:
    ///         - When setting the max borrow percentage, keep in mind the annual interest rate and claim default reward percentage, as the three configuration values can create incentives for borrowers to not repay their loans (e.g. claim default on their own loan)
    function setMaxBorrowPercentage(
        IERC20 asset_,
        uint16 percent_
    ) external onlyEnabled onlyManagerOrAdminRole {
        if (percent_ > ONE_HUNDRED_PERCENT) revert RedemptionVault_OutOfBounds(percent_);

        _assetMaxBorrowPercentages[address(asset_)] = percent_;

        emit MaxBorrowPercentageSet(address(asset_), percent_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function getMaxBorrowPercentage(IERC20 asset_) external view returns (uint16) {
        return _assetMaxBorrowPercentages[address(asset_)];
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev    Notes:
    ///         - When setting the annual interest rate, keep in mind the max borrow percentage and claim default reward percentage, as the three configuration values can create incentives for borrowers to not repay their loans (e.g. claim default on their own loan)
    function setAnnualInterestRate(
        IERC20 asset_,
        uint16 rate_
    ) external onlyEnabled onlyManagerOrAdminRole {
        if (rate_ > ONE_HUNDRED_PERCENT) revert RedemptionVault_OutOfBounds(rate_);

        _assetAnnualInterestRates[address(asset_)] = rate_;

        emit AnnualInterestRateSet(address(asset_), rate_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function getAnnualInterestRate(IERC20 asset_) external view returns (uint16) {
        return _assetAnnualInterestRates[address(asset_)];
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev    Notes:
    ///         - When setting the claim default reward percentage, keep in mind the annual interest rate and max borrow percentage, as the three configuration values can create incentives for borrowers to not repay their loans (e.g. claim default on their own loan)
    function setClaimDefaultRewardPercentage(
        uint16 percent_
    ) external onlyEnabled onlyManagerOrAdminRole {
        if (percent_ > ONE_HUNDRED_PERCENT) revert RedemptionVault_OutOfBounds(percent_);

        _claimDefaultRewardPercentage = percent_;

        emit ClaimDefaultRewardPercentageSet(percent_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function getClaimDefaultRewardPercentage() external view returns (uint16) {
        return _claimDefaultRewardPercentage;
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IDepositRedemptionVault).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
