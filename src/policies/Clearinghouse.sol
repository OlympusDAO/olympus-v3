// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {IStaking} from "interfaces/IStaking.sol";

import {CoolerFactory, Cooler} from "cooler/CoolerFactory.sol";
import {CoolerCallback} from "cooler/CoolerCallback.sol";

import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import "src/Kernel.sol";

/// @title  Olympus Clearinghouse.
/// @notice Olympus Clearinghouse (Policy) Contract.
/// @dev    The Olympus Clearinghouse is a lending facility built on top of Cooler Loans. The Clearinghouse
///         ensures that OHM holders can take loans against their gOHM holdings according to the parameters
///         approved by the community in OIP-144 and its subsequent RFCs. The Clearinghouse parameters are
///         immutable, because of that, if backing was to increase substantially, a new governance process
///         to fork this implementation with upgraded parameters should take place.
///         Although the Cooler contracts allow lenders to transfer ownership of their repayment rights, the
///         Clearinghouse doesn't implement any functions to use that feature.
contract Clearinghouse is Policy, RolesConsumer, CoolerCallback {
    // --- ERRORS ----------------------------------------------------

    error BadEscrow();
    error DurationMaximum();
    error OnlyBurnable();
    error TooEarlyToFund();
    error LengthDiscrepancy();

    // --- EVENTS ----------------------------------------------------

    event Deactivated();
    event Reactivated();

    // --- RELEVANT CONTRACTS ----------------------------------------

    ERC20 public immutable dai;
    ERC4626 public immutable sdai;
    ERC20 public immutable gOHM;
    IStaking public immutable staking;

    // --- MODULES ---------------------------------------------------

    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;

    // --- PARAMETER BOUNDS ------------------------------------------

    uint256 public constant INTEREST_RATE = 5e15; // 0.5% anually
    uint256 public constant LOAN_TO_COLLATERAL = 3000e18; // 3,000 DAI/gOHM
    uint256 public constant DURATION = 121 days; // Four months
    uint256 public constant FUND_CADENCE = 7 days; // One week
    uint256 public constant FUND_AMOUNT = 18_000_000e18; // 18 million
    uint256 public constant MAX_REWARD = 1e17; // 0.1 gOHM

    // --- STATE VARIABLES -------------------------------------------

    /// @notice determines whether the contract can be funded or not.
    bool public active;
    /// @notice timestamp at which the next rebalance can occur.
    uint256 public fundTime;
    /// @notice outstanding loan receivables.
    /// Incremented when a loan is made or rolled.
    /// Decremented when a loan is repaid or collateral is burned.
    uint256 public receivables;

    // --- INITIALIZATION --------------------------------------------

    constructor(
        address gohm_,
        address staking_,
        address sdai_,
        address coolerFactory_,
        address kernel_
    ) Policy(Kernel(kernel_)) CoolerCallback(coolerFactory_) {
        gOHM = ERC20(gohm_);
        staking = IStaking(staking_);
        sdai = ERC4626(sdai_);
        dai = ERC20(sdai.asset());

        // Initialize the contract status and its funding schedule.
        active = true;
        fundTime = block.timestamp;
    }

    /// @notice Default framework setup.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(toKeycode("TRSRY")));
        MINTR = MINTRv1(getModuleAddress(toKeycode("MINTR")));
        ROLES = ROLESv1(getModuleAddress(toKeycode("ROLES")));
    }

    /// @notice Default framework setup.
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        requests = new Permissions[](4);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[3] = Permissions(toKeycode("MINTR"), MINTR.burnOhm.selector);
    }

    // --- OPERATION -------------------------------------------------

    /// @notice Lend to a cooler.
    /// @dev    To simplify the UX and easily ensure that all holders get the same terms,
    ///         this function requests a new loan and clears it in the same transaction.
    /// @param  cooler_ to lend to.
    /// @param  amount_ of DAI to lend.
    /// @return the id of the granted loan.
    function lendToCooler(Cooler cooler_, uint256 amount_) external returns (uint256) {
        // Attempt a clearinghouse <> treasury rebalance.
        rebalance();
        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();
        // Validate cooler collateral and debt tokens.
        if (cooler_.collateral() != gOHM || cooler_.debt() != dai) revert BadEscrow();

        // Compute and access collateral. Increment loan receivables.
        uint256 collateral = cooler_.collateralFor(amount_, LOAN_TO_COLLATERAL);
        receivables += debtForCollateral(collateral);
        gOHM.transferFrom(msg.sender, address(this), collateral);

        // Create loan request.
        gOHM.approve(address(cooler_), collateral);
        uint256 reqID = cooler_.requestLoan(amount_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);

        // Clear loan request by providing enough DAI.
        sdai.withdraw(amount_, address(this), address(this));
        dai.approve(address(cooler_), amount_);
        uint256 loanID = cooler_.clearRequest(reqID, true, true);

        return loanID;
    }

    /// @notice Rollover an existing loan.
    /// @dev    To simplify the UX and easily ensure that all holders get the same terms,
    ///         this function provides the governance-approved terms for a rollover and
    ///         does the loan rollover in the same transaction.
    /// @param  cooler_ to provide terms.
    /// @param  loanID_ of loan in cooler.
    function rollLoan(Cooler cooler_, uint256 loanID_) external {
        // Validate that cooler was deployed by the trusted factory.
        if (!factory.created(address(cooler_))) revert OnlyFromFactory();

        // Provide rollover terms.
        cooler_.provideNewTermsForRoll(loanID_, INTEREST_RATE, LOAN_TO_COLLATERAL, DURATION);

        // Increment loan receivables by applying the interest to the previous debt.
        uint256 newDebt = cooler_.interestFor(
            cooler_.getLoan(loanID_).amount,
            INTEREST_RATE,
            DURATION
        );
        receivables += newDebt;

        // Collect applicable new collateral from user.
        uint256 newCollateral = cooler_.newCollateralFor(loanID_);
        if (newCollateral > 0) {
            gOHM.transferFrom(msg.sender, address(this), newCollateral);
            gOHM.approve(address(cooler_), newCollateral);
        }

        // Roll loan.
        cooler_.rollLoan(loanID_);
    }

    /// @notice Batch several default claims to save gas.
    ///         The elements on both arrays must be paired based on their index.
    /// @dev    Implements an auction style reward system that linearly increases up to a max reward.
    /// @param  coolers_ Array of contracts where the default must be claimed.
    /// @param  loans_ Array of defaulted loan ids.
    function claimDefaulted(address[] calldata coolers_, uint256[] calldata loans_) external {
        uint256 loans = loans_.length;
        if (loans != coolers_.length) revert LengthDiscrepancy();

        uint256 totalDebt;
        uint256 totalInterest;
        uint256 totalCollateral;
        uint256 keeperRewards;
        for (uint256 i = 0; i < loans; ) {
            // Validate that cooler was deployed by the trusted factory.
            if (!factory.created(coolers_[i])) revert OnlyFromFactory();

            (uint256 debt, uint256 collateral, uint256 elapsed) = Cooler(coolers_[i])
                .claimDefaulted(loans_[i]);
            uint256 interest = interestFromDebt(debt);
            unchecked {
                // Cannot overflow due to max supply limits for both tokens
                totalDebt += debt;
                totalInterest += interest;
                totalCollateral += collateral;
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
        receivables = (receivables > totalDebt) ? receivables - totalDebt : 0;
        // Update outstanding debt owed to the Treasury upon default.
        uint256 outstandingDebt = TRSRY.reserveDebt(dai, address(this));
        // debt owed to TRSRY = user debt - user interest
        TRSRY.setDebt({
            debtor_: address(this),
            token_: dai,
            amount_: (outstandingDebt > (totalDebt - totalInterest))
                ? outstandingDebt - (totalDebt - totalInterest)
                : 0
        });

        // Reward keeper.
        gOHM.transfer(msg.sender, keeperRewards);
        // Unstake and burn the collateral of the defaulted loans.
        gOHM.approve(address(staking), totalCollateral - keeperRewards);
        MINTR.burnOhm(
            address(this),
            staking.unstake(address(this), totalCollateral - keeperRewards, false, false)
        );
    }

    // --- CALLBACKS -----------------------------------------------------

    /// @notice Overridden callback to decrement loan receivables.
    /// @param *unused loadID_ of the load.
    /// @param amount_ repaid (in DAI).
    function _onRepay(uint256, uint256 amount_) internal override {
        _sweepIntoDSR(amount_);

        // Decrement loan receivables.
        receivables = (receivables > amount_) ? receivables - amount_ : 0;
    }

    /// @notice Unused callback since rollovers are handled by the clearinghouse.
    /// @dev Overriden and left empty to save gas.
    function _onRoll(uint256, uint256, uint256) internal override {}

    /// @notice Unused callback since defaults are handled by the clearinghouse.
    /// @dev Overriden and left empty to save gas.
    function _onDefault(uint256, uint256, uint256) internal override {}

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

        uint256 daiBalance = sdai.maxWithdraw(address(this));
        uint256 outstandingDebt = TRSRY.reserveDebt(dai, address(this));
        // Rebalance funds on hand with treasury's reserves.
        if (daiBalance < maxFundAmount) {
            // Since users loans are denominated in DAI, the clearinghouse
            // debt is set in DAI terms. It must be adjusted when funding.
            uint256 fundAmount = maxFundAmount - daiBalance;
            TRSRY.setDebt({
                debtor_: address(this),
                token_: dai,
                amount_: outstandingDebt + fundAmount
            });

            // Since TRSRY holds sDAI, a conversion must be done before
            // funding the clearinghouse.
            uint256 sdaiAmount = sdai.previewWithdraw(fundAmount);
            TRSRY.increaseWithdrawApproval(address(this), sdai, sdaiAmount);
            TRSRY.withdrawReserves(address(this), sdai, sdaiAmount);

            // Sweep DAI into DSR if necessary.
            uint256 idle = dai.balanceOf(address(this));
            if (idle != 0) _sweepIntoDSR(idle);
        } else if (daiBalance > maxFundAmount) {
            // Since users loans are denominated in DAI, the clearinghouse
            // debt is set in DAI terms. It must be adjusted when defunding.
            uint256 defundAmount = daiBalance - maxFundAmount;
            TRSRY.setDebt({
                debtor_: address(this),
                token_: dai,
                amount_: (outstandingDebt > defundAmount) ? outstandingDebt - defundAmount : 0
            });

            // Since TRSRY holds sDAI, a conversion must be done before
            // sending sDAI back.
            uint256 sdaiAmount = sdai.previewWithdraw(defundAmount);
            sdai.approve(address(TRSRY), sdaiAmount);
            sdai.transfer(address(TRSRY), sdaiAmount);
        }
        return true;
    }

    /// @notice Sweep excess DAI into vault.
    function sweepIntoDSR() public {
        uint256 daiBalance = dai.balanceOf(address(this));
        _sweepIntoDSR(daiBalance);
    }

    /// @notice Sweep excess DAI into vault.
    function _sweepIntoDSR(uint256 amount_) internal {
        dai.approve(address(sdai), amount_);
        sdai.deposit(amount_, address(this));
    }

    /// @notice Return funds to treasury.
    /// @param  token_ to transfer.
    /// @param  amount_ to transfer.
    function defund(ERC20 token_, uint256 amount_) public onlyRole("cooler_overseer") {
        if (token_ == gOHM) revert OnlyBurnable();
        if (token_ == sdai || token_ == dai) {
            // Since users loans are denominated in DAI, the clearinghouse
            // debt is set in DAI terms. It must be adjusted when defunding.
            uint256 outstandingDebt = TRSRY.reserveDebt(dai, address(this));
            uint256 daiAmount = (token_ == sdai) ? sdai.previewRedeem(amount_) : amount_;

            TRSRY.setDebt({
                debtor_: address(this),
                token_: dai,
                amount_: (outstandingDebt > daiAmount) ? outstandingDebt - daiAmount : 0
            });
        }

        token_.transfer(address(TRSRY), amount_);
    }

    /// @notice Deactivate the contract and return funds to treasury.
    function emergencyShutdown() external onlyRole("emergency_shutdown") {
        active = false;

        // If necessary, defund sDAI.
        uint256 sdaiBalance = sdai.balanceOf(address(this));
        if (sdaiBalance != 0) defund(sdai, sdaiBalance);

        // If necessary, defund DAI.
        uint256 daiBalance = dai.balanceOf(address(this));
        if (daiBalance != 0) defund(dai, daiBalance);

        emit Deactivated();
    }

    /// @notice Reactivate the contract.
    function reactivate() external onlyRole("cooler_overseer") {
        active = true;

        emit Reactivated();
    }

    // --- AUX FUNCTIONS ---------------------------------------------

    /// @notice view function computing loan for a collateral amount.
    /// @param  collateral_ amount of gOHM.
    /// @return debt (amount to be lent + interest) for a given collateral amount.
    function debtForCollateral(uint256 collateral_) public pure returns (uint256) {
        uint256 interestPercent = (INTEREST_RATE * DURATION) / 365 days;
        uint256 loan = (collateral_ * LOAN_TO_COLLATERAL) / 1e18;
        uint256 interest = (loan * interestPercent) / 1e18;
        return loan + interest;
    }

    /// @notice view function to compute the interest for a given debt amount.
    /// @param debt_ amount of gOHM.
    function interestFromDebt(uint256 debt_) public pure returns (uint256) {
        uint256 interestPercent = (INTEREST_RATE * DURATION) / 365 days;
        return (debt_ * interestPercent) / 1e18;
    }
}
