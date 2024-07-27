// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

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

contract CoolerUtils is IERC3156FlashBorrower {
    // --- ERRORS ------------------------------------------------------------------

    error OnlyThis();
    error OnlyOwner();
    error OnlyLender();
    error OnlyCoolerOwner();

    // --- DATA STRUCTURES ---------------------------------------------------------

    struct Batch {
        address cooler;
        uint256[] ids;
    }

    // --- IMMUTABLES AND STATE VARIABLES ------------------------------------------

    // relevant contracts
    IERC3156FlashLender public immutable lender;
    IERC20 public immutable gohm;
    IERC4626 public immutable sdai;
    IERC20 public immutable dai;

    uint256 constant DENOMINATOR = 1e5;

    // ownership
    address public immutable owner;

    // protocol fees
    uint256 public feePercentage;
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
    ) {
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

        // Cache batch debt and principal
        (uint256 totalDebt, uint256 totalPrincipal) = _getDebtForLoans(address(cooler), ids_);

        // Grant approval to the Cooler to spend the debt
        dai.approve(address(cooler), totalDebt);

        // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
        if (cooler.owner() != msg.sender) revert OnlyCoolerOwner();

        // Transfer in necessary funds to repay the fee
        if (useFunds_ != 0) {
            if (sdai_) {
                sdai.redeem(useFunds_, address(this), msg.sender);
            } else {
                dai.transferFrom(msg.sender, address(this), useFunds_);
            }
        }

        // Calculate the required flashloan amount based on available funds and protocol fee.
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 fee = ((totalDebt - daiBalance) * feePercentage) / DENOMINATOR;
        uint256 flashloan = totalDebt - daiBalance + fee;

        bytes memory params = abi.encode(clearinghouse_, cooler_, ids_, totalPrincipal, fee);

        // Take flashloan.
        lender.flashLoan(this, address(dai), flashloan, params);
    }

    function onFlashLoan(
        address initiator_,
        address token_,
        uint256 amount_,
        uint256 fee_,
        bytes calldata params_
    ) external override returns (bytes32) {
        (
            address clearinghouse,
            address coolerAddress,
            uint256[] memory ids,
            uint256 principal,
            uint256 fee
        ) = abi.decode(params_, (address, address, uint256[], uint256, uint256));
        Cooler cooler = Cooler(coolerAddress);

        // perform sanity checks
        if (msg.sender != address(lender)) revert OnlyLender();
        if (initiator_ != address(this)) revert OnlyThis();

        // Iterate over all batches
        _repayDebtForLoans(coolerAddress, ids);

        // Take a new loan with all the received collateral
        gohm.approve(clearinghouse, gohm.balanceOf(address(this)));
        Clearinghouse(clearinghouse).lendToCooler(cooler, principal);

        // Repay flashloan
        dai.transferFrom(cooler.owner(), address(this), amount_ + fee_);
        dai.approve(address(lender), amount_ + fee_);
        // Pay protocol fee
        if (fee != 0) dai.transferFrom(cooler.owner(), collector, fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // --- ADMIN ---------------------------------------------------

    function setFeePercentage(uint256 feePercentage_) external {
        if (msg.sender != owner) revert OnlyOwner();
        feePercentage = feePercentage_;
    }

    function setCollector(address collector_) external {
        if (msg.sender != owner) revert OnlyOwner();
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

    function _repayDebtForLoans(address cooler_, uint256[] memory ids_) internal {
        uint256 totalCollateral;
        Cooler cooler = Cooler(cooler_);

        uint256 numLoans = ids_.length;
        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, uint256 collateral, , , , ) = cooler.loans(
                ids_[i]
            );
            cooler.repayLoan(ids_[i], principal + interestDue);
            totalCollateral += collateral;
        }

        gohm.transferFrom(cooler.owner(), address(this), totalCollateral);
    }

    // --- AUX FUNCTIONS -----------------------------------------------------------

    /// @notice View function to compute the required approval amounts that the owner of a given Cooler
    ///         must give to this contract in order to consolidate the loans.
    ///
    /// @param  cooler_ Contract which issued the loans.
    /// @param  ids_    Array of loan ids to be consolidated.
    /// @return         Tuple with the following values:
    ///                  - Owner of the Cooler (address that should grant the approval).
    ///                  - gOHM amount to be approved.
    ///                  - DAI amount to be approved (if sDAI option will be set to false).
    ///                  - sDAI amount to be approved (if sDAI option will be set to true).
    function requiredApprovals(
        address cooler_,
        uint256[] calldata ids_
    ) external view returns (address, uint256, uint256, uint256) {
        uint256 totalDebt;
        uint256 totalCollateral;
        uint256 numLoans = ids_.length;
        Cooler cooler = Cooler(cooler_);

        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, uint256 collateral, , , , ) = cooler.loans(
                ids_[i]
            );
            totalDebt += principal + interestDue;
            totalCollateral += collateral;
        }
        uint256 totalDebtWithFee = totalDebt + (totalDebt * feePercentage) / DENOMINATOR;

        return (
            cooler.owner(),
            totalCollateral,
            totalDebtWithFee,
            sdai.previewWithdraw(totalDebtWithFee)
        );
    }
}
