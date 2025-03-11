// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";
import {ICoolerFactory} from "src/external/cooler/interfaces/ICoolerFactory.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";

contract CDClearinghouse is IGenericClearinghouse, Policy, PolicyEnabler, CoolerCallback {
    // ===== STATE VARIABLES ===== //

    ERC20 internal immutable _debtToken;

    ERC4626 internal immutable _sDebtToken;

    ERC20 internal immutable _collateralToken;

    ICoolerFactory public immutable coolerFactory;

    uint256 public principalReceivables;

    uint256 public interestReceivables;

    uint256 public constant DURATION = 121 days; // Four months

    uint256 public constant INTEREST_RATE = 1e18;
    uint256 public constant MAX_REWARD = 5e16; // 5%

    // TODO interest rate

    // TODO max reward

    uint256 public loanToCollateral = 9e17; // 0.9 debt token per collateral token

    // ===== MODULES ===== //

    CHREGv1 public CHREG; // Olympus V3 Clearinghouse Registry Module

    // ===== CONSTRUCTOR ===== //

    constructor(
        address collateralToken_,
        address sDebtToken_,
        address coolerFactory_,
        address kernel_
    ) Policy(Kernel(kernel_)) CoolerCallback(coolerFactory_) {
        _collateralToken = ERC20(collateralToken_);
        _sDebtToken = ERC4626(sDebtToken_);
        _debtToken = ERC20(address(_sDebtToken.asset()));
        coolerFactory = ICoolerFactory(coolerFactory_);
    }

    // ===== POLICY FUNCTIONS ===== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("ROLES");

        CHREG = CHREGv1(getModuleAddress(toKeycode("CHREG")));
        ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));

        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // TODO add DEPO
        // TODO consider what if CDEPO changes

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (CHREG_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode CHREG_KEYCODE = toKeycode("CHREG");

        requests = new Permissions[](2);
        requests[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        requests[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);

        // TODO CDEPO permissions
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
    function lendToCooler(ICooler cooler_, uint256 amount_) external returns (uint256) {
        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();

        // Validate cooler collateral and debt tokens.
        if (
            address(cooler_.collateral()) != address(_collateralToken) ||
            address(cooler_.debt()) != address(_debtToken)
        ) revert BadEscrow();

        // Transfer in collateral owed
        uint256 collateral = cooler_.collateralFor(amount_, loanToCollateral);
        _collateralToken.transferFrom(msg.sender, address(this), collateral);

        // Increment interest to be expected
        (, uint256 interest) = getLoanForCollateral(collateral);
        interestReceivables += interest;
        principalReceivables += amount_;

        // Create a new loan request.
        _collateralToken.approve(address(cooler_), collateral);
        uint256 reqID = cooler_.requestLoan(amount_, INTEREST_RATE, loanToCollateral, DURATION);

        // Clear the created loan request by providing enough reserve.
        _sDebtToken.withdraw(amount_, address(this), address(this));
        _debtToken.approve(address(cooler_), amount_);
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
        _debtToken.transferFrom(msg.sender, address(this), interestBase * times_);
        // TODO implement sweep
        // if (active) {
        //     _sweepIntoSavingsVault(interestBase * times_);
        // } else {
        //     _defund(reserve, interestBase * times_);
        // }

        // Signal to cooler that loan should be extended.
        cooler_.extendLoanTerms(loanId_, times_);
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
            uint256 maxReward = (maxAuctionReward < MAX_REWARD) ? maxAuctionReward : MAX_REWARD;

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

        // TODO handle debt

        // // Update outstanding debt owed to the Treasury upon default.
        // uint256 outstandingDebt = TRSRY.reserveDebt(reserve, address(this));

        // // debt owed to TRSRY = user debt - user interest
        // TRSRY.setDebt({
        //     debtor_: address(this),
        //     token_: reserve,
        //     amount_: (outstandingDebt > totalPrincipal) ? outstandingDebt - totalPrincipal : 0
        // });

        // Reward keeper.
        _collateralToken.transfer(msg.sender, keeperRewards);
    }

    // ===== COOLER CALLBACKS ===== //

    /// @notice Overridden callback to decrement loan receivables.
    ///
    /// @param  principalPaid_ in reserve.
    /// @param  interestPaid_ in reserve.
    function _onRepay(uint256, uint256 principalPaid_, uint256 interestPaid_) internal override {
        // TODO handle sweep
        // if (active) {
        //     _sweepIntoSavingsVault(principalPaid_ + interestPaid_);
        // } else {
        //     _defund(reserve, principalPaid_ + interestPaid_);
        // }

        // Decrement loan receivables.
        interestReceivables = (interestReceivables > interestPaid_)
            ? interestReceivables - interestPaid_
            : 0;
        principalReceivables = (principalReceivables > principalPaid_)
            ? principalReceivables - principalPaid_
            : 0;
    }

    /// @notice Unused callback since defaults are handled by the clearinghouse.
    /// @dev    Overriden and left empty to save gas.
    function _onDefault(uint256, uint256, uint256, uint256) internal override {}

    // ===== AUX FUNCTIONS ===== //

    /// @inheritdoc IGenericClearinghouse
    function getCollateralForLoan(uint256 principal_) external view returns (uint256) {
        return (principal_ * 1e18) / loanToCollateral;
    }

    /// @inheritdoc IGenericClearinghouse
    function getLoanForCollateral(uint256 collateral_) public view returns (uint256, uint256) {
        uint256 principal = (collateral_ * loanToCollateral) / 1e18;
        uint256 interest = interestForLoan(principal, DURATION);
        return (principal, interest);
    }

    /// @inheritdoc IGenericClearinghouse
    function interestForLoan(uint256 principal_, uint256 duration_) public view returns (uint256) {
        uint256 interestPercent = (INTEREST_RATE * duration_) / 365 days;
        return (principal_ * interestPercent) / 1e18;
    }

    /// @inheritdoc IGenericClearinghouse
    function getTotalReceivables() external view returns (uint256) {
        return principalReceivables + interestReceivables;
    }

    // ===== OVERRIDE FUNCTIONS ===== //

    function debtToken() external view override returns (IERC20) {
        return IERC20(address(_debtToken));
    }

    function collateralToken() external view override returns (IERC20) {
        return IERC20(address(_collateralToken));
    }

    function _enable(bytes calldata) internal override {
        // Activate the Clearinghouse in CHREG
        CHREG.activateClearinghouse(address(this));
    }

    function _disable(bytes calldata) internal override {
        // Deactivate the Clearinghouse in CHREG
        CHREG.deactivateClearinghouse(address(this));
    }
}
