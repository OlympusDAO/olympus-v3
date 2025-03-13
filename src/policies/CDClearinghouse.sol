// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Libraries
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FullMath} from "src/libraries/FullMath.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";
import {CDEPOv1} from "modules/CDEPO/CDEPO.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";

/// @title  Convertible Depository Clearinghouse
/// @notice Enables CD token holders to borrow against their position
contract CDClearinghouse is IGenericClearinghouse, Policy, PolicyEnabler, CoolerCallback {
    using SafeTransferLib for ERC4626;
    using FullMath for uint256;

    // ===== STATE VARIABLES ===== //

    ERC4626 internal immutable _DEBT_TOKEN;

    /// @inheritdoc IGenericClearinghouse
    uint256 public principalReceivables;

    /// @inheritdoc IGenericClearinghouse
    uint256 public interestReceivables;

    /// @inheritdoc IGenericClearinghouse
    uint256 public override maxRewardPerLoan;

    /// @inheritdoc IGenericClearinghouse
    uint48 public override duration;

    /// @inheritdoc IGenericClearinghouse
    uint16 public override interestRate;

    /// @notice The ratio of the debt token (ERC4626) underlying asset to collateral tokens.
    ///         The ERC4626 underlying asset is used as it has the same terms as the collateral (CD) token. When a loan is originated, the current value in debt tokens will be calculated.
    /// @dev    Stored as a percentage, in terms of `ONE_HUNDRED_PERCENT`.
    ///         As the debt token is the yield-bearing vault token and the collateral is the CD token (which is in terms of the vault token's underlying asset), the ratio should be less than 100%. Otherwise, a borrower can borrow more than the value of the collateral that they provide.
    uint16 public loanToCollateral;

    /// @notice The constant value of 100%.
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    // ===== MODULES ===== //

    /// @notice Clearinghouse Registry Module
    CHREGv1 public CHREG;

    /// @notice Convertible Depository Module
    /// @dev    The value for this module cannot be changed after it is initially set through `configureDependencies()`.
    CDEPOv1 public CDEPO;

    /// @notice Treasury Module
    TRSRYv1 public TRSRY;

    // ===== CONSTRUCTOR ===== //

    constructor(
        address debtToken_,
        address coolerFactory_,
        address kernel_,
        uint256 maxRewardPerLoan_,
        uint48 duration_,
        uint16 loanToCollateral_,
        uint16 interestRate_
    ) Policy(Kernel(kernel_)) CoolerCallback(coolerFactory_) {
        // Validate that the debt token is an ERC4626
        if (address(ERC4626(debtToken_).asset()) == address(0)) revert InvalidParams("debt token");

        _DEBT_TOKEN = ERC4626(debtToken_);

        maxRewardPerLoan = maxRewardPerLoan_;
        duration = duration_;
        loanToCollateral = loanToCollateral_;
        interestRate = interestRate_;

        emit MaxRewardPerLoanSet(maxRewardPerLoan_);
        emit LoanToCollateralSet(loanToCollateral_);
        emit InterestRateState(interestRate_);
    }

    // ===== POLICY FUNCTIONS ===== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("CDEPO");
        dependencies[1] = toKeycode("CHREG");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        // Validate that CDEPO is not being changed
        address newCDEPO = getModuleAddress(dependencies[0]);
        if (address(CDEPO) != address(0) && address(CDEPO) != address(newCDEPO))
            revert InvalidParams("CDEPO");

        CDEPO = CDEPOv1(newCDEPO);
        CHREG = CHREGv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        (uint8 CDEPO_MAJOR, ) = CDEPO.VERSION();
        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        if (CDEPO_MAJOR != 1 || CHREG_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Ensure that the tokens match with CDEPO's
        if (address(CDEPO.VAULT()) != address(_DEBT_TOKEN)) revert InvalidParams("CDEPO vault");
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        Keycode CDEPO_KEYCODE = toKeycode("CDEPO");

        requests = new Permissions[](4);
        requests[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        requests[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        requests[2] = Permissions(CDEPO_KEYCODE, CDEPO.incurDebt.selector);
        requests[3] = Permissions(CDEPO_KEYCODE, CDEPO.repayDebt.selector);

        return requests;
    }

    /// @notice Returns the version of the policy.
    ///
    /// @return major The major version of the policy.
    /// @return minor The minor version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ===== LENDING FUNCTIONS ===== //

    /// @inheritdoc IGenericClearinghouse
    function lendToCooler(ICooler cooler_, uint256 amount_) external onlyEnabled returns (uint256) {
        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();

        // Validate cooler collateral and debt tokens.
        if (
            address(cooler_.collateral()) != address(CDEPO) ||
            address(cooler_.debt()) != address(_DEBT_TOKEN)
        ) revert BadEscrow();

        // Transfer in collateral owed
        uint256 collateral = cooler_.collateralFor(amount_, loanToCollateral);
        CDEPO.transferFrom(msg.sender, address(this), collateral);

        // Increment interest to be expected
        (, uint256 interest) = getLoanForCollateral(collateral);
        interestReceivables += interest;
        principalReceivables += amount_;

        // Create a new loan request.
        CDEPO.approve(address(cooler_), collateral);
        uint256 reqID = cooler_.requestLoan(
            amount_,
            interestRate,
            loanToCollateral,
            uint256(duration)
        );

        // Borrow from CDEPO
        // This will transfer `_DEBT_TOKEN` from CDEPO to this contract
        CDEPO.incurDebt(amount_);

        // Clear the created loan request by providing enough reserve.
        _DEBT_TOKEN.approve(address(cooler_), amount_);
        uint256 loanID = cooler_.clearRequest(reqID, address(this), true);

        return loanID;
    }

    /// @inheritdoc IGenericClearinghouse
    function extendLoan(ICooler cooler_, uint256 loanId_, uint8 times_) external {
        ICooler.Loan memory loan = cooler_.getLoan(loanId_);

        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();

        // Calculate extension interest based on the remaining principal.
        uint256 interestBase = interestForLoan(loan.principal, loan.request.duration);

        // Transfer in extension interest from the caller.
        _DEBT_TOKEN.transferFrom(msg.sender, address(this), interestBase * times_);

        // Signal to cooler that loan should be extended.
        cooler_.extendLoanTerms(loanId_, times_);

        // Sweep yield
        _sweepYield();
    }

    /// @inheritdoc IGenericClearinghouse
    function claimDefaulted(address[] calldata coolers_, uint256[] calldata loans_) external {
        uint256 loans = loans_.length;
        if (loans != coolers_.length) revert LengthDiscrepancy();

        uint256 keeperRewards;
        uint256 totalInterest;
        uint256 totalPrincipal;
        for (uint256 i = 0; i < loans; ) {
            // Validate that cooler was deployed by the trusted factory.
            if (!factory.created(coolers_[i])) revert OnlyFromFactory();

            // Validate that loan was written by clearinghouse.
            if (ICooler(coolers_[i]).getLoan(loans_[i]).lender != address(this)) revert NotLender();

            // Claim defaults and update cached metrics.
            // This will transfer the collateral from the cooler to this contract
            (uint256 principal, uint256 interest, uint256 collateral, uint256 elapsed) = ICooler(
                coolers_[i]
            ).claimDefaulted(loans_[i]);

            unchecked {
                // Cannot overflow due to max supply limits for both tokens
                totalPrincipal += principal;
                totalInterest += interest;
                // There will not exist more than 2**256 loans
                ++i;
            }

            // Cap rewards to 5% of the collateral
            uint256 maxAuctionReward = (collateral * 5e16) / 1e18;

            // Cap rewards to avoid exorbitant amounts.
            uint256 maxReward = (maxAuctionReward < maxRewardPerLoan)
                ? maxAuctionReward
                : maxRewardPerLoan;

            // Calculate rewards based on the elapsed time since default.
            keeperRewards = (elapsed < 7 days)
                ? keeperRewards + (maxReward * elapsed) / 7 days
                : keeperRewards + maxReward;
        }

        // Decrement loan receivables.
        interestReceivables = (interestReceivables > totalInterest)
            ? interestReceivables - totalInterest
            : 0;
        principalReceivables = (principalReceivables > totalPrincipal)
            ? principalReceivables - totalPrincipal
            : 0;

        // Reduce the debt owed to CDEPO
        // CDEPO will cap the reduction to the amount owed
        CDEPO.reduceDebt(totalPrincipal);

        // Reward keeper.
        CDEPO.transfer(msg.sender, keeperRewards);

        // Burn the collateral token
        CDEPO.burn(CDEPO.balanceOf(address(this)));

        // Sweep yield
        _sweepYield();
    }

    /// @notice Sweeps yield held in the Clearinghouse into the TRSRY as `_DEBT_TOKEN`
    function _sweepYield() internal {
        // This contract does not hold any debt token or underlying assets as part of the operations
        // Any balances are therefore yield and should be swept to the TRSRY contract

        uint256 debtTokenBalance = _DEBT_TOKEN.balanceOf(address(this));
        if (debtTokenBalance == 0) return;

        // Transfer to the TRSRY
        _DEBT_TOKEN.safeTransfer(address(TRSRY), debtTokenBalance);

        // Emit event
        emit YieldSwept(address(TRSRY), debtTokenBalance);
    }

    // ===== COOLER CALLBACKS ===== //

    /// @notice Overridden callback to decrement loan receivables.
    ///
    /// @param  principalPaid_ in reserve.
    /// @param  interestPaid_ in reserve.
    function _onRepay(uint256, uint256 principalPaid_, uint256 interestPaid_) internal override {
        // Decrement loan receivables.
        interestReceivables = (interestReceivables > interestPaid_)
            ? interestReceivables - interestPaid_
            : 0;
        principalReceivables = (principalReceivables > principalPaid_)
            ? principalReceivables - principalPaid_
            : 0;

        // Repay the debt token to CDEPO
        _DEBT_TOKEN.safeApprove(address(CDEPO), principalPaid_);
        CDEPO.repayDebt(principalPaid_);

        // Sweep the yield
        _sweepYield();
    }

    /// @notice Unused callback since defaults are handled by the clearinghouse.
    /// @dev    Overriden and left empty to save gas.
    function _onDefault(uint256, uint256, uint256, uint256) internal override {}

    // ===== AUX FUNCTIONS ===== //

    /// @inheritdoc IGenericClearinghouse
    /// @dev    Adjusts the principal amount (in debt tokens) to the underlying asset of the debt token before calculating the collateral amount.
    function getCollateralForLoan(uint256 principal_) external view returns (uint256) {
        // Get the current value of the debt token in terms of the underlying asset
        uint256 debtTokenValue = _DEBT_TOKEN.convertToAssets(principal_);

        return debtTokenValue.mulDiv(ONE_HUNDRED_PERCENT, loanToCollateral);
    }

    /// @inheritdoc IGenericClearinghouse
    /// @dev    As the loan to collateral ratio is in terms of the debt token underlying asset, it is converted to debt token terms before returning.
    function getLoanForCollateral(uint256 collateral_) public view returns (uint256, uint256) {
        uint256 principalUnderlyingAsset = collateral_.mulDiv(
            loanToCollateral,
            ONE_HUNDRED_PERCENT
        );

        // Convert amount to debt token
        uint256 principal = _DEBT_TOKEN.convertToShares(principalUnderlyingAsset);

        uint256 interest = interestForLoan(principal, duration);
        return (principal, interest);
    }

    /// @inheritdoc IGenericClearinghouse
    function interestForLoan(uint256 principal_, uint256 duration_) public view returns (uint256) {
        uint256 interestPercent = uint256(interestRate).mulDiv(duration_, 365 days);
        return principal_.mulDiv(interestPercent, ONE_HUNDRED_PERCENT);
    }

    /// @inheritdoc IGenericClearinghouse
    function getTotalReceivables() external view returns (uint256) {
        return principalReceivables + interestReceivables;
    }

    // ===== OVERRIDE FUNCTIONS ===== //

    /// @inheritdoc IGenericClearinghouse
    /// @dev        In this implementation, the debt token is the ERC4626 vault token used by CDEPO to store deposited funds
    function debtToken() external view override returns (IERC20) {
        return IERC20(address(_DEBT_TOKEN));
    }

    /// @inheritdoc IGenericClearinghouse
    /// @dev        In this implementation, the collateral token is the CDEPO token
    function collateralToken() external view override returns (IERC20) {
        return IERC20(address(CDEPO));
    }

    /// @dev    This implementation activates the Clearinghouse in CHREG
    function _enable(bytes calldata) internal override {
        // Activate the Clearinghouse in CHREG
        CHREG.activateClearinghouse(address(this));
    }

    /// @dev    This implementation deactivates the Clearinghouse in CHREG
    function _disable(bytes calldata) internal override {
        // Deactivate the Clearinghouse in CHREG
        CHREG.deactivateClearinghouse(address(this));
    }

    // ===== ADMIN FUNCTIONS ===== //

    /// @notice Sets the maximum reward (in collateral tokens) per loan.
    /// @dev    This function is restricted to the admin role.
    ///
    /// @param  maxRewardPerLoan_ The maximum reward (in collateral tokens) per loan.
    function setMaxRewardPerLoan(uint256 maxRewardPerLoan_) external onlyAdminRole {
        maxRewardPerLoan = maxRewardPerLoan_;

        emit MaxRewardPerLoanSet(maxRewardPerLoan_);
    }

    /// @notice Sets the duration of the loan.
    /// @dev    This function is restricted to the admin role.
    ///
    /// @param  duration_ The duration of the loan.
    function setDuration(uint48 duration_) external onlyAdminRole {
        duration = duration_;

        emit DurationSet(duration_);
    }

    /// @notice Sets the ratio of debt tokens to collateral tokens.
    /// @dev    This function is restricted to the admin role.
    ///
    /// @param  loanToCollateral_ The ratio of debt tokens to collateral tokens.
    function setLoanToCollateral(uint16 loanToCollateral_) external onlyAdminRole {
        loanToCollateral = loanToCollateral_;

        emit LoanToCollateralSet(loanToCollateral_);
    }

    /// @notice Sets the interest rate of the loan.
    /// @dev    This function is restricted to the admin role.
    ///
    /// @param  interestRate_ The interest rate of the loan.
    function setInterestRate(uint16 interestRate_) external onlyAdminRole {
        interestRate = interestRate_;

        emit InterestRateState(interestRate_);
    }
}
