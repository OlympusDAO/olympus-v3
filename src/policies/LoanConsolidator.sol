// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {Kernel, Keycode, toKeycode, Permissions, Policy} from "src/Kernel.sol";

import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {RGSTYv1} from "src/modules/RGSTY/RGSTY.v1.sol";

import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

/// @title  Loan Consolidator
/// @notice A policy that consolidates loans taken with a single Cooler contract into a single loan using Maker flashloans.
///         This policy can be used to consolidate loans within the same Clearinghouse, or from one Clearinghouse to another.
///         This also enables migration between debt denominated in different assets (such as DAI and USDS).
/// @dev    This policy uses the `IERC3156FlashBorrower` interface to interact with Maker flashloans.
///
///         This contract utilises the following roles:
///         - `loan_consolidator_admin`: Can set the fee percentage
///         - `emergency_shutdown`: Can activate and deactivate the contract
contract LoanConsolidator is IERC3156FlashBorrower, Policy, RolesConsumer, ReentrancyGuard {
    // ========= ERRORS ========= //

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the caller is not the Cooler owner.
    error OnlyCoolerOwner();

    /// @notice Thrown when the contract is not active.
    error OnlyConsolidatorActive();

    /// @notice Thrown when the contract is not activated as a policy.
    error OnlyPolicyActive();

    /// @notice Thrown when the fee percentage is out of range.
    /// @dev    Valid values are 0 <= feePercentage <= 100e2
    error Params_FeePercentageOutOfRange();

    /// @notice Thrown when the address is invalid.
    error Params_InvalidAddress();

    /// @notice Thrown when the caller attempts to consolidate too few cooler loans. The minimum is two.
    error Params_InsufficientCoolerCount();

    /// @notice Thrown when the Clearinghouse is not registered with the Bophades kernel
    error Params_InvalidClearinghouse();

    /// @notice Thrown when the Cooler is not created by the CoolerFactory for the specified Clearinghouse
    error Params_InvalidCooler();

    // ========= EVENTS ========= //

    /// @notice Emitted when the contract is activated
    /// @dev    Note that this is different to activation of the contract as a policy
    event ConsolidatorActivated();

    /// @notice Emitted when the contract is deactivated
    /// @dev    Note that this is different to deactivation of the contract as a policy
    event ConsolidatorDeactivated();

    /// @notice Emitted when the fee percentage is set
    event FeePercentageSet(uint256 feePercentage);

    // ========= DATA STRUCTURES ========= //

    /// @notice Data structure used for flashloan parameters
    struct FlashLoanData {
        Clearinghouse clearinghouseFrom;
        Clearinghouse clearinghouseTo;
        Cooler coolerFrom;
        Cooler coolerTo;
        uint256[] ids;
        uint256 principal;
        uint256 interest;
        uint256 protocolFee;
        MigrationType migrationType;
        IERC20 reserveFrom;
        IERC20 reserveTo;
    }

    enum MigrationType {
        DAI_DAI,
        USDS_USDS,
        DAI_USDS,
        USDS_DAI
    }

    // ========= STATE ========= //

    /// @notice The Clearinghouse registry module
    /// @dev    The value is set when the policy is activated
    CHREGv1 internal CHREG;

    /// @notice The treasury module
    /// @dev    The value is set when the policy is activated
    TRSRYv1 internal TRSRY;

    /// @notice The contract registry module
    /// @dev    The value is set when the policy is activated
    RGSTYv1 internal RGSTY;

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

    /// @notice The denominator for percentage calculations
    uint256 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice Percentage of the debt to be paid as a fee
    /// @dev    In terms of `ONE_HUNDRED_PERCENT`
    uint256 public feePercentage;

    /// @notice Whether the contract is active
    /// @dev    Note that this is different to the policy activation status
    bool public consolidatorActive;

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

        // Store protocol data
        feePercentage = feePercentage_;

        // Set the contract to be disabled by default
        // It must be activated as a policy and activated before being used
        consolidatorActive = false;

        // Emit events
        emit FeePercentageSet(feePercentage);
        emit ConsolidatorActivated();
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("RGSTY");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        // Populate module dependencies
        CHREG = CHREGv1(getModuleAddress(dependencies[0]));
        RGSTY = RGSTYv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1, 1]);
        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 RGSTY_MAJOR, ) = RGSTY.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        if (CHREG_MAJOR != 1 || RGSTY_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Populate variables
        // This function will be called whenever a contract is registered or deregistered, which enables caching of the values
        // Token contract addresses are immutable
        DAI = IERC20(RGSTY.getImmutableContract("dai"));
        USDS = IERC20(RGSTY.getImmutableContract("usds"));
        GOHM = IERC20(RGSTY.getImmutableContract("gohm"));
        // Utility contract addresses are mutable
        FLASH = IERC3156FlashLender(RGSTY.getContract("flash"));
        MIGRATOR = IDaiUsdsMigrator(RGSTY.getContract("dmgtr"));

        return dependencies;
    }

    /// @inheritdoc Policy
    /// @dev        This policy does not require any permissions
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        requests = new Permissions[](0);

        return requests;
    }

    // ========= OPERATION ========= //

    /// @notice Consolidate loans (taken with a single Cooler contract) into a single loan by using flashloans.
    ///
    ///         Unlike `consolidateWithNewOwner()`, the owner of the new Cooler must be the same as the Cooler being repaid.
    ///
    ///         The caller will be required to provide additional funds to cover accrued interest on the Cooler loans and the lender and protocol fees (if applicable). Use the `requiredApprovals()` function to determine the amount of funds and approvals required.
    ///
    ///         It is expected that the caller will have already provided approval for this contract to spend the required tokens. See `requiredApprovals()` for more details.
    ///
    /// @dev    This function will revert if:
    ///         - The caller is not the 'coolerFrom' and 'coolerTo' owner.
    ///         - The caller has not approved this contract to spend the reserve token of `clearinghouseTo_` in order to pay the interest, lender and protocol fees.
    ///         - The caller has not approved this contract to spend the gOHM escrowed by `coolerFrom_`.
    ///         - `clearinghouseFrom_` or `clearinghouseTo_` is not registered with the Clearinghouse registry.
    ///         - `coolerFrom_` or `coolerTo_` is not a valid Cooler for the respective Clearinghouse.
    ///         - Consolidation is taking place within the same Cooler, and less than two loans are being consolidated.
    ///         - The available funds are less than the required flashloan amount.
    ///         - The contract is not active.
    ///         - The contract has not been activated as a policy.
    ///         - Re-entrancy is detected.
    ///
    /// @param  clearinghouseFrom_ Olympus Clearinghouse that issued the existing loans.
    /// @param  clearinghouseTo_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  coolerFrom_     Cooler from which the loans will be consolidated.
    /// @param  coolerTo_     Cooler to which the loans will be consolidated
    /// @param  ids_           Array containing the ids of the loans to be consolidated.
    function consolidate(
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] calldata ids_
    ) public onlyPolicyActive onlyConsolidatorActive nonReentrant {
        // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
        if (Cooler(coolerFrom_).owner() != msg.sender || Cooler(coolerTo_).owner() != msg.sender)
            revert OnlyCoolerOwner();

        _consolidateWithFlashLoan(
            clearinghouseFrom_,
            clearinghouseTo_,
            coolerFrom_,
            coolerTo_,
            ids_
        );
    }

    /// @notice Consolidate loans (taken with a single Cooler contract) into a single loan by using flashloans.
    ///
    ///         Unlike `consolidate()`, the owner of the new Cooler can be different from the Cooler being repaid.
    ///
    ///         The caller will be required to provide additional funds to cover accrued interest on the Cooler loans and the lender and protocol fees (if applicable). Use the `requiredApprovals()` function to determine the amount of funds and approvals required.
    ///
    ///         It is expected that the caller will have already provided approval for this contract to spend the required tokens. See `requiredApprovals()` for more details.
    ///
    /// @dev    This function will revert if:
    ///         - The caller is not the `coolerFrom_` owner.
    ///         - `coolerFrom_` is the same as `coolerTo_` (in which case `consolidate()` should be used).
    ///         - The owner of `coolerFrom_` is the same as `coolerTo_` (in which case `consolidate()` should be used).
    ///         - The caller has not approved this contract to spend the reserve token of `clearinghouseTo_` in order to pay the interest, lender and protocol fees.
    ///         - The caller has not approved this contract to spend the gOHM escrowed by the target Cooler.
    ///         - `clearinghouseFrom_` or `clearinghouseTo_` is not registered with the Clearinghouse registry.
    ///         - `coolerFrom_` or `coolerTo_` is not a valid Cooler for the respective Clearinghouse.
    ///         - Consolidation is taking place within the same Cooler, and less than two loans are being consolidated.
    ///         - The available funds are less than the required flashloan amount.
    ///         - The contract is not active.
    ///         - The contract has not been activated as a policy.
    ///         - Re-entrancy is detected.
    ///
    /// @param  clearinghouseFrom_ Olympus Clearinghouse that issued the existing loans.
    /// @param  clearinghouseTo_ Olympus Clearinghouse to be used to issue the consolidated loan.
    /// @param  coolerFrom_     Cooler from which the loans will be consolidated.
    /// @param  coolerTo_     Cooler to which the loans will be consolidated
    /// @param  ids_           Array containing the ids of the loans to be consolidated.
    function consolidateWithNewOwner(
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] calldata ids_
    ) public onlyPolicyActive onlyConsolidatorActive nonReentrant {
        // Ensure `msg.sender` is allowed to spend cooler funds on behalf of this contract
        if (Cooler(coolerFrom_).owner() != msg.sender) revert OnlyCoolerOwner();

        // Ensure that the owner of the coolerFrom_ is not the same as coolerTo_
        // This also implicitly checks that the coolers must be different, ie. can't operate on the same Cooler
        if (Cooler(coolerTo_).owner() == msg.sender) revert Params_InvalidCooler();

        _consolidateWithFlashLoan(
            clearinghouseFrom_,
            clearinghouseTo_,
            coolerFrom_,
            coolerTo_,
            ids_
        );
    }

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
    function _consolidateWithFlashLoan(
        address clearinghouseFrom_,
        address clearinghouseTo_,
        address coolerFrom_,
        address coolerTo_,
        uint256[] calldata ids_
    ) internal {
        // Validate that the Clearinghouses are registered with the Bophades kernel
        if (!_isValidClearinghouse(clearinghouseFrom_) || !_isValidClearinghouse(clearinghouseTo_))
            revert Params_InvalidClearinghouse();

        // Validate that the previous cooler was created by the CoolerFactory for the Clearinghouse
        if (
            !_isValidCooler(clearinghouseFrom_, coolerFrom_) ||
            !_isValidCooler(clearinghouseTo_, coolerTo_)
        ) revert Params_InvalidCooler();

        // If consolidating within the same Cooler, ensure that at least two loans are being consolidated
        if (coolerFrom_ == coolerTo_ && ids_.length < 2) revert Params_InsufficientCoolerCount();

        // If consolidating across different Coolers, ensure that at least one loan is being consolidated
        if (coolerFrom_ != coolerTo_ && ids_.length == 0) revert Params_InsufficientCoolerCount();

        // Get the migration type and reserve tokens
        (MigrationType migrationType, IERC20 reserveFrom, IERC20 reserveTo) = _getMigrationType(
            clearinghouseFrom_,
            clearinghouseTo_
        );

        (uint256 flashloanAmount, FlashLoanData memory flashloanParams) = _getFlashloanParameters(
            Clearinghouse(clearinghouseFrom_),
            Clearinghouse(clearinghouseTo_),
            Cooler(coolerFrom_),
            Cooler(coolerTo_),
            ids_,
            migrationType,
            reserveFrom,
            reserveTo
        );

        // Transfer in the interest and fees from the caller, in terms of the reserveTo token
        // The Cooler owner will supply the principal, so the balance needs to be provided by the caller
        {
            uint256 lenderFee = FLASH.flashFee(address(DAI), flashloanAmount);
            reserveTo.transferFrom(
                msg.sender,
                address(this),
                flashloanParams.interest + flashloanParams.protocolFee + lenderFee
            );
        }

        // Take flashloan
        // This will trigger the `onFlashLoan` function after the flashloan amount has been transferred to this contract
        FLASH.flashLoan(this, address(DAI), flashloanAmount, abi.encode(flashloanParams));
        // State:
        // - reserveFrom: 0
        // - reserveTo: 0
        // - gOHM: 0

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 daiBalanceAfter = DAI.balanceOf(address(this));
        if (daiBalanceAfter > 0) {
            DAI.transfer(msg.sender, daiBalanceAfter);
        }
        uint256 usdsBalanceAfter = USDS.balanceOf(address(this));
        if (usdsBalanceAfter > 0) {
            USDS.transfer(msg.sender, usdsBalanceAfter);
        }
    }

    /// @inheritdoc IERC3156FlashBorrower
    /// @dev        This function reverts if:
    ///             - The caller is not the flash loan provider
    ///             - The initiator is not this contract
    function onFlashLoan(
        address initiator_,
        address, // flashloan token is only DAI
        uint256 amount_,
        uint256 lenderFee_,
        bytes calldata params_
    ) external override returns (bytes32) {
        FlashLoanData memory flashLoanData = abi.decode(params_, (FlashLoanData));

        // perform sanity checks
        if (msg.sender != address(FLASH)) revert OnlyLender();
        if (initiator_ != address(this)) revert OnlyThis();

        // Assumptions:
        // - The flashloan provider has transferred amount_ in DAI, which is equal to the principal
        // - This contract has transferred from the caller the interest, lender fee and protocol fee to this contract

        // If clearinghouseFrom is in USDS, then we need to convert the flashloan DAI to USDS in order to repay the principal
        if (
            flashLoanData.migrationType == MigrationType.USDS_DAI ||
            flashLoanData.migrationType == MigrationType.USDS_USDS
        ) {
            DAI.approve(address(MIGRATOR), flashLoanData.principal);
            MIGRATOR.daiToUsds(address(this), flashLoanData.principal);
        }

        // Ensure that the interest transferred from the caller is in terms of the reserveFrom token
        // Interest was collected in terms of the reserveTo token
        if (flashLoanData.migrationType == MigrationType.USDS_DAI) {
            DAI.approve(address(MIGRATOR), flashLoanData.interest);
            MIGRATOR.daiToUsds(address(this), flashLoanData.interest);
        }
        if (flashLoanData.migrationType == MigrationType.DAI_USDS) {
            USDS.approve(address(MIGRATOR), flashLoanData.interest);
            MIGRATOR.usdsToDai(address(this), flashLoanData.interest);
        }

        // Grant approval to the Cooler to spend the debt
        flashLoanData.reserveFrom.approve(
            address(flashLoanData.coolerFrom),
            flashLoanData.principal + flashLoanData.interest
        );
        // Iterate over all batches, repay the debt
        _repayDebtForLoans(address(flashLoanData.coolerFrom), flashLoanData.ids);
        // State:
        // - reserveFrom: reduced by principal and interest, should be 0
        // - reserveTo: no change, balance is lender fee + protocol fee
        // - gOHM: no change, should be 0

        // Calculate the amount of collateral that will be needed for the consolidated loan
        // This is performed on the destination Clearinghouse, since it will be the one issuing the consolidated loan
        uint256 consolidatedLoanCollateral = flashLoanData.clearinghouseTo.getCollateralForLoan(
            flashLoanData.principal
        );

        // Transfer the collateral from the cooler owner to this contract
        GOHM.transferFrom(
            flashLoanData.coolerFrom.owner(),
            address(this),
            consolidatedLoanCollateral
        );
        // State:
        // - reserveFrom: no change
        // - reserveTo: no change
        // - gOHM: increased by consolidatedLoanCollateral

        // Take a new Cooler loan for the principal required
        GOHM.approve(address(flashLoanData.clearinghouseTo), consolidatedLoanCollateral);
        flashLoanData.clearinghouseTo.lendToCooler(flashLoanData.coolerTo, flashLoanData.principal);
        // State:
        // - reserveFrom: no change
        // - reserveTo: no change, as the cooler owner received it
        // - gOHM: reduced by the collateral used for the consolidated loan. gOHM balance in this contract is now 0.

        // The coolerTo owner will receive `principal` quantity of `reserveTo` tokens for the consolidated loan
        // Transfer the principal amount in terms of `reserveTo`. The lender fee and protocol fee have already been transferred to this contract.
        // Approval must have already been granted by the Cooler owner
        flashLoanData.reserveTo.transferFrom(
            flashLoanData.coolerTo.owner(),
            address(this),
            flashLoanData.principal
        );
        // State:
        // - reserveFrom: no change
        // - reserveTo: increased by the loan principal, balance is principal + lender fee + protocol fee
        // - gOHM: no change, 0

        // The flashloan needs to be repaid in DAI
        // Convert the proceeds to DAI if necessary
        if (
            flashLoanData.migrationType == MigrationType.DAI_USDS ||
            flashLoanData.migrationType == MigrationType.USDS_USDS
        ) {
            USDS.approve(address(MIGRATOR), amount_ + lenderFee_);
            MIGRATOR.usdsToDai(address(this), amount_ + lenderFee_);
        }

        // Approve the flash loan provider to collect the flashloan amount and fee
        DAI.approve(address(FLASH), amount_ + lenderFee_);

        // Pay protocol fee, which would be left over
        if (flashLoanData.protocolFee != 0)
            flashLoanData.reserveTo.transfer(address(TRSRY), flashLoanData.protocolFee);
        // State:
        // - reserveFrom: no change
        // - reserveTo: reduced by the protocol fee, balance should be 0
        // - gOHM: no change, balance should be 0

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // ========= ADMIN ========= //

    /// @notice Set the fee percentage
    /// @dev    This function will revert if:
    ///         - The contract has not been activated as a policy.
    ///         - The fee percentage is above `ONE_HUNDRED_PERCENT`
    ///         - The caller does not have the `ROLE_ADMIN` role
    function setFeePercentage(
        uint256 feePercentage_
    ) external onlyPolicyActive onlyRole(ROLE_ADMIN) {
        if (feePercentage_ > ONE_HUNDRED_PERCENT) revert Params_FeePercentageOutOfRange();

        feePercentage = feePercentage_;
        emit FeePercentageSet(feePercentage_);
    }

    /// @notice Activate the contract
    /// @dev    This function will revert if:
    ///         - The contract has not been activated as a policy.
    ///         - The caller does not have the `ROLE_EMERGENCY_SHUTDOWN` role
    ///
    ///         If the contract is already active, it will do nothing.
    function activate() external onlyPolicyActive onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // Skip if already activated
        if (consolidatorActive) return;

        consolidatorActive = true;
        emit ConsolidatorActivated();
    }

    /// @notice Deactivate the contract
    /// @dev    This function will revert if:
    ///         - The contract has not been activated as a policy.
    ///         - The caller does not have the `ROLE_EMERGENCY_SHUTDOWN` role
    ///
    ///         If the contract is already deactivated, it will do nothing.
    function deactivate() external onlyPolicyActive onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // Skip if already deactivated
        if (!consolidatorActive) return;

        consolidatorActive = false;
        emit ConsolidatorDeactivated();
    }

    /// @notice Modifier to check that the contract is active
    modifier onlyConsolidatorActive() {
        if (!consolidatorActive) revert OnlyConsolidatorActive();
        _;
    }

    /// @notice Modifier to check that the contract is activated as a policy
    modifier onlyPolicyActive() {
        if (!kernel.isPolicyActive(this)) revert OnlyPolicyActive();
        _;
    }

    // =========  FUNCTIONS ========= //

    /// @notice Get the total principal and interest for a given set of loans
    ///
    /// @param  cooler_         Cooler contract that issued the loans
    /// @param  ids_            Array of loan ids to be consolidated
    /// @return totalPrincipal_ Total principal
    /// @return totalInterest_  Total interest
    function _getDebtForLoans(
        address cooler_,
        uint256[] calldata ids_
    ) internal view returns (uint256, uint256) {
        uint256 totalInterest;
        uint256 totalPrincipal;

        uint256 numLoans = ids_.length;
        for (uint256 i; i < numLoans; i++) {
            (, uint256 principal, uint256 interestDue, , , , , ) = Cooler(cooler_).loans(ids_[i]);
            totalInterest += interestDue;
            totalPrincipal += principal;
        }

        return (totalPrincipal, totalInterest);
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

        // Upon repayment, the collateral is released to the owner
        // After this function concludes, the contract needs to transfer the collateral to itself
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

    /// @notice Get the reserve token for a given Clearinghouse
    /// @dev    This function will revert if the reserve token cannot be determined
    ///
    /// @param  clearinghouse_  Clearinghouse contract
    /// @return address         Reserve token
    function _getClearinghouseReserveToken(address clearinghouse_) internal view returns (address) {
        // Clearinghouse v1, v1.1 has a `dai()` function
        // Perform a low-level call to check if it exists
        (bool success, bytes memory data) = address(clearinghouse_).staticcall(
            abi.encodeWithSignature("dai()")
        );
        if (success) {
            return abi.decode(data, (address));
        }

        // Clearinghouse v2 has a `reserve()` function
        // Perform a low-level call to check if it exists
        (success, data) = address(clearinghouse_).staticcall(abi.encodeWithSignature("reserve()"));
        if (success) {
            return abi.decode(data, (address));
        }

        revert Params_InvalidClearinghouse();
    }

    /// @notice Get the migration type for a given pair of Clearinghouses
    /// @dev    This function will revert if the migration type cannot be determined
    ///
    /// @param  clearinghouseFrom_  Clearinghouse that issued the existing loans
    /// @param  clearinghouseTo_    Clearinghouse to be used to issue the consolidated loan
    /// @return migrationType       Migration type
    /// @return reserveFrom         Reserve token for the existing loans
    /// @return reserveTo           Reserve token for the consolidated loan
    function _getMigrationType(
        address clearinghouseFrom_,
        address clearinghouseTo_
    ) internal view returns (MigrationType migrationType, IERC20 reserveFrom, IERC20 reserveTo) {
        // Determine the reserve token for each Clearinghouse
        address reserveFromAddress = _getClearinghouseReserveToken(clearinghouseFrom_);
        address reserveToAddress = _getClearinghouseReserveToken(clearinghouseTo_);
        reserveFrom = IERC20(reserveFromAddress);
        reserveTo = IERC20(reserveToAddress);

        // DAI, no migration
        if (reserveFromAddress == address(DAI) && reserveFromAddress == reserveToAddress) {
            return (MigrationType.DAI_DAI, reserveFrom, reserveTo);
        }

        // USDS, no migration
        if (reserveFromAddress == address(USDS) && reserveFromAddress == reserveToAddress) {
            return (MigrationType.USDS_USDS, reserveFrom, reserveTo);
        }

        // DAI -> USDS migration
        if (reserveFromAddress == address(DAI) && reserveToAddress == address(USDS)) {
            return (MigrationType.DAI_USDS, reserveFrom, reserveTo);
        }

        // USDS -> DAI migration
        if (reserveFromAddress == address(USDS) && reserveToAddress == address(DAI)) {
            return (MigrationType.USDS_DAI, reserveFrom, reserveTo);
        }

        // Otherwise it is unsupported
        revert Params_InvalidClearinghouse();
    }

    /// @notice Assembles the parameters for a flashloan
    ///
    /// @param  clearinghouseFrom_  Clearinghouse that issued the existing loans
    /// @param  clearinghouseTo_    Clearinghouse to be used to issue the consolidated loan
    /// @param  coolerFrom_         Cooler contract that issued the existing loans
    /// @param  coolerTo_           Cooler contract to be used to issue the consolidated loan
    /// @param  ids_                Array of loan ids to be consolidated
    /// @param  migrationType_      Migration type
    /// @param  reserveFrom_        Reserve token for the existing loans
    /// @param  reserveTo_          Reserve token for the consolidated loan
    /// @return flashloanAmount     Amount of the flashloan
    /// @return flashloanParams     Flashloan parameters
    function _getFlashloanParameters(
        Clearinghouse clearinghouseFrom_,
        Clearinghouse clearinghouseTo_,
        Cooler coolerFrom_,
        Cooler coolerTo_,
        uint256[] calldata ids_,
        MigrationType migrationType_,
        IERC20 reserveFrom_,
        IERC20 reserveTo_
    ) internal view returns (uint256 flashloanAmount, FlashLoanData memory flashloanParams) {
        // Cache principal and interest
        (uint256 totalPrincipal, uint256 totalInterest) = _getDebtForLoans(
            address(coolerFrom_),
            ids_
        );

        uint256 protocolFee = getProtocolFee(totalPrincipal + totalInterest);

        // The flashloan amount is in DAI. This assumes a 1:1 exchange rate.
        // The flashloan amount is the total principal, without any interest
        // This is because the interest is paid by the caller, not the flashloan provider
        flashloanAmount = totalPrincipal;

        flashloanParams = FlashLoanData({
            clearinghouseFrom: clearinghouseFrom_,
            clearinghouseTo: clearinghouseTo_,
            coolerFrom: coolerFrom_,
            coolerTo: coolerTo_,
            ids: ids_,
            principal: totalPrincipal,
            interest: totalInterest,
            protocolFee: protocolFee,
            migrationType: migrationType_,
            reserveFrom: reserveFrom_,
            reserveTo: reserveTo_
        });

        return (flashloanAmount, flashloanParams);
    }

    // ========= AUX FUNCTIONS ========= //

    /// @notice View function to compute the protocol fee for a given total debt.
    function getProtocolFee(uint256 totalDebt_) public view returns (uint256) {
        return (totalDebt_ * feePercentage) / ONE_HUNDRED_PERCENT;
    }

    /// @notice View function to compute the required approval amounts that the owner of a given Cooler
    ///         must give to this contract in order to consolidate the loans.
    ///
    /// @dev    This function will revert if:
    ///         - The contract has not been activated as a policy.
    ///
    /// @param  clearinghouseTo_    Clearinghouse contract used to issue the consolidated loan.
    /// @param  coolerFrom_         Cooler contract that issued the loans.
    /// @param  ids_                Array of loan ids to be consolidated.
    /// @return owner               Owner of the Cooler (address that should grant the approval).
    /// @return gOhmAmount          Amount of gOHM to be approved by the Cooler owner.
    /// @return reserveTo           Token that the approval is in terms of
    /// @return ownerReserveTo      Amount of `reserveTo` to be approved by the Cooler owner. This will be the principal of the consolidated loan.
    /// @return callerReserveTo     Amount of `reserveTo` that the caller will need to provide.
    function requiredApprovals(
        address clearinghouseTo_,
        address coolerFrom_,
        uint256[] calldata ids_
    ) external view onlyPolicyActive returns (address, uint256, address, uint256, uint256) {
        // Cache the total principal and interest
        (uint256 totalPrincipal, uint256 totalInterest) = _getDebtForLoans(
            address(coolerFrom_),
            ids_
        );

        uint256 totalFees;
        {
            uint256 protocolFee = getProtocolFee(totalPrincipal + totalInterest);
            uint256 lenderFee = FLASH.flashFee(address(DAI), totalPrincipal);

            totalFees = totalInterest + lenderFee + protocolFee;
        }

        // Calculate the collateral required for the consolidated loan principal
        uint256 consolidatedLoanCollateral = Clearinghouse(clearinghouseTo_).getCollateralForLoan(
            totalPrincipal
        );

        return (
            Cooler(coolerFrom_).owner(),
            consolidatedLoanCollateral,
            _getClearinghouseReserveToken(clearinghouseTo_),
            totalPrincipal,
            totalFees
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

    /// @notice View function to compute the funds required to consolidate a set of loans.
    ///         The sum of the values must be held in the caller's wallet, in terms of the reserve token.
    ///
    /// @param  clearinghouseTo_    Clearinghouse contract to be used to issue the consolidated loan.
    /// @param  coolerFrom_         Cooler contract that issued the loans.
    /// @param  ids_                Array of loan ids to be consolidated.
    /// @return reserveTo           Token the fund amounts are in terms of
    /// @return interest            Total interest
    /// @return lenderFee           Lender fee
    /// @return protocolFee         Protocol fee
    function fundsRequired(
        address clearinghouseTo_,
        address coolerFrom_,
        uint256[] calldata ids_
    )
        public
        view
        onlyPolicyActive
        returns (address reserveTo, uint256 interest, uint256 lenderFee, uint256 protocolFee)
    {
        (uint256 totalPrincipal, uint256 totalInterest) = _getDebtForLoans(
            address(coolerFrom_),
            ids_
        );
        reserveTo = _getClearinghouseReserveToken(clearinghouseTo_);
        protocolFee = getProtocolFee(totalPrincipal + totalInterest);
        interest = totalInterest;
        lenderFee = FLASH.flashFee(address(DAI), totalPrincipal);

        return (reserveTo, interest, lenderFee, protocolFee);
    }

    /// @notice Version of the contract
    ///
    /// @return Version number
    function VERSION() external pure returns (uint256) {
        return 4;
    }
}
