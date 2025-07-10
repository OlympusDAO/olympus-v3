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
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";

// Bophades
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title  DepositRedemptionVault
/// @notice A contract that manages the redemption of receipt tokens with facility coordination and borrowing
contract DepositRedemptionVault is Policy, IDepositRedemptionVault, PolicyEnabler, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FullMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ========== CONFIGURABLE PARAMETERS ========== //

    /// @notice Per-asset max borrow percentage (in 100e2, e.g. 8500 = 85%)
    mapping(address => uint16) public maxBorrowPercentage;

    /// @notice Per-asset interest rate (annual, in 100e2, e.g. 500 = 5%)
    mapping(address => uint16) public interestRatePerYear;

    /// @notice Keeper reward percentage (in 100e2, e.g. 500 = 5%)
    uint16 public keeperRewardPercentage;

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

    /// @notice Loans for each redemption
    /// @dev    Use `_getUserRedemptionKey()` to calculate the key for the mapping.
    ///         A complex key is used to save gas compared to a nested mapping.
    mapping(bytes32 => Loan[]) internal _redemptionLoans;

    /// @notice The total borrowed amount per redemption
    /// @dev    Use `_getUserRedemptionKey()` to calculate the key for the mapping.
    ///         A complex key is used to save gas compared to a nested mapping.
    mapping(bytes32 => uint256) internal _totalBorrowedPerRedemption;

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
        view
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

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
        uint256 amount_
    ) internal {
        // Transfer the receipt tokens from the caller to this contract
        IERC6909(address(DEPOSIT_MANAGER)).transferFrom(
            msg.sender,
            address(this),
            DEPOSIT_MANAGER.getReceiptTokenId(depositToken_, depositPeriod_),
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
            redeemableAt: uint48(block.timestamp + uint48(depositPeriod_) * 30 days),
            amount: amount_,
            facility: facility_
        });

        // Mark the funds as committed
        IDepositFacility(facility_).handleCommit(depositToken_, depositPeriod_, amount_);

        // Pull the receipt tokens from the caller
        _pullReceiptToken(depositToken_, depositPeriod_, amount_);

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
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Check that the facility is authorized
        _validateFacility(redemption.facility);

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Check that the amount is not greater than the redemption
        if (amount_ > redemption.amount)
            revert RedemptionVault_InvalidAmount(msg.sender, redemptionId_, amount_);

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
                redemption.depositPeriod
            ),
            amount_
        );

        // Emit the cancelled event
        emit RedemptionCancelled(
            msg.sender,
            redemptionId_,
            redemption.depositToken,
            redemption.depositPeriod,
            amount_
        );
    }

    /// @inheritdoc IDepositRedemptionVault
    function finishRedemption(
        uint16 redemptionId_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Validate that the facility is authorized
        _validateFacility(redemption.facility);

        // Check that the redemption is not already redeemed
        if (redemption.amount == 0)
            revert RedemptionVault_AlreadyRedeemed(msg.sender, redemptionId_);

        // Check that the redemption is redeemable
        if (block.timestamp < redemption.redeemableAt)
            revert RedemptionVault_TooEarly(msg.sender, redemptionId_, redemption.redeemableAt);

        // Update the redemption
        uint256 redemptionAmount = redemption.amount;
        redemption.amount = 0;

        // Handle the withdrawal
        // Redemptions are only accessible to the owner, so msg.sender is safe here
        IERC6909(address(DEPOSIT_MANAGER)).approve(
            address(DEPOSIT_MANAGER),
            DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod
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

    modifier onlyValidLoanId(
        address user_,
        uint16 redemptionId_,
        uint16 loanId_
    ) {
        if (loanId_ >= _redemptionLoans[_getUserRedemptionKey(user_, redemptionId_)].length)
            revert RedemptionVault_InvalidLoanId(user_, redemptionId_, loanId_);
        _;
    }

    // NOTE: implementation not reviewed or tested yet

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The facility is not authorized
    ///             - The amount is 0
    ///             - The borrow limit is exceeded
    ///             - The interest rate is not set
    function borrowAgainstRedemption(
        uint16 redemptionId_,
        uint256 amount_
    )
        external
        nonReentrant
        onlyEnabled
        onlyValidRedemptionId(msg.sender, redemptionId_)
        returns (uint16 loanId)
    {
        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption storage redemption = _userRedemptions[redemptionKey];

        // Check that the facility is still authorized
        if (!_authorizedFacilities.contains(redemption.facility))
            revert RedemptionVault_FacilityNotRegistered(redemption.facility);

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Check that the borrow limit is not exceeded
        {
            // Use per-asset config
            uint16 borrowPct = maxBorrowPercentage[redemption.depositToken];
            uint256 maxBorrow = redemption.amount.mulDiv(borrowPct, ONE_HUNDRED_PERCENT);
            uint256 availableBorrow = maxBorrow - _totalBorrowedPerRedemption[redemptionKey];
            if (amount_ > availableBorrow)
                revert RedemptionVault_BorrowLimitExceeded(amount_, availableBorrow);
        }

        // Interest: annualized, prorated for period
        uint256 interest;
        {
            uint16 rate = interestRatePerYear[redemption.depositToken];
            if (rate == 0) revert RedemptionVault_InterestRateNotSet(redemption.depositToken);

            interest = (amount_.mulDiv(rate, ONE_HUNDRED_PERCENT) * redemption.depositPeriod) / 12;
        }

        // Create loan
        Loan memory newLoan = Loan({
            principal: amount_,
            interest: interest,
            dueDate: redemption.redeemableAt,
            isDefaulted: false
        });

        // Check that the max loans per redemption is not exceeded
        if (_redemptionLoans[redemptionKey].length >= type(uint16).max)
            revert RedemptionVault_MaxLoans(msg.sender, redemptionId_);

        // Add loan to the redemption
        _redemptionLoans[redemptionKey].push(newLoan);
        loanId = uint16(_redemptionLoans[redemptionKey].length) - 1;

        // Update total borrowed
        _totalBorrowedPerRedemption[redemptionKey] += amount_;

        // Delegate to the facility for borrowing
        IDepositFacility(redemption.facility).handleBorrow(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            amount_,
            msg.sender
        );

        // Emit event
        emit LoanCreated(msg.sender, redemptionId_, loanId, amount_, redemption.facility);

        return loanId;
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The loan ID is invalid
    ///             - The amount is 0
    ///             - The loan is repaid
    function repayLoan(
        uint16 redemptionId_,
        uint16 loanId_,
        uint256 amount_
    )
        external
        nonReentrant
        onlyEnabled
        onlyValidRedemptionId(msg.sender, redemptionId_)
        onlyValidLoanId(msg.sender, redemptionId_, loanId_)
    {
        // Validate that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        UserRedemption memory redemption = _userRedemptions[redemptionKey];

        // Get the loan
        Loan storage loan = _redemptionLoans[redemptionKey][loanId_];

        // Validate that the loan is not repaid
        if (loan.principal == 0)
            revert RedemptionVault_InvalidLoanId(msg.sender, redemptionId_, loanId_);

        // Delegate to the facility for repayment
        // This will revert if there is an over-payment
        IDepositFacility(redemption.facility).handleRepay(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            amount_,
            msg.sender
        );

        // Update loan state
        // Partial repayment (pay interest first, then principal)
        uint256 principalRepaid;
        uint256 interestRepaid;
        if (amount_ <= loan.interest) {
            loan.interest -= amount_;

            // Update loan data
            interestRepaid = amount_;
        } else {
            uint256 remainingRepay = amount_ - loan.interest;
            loan.interest = 0;
            loan.principal -= remainingRepay;

            // Update loan data
            interestRepaid = loan.interest;
            principalRepaid = remainingRepay;

            // Update total principal borrowed
            _totalBorrowedPerRedemption[redemptionKey] -= principalRepaid;
        }

        // Receipt tokens are not returned here.
        // They are only returned through cancelRedemption() or finishRedemption().

        emit LoanRepaid(msg.sender, redemptionId_, loanId_, principalRepaid, interestRepaid);
    }

    /// @inheritdoc IDepositRedemptionVault
    function extendLoan(
        uint16 redemptionId_,
        uint16 loanId_,
        uint8 months_
    )
        external
        nonReentrant
        onlyEnabled
        onlyValidRedemptionId(msg.sender, redemptionId_)
        onlyValidLoanId(msg.sender, redemptionId_, loanId_)
    {
        // Validate that the months is not 0
        if (months_ == 0) revert RedemptionVault_ZeroAmount();

        // Get the redemption
        UserRedemption memory redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Get the loan
        bytes32 redemptionKey = _getUserRedemptionKey(msg.sender, redemptionId_);
        Loan storage loan = _redemptionLoans[redemptionKey][loanId_];

        // Check that the loan is not defaulted
        if (loan.isDefaulted)
            revert RedemptionVault_LoanExpired(msg.sender, redemptionId_, loanId_);

        // Check that the loan is not repaid
        if (loan.principal == 0)
            revert RedemptionVault_InvalidLoanId(msg.sender, redemptionId_, loanId_);

        // Update due date by the number of months
        loan.dueDate += months_ * 30 days;

        // Update interest
        loan.interest +=
            (loan.principal.mulDiv(
                interestRatePerYear[redemption.depositToken],
                ONE_HUNDRED_PERCENT
            ) * months_) /
            12;

        emit LoanExtended(msg.sender, redemptionId_, loanId_, loan.dueDate);
    }

    /// @inheritdoc IDepositRedemptionVault
    /// @dev        This function will revert if:
    ///             - The contract is not enabled
    ///             - The redemption ID is invalid
    ///             - The loan ID is invalid
    ///             - The loan is not expired
    ///             - The loan is already defaulted
    function claimDefaultedLoan(
        address user_,
        uint16 redemptionId_,
        uint16 loanId_
    )
        external
        nonReentrant
        onlyEnabled
        onlyValidRedemptionId(user_, redemptionId_)
        onlyValidLoanId(user_, redemptionId_, loanId_)
    {
        // Get the redemption and loan
        UserRedemption storage redemption;
        Loan storage loan;
        {
            bytes32 redemptionKey = _getUserRedemptionKey(user_, redemptionId_);
            redemption = _userRedemptions[redemptionKey];
            loan = _redemptionLoans[redemptionKey][loanId_];
        }

        // Check if loan is expired
        if (block.timestamp < loan.dueDate)
            revert RedemptionVault_LoanNotExpired(user_, redemptionId_, loanId_);

        // Check that the loan is not already defaulted
        if (loan.isDefaulted)
            revert RedemptionVault_LoanAlreadyDefaulted(user_, redemptionId_, loanId_);

        // Check that the loan is not repaid
        if (loan.principal == 0)
            revert RedemptionVault_InvalidLoanId(user_, redemptionId_, loanId_);

        // Mark loan as defaulted
        uint256 previousPrincipal = loan.principal;
        loan.isDefaulted = true;
        loan.principal = 0;
        loan.interest = 0;

        // Withdraw deposit
        // This will burn the receipt tokens and return the deposit tokens
        IDepositFacility(redemption.facility).handleCommitWithdraw(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            previousPrincipal,
            address(this)
        );

        // Reduce redemption amount
        redemption.amount -= previousPrincipal;

        // Distribute residual value (keeper reward + treasury)
        uint256 keeperReward = previousPrincipal.mulDiv(
            keeperRewardPercentage,
            ONE_HUNDRED_PERCENT
        );
        uint256 treasuryAmount = previousPrincipal - keeperReward;

        if (keeperReward > 0) {
            ERC20(redemption.depositToken).safeTransfer(msg.sender, keeperReward);
        }

        if (treasuryAmount > 0) {
            ERC20(redemption.depositToken).safeTransfer(address(TRSRY), treasuryAmount);
        }

        emit LoanDefaulted(
            user_,
            redemptionId_,
            loanId_,
            loan.principal,
            loan.interest,
            previousPrincipal
        );
        emit RedemptionCancelled(
            user_,
            redemptionId_,
            address(redemption.depositToken),
            redemption.depositPeriod,
            previousPrincipal
        );
    }

    // ========== BORROWING VIEW FUNCTIONS ========== //

    /// @inheritdoc IDepositRedemptionVault
    function getAvailableBorrowForRedemption(
        address user_,
        uint16 redemptionId_
    ) public view returns (uint256) {
        // Get the redemption
        bytes32 redemptionKey = _getUserRedemptionKey(user_, redemptionId_);
        UserRedemption memory redemption = _userRedemptions[redemptionKey];

        if (redemption.depositToken == address(0)) return 0;

        // No need to check for the asset in maxBorrowPercentage, as the borrowPct will end up as 0.
        uint16 borrowPct = maxBorrowPercentage[redemption.depositToken];
        uint256 maxBorrow = redemption.amount.mulDiv(borrowPct, ONE_HUNDRED_PERCENT);
        uint256 totalBorrowed = _totalBorrowedPerRedemption[redemptionKey];

        return totalBorrowed >= maxBorrow ? 0 : maxBorrow - totalBorrowed;
    }

    /// @inheritdoc IDepositRedemptionVault
    function getRedemptionLoans(
        address user_,
        uint16 redemptionId_
    ) external view returns (Loan[] memory) {
        return _redemptionLoans[_getUserRedemptionKey(user_, redemptionId_)];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getTotalBorrowedForRedemption(
        address user_,
        uint16 redemptionId_
    ) external view returns (uint256) {
        return _totalBorrowedPerRedemption[_getUserRedemptionKey(user_, redemptionId_)];
    }

    // ========== ADMIN FUNCTIONS ========== //

    function setMaxBorrowPercentage(address asset, uint16 percent) external onlyAdminRole {
        require(percent <= 10000, "max 100%");
        maxBorrowPercentage[asset] = percent;
    }

    function setInterestRatePerYear(address asset, uint16 rate) external onlyAdminRole {
        interestRatePerYear[asset] = rate;
    }

    function setKeeperRewardPercentage(uint16 percent) external onlyAdminRole {
        require(percent <= 10000, "max 100%");
        keeperRewardPercentage = percent;
    }

    // ========== ERC165 ========== //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IDepositRedemptionVault).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
