// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {IStaking} from "interfaces/IStaking.sol";

import {Cooler} from "src/external/cooler/CoolerFactory.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";

import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {CHREGv1} from "modules/CHREG/CHREG.v1.sol";
import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";

import {TransferHelper} from "src/libraries/TransferHelper.sol";

/// @notice Copy of the Clearinghouse policy with a lower LTC
contract ClearinghouseLowerLTC is Policy, RolesConsumer, CoolerCallback {
    using TransferHelper for ERC20;
    using TransferHelper for ERC4626;

    // --- ERRORS ----------------------------------------------------

    error BadEscrow();
    error DurationMaximum();
    error OnlyBurnable();
    error TooEarlyToFund();
    error LengthDiscrepancy();
    error OnlyBorrower();
    error NotLender();

    // --- EVENTS ----------------------------------------------------

    /// @notice Logs whenever the Clearinghouse is initialized or reactivated.
    event Activate();
    /// @notice Logs whenever the Clearinghouse is deactivated.
    event Deactivate();
    /// @notice Logs whenever the treasury is defunded.
    event Defund(address token, uint256 amount);
    /// @notice Logs the balance change (in RESERVE terms) whenever a rebalance occurs.
    event Rebalance(bool defund, uint256 reserveAmount);

    // --- RELEVANT CONTRACTS ----------------------------------------

    ERC20 public immutable RESERVE; // Debt token
    ERC4626 public immutable SRESERVE; // Idle RESERVE will be wrapped into SRESERVE
    ERC20 public immutable GOHM; // Collateral token
    ERC20 public immutable OHM; // Unwrapped gOHM
    IStaking public immutable STAKING; // Necessary to unstake (and burn) OHM from defaults

    // --- MODULES ---------------------------------------------------

    CHREGv1 public CHREG; // Olympus V3 Clearinghouse Registry Module
    MINTRv1 public MINTR; // Olympus V3 Minter Module
    TRSRYv1 public TRSRY; // Olympus V3 Treasury Module

    // --- PARAMETER BOUNDS ------------------------------------------

    uint256 public constant INTEREST_RATE = 5e15; // 0.5% anually
    uint256 public constant LOAN_TO_COLLATERAL = 2000e18;
    uint256 public constant DURATION = 121 days; // Four months
    uint256 public constant FUND_CADENCE = 7 days; // One week
    uint256 public constant FUND_AMOUNT = 18_000_000e18; // 18 million
    uint256 public constant MAX_REWARD = 1e17; // 0.1 gOHM

    // --- STATE VARIABLES -------------------------------------------

    /// @notice determines whether the contract can be funded or not.
    bool public active;

    /// @notice timestamp at which the next rebalance can occur.
    uint256 public fundTime;

    /// @notice Outstanding receivables.
    /// Incremented when a loan is taken or rolled.
    /// Decremented when a loan is repaid or collateral is burned.
    uint256 public interestReceivables;
    uint256 public principalReceivables;

    // --- INITIALIZATION --------------------------------------------

    constructor(
        address ohm_,
        address gohm_,
        address staking_,
        address sReserve_,
        address coolerFactory_,
        address kernel_
    ) Policy(Kernel(kernel_)) CoolerCallback(coolerFactory_) {
        // Store the relevant contracts.
        OHM = ERC20(ohm_);
        GOHM = ERC20(gohm_);
        STAKING = IStaking(staking_);
        SRESERVE = ERC4626(sReserve_);
        RESERVE = ERC20(SRESERVE.asset());
    }

    /// @notice Default framework setup. Configure dependencies for olympus-v3 modules.
    /// @dev    This function will be called when the `executor` installs the Clearinghouse
    ///         policy in the olympus-v3 `Kernel`.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        CHREG = CHREGv1(getModuleAddress(toKeycode("CHREG")));
        MINTR = MINTRv1(getModuleAddress(toKeycode("MINTR")));
        ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));
        TRSRY = TRSRYv1(getModuleAddress(toKeycode("TRSRY")));

        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        if (CHREG_MAJOR != 1 || MINTR_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        OHM.approve(address(MINTR), type(uint256).max);
    }

    /// @notice Default framework setup. Request permissions for interacting with olympus-v3 modules.
    /// @dev    This function will be called when the `executor` installs the Clearinghouse
    ///         policy in the olympus-v3 `Kernel`.
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode CHREG_KEYCODE = toKeycode("CHREG");
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        requests = new Permissions[](6);
        requests[0] = Permissions(CHREG_KEYCODE, CHREG.activateClearinghouse.selector);
        requests[1] = Permissions(CHREG_KEYCODE, CHREG.deactivateClearinghouse.selector);
        requests[2] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[5] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
    }

    /// @notice Returns the version of the policy.
    ///
    /// @return major The major version of the policy.
    /// @return minor The minor version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 2);
    }

    // --- OPERATION -------------------------------------------------

    /// @notice Lend to a cooler.
    /// @dev    To simplify the UX and easily ensure that all holders get the same terms,
    ///         this function requests a new loan and clears it in the same transaction.
    /// @param  cooler_ to lend to.
    /// @param  amount_ of RESERVE to lend.
    /// @return the id of the granted loan.
    function lendToCooler(Cooler cooler_, uint256 amount_) external returns (uint256) {
        // Attempt a Clearinghouse <> Treasury rebalance.
        rebalance();

        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();

        // Validate cooler collateral and debt tokens.
        if (cooler_.collateral() != GOHM || cooler_.debt() != RESERVE) revert BadEscrow();

        // Transfer in collateral owed
        uint256 collateral = cooler_.collateralFor(amount_, LOAN_TO_COLLATERAL);
        GOHM.safeTransferFrom(msg.sender, address(this), collateral);

        // Increment interest to be expected
        (, uint256 interest) = getLoanForCollateral(collateral);
        interestReceivables += interest;
        principalReceivables += amount_;

        // Create a new loan request.
        GOHM.approve(address(cooler_), collateral);
        uint256 reqID = cooler_.requestLoan(amount_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);

        // Clear the created loan request by providing enough RESERVE.
        SRESERVE.withdraw(amount_, address(this), address(this));
        RESERVE.approve(address(cooler_), amount_);
        uint256 loanID = cooler_.clearRequest(reqID, address(this), true);

        return loanID;
    }

    /// @notice Extend the loan expiry by repaying the extension interest in advance.
    ///         The extension cost is paid by the caller. If a third-party executes the
    ///         extension, the loan period is extended, but the borrower debt does not increase.
    /// @param  cooler_ holding the loan to be extended.
    /// @param  loanID_ index of loan in loans[].
    /// @param  times_ Amount of times that the fixed-term loan duration is extended.
    function extendLoan(Cooler cooler_, uint256 loanID_, uint8 times_) external {
        Cooler.Loan memory loan = cooler_.getLoan(loanID_);

        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();

        // Calculate extension interest based on the remaining principal.
        uint256 interestBase = interestForLoan(loan.principal, loan.request.duration);

        // Transfer in extension interest from the caller.
        RESERVE.safeTransferFrom(msg.sender, address(this), interestBase * times_);
        if (active) {
            _sweepIntoSavingsVault(interestBase * times_);
        } else {
            _defund(RESERVE, interestBase * times_);
        }

        // Signal to cooler that loan should be extended.
        cooler_.extendLoanTerms(loanID_, times_);
    }

    /// @notice Batch several default claims to save gas.
    ///         The elements on both arrays must be paired based on their index.
    /// @dev    Implements an auction style reward system that linearly increases up to a max reward.
    /// @param  coolers_ Array of contracts where the default must be claimed.
    /// @param  loans_ Array of defaulted loan ids.
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
            if (Cooler(coolers_[i]).getLoan(loans_[i]).lender != address(this)) revert NotLender();

            // Claim defaults and update cached metrics.
            (uint256 principal, uint256 interest, uint256 collateral, uint256 elapsed) = Cooler(
                coolers_[i]
            ).claimDefaulted(loans_[i]);

            unchecked {
                // Cannot overflow due to max supply limits for both tokens
                totalPrincipal += principal;
                totalInterest += interest;
                // There will not exist more than 2**256 loans
                ++i;
            }

            // Cap rewards to 5% of the collateral to avoid OHM holder's dillution.
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

        // Update outstanding debt owed to the Treasury upon default.
        uint256 outstandingDebt = TRSRY.reserveDebt(RESERVE, address(this));

        // debt owed to TRSRY = user debt - user interest
        TRSRY.setDebt({
            debtor_: address(this),
            token_: RESERVE,
            amount_: (outstandingDebt > totalPrincipal) ? outstandingDebt - totalPrincipal : 0
        });

        // Reward keeper.
        GOHM.safeTransfer(msg.sender, keeperRewards);
        // Burn the outstanding collateral of defaulted loans.
        burn();
    }

    // --- CALLBACKS -----------------------------------------------------

    /// @notice Overridden callback to decrement loan receivables.
    /// @param *unused loadID_ of the load.
    /// @param  principalPaid_ in RESERVE.
    /// @param  interestPaid_ in RESERVE.
    function _onRepay(uint256, uint256 principalPaid_, uint256 interestPaid_) internal override {
        if (active) {
            _sweepIntoSavingsVault(principalPaid_ + interestPaid_);
        } else {
            _defund(RESERVE, principalPaid_ + interestPaid_);
        }

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

    // --- FUNDING ---------------------------------------------------

    /// @notice Fund loan liquidity from treasury.
    /// @dev    Exposure is always capped at FUND_AMOUNT and rebalanced at up to FUND_CADANCE.
    ///         If several rebalances are available (because some were missed), calling this
    ///         function several times won't impact the funds controlled by the contract.
    ///         If the emergency shutdown is triggered, a rebalance will send funds back to
    ///         the treasury.
    /// @return False if too early to rebalance. Otherwise, true.
    function rebalance() public returns (bool) {
        // If the contract is deactivated, defund.
        uint256 maxFundAmount = active ? FUND_AMOUNT : 0;
        // Update funding schedule if necessary.
        if (fundTime > block.timestamp) return false;
        fundTime += FUND_CADENCE;

        // Sweep RESERVE into DSR if necessary.
        uint256 idle = RESERVE.balanceOf(address(this));
        if (idle != 0) _sweepIntoSavingsVault(idle);

        uint256 reserveBalance = SRESERVE.maxWithdraw(address(this));
        uint256 outstandingDebt = TRSRY.reserveDebt(RESERVE, address(this));
        // Rebalance funds on hand with treasury's reserves.
        if (reserveBalance < maxFundAmount) {
            // Since users loans are denominated in RESERVE, the clearinghouse
            // debt is set in RESERVE terms. It must be adjusted when funding.
            uint256 fundAmount = maxFundAmount - reserveBalance;
            TRSRY.setDebt({
                debtor_: address(this),
                token_: RESERVE,
                amount_: outstandingDebt + fundAmount
            });

            // Since TRSRY holds SRESERVE, a conversion must be done before
            // funding the clearinghouse.
            uint256 sReserveAmount = SRESERVE.previewWithdraw(fundAmount);
            TRSRY.increaseWithdrawApproval(address(this), SRESERVE, sReserveAmount);
            TRSRY.withdrawReserves(address(this), SRESERVE, sReserveAmount);

            // Log the event.
            emit Rebalance(false, fundAmount);
        } else if (reserveBalance > maxFundAmount) {
            // Since users loans are denominated in RESERVE, the clearinghouse
            // debt is set in RESERVE terms. It must be adjusted when defunding.
            uint256 defundAmount = reserveBalance - maxFundAmount;
            TRSRY.setDebt({
                debtor_: address(this),
                token_: RESERVE,
                amount_: (outstandingDebt > defundAmount) ? outstandingDebt - defundAmount : 0
            });

            // Since TRSRY holds SRESERVE, a conversion must be done before
            // sending SRESERVE back.
            uint256 sReserveAmount = SRESERVE.previewWithdraw(defundAmount);
            SRESERVE.safeTransfer(address(TRSRY), sReserveAmount);

            // Log the event.
            emit Rebalance(true, defundAmount);
        }

        return true;
    }

    /// @notice Sweep excess RESERVE into savings vault.
    function sweepIntoSavingsVault() public {
        uint256 reserveBalance = RESERVE.balanceOf(address(this));
        _sweepIntoSavingsVault(reserveBalance);
    }

    /// @notice Sweep excess RESERVE into vault.
    function _sweepIntoSavingsVault(uint256 amount_) internal {
        RESERVE.approve(address(SRESERVE), amount_);
        SRESERVE.deposit(amount_, address(this));
    }

    /// @notice Public function to burn gOHM.
    /// @dev    Can be used to burn any gOHM defaulted using the Cooler instead of the Clearinghouse.
    function burn() public {
        uint256 gohmBalance = GOHM.balanceOf(address(this));
        // Unstake and burn gOHM holdings.
        GOHM.approve(address(STAKING), gohmBalance);
        MINTR.burnOhm(address(this), STAKING.unstake(address(this), gohmBalance, false, false));
    }

    // --- ADMIN ---------------------------------------------------

    /// @notice Activate the contract.
    function activate() external onlyRole("cooler_overseer") {
        active = true;
        fundTime = block.timestamp;

        // Signal to CHREG that the contract has been activated.
        CHREG.activateClearinghouse(address(this));

        emit Activate();
    }

    /// @notice Deactivate the contract and return funds to treasury.
    function emergencyShutdown() external onlyRole("emergency_shutdown") {
        active = false;

        // If necessary, defund SRESERVE.
        uint256 sReserveBalance = SRESERVE.balanceOf(address(this));
        if (sReserveBalance != 0) _defund(SRESERVE, sReserveBalance);

        // If necessary, defund RESERVE.
        uint256 reserveBalance = RESERVE.balanceOf(address(this));
        if (reserveBalance != 0) _defund(RESERVE, reserveBalance);

        // Signal to CHREG that the contract has been deactivated.
        CHREG.deactivateClearinghouse(address(this));

        emit Deactivate();
    }

    /// @notice Return funds to treasury.
    /// @param  token_ to transfer.
    /// @param  amount_ to transfer.
    function defund(ERC20 token_, uint256 amount_) external onlyRole("cooler_overseer") {
        if (token_ == GOHM) revert OnlyBurnable();
        _defund(token_, amount_);
    }

    /// @notice Internal function to return funds to treasury.
    /// @param  token_ to transfer.
    /// @param  amount_ to transfer.
    function _defund(ERC20 token_, uint256 amount_) internal {
        if (token_ == SRESERVE || token_ == RESERVE) {
            // Since users loans are denominated in RESERVE, the clearinghouse
            // debt is set in RESERVE terms. It must be adjusted when defunding.
            uint256 outstandingDebt = TRSRY.reserveDebt(RESERVE, address(this));
            uint256 reserveAmount = (token_ == SRESERVE)
                ? SRESERVE.previewRedeem(amount_)
                : amount_;

            TRSRY.setDebt({
                debtor_: address(this),
                token_: RESERVE,
                amount_: (outstandingDebt > reserveAmount) ? outstandingDebt - reserveAmount : 0
            });
        }

        // Defund and log the event
        token_.safeTransfer(address(TRSRY), amount_);
        emit Defund(address(token_), amount_);
    }

    // --- AUX FUNCTIONS ---------------------------------------------

    /// @notice view function computing collateral for a loan amount.
    function getCollateralForLoan(uint256 principal_) external pure returns (uint256) {
        return (principal_ * 1e18) / LOAN_TO_COLLATERAL;
    }

    /// @notice view function computing loan for a collateral amount.
    /// @param  collateral_ amount of gOHM.
    /// @return debt (amount to be lent + interest) for a given collateral amount.
    function getLoanForCollateral(uint256 collateral_) public pure returns (uint256, uint256) {
        uint256 principal = (collateral_ * LOAN_TO_COLLATERAL) / 1e18;
        uint256 interest = interestForLoan(principal, DURATION);
        return (principal, interest);
    }

    /// @notice view function to compute the interest for given principal amount.
    /// @param principal_ amount of RESERVE being lent.
    /// @param duration_ elapsed time in seconds.
    function interestForLoan(uint256 principal_, uint256 duration_) public pure returns (uint256) {
        uint256 interestPercent = (INTEREST_RATE * duration_) / 365 days;
        return (principal_ * interestPercent) / 1e18;
    }

    /// @notice Get total receivable RESERVE for the treasury.
    ///         Includes both principal and interest.
    function getTotalReceivables() external view returns (uint256) {
        return principalReceivables + interestReceivables;
    }
}
