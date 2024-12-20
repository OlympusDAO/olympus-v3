// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";

//
//    ██████╗ ██████╗  ██████╗ ██╗     ███████╗██████╗     ██╗   ██╗████████╗██╗██╗     ███████╗
//   ██╔════╝██╔═══██╗██╔═══██╗██║     ██╔════╝██╔══██╗    ██║   ██║╚══██╔══╝██║██║     ██╔════╝
//   ██║     ██║   ██║██║   ██║██║     █████╗  ██████╔╝    ██║   ██║   ██║   ██║██║     ███████╗
//   ██║     ██║   ██║██║   ██║██║     ██╔══╝  ██╔══██╗    ██║   ██║   ██║   ██║██║     ╚════██║
//   ╚██████╗╚██████╔╝╚██████╔╝███████╗███████╗██║  ██║    ╚██████╔╝   ██║   ██║███████╗███████║
//    ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝     ╚═════╝    ╚═╝   ╚═╝╚══════╝╚══════╝
//

contract CoolerUtils is IERC3156FlashBorrower, Owned {
    // --- ERRORS ------------------------------------------------------------------

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the caller is not the Cooler owner.
    error OnlyCoolerOwner();

    /// @notice Thrown when the fee percentage is out of range.
    /// @dev    Valid values are 0 <= feePercentage <= 100e2
    error Params_FeePercentageOutOfRange();

    /// @notice Thrown when the address is invalid.
    error Params_InvalidAddress();

    /// @notice Thrown when the caller attempts to provide more funds than are required.
    error Params_UseFundsOutOfBounds();

    /// @notice Thrown when the caller attempts to consolidate too few cooler loans. The minimum is two.
    error InsufficientCoolerCount();

    // --- DATA STRUCTURES ---------------------------------------------------------

    struct Batch {
        address cooler;
        uint256[] ids;
    }

    struct FlashLoanData {
        address clearinghouse;
        address cooler;
        uint256[] ids;
        uint256 principal;
        uint256 protocolFee;
    }

    // --- IMMUTABLES AND STATE VARIABLES ------------------------------------------

    /// @notice FlashLender contract used to take flashloans
    IERC3156FlashLender public immutable lender;
    IERC20 public immutable gohm;
    IERC4626 public immutable sdai;
    IERC20 public immutable dai;

    uint256 public constant ONE_HUNDRED_PERCENT = 100e2;

    // protocol fees
    uint256 public feePercentage;

    /// @notice Address permitted to collect protocol fees
    address public collector;

    // --- INITIALIZATION ----------------------------------------------------------

    constructor(
        address gohm_,
        address sdai_,
        address dai_,
        address owner_,
        address lender_,
        address collector_,
        uint256 feePercentage_
    ) Owned(owner_) {
        // Validation
        if (feePercentage_ > ONE_HUNDRED_PERCENT) revert Params_FeePercentageOutOfRange();
        if (collector_ == address(0)) revert Params_InvalidAddress();
        if (owner_ == address(0)) revert Params_InvalidAddress();
        if (lender_ == address(0)) revert Params_InvalidAddress();
        if (gohm_ == address(0)) revert Params_InvalidAddress();
        if (sdai_ == address(0)) revert Params_InvalidAddress();
        if (dai_ == address(0)) revert Params_InvalidAddress();

        // store contracts
        gohm = IERC20(gohm_);
        sdai = IERC4626(sdai_);
        dai = IERC20(dai_);

        lender = IERC3156FlashLender(lender_);

        // store protocol data
        owner = owner_;
        collector = collector_;
        feePercentage = feePercentage_;
    }

    // --- OPERATION ---------------------------------------------------------------

    /// @notice Consolidate loans (taken with a single Cooler contract) into a single loan by using
    ///         Maker flashloans.
    ///
    /// @dev    This function will revert unless the message sender has:
    ///            - Approved this contract to spend the `useFunds_`.
    ///            - Approved this contract to spend the gOHM escrowed by the target Cooler.
    ///         For flexibility purposes, the user can either pay with DAI or sDAI.
    ///
    /// @param  clearinghouse_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  cooler_        Cooler to which the loans will be consolidated.
    /// @param  ids_           Array containing the ids of the loans to be consolidated.
    /// @param  useFunds_      Amount of DAI/sDAI available to repay the fee.
    /// @param  sdai_          Whether the available funds are in sDAI or DAI.
    function consolidateWithFlashLoan(
        address clearinghouse_,
        address cooler_,
        uint256[] calldata ids_,
        uint256 useFunds_,
        bool sdai_
    ) public {
        Cooler cooler = Cooler(cooler_);

        // Ensure at least two loans are being consolidated
        if (ids_.length < 2) revert InsufficientCoolerCount();

        // Cache batch debt and principal
        (uint256 totalDebt, uint256 totalPrincipal) = _getDebtForLoans(address(cooler), ids_);

        // Grant approval to the Cooler to spend the debt
        dai.approve(address(cooler), totalDebt);

        // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
        if (cooler.owner() != msg.sender) revert OnlyCoolerOwner();

        // Transfer in necessary funds to repay the fee
        // This can also reduce the flashloan fee
        if (useFunds_ != 0) {
            if (sdai_) {
                sdai.redeem(useFunds_, address(this), msg.sender);
            } else {
                dai.transferFrom(msg.sender, address(this), useFunds_);
            }
        }

        // Calculate the required flashloan amount based on available funds and protocol fee.
        uint256 daiBalance = dai.balanceOf(address(this));
        // Prevent an underflow
        if (daiBalance > totalDebt) {
            revert Params_UseFundsOutOfBounds();
        }

        uint256 protocolFee = getProtocolFee(totalDebt - daiBalance);
        uint256 flashloan = totalDebt - daiBalance + protocolFee;

        bytes memory params = abi.encode(
            FlashLoanData({
                clearinghouse: clearinghouse_,
                cooler: cooler_,
                ids: ids_,
                principal: totalPrincipal,
                protocolFee: protocolFee
            })
        );

        // Take flashloan
        // This will trigger the `onFlashLoan` function after the flashloan amount has been transferred to this contract
        lender.flashLoan(this, address(dai), flashloan, params);

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 daiBalanceAfter = dai.balanceOf(address(this));
        if (daiBalanceAfter > 0) {
            dai.transfer(msg.sender, daiBalanceAfter);
        }
    }

    function onFlashLoan(
        address initiator_,
        address,
        uint256 amount_,
        uint256 lenderFee_,
        bytes calldata params_
    ) external override returns (bytes32) {
        FlashLoanData memory flashLoanData = abi.decode(params_, (FlashLoanData));
        Cooler cooler = Cooler(flashLoanData.cooler);

        // perform sanity checks
        if (msg.sender != address(lender)) revert OnlyLender();
        if (initiator_ != address(this)) revert OnlyThis();

        // Iterate over all batches, repay the debt and collect the collateral
        _repayDebtForLoans(flashLoanData.cooler, flashLoanData.ids);

        // Calculate the amount of collateral that will be needed for the consolidated loan
        uint256 consolidatedLoanCollateral = Clearinghouse(flashLoanData.clearinghouse)
            .getCollateralForLoan(flashLoanData.principal);

        // If the collateral required is greater than the collateral that was returned, then transfer gOHM from the cooler owner
        // This can happen as the collateral required for the consolidated loan can be greater than the sum of the collateral of the loans being consolidated
        if (consolidatedLoanCollateral > gohm.balanceOf(address(this))) {
            gohm.transferFrom(
                cooler.owner(),
                address(this),
                consolidatedLoanCollateral - gohm.balanceOf(address(this))
            );
        }

        // Take a new Cooler loan for the principal required
        gohm.approve(flashLoanData.clearinghouse, consolidatedLoanCollateral);
        Clearinghouse(flashLoanData.clearinghouse).lendToCooler(cooler, flashLoanData.principal);

        // The cooler owner will receive DAI for the consolidated loan
        // Transfer this amount, plus the fee, to this contract
        // Approval must have already been granted by the Cooler owner
        dai.transferFrom(cooler.owner(), address(this), amount_ + lenderFee_);
        // Approve the flash loan provider to collect the flashloan amount and fee
        dai.approve(address(lender), amount_ + lenderFee_);

        // Pay protocol fee
        if (flashLoanData.protocolFee != 0) dai.transfer(collector, flashLoanData.protocolFee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // --- ADMIN ---------------------------------------------------

    function setFeePercentage(uint256 feePercentage_) external onlyOwner {
        if (feePercentage_ > ONE_HUNDRED_PERCENT) revert Params_FeePercentageOutOfRange();

        feePercentage = feePercentage_;
    }

    function setCollector(address collector_) external onlyOwner {
        if (collector_ == address(0)) revert Params_InvalidAddress();

        collector = collector_;
    }

    // --- INTERNAL FUNCTIONS ------------------------------------------------------

    function _getDebtForLoans(
        address cooler_,
        uint256[] calldata ids_
    ) internal view returns (uint256, uint256) {
        uint256 totalDebt;
        uint256 totalPrincipal;

        uint256 numLoans = ids_.length;
        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, , , , , ) = Cooler(cooler_).loans(ids_[i]);
            totalDebt += principal + interestDue;
            totalPrincipal += principal;
        }

        return (totalDebt, totalPrincipal);
    }

    /// @notice Repay the debt for a given set of loans and collect the collateral.
    /// @dev    This function assumes:
    ///         - The cooler owner has granted approval for this contract to spend the gOHM collateral
    ///
    /// @param  cooler_ Cooler contract that issued the loans
    /// @param  ids_    Array of loan ids to be repaid
    function _repayDebtForLoans(address cooler_, uint256[] memory ids_) internal {
        uint256 totalCollateral;
        Cooler cooler = Cooler(cooler_);

        // Iterate over all loans in the cooler and repay
        uint256 numLoans = ids_.length;
        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, , , , , ) = cooler.loans(ids_[i]);

            // Repay. This also releases the collateral to the owner.
            uint256 collateralReturned = cooler.repayLoan(ids_[i], principal + interestDue);
            totalCollateral += collateralReturned;
        }

        // Transfers all of the gOHM collateral to this contract
        gohm.transferFrom(cooler.owner(), address(this), totalCollateral);
    }

    // --- AUX FUNCTIONS -----------------------------------------------------------

    /// @notice View function to compute the protocol fee for a given total debt.
    function getProtocolFee(uint256 totalDebt_) public view returns (uint256) {
        return (totalDebt_ * feePercentage) / ONE_HUNDRED_PERCENT;
    }

    /// @notice View function to compute the required approval amounts that the owner of a given Cooler
    ///         must give to this contract in order to consolidate the loans.
    ///
    /// @param  cooler_         Contract which issued the loans.
    /// @param  ids_            Array of loan ids to be consolidated.
    /// @return owner           Owner of the Cooler (address that should grant the approval).
    /// @return collateral      gOHM amount to be approved.
    /// @return debtWithFee     Total debt to be approved in DAI, including the protocol fee (if sDAI option will be set to false).
    /// @return sDaiDebtWithFee Total debt to be approved in sDAI, including the protocol fee (is sDAI option will be set to true).
    /// @return protocolFee     Fee to be paid to the protocol.
    function requiredApprovals(
        address clearinghouse_,
        address cooler_,
        uint256[] calldata ids_
    ) external view returns (address, uint256, uint256, uint256, uint256) {
        if (ids_.length < 2) revert InsufficientCoolerCount();

        uint256 totalPrincipal;
        uint256 totalDebtWithInterest;
        uint256 numLoans = ids_.length;

        // Calculate the total debt and collateral for the loans
        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, , , , , ) = Cooler(cooler_).loans(ids_[i]);
            totalPrincipal += principal;
            totalDebtWithInterest += principal + interestDue;
        }

        uint256 protocolFee = getProtocolFee(totalDebtWithInterest);
        uint256 totalDebtWithFee = totalDebtWithInterest + protocolFee;

        // Calculate the collateral required for the consolidated loan principal
        uint256 consolidatedLoanCollateral = Clearinghouse(clearinghouse_).getCollateralForLoan(
            totalPrincipal
        );

        return (
            Cooler(cooler_).owner(),
            consolidatedLoanCollateral,
            totalDebtWithFee,
            sdai.previewWithdraw(totalDebtWithFee),
            protocolFee
        );
    }

    /// @notice Calculates the collateral required to consolidate a set of loans.
    /// @dev    Due to rounding, the collateral required for the consolidated loan may be greater than the collateral of the loans being consolidated.
    ///         This function calculates the additional collateral required.
    ///
    /// @param  clearinghouse_      Clearinghouse contract used to issue the consolidated loan.
    /// @param  cooler_             Cooler contract that issued the loans.
    /// @param  ids_                Array of loan ids to be consolidated.
    /// @return consolidatedLoanCollateral  Collateral required for the consolidated loan.
    /// @return existingLoanCollateral      Collateral of the existing loans.
    /// @return additionalCollateral        Additional collateral required to consolidate the loans. This will need to be supplied by the Cooler owner.
    function collateralRequired(
        address clearinghouse_,
        address cooler_,
        uint256[] memory ids_
    )
        public
        view
        returns (
            uint256 consolidatedLoanCollateral,
            uint256 existingLoanCollateral,
            uint256 additionalCollateral
        )
    {
        if (ids_.length == 0) revert InsufficientCoolerCount();

        // Calculate the total principal of the existing loans
        uint256 totalPrincipal;
        for (uint256 i; i < ids_.length; i++) {
            (, uint256 principal, , uint256 collateral, , , , ) = Cooler(cooler_).loans(ids_[i]);
            totalPrincipal += principal;
            existingLoanCollateral += collateral;
        }

        // Calculate the collateral required for the consolidated loan
        consolidatedLoanCollateral = Clearinghouse(clearinghouse_).getCollateralForLoan(
            totalPrincipal
        );

        // Calculate the additional collateral required
        if (consolidatedLoanCollateral > existingLoanCollateral) {
            additionalCollateral = consolidatedLoanCollateral - existingLoanCollateral;
        }

        return (consolidatedLoanCollateral, existingLoanCollateral, additionalCollateral);
    }

    /// @notice Version of the contract
    ///
    /// @return Version number
    function VERSION() external pure returns (uint256) {
        return 3;
    }
}
