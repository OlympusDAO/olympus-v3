// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "src/interfaces/IERC20.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";
import {ICoolerFactory} from "src/external/cooler/interfaces/ICoolerFactory.sol";

interface IGenericClearinghouse {
    // ===== ERRORS ===== //

    error BadEscrow();
    error DurationMaximum();
    error OnlyBurnable();
    error TooEarlyToFund();
    error LengthDiscrepancy();
    error OnlyBorrower();
    error NotLender();

    // ===== STATE VARIABLES ===== //

    /// @notice The debt token of the clearinghouse.
    function debtToken() external view returns (IERC20);

    /// @notice The collateral token of the clearinghouse.
    function collateralToken() external view returns (IERC20);

    /// @notice The factory for generating new Coolers.
    function coolerFactory() external view returns (ICoolerFactory);

    // ===== LENDING FUNCTIONS ===== //

    /// @notice Lend to a cooler.
    ///
    /// @param  cooler_ The Cooler instance to lend to.
    /// @param  amount_ The amount of debt token to lend.
    /// @return loanId  The id of the granted loan.
    function lendToCooler(ICooler cooler_, uint256 amount_) external returns (uint256 loanId);

    /// @notice Extend the loan duration.
    ///
    /// @param  cooler_ The Cooler instance to extend the loan for.
    /// @param  loanId_ The id of the loan to extend.
    /// @param  times_  The number of times to extend the loan.
    function extendLoan(ICooler cooler_, uint256 loanId_, uint8 times_) external;

    /// @notice Batch several default claims to save gas.
    ///         The elements on both arrays must be paired based on their index.
    /// @dev    Implements an auction style reward system that linearly increases up to a max reward.
    /// @param  coolers_ Array of contracts where the default must be claimed.
    /// @param  loans_ Array of defaulted loan ids.
    function claimDefaulted(address[] calldata coolers_, uint256[] calldata loans_) external;

    // ===== AUX FUNCTIONS ===== //

    /// @notice View function computing collateral for a loan amount.
    ///
    /// @param  principal_ The amount of debt tokens to compute collateral for.
    /// @return collateral_ The amount of collateral tokens required for the loan.
    function getCollateralForLoan(uint256 principal_) external view returns (uint256);

    /// @notice View function computing loan for a collateral amount.
    ///
    /// @param  collateral_ The amount of collateral tokens to compute the loan for.
    /// @return principal   The amount of debt tokens for the loan.
    /// @return interest    The amount of interest tokens for the loan.
    function getLoanForCollateral(
        uint256 collateral_
    ) external view returns (uint256 principal, uint256 interest);

    /// @notice View function to compute the interest for given principal amount.
    ///
    /// @param  principal_  The amount of reserve being lent.
    /// @param  duration_   The elapsed time in seconds.
    /// @return interest    The amount of interest for the loan.
    function interestForLoan(
        uint256 principal_,
        uint256 duration_
    ) external view returns (uint256 interest);

    /// @notice The amount of principal receivables.
    function principalReceivables() external view returns (uint256);

    /// @notice The amount of interest receivables.
    function interestReceivables() external view returns (uint256);

    /// @notice Get total receivable reserve for the treasury.
    ///         Includes both principal and interest.
    function getTotalReceivables() external view returns (uint256);
}
