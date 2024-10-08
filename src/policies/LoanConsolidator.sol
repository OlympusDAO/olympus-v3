// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {Kernel, Keycode, toKeycode, Permissions, Policy} from "src/Kernel.sol";

import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {EXREGv1} from "src/modules/EXREG/EXREG.v1.sol";

import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

/// @title  Loan Consolidator
/// @notice A policy that consolidates loans taken with a single Cooler contract into a single loan using Maker flashloans.
/// @dev    This policy uses the `IERC3156FlashBorrower` interface to interact with Maker flashloans.
contract LoanConsolidator is IERC3156FlashBorrower, Policy, RolesConsumer, ReentrancyGuard {
    // ========= ERRORS ========= //

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the caller is not the Cooler owner.
    error OnlyCoolerOwner();

    /// @notice Thrown when the contract is not active.
    error OnlyActive();

    /// @notice Thrown when the fee percentage is out of range.
    /// @dev    Valid values are 0 <= feePercentage <= 100e2
    error Params_FeePercentageOutOfRange();

    /// @notice Thrown when the address is invalid.
    error Params_InvalidAddress();

    /// @notice Thrown when the caller attempts to provide more funds than are required.
    error Params_UseFundsOutOfBounds();

    /// @notice Thrown when the caller attempts to consolidate too few cooler loans. The minimum is two.
    error Params_InsufficientCoolerCount();

    /// @notice Thrown when the Clearinghouse is not registered with the Bophades kernel
    error Params_InvalidClearinghouse();

    /// @notice Thrown when the Cooler is not created by the CoolerFactory for the specified Clearinghouse
    error Params_InvalidCooler();

    // ========= EVENTS ========= //

    /// @notice Emitted when the contract is activated
    event Activated();

    /// @notice Emitted when the contract is deactivated
    event Deactivated();

    /// @notice Emitted when the fee percentage is set
    event FeePercentageSet(uint256 feePercentage);

    // ========= DATA STRUCTURES ========= //

    /// @notice Data structure used for flashloan parameters
    struct FlashLoanData {
        address clearinghouse;
        address cooler;
        uint256[] ids;
        uint256 principal;
        uint256 protocolFee;
    }

    // ========= STATE ========= //

    /// @notice The Clearinghouse registry module
    CHREGv1 internal CHREG;

    /// @notice The treasury module
    TRSRYv1 internal TRSRY;

    /// @notice The external contract registry module
    EXREGv1 internal EXREG;

    /// @notice The DAI token
    IERC20 internal DAI;

    /// @notice The sDAI token
    IERC4626 internal SDAI;

    /// @notice The gOHM token
    IERC20 internal GOHM;

    /// @notice The flash loan provider
    IERC3156FlashLender internal FLASH;

    /// @notice The denominator for percentage calculations
    uint256 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice Percentage of the debt to be paid as a fee
    /// @dev    In terms of `ONE_HUNDRED_PERCENT`
    uint256 public feePercentage;

    /// @notice Whether the contract is active
    bool public active;

    /// @notice The role required to call admin functions
    bytes32 public constant ROLE_ADMIN = "loan_consolidator_admin";

    /// @notice The role required to call emergency shutdown functions
    bytes32 public constant ROLE_EMERGENCY_SHUTDOWN = "emergency_shutdown";

    // ========= CONSTRUCTOR ========= //

    /// @notice Constructor for the Loan Consolidator
    /// @dev    This function will revert if:
    ///         - The fee percentage is above `ONE_HUNDRED_PERCENT`
    ///         - The kernel address is zero
    constructor(address kernel_, uint256 feePercentage_) Policy(Kernel(kernel_)) {
        // Validation
        if (feePercentage_ > ONE_HUNDRED_PERCENT) revert Params_FeePercentageOutOfRange();
        if (kernel_ == address(0)) revert Params_InvalidAddress();

        // store protocol data
        feePercentage = feePercentage_;

        // Activate the contract
        active = true;

        // Emit events
        emit FeePercentageSet(feePercentage);
        emit Activated();
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("EXREG");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        // Populate module dependencies
        CHREG = CHREGv1(getModuleAddress(dependencies[0]));
        EXREG = EXREGv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 EXREG_MAJOR, ) = EXREG.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        if (CHREG_MAJOR != 1 || EXREG_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Populate variables
        // This function will be called whenever a contract is registered or deregistered, which enables caching of the values
        DAI = IERC20(EXREG.getContract("dai"));
        SDAI = IERC4626(EXREG.getContract("sdai"));
        GOHM = IERC20(EXREG.getContract("gohm"));
        FLASH = IERC3156FlashLender(EXREG.getContract("flash"));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev        This policy does not require any permissions
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);

        return requests;
    }

    // ========= OPERATION ========= //

    /// @notice Consolidate loans (taken with a single Cooler contract) into a single loan by using
    ///         Maker flashloans.
    ///
    /// @dev    This function will revert if:
    ///         - The caller has not approved this contract to spend the `useFunds_`.
    ///         - The caller has not approved this contract to spend the gOHM escrowed by the target Cooler.
    ///         - `clearinghouse_` is not registered with the Clearinghouse registry.
    ///         - `cooler_` is not a valid Cooler for the Clearinghouse.
    ///         - Less than two loans are being consolidated.
    ///         - The available funds are less than the required flashloan amount.
    ///         - The contract is not active.
    ///         - Re-entrancy is detected.
    ///
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
    ) public onlyActive nonReentrant {
        // Validate that the Clearinghouse is registered with the Bophades kernel
        if (!_isValidClearinghouse(clearinghouse_)) revert Params_InvalidClearinghouse();

        // Validate that the cooler was created by the CoolerFactory for the Clearinghouse
        if (!_isValidCooler(clearinghouse_, cooler_)) revert Params_InvalidCooler();

        // Ensure at least two loans are being consolidated
        if (ids_.length < 2) revert Params_InsufficientCoolerCount();

        // Cache batch debt and principal
        (uint256 totalDebt, uint256 totalPrincipal) = _getDebtForLoans(cooler_, ids_);

        // Grant approval to the Cooler to spend the debt
        DAI.approve(cooler_, totalDebt);

        // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
        Cooler cooler = Cooler(cooler_);
        if (cooler.owner() != msg.sender) revert OnlyCoolerOwner();

        // Transfer in necessary funds to repay the fee
        // This can also reduce the flashloan fee
        if (useFunds_ != 0) {
            if (sdai_) {
                SDAI.redeem(useFunds_, address(this), msg.sender);
            } else {
                DAI.transferFrom(msg.sender, address(this), useFunds_);
            }
        }

        // Calculate the required flashloan amount based on available funds and protocol fee.
        uint256 daiBalance = DAI.balanceOf(address(this));
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
        FLASH.flashLoan(this, address(DAI), flashloan, params);

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 daiBalanceAfter = DAI.balanceOf(address(this));
        if (daiBalanceAfter > 0) {
            DAI.transfer(msg.sender, daiBalanceAfter);
        }
    }

    /// @inheritdoc IERC3156FlashBorrower
    /// @dev        This function reverts if:
    ///             - The caller is not the flash loan provider
    ///             - The initiator is not this contract
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
        if (msg.sender != address(FLASH)) revert OnlyLender();
        if (initiator_ != address(this)) revert OnlyThis();

        // Iterate over all batches, repay the debt and collect the collateral
        _repayDebtForLoans(flashLoanData.cooler, flashLoanData.ids);

        // Calculate the amount of collateral that will be needed for the consolidated loan
        uint256 consolidatedLoanCollateral = Clearinghouse(flashLoanData.clearinghouse)
            .getCollateralForLoan(flashLoanData.principal);

        // If the collateral required is greater than the collateral that was returned, then transfer gOHM from the cooler owner
        // This can happen as the collateral required for the consolidated loan can be greater than the sum of the collateral of the loans being consolidated
        if (consolidatedLoanCollateral > GOHM.balanceOf(address(this))) {
            GOHM.transferFrom(
                cooler.owner(),
                address(this),
                consolidatedLoanCollateral - GOHM.balanceOf(address(this))
            );
        }

        // Take a new Cooler loan for the principal required
        GOHM.approve(flashLoanData.clearinghouse, consolidatedLoanCollateral);
        Clearinghouse(flashLoanData.clearinghouse).lendToCooler(cooler, flashLoanData.principal);

        // The cooler owner will receive DAI for the consolidated loan
        // Transfer this amount, plus the fee, to this contract
        // Approval must have already been granted by the Cooler owner
        DAI.transferFrom(cooler.owner(), address(this), amount_ + lenderFee_);
        // Approve the flash loan provider to collect the flashloan amount and fee
        DAI.approve(address(FLASH), amount_ + lenderFee_);

        // Pay protocol fee
        if (flashLoanData.protocolFee != 0) DAI.transfer(address(TRSRY), flashLoanData.protocolFee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // ========= ADMIN ========= //

    /// @notice Set the fee percentage
    /// @dev    This function will revert if:
    ///         - The fee percentage is above `ONE_HUNDRED_PERCENT`
    ///         - The caller does not have the `ROLE_ADMIN` role
    function setFeePercentage(uint256 feePercentage_) external onlyRole(ROLE_ADMIN) {
        if (feePercentage_ > ONE_HUNDRED_PERCENT) revert Params_FeePercentageOutOfRange();

        feePercentage = feePercentage_;
        emit FeePercentageSet(feePercentage_);
    }

    /// @notice Activate the contract
    /// @dev    This function will revert if:
    ///         - The caller does not have the `ROLE_EMERGENCY_SHUTDOWN` role
    ///
    ///         If the contract is already active, it will do nothing.
    function activate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // Skip if already activated
        if (active) return;

        active = true;
        emit Activated();
    }

    /// @notice Deactivate the contract
    /// @dev    This function will revert if:
    ///         - The caller does not have the `ROLE_EMERGENCY_SHUTDOWN` role
    ///
    ///         If the contract is already deactivated, it will do nothing.
    function deactivate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // Skip if already deactivated
        if (!active) return;

        active = false;
        emit Deactivated();
    }

    /// @notice Modifier to check that the contract is active
    modifier onlyActive() {
        if (!active) revert OnlyActive();
        _;
    }

    // =========  FUNCTIONS ========= //

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
        GOHM.transferFrom(cooler.owner(), address(this), totalCollateral);
    }

    function _isValidClearinghouse(address clearinghouse_) internal view returns (bool) {
        // We check against the registry (not just active), as repayments are still allowed when a Clearinghouse is deactivated
        uint256 registryCount = CHREG.registryCount();
        bool found;
        for (uint256 i; i < registryCount; i++) {
            if (CHREG.registry(i) == clearinghouse_) {
                found = true;
                break;
            }
        }

        return found;
    }

    /// @notice Check if a given cooler was created by the CoolerFactory for a Clearinghouse
    /// @dev    This function assumes that the authenticity of the Clearinghouse is already verified
    ///
    /// @param  clearinghouse_ Clearinghouse contract
    /// @param  cooler_       Cooler contract
    /// @return bool          Whether the cooler was created by the CoolerFactory for the Clearinghouse
    function _isValidCooler(address clearinghouse_, address cooler_) internal view returns (bool) {
        Clearinghouse clearinghouse = Clearinghouse(clearinghouse_);
        CoolerFactory coolerFactory = CoolerFactory(clearinghouse.factory());

        return coolerFactory.created(cooler_);
    }

    // ========= AUX FUNCTIONS ========= //

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
        if (ids_.length < 2) revert Params_InsufficientCoolerCount();

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
            SDAI.previewWithdraw(totalDebtWithFee),
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
        if (ids_.length == 0) revert Params_InsufficientCoolerCount();

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
        return 4;
    }
}
