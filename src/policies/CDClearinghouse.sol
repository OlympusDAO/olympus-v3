// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ERC4626} from "@solmate-6.2.0/mixins/ERC4626.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate-6.2.0/utils/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";
// import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

/// @title  Convertible Deposit Clearinghouse
/// @notice Enables holders of a specific CD token to borrow against their position
contract CDClearinghouse is IGenericClearinghouse, Policy, PolicyEnabler, CoolerCallback {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;
    using FixedPointMathLib for uint256;

    // ===== STATE VARIABLES ===== //

    /// @notice The debt token of the clearinghouse.
    ERC4626 internal immutable _DEBT_TOKEN;

    /// @notice The collateral token of the clearinghouse.
    /// @dev    This is set in `configureDependencies()`
    IERC20 internal _collateralToken;

    /// @notice The scale of the collateral token.
    /// @dev    This is the number of decimals of the collateral token.
    uint256 internal immutable _COLLATERAL_TOKEN_SCALE;

    /// @inheritdoc IGenericClearinghouse
    uint256 public principalReceivables;

    /// @inheritdoc IGenericClearinghouse
    uint256 public interestReceivables;

    /// @inheritdoc IGenericClearinghouse
    uint256 public override maxRewardPerLoan;

    /// @inheritdoc IGenericClearinghouse
    uint48 public override duration;

    /// @inheritdoc IGenericClearinghouse
    uint256 public override interestRate;

    /// @notice The ratio of the debt token (ERC4626) underlying asset to collateral tokens. Stored in terms of collateral tokens.
    ///         The ERC4626 underlying asset is used as it has the same terms as the collateral (CD) token. When a loan is originated, the current value in debt tokens will be calculated.
    ///         As the debt token is the yield-bearing vault token and the collateral is the CD token (which is in terms of the vault token's underlying asset), the ratio should be less than 100%. Otherwise, a borrower can borrow more than the value of the collateral that they provide.
    uint256 public loanToCollateral;

    // ===== MODULES ===== //

    /// @notice Clearinghouse Registry Module
    CHREGv1 public CHREG;

    /// @notice Convertible Depository Module
    // CDEPOv1 public CDEPO;

    /// @notice Treasury Module
    TRSRYv1 public TRSRY;

    // ===== CONSTRUCTOR ===== //

    constructor(
        address debtToken_,
        address coolerFactory_,
        address kernel_,
        uint256 maxRewardPerLoan_,
        uint48 duration_,
        uint256 loanToCollateral_,
        uint256 interestRate_
    ) Policy(Kernel(kernel_)) CoolerCallback(coolerFactory_) {
        _DEBT_TOKEN = ERC4626(debtToken_);

        // Validate that the debt token is an ERC4626 and not the zero address
        if (address(_DEBT_TOKEN.asset()) == address(0)) revert InvalidParams("debt token");

        // Set the collateral token scale
        // This is possible, since the ERC4626 vault and underlying asset have the same number of decimals, and the corresponding CD token from CDEPO (see `configureDependencies()`) has the same number of decimals as the ERC4626 underlying asset
        _COLLATERAL_TOKEN_SCALE = 10 ** _DEBT_TOKEN.decimals();

        maxRewardPerLoan = maxRewardPerLoan_;
        duration = duration_;
        loanToCollateral = loanToCollateral_;
        interestRate = interestRate_;

        // Emit events
        emit MaxRewardPerLoanSet(maxRewardPerLoan_);
        emit DurationSet(duration_);
        emit LoanToCollateralSet(loanToCollateral_);
        emit InterestRateSet(interestRate_);
    }

    // ===== POLICY FUNCTIONS ===== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        // dependencies[0] = toKeycode("CDEPO");
        dependencies[1] = toKeycode("CHREG");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        // CDEPO = CDEPOv1(getModuleAddress(dependencies[0]));
        CHREG = CHREGv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        // (uint8 CDEPO_MAJOR, ) = CDEPO.VERSION();
        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1]);
        if (CHREG_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Validate that the debt token's underlying asset is supported by the CDEPO module
        // TODO configure period months
        // _collateralToken = CDEPO.getConvertibleDepositToken(address(_DEBT_TOKEN.asset()), 6);
        if (address(_collateralToken) == address(0)) revert InvalidParams("debt token");

        // Validate that the decimals are the same
        if (_COLLATERAL_TOKEN_SCALE != 10 ** _collateralToken.decimals())
            revert InvalidParams("decimals");
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        // Keycode CDEPO_KEYCODE = toKeycode("CDEPO");

        requests = new Permissions[](2);
        requests[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        requests[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        // requests[2] = Permissions(CDEPO_KEYCODE, CDEPO.incurDebt.selector);
        // requests[3] = Permissions(CDEPO_KEYCODE, CDEPO.repayDebt.selector);
        // requests[4] = Permissions(CDEPO_KEYCODE, CDEPO.reduceDebt.selector);

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
            address(cooler_.collateral()) != address(_collateralToken) ||
            address(cooler_.debt()) != address(_DEBT_TOKEN)
        ) revert BadEscrow();

        // Adjust the loanToCollateral ratio to be in terms of the debt token
        uint256 loanToCollateralShares = loanToCollateral.mulDivDown(
            _DEBT_TOKEN.convertToShares(1e18),
            _COLLATERAL_TOKEN_SCALE
        );

        // Transfer in collateral owed
        uint256 collateral = cooler_.collateralFor(amount_, loanToCollateralShares);
        ERC20(address(_collateralToken)).safeTransferFrom(msg.sender, address(this), collateral);

        // Increment interest to be expected
        (, uint256 interest) = getLoanForCollateral(collateral);
        interestReceivables += interest;
        principalReceivables += amount_;

        // Create a new loan request.
        ERC20(address(_collateralToken)).safeApprove(address(cooler_), collateral);
        uint256 reqID = cooler_.requestLoan(
            amount_,
            interestRate,
            loanToCollateralShares,
            uint256(duration)
        );

        // Borrow from CDEPO
        // This will transfer the debt token from CDEPO to this contract
        // CDEPO.incurDebt(IERC4626(address(_DEBT_TOKEN)), amount_);

        // Clear the created loan request by providing enough reserve.
        _DEBT_TOKEN.safeApprove(address(cooler_), amount_);
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
        _DEBT_TOKEN.safeTransferFrom(msg.sender, address(this), interestBase * times_);

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
        // CDEPO.reduceDebt(IERC4626(address(_DEBT_TOKEN)), totalPrincipal);

        // Reward keeper.
        ERC20(address(_collateralToken)).safeTransfer(msg.sender, keeperRewards);

        // Burn the collateral token
        uint256 collateralBalance = _collateralToken.balanceOf(address(this));
        // ERC20(address(_collateralToken)).safeApprove(address(CDEPO), collateralBalance);
        // CDEPO.burn(_collateralToken, collateralBalance);

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
        if (principalPaid_ > 0) {
            // _DEBT_TOKEN.safeApprove(address(CDEPO), principalPaid_);
            // CDEPO.repayDebt(IERC4626(address(_DEBT_TOKEN)), principalPaid_);
        }

        // Sweep the yield
        _sweepYield();
    }

    /// @notice Unused callback since defaults are handled by the clearinghouse.
    /// @dev    Overriden and left empty to save gas.
    function _onDefault(uint256, uint256, uint256, uint256) internal override {}

    // ===== AUX FUNCTIONS ===== //

    /// @inheritdoc IGenericClearinghouse
    /// @dev    Adjusts the principal amount (in debt tokens) to the underlying asset of the debt token before calculating the collateral amount.
    ///         The collateral calculation rounds up to ensure that the collateral is sufficient to cover the loan.
    function getCollateralForLoan(uint256 principal_) external view returns (uint256) {
        // Get the current value of the debt token in terms of the underlying asset
        uint256 debtTokenValue = _DEBT_TOKEN.convertToAssets(principal_);

        // Principal = Collateral * LoanToCollateral
        // => Collateral = Principal / LoanToCollateral
        // This uses mulDivDown to be consistent with the calculations in Cooler.collateralFor()
        return debtTokenValue.mulDivDown(_COLLATERAL_TOKEN_SCALE, loanToCollateral);
    }

    /// @inheritdoc IGenericClearinghouse
    /// @dev    As the loan to collateral ratio is in terms of the debt token underlying asset, it is converted to debt token terms before returning.
    function getLoanForCollateral(uint256 collateral_) public view returns (uint256, uint256) {
        // This uses mulDivUp to avoid double-rounding when converting to debt token terms
        uint256 principalUnderlyingAsset = collateral_.mulDivUp(
            loanToCollateral,
            _COLLATERAL_TOKEN_SCALE
        );

        // Convert amount to debt token
        uint256 principal = _DEBT_TOKEN.convertToShares(principalUnderlyingAsset);

        uint256 interest = interestForLoan(principal, duration);
        return (principal, interest);
    }

    /// @inheritdoc IGenericClearinghouse
    function interestForLoan(uint256 principal_, uint256 duration_) public view returns (uint256) {
        uint256 interestPercent = uint256(interestRate).mulDivDown(duration_, 365 days);
        return principal_.mulDivDown(interestPercent, 1e18);
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
    /// @dev        In this implementation, the collateral token is the convertible deposit token corresponding to the debt token
    function collateralToken() external view override returns (IERC20) {
        return IERC20(address(_collateralToken));
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
    function setLoanToCollateral(uint256 loanToCollateral_) external onlyAdminRole {
        loanToCollateral = loanToCollateral_;

        emit LoanToCollateralSet(loanToCollateral_);
    }

    /// @notice Sets the interest rate of the loan.
    /// @dev    This function is restricted to the admin role.
    ///
    /// @param  interestRate_ The interest rate of the loan.
    function setInterestRate(uint256 interestRate_) external onlyAdminRole {
        interestRate = interestRate_;

        emit InterestRateSet(interestRate_);
    }
}
