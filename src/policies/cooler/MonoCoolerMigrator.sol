// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

/// @title  Loan Consolidator
/// @notice A contract that migrates debt from Olympus Cooler V1 facilities to Cooler V2.
///         This is compatible with all three versions of Cooler V1.
/// @dev    This contract uses the `IERC3156FlashBorrower` interface to interact with Maker flashloans.
contract LoanConsolidator is IERC3156FlashBorrower, ReentrancyGuard {
    // ========= ERRORS ========= //

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the number of Clearinghouses does not equal the number of Coolers
    error Params_InvalidArrays();

    /// @notice Thrown when the new owner address provided does not match the authorization
    error Params_InvalidNewOwner();

    // ========= DATA STRUCTURES ========= //

    /// @notice Data structure used for flashloan parameters
    struct FlashLoanData {
        address[] clearinghouses;
        address[] coolers;
        address currentOwner;
        address newOwner;
        uint256 toDAI;
    }

    // ========= STATE ========= //

    /// @notice The DAI token
    /// @dev    The value is set when the policy is activated
    IERC20 internal DAI;

    /// @notice The USDS token
    /// @dev    The value is set when the policy is activated
    IERC20 internal USDS;

    /// @notice The gOHM token
    /// @dev    The value is set when the policy is activated
    IERC20 internal GOHM;

    /// @notice The DAI <> USDS Migrator
    /// @dev    The value is set when the policy is activated
    IDaiUsdsMigrator internal MIGRATOR;

    /// @notice The ERC3156 flash loan provider
    /// @dev    The value is set when the policy is activated
    IERC3156FlashLender internal FLASH;

    MonoCooler internal COOLERV2;

    /// @notice A mapping to validate clearinghouses
    mapping(address => bool) public isCHV1;

    // ========= CONSTRUCTOR ========= //

    constructor(
        address _dai,
        address _usds,
        address _gohm,
        address _migrator,
        address _flash,
        address _coolerv2,
        address[] memory chV1s
    ) {
        DAI = IERC20(_dai);
        USDS = IERC20(_usds);
        GOHM = IERC20(_gohm);
        MIGRATOR = IDaiUsdsMigrator(_migrator);
        FLASH = IERC3156FlashLender(_flash);
        COOLERV2 = MonoCooler(_coolerv2);

        for (uint256 i; i < chV1s.length; ++i) {
            isCHV1[chV1s[i]] = true;
        }

        IERC20(_gohm).approve(_coolerv2, type(uint256).max);
        IERC20(_usds).approve(_migrator, type(uint256).max);
        IERC20(_dai).approve(_migrator, type(uint256).max);
    }

    // ========= OPERATION ========= //

    /// @notice Internal logic for loan consolidation
    /// @dev    Utilized by `consolidate()` and `consolidateWithNewOwner()`
    ///
    ///         This function assumes:
    ///         - The calling external-facing function has checked that the caller is permitted to operate on `coolerFrom_`.
    ///
    /// @param  clearinghouseFrom_ Olympus Clearinghouse that issued the existing loans.
    /// @param  clearinghouseTo_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  coolerFrom_     Cooler from which the loans will be consolidated.
    /// @param  coolerTo_     Cooler to which the loans will be consolidated
    /// @param  ids_           Array containing the ids of the loans to be consolidated.
    function consolidate (
        address[] memory clearinghouses,
        address[] memory coolers,
        uint256 flashBorrow,
        uint256 toDAI,
        address newOwner,
        MonoCooler.Authorization memory authorization, 
        MonoCooler.Signature calldata signature
    ) external {
        // Validate array length
        if (clearinghouses.length != coolers.length) revert Params_InvalidArrays();

        // Validate new owner
        if (authorization.account != newOwner) revert Params_InvalidNewOwner();

        // Authorize this contract to manage user Cooler V2 position
        COOLERV2.setAuthorizationWithSig(authorization, signature);

        // Take flashloan
        // This will trigger the `onFlashLoan` function after the flashloan amount has been transferred to this contract
        FLASH.flashLoan(this, address(USDS), flashBorrow, abi.encode(FlashLoanData(clearinghouses, coolers, msg.sender, newOwner, toDAI)));

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 usdsBalanceAfter = USDS.balanceOf(address(this));
        if (usdsBalanceAfter > 0) {
            USDS.transfer(msg.sender, usdsBalanceAfter);
        }
    }

    /// @inheritdoc IERC3156FlashBorrower
    /// @dev        This function reverts if:
    ///             - The caller is not the flash loan provider
    ///             - The initiator is not this contract
    function onFlashLoan (
        address initiator_,
        address, // flashloan token is only DAI
        uint256 amount_,
        uint256 lenderFee_,
        bytes calldata params_
    ) external override returns (bytes32) {
        // perform sanity checks
        if (msg.sender != address(FLASH)) revert OnlyLender();
        if (initiator_ != address(this)) revert OnlyThis();

        // Unpack param data
        FlashLoanData memory flashLoanData = abi.decode(params_, (FlashLoanData));
        address[] memory clearinghouses = flashLoanData.clearinghouses;
        address[] memory coolers = flashLoanData.coolers;
        address currentOwner = flashLoanData.currentOwner;
        address newOwner = flashLoanData.newOwner;
        uint256 toDAI = flashLoanData.toDAI;

        // Convert USDS to DAI as needed
        if (toDAI > 0) MIGRATOR.usdsToDai(address(this), toDAI);

        // Keep track of debt tokens out and collateral in
        uint256 totalRepaid;
        uint256 totalCollateral;

        // Validate and repay loans for each cooler
        for (uint256 i; i < coolers.length; ++i) {
            Cooler cooler = Cooler(coolers[i]);

            // Validate legitimacy of clearinghouse and cooler
            if (!isCHV1[clearinghouses[i]]) continue;
            if (!Clearinghouse(clearinghouses[i]).factory().created(coolers[i])) continue;
            if (cooler.owner() != currentOwner) continue;

            (uint256 repaid, uint256 collateral) = _handleRepayments(cooler);
            totalRepaid += repaid;
            totalCollateral += collateral;
        }

        // Transfer the collateral from the cooler owner to this contract
        GOHM.transferFrom(currentOwner, address(this), totalCollateral);

        // Add collateral and borrow spent flash loan from Cooler V2
        COOLERV2.addCollateral(totalCollateral, newOwner, delegationRequests);
        COOLERV2.borrow(totalRepaid + lenderFee_, newOwner, address(this));

        // Convert any remaining DAI back to USDS
        uint256 daiBalance = DAI.balanceOf(address(this));
        if (daiBalance > 0) MIGRATOR.daiToUsds(address(this), daiBalance);

        // Approve the flash loan provider to collect the flashloan amount and fee
        USDS.approve(address(FLASH), amount_ + lenderFee_);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _handleRepayments (Cooler cooler) internal returns (uint256 repaid, uint256 collateral) {
        // provide upfront infinite approval to cooler
        cooler.debt().approve(cooler, type(uint256).max);

        // iterate through and repay loans
        Cooler.Loan[] memory loans = cooler.loans();
        for (uint256 i; i < loans.length; ++i) {
            Cooler.Loan loan = loans[i];

            // only repay outstanding loans
            if (loan.principal > 0) {
                uint256 amount = loan.principal + loan.interestDue;

                repaid += amount;
                collateral += loan.collateral;
                
                cooler.repayLoan(i, amount);
            }
        }

        // revoke approval
        cooler.debt().approve(cooler, 0);
    }
}
