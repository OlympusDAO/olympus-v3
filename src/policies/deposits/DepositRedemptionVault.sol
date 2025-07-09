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

    /// @notice The amount of deposit tokens that have been committed for redemption per facility
    /// @dev    This tracks committed deposits per facility for better coordination
    mapping(address => mapping(address => uint256)) internal _facilityCommittedDeposits;

    /// @notice The total committed deposits per token across all facilities
    mapping(address => uint256) internal _totalCommittedDeposits;

    /// @notice Registered facilities
    EnumerableSet.AddressSet internal _authorizedFacilities;

    /// @notice Loans for each redemption
    mapping(uint16 => Loan[]) internal _redemptionLoans;

    /// @notice The total borrowed amount per redemption
    mapping(uint16 => uint256) internal _totalBorrowedPerRedemption;

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
        if (_authorizedFacilities.contains(facility_)) revert RedemptionVault_FacilityExists(facility_);

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

    // NOTE: implementation not reviewed or tested yet

    /// @inheritdoc IDepositRedemptionVault
    function borrowAgainstRedemption(
        uint16 redemptionId_,
        uint256 amount_,
        address facility_
    )
        external
        nonReentrant
        onlyEnabled
        onlyValidRedemptionId(msg.sender, redemptionId_)
        onlyValidFacility(facility_)
        returns (uint256 loanIndex)
    {
        // TODO derive facility from redemption

        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // TODO Confirm that the borrow and interest rates are set

        {
            // Use per-asset config
            uint16 borrowPct = maxBorrowPercentage[redemption.depositToken];
            uint256 maxBorrow = redemption.amount.mulDiv(borrowPct, ONE_HUNDRED_PERCENT);
            uint256 availableBorrow = maxBorrow - _totalBorrowedPerRedemption[redemptionId_];
            if (amount_ > availableBorrow)
                revert RedemptionVault_BorrowLimitExceeded(amount_, availableBorrow);
        }

        // Interest: annualized, prorated for period
        uint256 interest;
        {
            uint16 rate = interestRatePerYear[redemption.depositToken];
            if (rate == 0) rate = 500; // default 5%
            interest = (amount_.mulDiv(rate, ONE_HUNDRED_PERCENT) * redemption.depositPeriod) / 12;
        }

        // Create loan
        Loan memory newLoan = Loan({
            principal: amount_,
            interest: interest,
            dueDate: redemption.redeemableAt,
            facility: facility_,
            isDefaulted: false
        });

        // Add loan to the redemption
        _redemptionLoans[redemptionId_].push(newLoan);
        loanIndex = _redemptionLoans[redemptionId_].length - 1;

        // Update total borrowed
        _totalBorrowedPerRedemption[redemptionId_] += amount_;

        // Delegate to the facility for borrowing
        IDepositFacility(facility_).handleBorrow(
            IERC20(redemption.depositToken),
            redemption.depositPeriod,
            amount_,
            msg.sender
        );

        // Emit event
        emit LoanCreated(msg.sender, redemptionId_, amount_, loanIndex, facility_);

        return loanIndex;
    }

    /// @inheritdoc IDepositRedemptionVault
    function repayBorrow(uint16 redemptionId_, uint256 amount_) external nonReentrant onlyEnabled {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        if (redemption.depositToken == address(0))
            revert RedemptionVault_InvalidRedemptionId(msg.sender, redemptionId_);

        // Get loans for this redemption
        Loan[] storage loans = _redemptionLoans[redemptionId_];
        if (loans.length == 0) revert RedemptionVault_NoActiveLoans(redemptionId_);

        uint256 remainingAmount = amount_;
        uint256 totalRepaid = 0;

        // Repay loans in FIFO order
        for (uint256 i = 0; i < loans.length && remainingAmount > 0; i++) {
            if (loans[i].isDefaulted) continue; // Skip defaulted loans

            uint256 loanTotal = loans[i].principal + loans[i].interest;
            uint256 repayAmount = remainingAmount > loanTotal ? loanTotal : remainingAmount;

            if (repayAmount > 0) {
                // Delegate repayment handling to the facility
                IDepositFacility(loans[i].facility).handleRepay(
                    IERC20(redemption.depositToken),
                    redemption.depositPeriod,
                    repayAmount,
                    msg.sender
                );

                // Update loan state
                if (repayAmount >= loanTotal) {
                    // Full repayment
                    loans[i].principal = 0;
                    loans[i].interest = 0;
                } else {
                    // Partial repayment (pay interest first, then principal)
                    if (repayAmount <= loans[i].interest) {
                        loans[i].interest -= repayAmount;
                    } else {
                        uint256 remainingRepay = repayAmount - loans[i].interest;
                        loans[i].interest = 0;
                        loans[i].principal -= remainingRepay;
                    }
                }

                remainingAmount -= repayAmount;
                totalRepaid += repayAmount;

                emit LoanRepaid(msg.sender, redemptionId_, repayAmount, i);
            }
        }

        // Update total borrowed
        _totalBorrowedPerRedemption[redemptionId_] -= totalRepaid;

        // Return receipt tokens if fully repaid
        if (_totalBorrowedPerRedemption[redemptionId_] == 0) {
            uint256 receiptTokenId = DEPOSIT_MANAGER.getReceiptTokenId(
                IERC20(redemption.depositToken),
                redemption.depositPeriod
            );
            uint256 receiptTokenBalance = IERC6909(address(DEPOSIT_MANAGER)).balanceOf(
                address(this),
                receiptTokenId
            );

            if (receiptTokenBalance > 0) {
                IERC6909(address(DEPOSIT_MANAGER)).transfer(
                    msg.sender,
                    receiptTokenId,
                    receiptTokenBalance
                );
            }
        }
    }

    /// @inheritdoc IDepositRedemptionVault
    function extendLoan(
        uint16 redemptionId_,
        uint256 loanIndex_,
        uint48 newDueDate_
    ) external onlyEnabled {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        if (redemption.depositToken == address(0))
            revert RedemptionVault_InvalidRedemptionId(msg.sender, redemptionId_);

        // Get loans for this redemption
        Loan[] storage loans = _redemptionLoans[redemptionId_];
        if (loanIndex_ >= loans.length)
            revert RedemptionVault_InvalidLoanId(redemptionId_, loanIndex_);

        Loan storage loan = loans[loanIndex_];
        if (loan.isDefaulted) revert RedemptionVault_InvalidLoanId(redemptionId_, loanIndex_);

        // Update due date
        loan.dueDate = newDueDate_;

        emit LoanExtended(msg.sender, redemptionId_, loanIndex_, newDueDate_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function handleLoanDefault(uint16 redemptionId_, uint256 loanIndex_) external {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        if (redemption.depositToken == address(0))
            revert RedemptionVault_InvalidRedemptionId(msg.sender, redemptionId_);

        // Get loans for this redemption
        Loan[] storage loans = _redemptionLoans[redemptionId_];
        if (loanIndex_ >= loans.length)
            revert RedemptionVault_InvalidLoanId(redemptionId_, loanIndex_);

        Loan storage loan = loans[loanIndex_];
        if (loan.isDefaulted) revert RedemptionVault_InvalidLoanId(redemptionId_, loanIndex_);

        // Check if loan is expired
        if (block.timestamp < loan.dueDate)
            revert RedemptionVault_LoanNotExpired(redemptionId_, loanIndex_);

        // Mark loan as defaulted
        loan.isDefaulted = true;

        // Calculate collateral to burn (receipt tokens)
        uint256 collateralToBurn = loan.principal + loan.interest;

        // Burn collateral
        uint256 receiptTokenId = DEPOSIT_MANAGER.getReceiptTokenId(
            IERC20(redemption.depositToken),
            redemption.depositPeriod
        );
        // TODO burn receipt tokens
        // DEPOSIT_MANAGER.burn(address(this), receiptTokenId, collateralToBurn);

        // Reduce redemption amount
        redemption.amount -= collateralToBurn;

        // Update committed deposits
        _facilityCommittedDeposits[redemption.depositToken][
            redemption.facility
        ] -= collateralToBurn;
        _totalCommittedDeposits[redemption.depositToken] -= collateralToBurn;

        // Distribute residual value (keeper reward + treasury)
        uint16 keeperPct = keeperRewardPercentage;
        if (keeperPct == 0) keeperPct = 500; // default 5%
        uint256 keeperReward = collateralToBurn.mulDiv(keeperPct, ONE_HUNDRED_PERCENT);
        uint256 treasuryAmount = collateralToBurn - keeperReward;

        if (keeperReward > 0) {
            ERC20(redemption.depositToken).safeTransfer(msg.sender, keeperReward);
        }

        if (treasuryAmount > 0) {
            ERC20(redemption.depositToken).safeTransfer(address(TRSRY), treasuryAmount);
        }

        emit LoanDefaulted(
            redemptionId_,
            loanIndex_,
            loan.principal,
            loan.interest,
            collateralToBurn
        );
        emit RedemptionAmountDecreased(redemptionId_, collateralToBurn);
    }

    // ========== BORROWING VIEW FUNCTIONS ========== //

    /// @inheritdoc IDepositRedemptionVault
    function getAvailableBorrowForRedemption(uint16 redemptionId_) public view returns (uint256) {
        // Get the redemption
        UserRedemption memory redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        if (redemption.depositToken == address(0)) return 0;

        // No need to check for the asset in maxBorrowPercentage, as the borrowPct will end up as 0.
        uint16 borrowPct = maxBorrowPercentage[redemption.depositToken];
        uint256 maxBorrow = redemption.amount.mulDiv(borrowPct, ONE_HUNDRED_PERCENT);
        uint256 totalBorrowed = _totalBorrowedPerRedemption[redemptionId_];

        return totalBorrowed >= maxBorrow ? 0 : maxBorrow - totalBorrowed;
    }

    /// @inheritdoc IDepositRedemptionVault
    function getRedemptionLoans(uint16 redemptionId_) external view returns (Loan[] memory) {
        return _redemptionLoans[redemptionId_];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getTotalBorrowedForRedemption(uint16 redemptionId_) external view returns (uint256) {
        return _totalBorrowedPerRedemption[redemptionId_];
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
