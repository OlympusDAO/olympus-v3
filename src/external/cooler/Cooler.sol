// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Clone} from "clones/Clone.sol";

import {CoolerFactory} from "./CoolerFactory.sol";
import {CoolerCallback} from "./CoolerCallback.sol";

// Function sig taken from gOHM contract
interface IDelegate {
    function delegate(address to_) external;
}

/// @title  Cooler Loans.
/// @notice A Cooler is a smart contract escrow that facilitates fixed-duration, peer-to-peer
///         loans for a user-defined debt-collateral pair.
/// @dev    This contract uses Clones (https://github.com/wighawag/clones-with-immutable-args)
///         to save gas on deployment.
contract Cooler is Clone {
    using SafeTransferLib for ERC20;

    // --- ERRORS ----------------------------------------------------

    error OnlyApproved();
    error Deactivated();
    error Default();
    error NotExpired();
    error NotCoolerCallback();

    // --- DATA STRUCTURES -------------------------------------------

    /// @notice A loan begins with a borrow request.
    struct Request {
        uint256 amount; // Amount to be borrowed.
        uint256 interest; // Annualized percentage to be paid as interest.
        uint256 loanToCollateral; // Requested loan-to-collateral ratio.
        uint256 duration; // Time to repay the loan before it defaults.
        bool active; // Any lender can clear an active loan request.
        address requester; // The address that created the request.
    }

    /// @notice A request is converted to a loan when a lender clears it.
    struct Loan {
        Request request; // Loan terms specified in the request.
        uint256 principal; // Amount of principal debt owed to the lender.
        uint256 interestDue; // Interest owed to the lender.
        uint256 collateral; // Amount of collateral pledged.
        uint256 expiry; // Time when the loan defaults.
        address lender; // Lender's address.
        address recipient; // Recipient of repayments.
        bool callback; // If this is true, the lender must inherit CoolerCallback.
    }

    // --- IMMUTABLES ------------------------------------------------

    // This makes the code look prettier.
    uint256 private constant DECIMALS_INTEREST = 1e18;

    /// @notice This address owns the collateral in escrow.
    function owner() public pure returns (address _owner) {
        return _getArgAddress(0x0);
    }

    /// @notice This token is borrowed against.
    function collateral() public pure returns (ERC20 _collateral) {
        return ERC20(_getArgAddress(0x14));
    }

    /// @notice This token is lent.
    function debt() public pure returns (ERC20 _debt) {
        return ERC20(_getArgAddress(0x28));
    }

    /// @notice This contract created the Cooler
    function factory() public pure returns (CoolerFactory _factory) {
        return CoolerFactory(_getArgAddress(0x3c));
    }

    // --- STATE VARIABLES -------------------------------------------

    /// @notice Arrays stores all the loan requests.
    Request[] public requests;

    /// @notice Arrays stores all the granted loans.
    Loan[] public loans;

    /// @notice Facilitates transfer of lender ownership to new addresses
    mapping(uint256 => address) public approvals;

    // --- BORROWER --------------------------------------------------

    /// @notice Request a loan with given parameters.
    ///         Collateral is taken at time of request.
    /// @param  amount_ of debt tokens to borrow.
    /// @param  interest_ to pay (annualized % of 'amount_'). Expressed in DECIMALS_INTEREST.
    /// @param  loanToCollateral_ debt tokens per collateral token pledged. Expressed in 10**collateral().decimals().
    /// @param  duration_ of loan tenure in seconds.
    /// @return reqID of the created request. Equivalent to the index of request in requests[].
    function requestLoan(
        uint256 amount_,
        uint256 interest_,
        uint256 loanToCollateral_,
        uint256 duration_
    ) external returns (uint256 reqID) {
        reqID = requests.length;
        requests.push(
            Request({
                amount: amount_,
                interest: interest_,
                loanToCollateral: loanToCollateral_,
                duration: duration_,
                active: true,
                requester: msg.sender
            })
        );

        // The collateral is taken upfront. Will be escrowed
        // until the loan is repaid or defaulted.
        collateral().safeTransferFrom(
            msg.sender,
            address(this),
            collateralFor(amount_, loanToCollateral_)
        );

        // Log the event.
        factory().logRequestLoan(reqID);
    }

    /// @notice Cancel a loan request and get the collateral back.
    /// @param  reqID_ index of request in requests[].
    function rescindRequest(uint256 reqID_) external {
        if (msg.sender != owner()) revert OnlyApproved();

        Request storage req = requests[reqID_];

        if (!req.active) revert Deactivated();

        // Update storage and send collateral back to the owner.
        req.active = false;
        collateral().safeTransfer(owner(), collateralFor(req.amount, req.loanToCollateral));

        // Log the event.
        factory().logRescindRequest(reqID_);
    }

    /// @notice Repay a loan to get the collateral back.
    /// @dev    Despite a malicious lender could reenter with the callback, the
    ///         usage of `msg.sender` prevents any economical benefit to the
    ///         attacker, since they would be repaying the loan themselves.
    /// @param  loanID_ index of loan in loans[].
    /// @param  repayment_ debt tokens to be repaid.
    /// @return collateral given back to the borrower.
    function repayLoan(uint256 loanID_, uint256 repayment_) external returns (uint256) {
        Loan memory loan = loans[loanID_];

        if (block.timestamp > loan.expiry) revert Default();

        // Cap the repayment to the total debt of the loan
        uint256 totalDebt = loan.principal + loan.interestDue;
        if (repayment_ > totalDebt) repayment_ = totalDebt;

        // Need to repay interest first, then any extra goes to paying down principal.
        uint256 interestPaid;
        uint256 remainder;
        if (repayment_ >= loan.interestDue) {
            remainder = repayment_ - loan.interestDue;
            interestPaid = loan.interestDue;
            loan.interestDue = 0;
        } else {
            loan.interestDue -= repayment_;
            interestPaid = repayment_;
        }

        // We pay back only if user has paid back principal. This can be 0.
        uint256 decollateralized;
        if (remainder > 0) {
            decollateralized = (loan.collateral * remainder) / loan.principal;

            loan.principal -= remainder;
            loan.collateral -= decollateralized;
        }

        // Save updated loan info in storage.
        loans[loanID_] = loan;

        // Transfer repaid debt back to the lender and collateral back to the owner if applicable
        debt().safeTransferFrom(msg.sender, loan.recipient, repayment_);
        if (decollateralized > 0) collateral().safeTransfer(owner(), decollateralized);

        // Log the event.
        factory().logRepayLoan(loanID_, repayment_);

        // If necessary, trigger lender callback.
        if (loan.callback) {
            CoolerCallback(loan.lender).onRepay(loanID_, remainder, interestPaid);
        }

        return decollateralized;
    }

    /// @notice Delegate voting power on collateral.
    /// @param  to_ address to delegate.
    function delegateVoting(address to_) external {
        if (msg.sender != owner()) revert OnlyApproved();
        IDelegate(address(collateral())).delegate(to_);
    }

    // --- LENDER ----------------------------------------------------

    /// @notice Fill a requested loan as a lender.
    /// @param  reqID_ index of request in requests[].
    /// @param  recipient_ address to repay the loan to.
    /// @param  isCallback_ true if the lender implements the CoolerCallback abstract. False otherwise.
    /// @return loanID of the granted loan. Equivalent to the index of loan in loans[].
    function clearRequest(
        uint256 reqID_,
        address recipient_,
        bool isCallback_
    ) external returns (uint256 loanID) {
        Request memory req = requests[reqID_];

        // Loan callbacks are only allowed if:
        //  1. The loan request has been created via a trusted lender.
        //  2. The lender signals that it implements the CoolerCallback Abstract.
        bool callback = (isCallback_ && msg.sender == req.requester);

        // If necessary, ensure lender implements the CoolerCallback abstract.
        if (callback && !CoolerCallback(msg.sender).isCoolerCallback()) revert NotCoolerCallback();
        // Ensure loan request is active.
        if (!req.active) revert Deactivated();

        // Clear the loan request in memory.
        req.active = false;

        // Calculate and store loan terms.
        uint256 interest = interestFor(req.amount, req.interest, req.duration);
        uint256 collat = collateralFor(req.amount, req.loanToCollateral);
        loanID = loans.length;

        loans.push(
            Loan({
                request: req,
                principal: req.amount,
                interestDue: interest,
                collateral: collat,
                expiry: block.timestamp + req.duration,
                lender: msg.sender,
                recipient: recipient_,
                callback: callback
            })
        );

        // Clear the loan request storage.
        requests[reqID_].active = false;

        // Transfer debt tokens to the owner of the request.
        debt().safeTransferFrom(msg.sender, owner(), req.amount);

        // Log the event.
        factory().logClearRequest(reqID_, loanID);
    }

    /// @notice Allow lender to extend a loan for the borrower. Doesn't require
    ///         borrower permission because it doesn't have a negative impact for them.
    /// @dev    Since this function solely impacts the expiration day, the lender
    ///         should ensure that extension interest payments are done beforehand.
    /// @param  loanID_ index of loan in loans[].
    /// @param  times_ that the fixed-term loan duration is extended.
    function extendLoanTerms(uint256 loanID_, uint8 times_) external {
        Loan memory loan = loans[loanID_];

        if (msg.sender != loan.lender) revert OnlyApproved();
        if (block.timestamp > loan.expiry) revert Default();

        // Update loan terms to reflect the extension.
        loan.expiry += loan.request.duration * times_;

        // Save updated loan info in storage.
        loans[loanID_] = loan;

        // Log the event.
        factory().logExtendLoan(loanID_, times_);
    }

    /// @notice Claim collateral upon loan default.
    /// @param  loanID_ index of loan in loans[].
    /// @return defaulted debt by the borrower, collateral kept by the lender, elapsed time since expiry.
    function claimDefaulted(uint256 loanID_) external returns (uint256, uint256, uint256, uint256) {
        Loan memory loan = loans[loanID_];

        if (block.timestamp <= loan.expiry) revert NotExpired();

        loans[loanID_].principal = 0;
        loans[loanID_].interestDue = 0;
        loans[loanID_].collateral = 0;

        // Transfer defaulted collateral to the lender.
        collateral().safeTransfer(loan.lender, loan.collateral);

        // Log the event.
        factory().logDefaultLoan(loanID_, loan.collateral);

        // If necessary, trigger lender callback.
        if (loan.callback) {
            CoolerCallback(loan.lender).onDefault(
                loanID_,
                loan.principal,
                loan.interestDue,
                loan.collateral
            );
        }

        return (loan.principal, loan.interestDue, loan.collateral, block.timestamp - loan.expiry);
    }

    /// @notice Approve transfer of loan ownership rights to a new address.
    /// @param  to_ address to be approved.
    /// @param  loanID_ index of loan in loans[].
    function approveTransfer(address to_, uint256 loanID_) external {
        if (msg.sender != loans[loanID_].lender) revert OnlyApproved();

        // Update transfer approvals.
        approvals[loanID_] = to_;
    }

    /// @notice Execute loan ownership transfer. Must be previously approved by the lender.
    /// @param  loanID_ index of loan in loans[].
    function transferOwnership(uint256 loanID_) external {
        if (msg.sender != approvals[loanID_]) revert OnlyApproved();

        // Update the load lender and the recipient.
        loans[loanID_].lender = msg.sender;
        loans[loanID_].recipient = msg.sender;
        // Callbacks are disabled when transferring ownership.
        loans[loanID_].callback = false;
        // Clear transfer approvals.
        approvals[loanID_] = address(0);
    }

    /// @notice Allow lender to set repayment recipient of a given loan.
    /// @param  loanID_ of lender's loan.
    /// @param  recipient_ reciever of repayments
    function setRepaymentAddress(uint256 loanID_, address recipient_) external {
        if (msg.sender != loans[loanID_].lender) revert OnlyApproved();

        // Update the repayment method.
        loans[loanID_].recipient = recipient_;
    }

    // --- AUX FUNCTIONS ---------------------------------------------

    /// @notice Compute collateral needed for a desired loan amount at given loan to collateral ratio.
    /// @param  principal_ amount of debt tokens.
    /// @param  loanToCollateral_ ratio for loan. Expressed in 10**collateral().decimals().
    function collateralFor(
        uint256 principal_,
        uint256 loanToCollateral_
    ) public view returns (uint256) {
        return (principal_ * (10 ** collateral().decimals())) / loanToCollateral_;
    }

    /// @notice Compute interest cost on amount for duration at given annualized rate.
    /// @param  principal_ amount of debt tokens.
    /// @param  rate_ of interest (annualized).
    /// @param  duration_ of the loan in seconds.
    /// @return Interest in debt token terms.
    function interestFor(
        uint256 principal_,
        uint256 rate_,
        uint256 duration_
    ) public pure returns (uint256) {
        uint256 interest = (rate_ * duration_) / 365 days;
        return (principal_ * interest) / DECIMALS_INTEREST;
    }

    /// @notice Check if given loan has expired.
    /// @param  loanID_ index of loan in loans[].
    /// @return Expiration status.
    function hasExpired(uint256 loanID_) external view returns (bool) {
        return block.timestamp > loans[loanID_].expiry;
    }

    /// @notice Check if a given request is active.
    /// @param  reqID_ index of request in requests[].
    /// @return Active status.
    function isActive(uint256 reqID_) external view returns (bool) {
        return requests[reqID_].active;
    }

    /// @notice Getter for Request data as a struct.
    /// @param  reqID_ index of request in requests[].
    /// @return Request struct.
    function getRequest(uint256 reqID_) external view returns (Request memory) {
        return requests[reqID_];
    }

    /// @notice Getter for Loan data as a struct.
    /// @param loanID_ index of loan in loans[].
    /// @return Loan struct.
    function getLoan(uint256 loanID_) external view returns (Loan memory) {
        return loans[loanID_];
    }
}
