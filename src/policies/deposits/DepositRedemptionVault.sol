// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";

// Libraries
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate-6.2.0/utils/ReentrancyGuard.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @title  DepositRedemptionVault
/// @notice A contract that manages the redemption of receipt tokens with facility coordination and borrowing
contract DepositRedemptionVault is
    Policy,
    IDepositRedemptionVault,
    PolicyEnabler,
    ReentrancyGuard
{
    using SafeTransferLib for ERC20;
    using FullMath for uint256;

    // ========== CONSTANTS ========== //

    /// @notice The number representing 100%
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice The maximum borrow percentage (85%)
    uint16 public constant MAX_BORROW_PERCENTAGE = 85e2;

    /// @notice The interest rate per month (configurable)
    uint16 public constant INTEREST_RATE_PER_MONTH = 5e2; // 5%

    /// @notice The keeper reward percentage (5%)
    uint16 public constant KEEPER_REWARD_PERCENTAGE = 5e2;

    // ========== CONFIGURABLE PARAMETERS ========== //
    /// @notice Per-asset max borrow percentage (in 100e2, e.g. 8500 = 85%)
    mapping(address => uint16) public maxBorrowPercentage;
    /// @notice Per-asset interest rate (annual, in 100e2, e.g. 500 = 5%)
    mapping(address => uint16) public interestRatePerYear;
    /// @notice Keeper reward percentage (in 100e2, e.g. 500 = 5%)
    uint16 public keeperRewardPercentage;

    // ========== STATE VARIABLES ========== //

    /// @notice The address of the token manager
    DepositManager public immutable DEPOSIT_MANAGER;

    /// @notice The TRSRY module.
    TRSRYv1 public TRSRY;

    /// @notice The ROLES module.
    ROLESv1 public ROLES;

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
    mapping(address => bool) internal _registeredFacilities;

    /// @notice Array of registered facilities for iteration
    address[] internal _facilitiesArray;

    /// @notice Loans for each redemption
    mapping(uint16 => Loan[]) internal _redemptionLoans;

    /// @notice The total borrowed amount per redemption
    mapping(uint16 => uint256) internal _totalBorrowedPerRedemption;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address kernel_,
        address depositManager_
    ) Policy(Kernel(kernel_)) {
        DEPOSIT_MANAGER = DepositManager(depositManager_);
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
    function registerFacility(address facility_) external onlyRole("admin") {
        if (facility_ == address(0)) revert RedemptionVault_InvalidFacility(facility_);
        if (_registeredFacilities[facility_]) revert RedemptionVault_InvalidFacility(facility_);

        _registeredFacilities[facility_] = true;
        _facilitiesArray.push(facility_);

        emit FacilityRegistered(facility_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function deauthorizeFacility(address facility_) external onlyRole("admin") {
        if (!_registeredFacilities[facility_]) revert RedemptionVault_FacilityNotRegistered(facility_);

        _registeredFacilities[facility_] = false;

        // Remove from array (keep order for gas efficiency)
        for (uint256 i = 0; i < _facilitiesArray.length; i++) {
            if (_facilitiesArray[i] == facility_) {
                _facilitiesArray[i] = _facilitiesArray[_facilitiesArray.length - 1];
                _facilitiesArray.pop();
                break;
            }
        }

        emit FacilityDeauthorized(facility_);
    }

    /// @inheritdoc IDepositRedemptionVault
    function isRegisteredFacility(address facility_) external view returns (bool) {
        return _registeredFacilities[facility_];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getRegisteredFacilities() external view returns (address[] memory) {
        return _facilitiesArray;
    }

    // ========== ASSETS ========== //

    /// @notice Pull the receipt tokens from the caller
    function _pullReceiptToken(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) internal {
        // Transfer the receipt tokens from the caller to this contract
        DEPOSIT_MANAGER.transferFrom(
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

    modifier onlyValidFacility(address facility_) {
        if (!_registeredFacilities[facility_]) revert RedemptionVault_FacilityNotRegistered(facility_);
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

        // Validate that the deposit token and period are supported
        if (!DEPOSIT_MANAGER.isAssetPeriod(depositToken_, depositPeriod_).isConfigured)
            revert RedemptionVault_InvalidToken(address(depositToken_), depositPeriod_);

        // Check that there are enough available deposits at the facility
        _validateAvailableDeposits(depositToken_, facility_, amount_);

        // Create a User Redemption
        redemptionId = _userRedemptionCount[msg.sender]++;
        _userRedemptions[_getUserRedemptionKey(msg.sender, redemptionId)] = UserRedemption({
            depositToken: address(depositToken_),
            depositPeriod: depositPeriod_,
            redeemableAt: uint48(block.timestamp + uint48(depositPeriod_) * 30 days),
            amount: amount_,
            facility: facility_
        });

        // Update the committed deposits
        _facilityCommittedDeposits[address(depositToken_)][facility_] += amount_;
        _totalCommittedDeposits[address(depositToken_)] += amount_;

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
        emit DepositsCommitted(address(depositToken_), facility_, amount_);

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

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Check that the amount is not greater than the redemption
        if (amount_ > redemption.amount)
            revert RedemptionVault_InvalidAmount(msg.sender, redemptionId_, amount_);

        // Update the redemption
        redemption.amount -= amount_;

        // Update the committed deposits
        _facilityCommittedDeposits[redemption.depositToken][redemption.facility] -= amount_;
        _totalCommittedDeposits[redemption.depositToken] -= amount_;

        // Transfer the quantity of receipt tokens to the caller
        DEPOSIT_MANAGER.transfer(
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

        // Check that the redemption is not already redeemed
        if (redemption.amount == 0)
            revert RedemptionVault_AlreadyRedeemed(msg.sender, redemptionId_);

        // Check that the redemption is redeemable
        if (block.timestamp < redemption.redeemableAt)
            revert RedemptionVault_TooEarly(msg.sender, redemptionId_);

        // Update the redemption
        uint256 redemptionAmount = redemption.amount;
        redemption.amount = 0;

        // Update the committed deposits
        _facilityCommittedDeposits[redemption.depositToken][redemption.facility] -= redemptionAmount;
        _totalCommittedDeposits[redemption.depositToken] -= redemptionAmount;

        // Delegate to the facility for withdrawal
        IDepositFacility(redemption.facility).handleWithdraw(
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

    /// @inheritdoc IDepositRedemptionVault
    function borrowAgainstRedemption(
        uint16 redemptionId_,
        uint256 amount_,
        address facility_
    ) external nonReentrant onlyEnabled onlyValidRedemptionId(msg.sender, redemptionId_) onlyValidFacility(facility_) returns (uint256 loanIndex) {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        // Check that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Use per-asset config
        uint16 borrowPct = maxBorrowPercentage[redemption.depositToken];
        if (borrowPct == 0) borrowPct = 8500; // default 85%
        uint256 maxBorrow = redemption.amount.mulDiv(borrowPct, ONE_HUNDRED_PERCENT);
        uint256 availableBorrow = maxBorrow - _totalBorrowedPerRedemption[redemptionId_];
        if (amount_ > availableBorrow) revert RedemptionVault_BorrowLimitExceeded(amount_, availableBorrow);

        // Interest: annualized, prorated for period
        uint16 rate = interestRatePerYear[redemption.depositToken];
        if (rate == 0) rate = 500; // default 5%
        uint256 interest = amount_.mulDiv(rate, ONE_HUNDRED_PERCENT) * redemption.depositPeriod / 12;

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
        emit LoanCreated(
            msg.sender,
            redemptionId_,
            amount_,
            loanIndex,
            facility_
        );

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
            uint256 receiptTokenBalance = DEPOSIT_MANAGER.balanceOf(address(this), receiptTokenId);

            if (receiptTokenBalance > 0) {
                DEPOSIT_MANAGER.transfer(msg.sender, receiptTokenId, receiptTokenBalance);
            }
        }
    }

    /// @inheritdoc IDepositRedemptionVault
    function extendLoan(uint16 redemptionId_, uint256 loanIndex_, uint48 newDueDate_) external onlyEnabled {
        // Get the redemption
        UserRedemption storage redemption = _userRedemptions[
            _getUserRedemptionKey(msg.sender, redemptionId_)
        ];

        if (redemption.depositToken == address(0))
            revert RedemptionVault_InvalidRedemptionId(msg.sender, redemptionId_);

        // Get loans for this redemption
        Loan[] storage loans = _redemptionLoans[redemptionId_];
        if (loanIndex_ >= loans.length) revert RedemptionVault_InvalidLoanIndex(redemptionId_, loanIndex_);

        Loan storage loan = loans[loanIndex_];
        if (loan.isDefaulted) revert RedemptionVault_InvalidLoanIndex(redemptionId_, loanIndex_);

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
        if (loanIndex_ >= loans.length) revert RedemptionVault_InvalidLoanIndex(redemptionId_, loanIndex_);

        Loan storage loan = loans[loanIndex_];
        if (loan.isDefaulted) revert RedemptionVault_InvalidLoanIndex(redemptionId_, loanIndex_);

        // Check if loan is expired
        if (block.timestamp < loan.dueDate) revert RedemptionVault_LoanNotExpired(redemptionId_, loanIndex_);

        // Mark loan as defaulted
        loan.isDefaulted = true;

        // Calculate collateral to burn (receipt tokens)
        uint256 collateralToBurn = loan.principal + loan.interest;

        // Burn collateral
        uint256 receiptTokenId = DEPOSIT_MANAGER.getReceiptTokenId(
            IERC20(redemption.depositToken),
            redemption.depositPeriod
        );
        DEPOSIT_MANAGER.burn(address(this), receiptTokenId, collateralToBurn);

        // Reduce redemption amount
        redemption.amount -= collateralToBurn;

        // Update committed deposits
        _facilityCommittedDeposits[redemption.depositToken][redemption.facility] -= collateralToBurn;
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

        emit LoanDefaulted(redemptionId_, loanIndex_, loan.principal, loan.interest, collateralToBurn);
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

        // Use per-asset config
        uint16 borrowPct = maxBorrowPercentage[redemption.depositToken];
        if (borrowPct == 0) borrowPct = 8500; // default 85%
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

    // ========== RECLAIM ========== //

    /// @inheritdoc IDepositRedemptionVault
    function previewReclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) public view onlyEnabled returns (uint256 reclaimed) {
        // Validate that the amount is not 0
        if (amount_ == 0) revert RedemptionVault_ZeroAmount();

        // Validate that there are enough available deposits
        _validateAvailableDeposits(depositToken_, address(0), amount_);

        // This is rounded down to keep assets in the vault, otherwise the contract may end up
        // in a state where there are not enough of the assets in the vault to redeem/reclaim
        reclaimed = amount_.mulDiv(
            DEPOSIT_MANAGER.getAssetPeriodReclaimRate(depositToken_, depositPeriod_),
            ONE_HUNDRED_PERCENT
        );

        // If the reclaimed amount is 0, revert
        if (reclaimed == 0) revert RedemptionVault_ZeroAmount();

        return reclaimed;
    }

    /// @inheritdoc IDepositRedemptionVault
    function reclaimFor(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        address recipient_,
        uint256 amount_
    ) public nonReentrant onlyEnabled returns (uint256 reclaimed) {
        // Calculate the quantity of deposit token to withdraw and return
        // This will create a difference between the quantity of deposit tokens and the vault shares, which will be swept as yield
        uint256 discountedAssetsOut = previewReclaim(depositToken_, depositPeriod_, amount_);

        // Withdraw the deposit tokens from the deposit manager
        // This will burn the receipt tokens from the caller and send the released deposit tokens to this contract
        DEPOSIT_MANAGER.withdraw(
            IDepositManager.WithdrawParams({
                asset: depositToken_,
                depositPeriod: depositPeriod_,
                depositor: msg.sender,
                recipient: address(this),
                amount: amount_,
                isWrapped: false
            })
        );

        // Transfer discounted amount of the deposit token to the recipient
        ERC20(address(depositToken_)).safeTransfer(recipient_, discountedAssetsOut);

        // Transfer the remaining deposit tokens to the TRSRY
        ERC20(address(depositToken_)).safeTransfer(address(TRSRY), amount_ - discountedAssetsOut);

        // Emit event
        emit Reclaimed(
            recipient_,
            address(depositToken_),
            depositPeriod_,
            discountedAssetsOut,
            amount_ - discountedAssetsOut
        );

        return discountedAssetsOut;
    }

    /// @inheritdoc IDepositRedemptionVault
    function reclaim(
        IERC20 depositToken_,
        uint8 depositPeriod_,
        uint256 amount_
    ) external returns (uint256 reclaimed) {
        reclaimed = reclaimFor(depositToken_, depositPeriod_, msg.sender, amount_);
    }

    // ========== DEPOSITS ========== //

    function _validateAvailableDeposits(IERC20 depositToken_, address facility_, uint256 amount_) internal view {
        uint256 availableDeposits;
        if (facility_ == address(0)) {
            availableDeposits = getAvailableDeposits(depositToken_);
        } else {
            availableDeposits = getAvailableDepositsForFacility(depositToken_, facility_);
        }

        if (amount_ > availableDeposits)
            revert RedemptionVault_InsufficientAvailableDeposits(amount_, availableDeposits);
    }

    /// @inheritdoc IDepositRedemptionVault
    function getAvailableDeposits(
        IERC20 depositToken_
    ) public view returns (uint256 availableDeposits) {
        // Get the amount of committed deposits
        uint256 committedDeposits = _totalCommittedDeposits[address(depositToken_)];

        // Get the amount of available deposits
        (, uint256 sharesInAssets) = DEPOSIT_MANAGER.getOperatorAssets(
            depositToken_,
            address(this)
        );

        // Ensure it doesn't revert
        if (committedDeposits > sharesInAssets) {
            return 0;
        }

        // Return the difference
        return sharesInAssets - committedDeposits;
    }

    /// @inheritdoc IDepositRedemptionVault
    function getFacilityCommittedDeposits(
        IERC20 depositToken_,
        address facility_
    ) external view returns (uint256) {
        return _facilityCommittedDeposits[address(depositToken_)][facility_];
    }

    /// @inheritdoc IDepositRedemptionVault
    function getTotalCommittedDeposits(IERC20 depositToken_) external view returns (uint256) {
        return _totalCommittedDeposits[address(depositToken_)];
    }

    /// @notice Get available deposits for a specific facility
    /// @param depositToken_ The deposit token to query
    /// @param facility_ The facility to query
    /// @return The available deposits for this facility
    function getAvailableDepositsForFacility(
        IERC20 depositToken_,
        address facility_
    ) public view returns (uint256) {
        // Get the facility's deposit balance
        uint256 facilityBalance = IDepositFacility(facility_).getDepositBalance(depositToken_);

        // Get the facility's committed deposits
        uint256 committedDeposits = _facilityCommittedDeposits[address(depositToken_)][facility_];

        // Return available deposits
        return committedDeposits > facilityBalance ? 0 : facilityBalance - committedDeposits;
    }

    // ========== ADMIN FUNCTIONS ========== //
    function setMaxBorrowPercentage(address asset, uint16 percent) external onlyRole("admin") {
        require(percent <= 10000, "max 100%");
        maxBorrowPercentage[asset] = percent;
    }
    function setInterestRatePerYear(address asset, uint16 rate) external onlyRole("admin") {
        interestRatePerYear[asset] = rate;
    }
    function setKeeperRewardPercentage(uint16 percent) external onlyRole("admin") {
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