// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

// Interfaces
import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";
import {ICoolerV2Migrator} from "../interfaces/cooler/ICoolerV2Migrator.sol";

// Libraries
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";
import {CHREGv1} from "src/modules/CHREG/CHREG.v1.sol";
import {RGSTYv1} from "src/modules/RGSTY/RGSTY.v1.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  CoolerV2Migrator
/// @notice A contract that migrates debt from Olympus Cooler V1 facilities to Cooler V2.
///         This is compatible with all three versions of Cooler V1.
/// @dev    This contract uses the `IERC3156FlashBorrower` interface to interact with Maker flashloans.
///         The debt token of MonoCooler is assumed to be USDS. If that is changed in the future, this contract will need to be re-deployed.
contract CoolerV2Migrator is
    IERC3156FlashBorrower,
    ICoolerV2Migrator,
    ReentrancyGuard,
    Policy,
    PolicyEnabler
{
    using SafeCast for uint256;
    using SafeTransferLib for ERC20;

    // ========= DATA STRUCTURES ========= //

    /// @notice Data structure used to store data about a Cooler
    struct CoolerData {
        Cooler cooler;
        ERC20 debtToken;
        uint8 numLoans;
    }

    /// @dev    Temporary storage for the principal and interest for each debt token
    struct CoolerTotal {
        uint256 daiPrincipal;
        uint256 daiInterest;
        uint256 usdsPrincipal;
        uint256 usdsInterest;
    }

    /// @notice Data structure used for flashloan parameters
    struct FlashLoanData {
        CoolerData[] coolers;
        address currentOwner;
        address newOwner;
        uint256 usdsRequired;
        bool callerPays;
        IDLGTEv1.DelegationRequest[] delegationRequests;
    }

    // ========= MODULES ========= //

    /// @notice The Clearinghouse registry module
    /// @dev    The value is set when the policy is activated
    CHREGv1 internal CHREG;

    /// @notice The contract registry module
    /// @dev    The value is set when the policy is activated
    RGSTYv1 internal RGSTY;

    // ========= STATE ========= //

    /// @notice The DAI token
    ERC20 internal immutable _DAI;

    /// @notice The USDS token
    ERC20 internal immutable _USDS;

    /// @notice The gOHM token
    ERC20 internal immutable _GOHM;

    /// @notice The DAI <> USDS Migrator
    /// @dev    The value is set when the policy is activated
    IDaiUsdsMigrator internal MIGRATOR;

    /// @notice The ERC3156 flash loan provider
    /// @dev    The value is set when the policy is activated
    IERC3156FlashLender internal FLASH;

    /// @notice The Cooler V2 contract
    IMonoCooler internal immutable COOLERV2;

    /// @notice This constant is used when iterating through the loans of a Cooler
    /// @dev    This is used to prevent infinite loops, and is an appropriate upper bound
    ///         as the maximum number of loans seen per Cooler is less than 50.
    uint8 internal constant MAX_LOANS = type(uint8).max;

    // ========= CONSTRUCTOR ========= //

    constructor(
        address kernel_,
        address coolerV2_,
        address dai_,
        address usds_,
        address gohm_
    ) Policy(Kernel(kernel_)) {
        // Validate
        if (coolerV2_ == address(0)) revert Params_InvalidAddress("coolerV2");
        if (dai_ == address(0)) revert Params_InvalidAddress("dai");
        if (usds_ == address(0)) revert Params_InvalidAddress("usds");
        if (gohm_ == address(0)) revert Params_InvalidAddress("gohm");

        COOLERV2 = IMonoCooler(coolerV2_);

        // Validate tokens
        if (address(COOLERV2.collateralToken()) != gohm_) revert Params_InvalidAddress("gohm");
        if (address(COOLERV2.debtToken()) != usds_) revert Params_InvalidAddress("usds");

        _DAI = ERC20(dai_);
        _USDS = ERC20(usds_);
        _GOHM = ERC20(gohm_);
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("CHREG");
        dependencies[1] = toKeycode("RGSTY");
        dependencies[2] = toKeycode("ROLES");

        // Populate module dependencies
        CHREG = CHREGv1(getModuleAddress(dependencies[0]));
        RGSTY = RGSTYv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1]);
        (uint8 CHREG_MAJOR, ) = CHREG.VERSION();
        (uint8 RGSTY_MAJOR, ) = RGSTY.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        if (CHREG_MAJOR != 1 || RGSTY_MAJOR != 1 || ROLES_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Populate variables
        // This function will be called whenever a contract is registered or deregistered, which enables caching of the values
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

    /// @inheritdoc ICoolerV2Migrator
    function previewConsolidate(
        address[] memory coolers_,
        bool callerPays_
    )
        external
        view
        onlyEnabled
        returns (uint256 collateralAmount, uint256 borrowAmount, uint256 paymentAmount)
    {
        // Determine the totals
        uint256 totalInterest;
        for (uint256 i; i < coolers_.length; i++) {
            Cooler cooler = Cooler(coolers_[i]);

            (uint256 principal, uint256 interest, uint256 collateral, , ) = _getDebtForCooler(
                cooler
            );

            collateralAmount += collateral;
            borrowAmount += principal;
            totalInterest += interest;
        }

        // If caller pays is false, we need to include the interest in the borrow amount, which is used to calculate the lender fee
        if (!callerPays_) {
            borrowAmount += totalInterest;
        }

        // Determine the lender fee
        uint256 lenderFee = FLASH.flashFee(address(_DAI), borrowAmount);

        // If enabled, the caller will pay for the interest and fee
        if (callerPays_) {
            paymentAmount += totalInterest + lenderFee;
        }
        // Otherwise the interest (already included) and lender fee will be borrowed
        else {
            borrowAmount += lenderFee;
        }

        return (collateralAmount, borrowAmount, paymentAmount);
    }

    /// @inheritdoc ICoolerV2Migrator
    /// @dev    This function will revert if:
    ///         - The number of elements in `clearinghouses_` and `coolers_` are not the same.
    ///         - Any of the Coolers are not owned by the caller.
    ///         - Any of the Clearinghouses are not owned by the Olympus protocol.
    ///         - Any of the Coolers have not been created by the Clearinghouse's CoolerFactory.
    ///         - A duplicate Cooler is provided.
    ///         - The owner of the destination Cooler V2 has not provided authorization for this contract to manage their Cooler V2 position.
    ///         - The caller has not approved this contract to spend the collateral token, gOHM.
    ///         - The contract is not active.
    ///         - Re-entrancy is detected.
    function consolidate(
        address[] memory coolers_,
        address[] memory clearinghouses_,
        address newOwner_,
        bool callerPays_,
        IMonoCooler.Authorization memory authorization_,
        IMonoCooler.Signature calldata signature_,
        IDLGTEv1.DelegationRequest[] calldata delegationRequests_
    ) external onlyEnabled nonReentrant {
        // Validate that the number of clearinghouses and coolers are the same
        if (clearinghouses_.length != coolers_.length) revert Params_InvalidArrays();

        // Validate that the Clearinghouses and Coolers are protocol-owned
        // Also calculate the principal and interest for each cooler
        CoolerData[] memory coolerData = new CoolerData[](clearinghouses_.length);

        // Keep track of the total principal and interest for each debt token
        CoolerTotal memory totals;
        for (uint256 i; i < clearinghouses_.length; i++) {
            // Check that the Clearinghouse is owned by the protocol
            if (!_isValidClearinghouse(clearinghouses_[i])) revert Params_InvalidClearinghouse();

            // Check that the Clearinghouse's CoolerFactory created the Cooler
            if (!_isValidCooler(clearinghouses_[i], coolers_[i])) revert Params_InvalidCooler();

            // Check that the Cooler is owned by the caller
            Cooler cooler = Cooler(coolers_[i]);
            if (cooler.owner() != msg.sender) revert Only_CoolerOwner();

            // Check that the Cooler is not already in the array
            for (uint256 j; j < coolerData.length; j++) {
                if (address(coolerData[j].cooler) == coolers_[i]) revert Params_DuplicateCooler();
            }

            // Determine the total principal and interest for the cooler
            (
                uint256 coolerPrincipal,
                uint256 coolerInterest,
                ,
                address debtToken,
                uint8 numLoans
            ) = _getDebtForCooler(cooler);
            coolerData[i] = CoolerData({
                cooler: cooler,
                debtToken: ERC20(debtToken),
                numLoans: numLoans
            });

            if (debtToken == address(_DAI)) {
                totals.daiPrincipal += coolerPrincipal;
                totals.daiInterest += coolerInterest;
            } else if (debtToken == address(_USDS)) {
                totals.usdsPrincipal += coolerPrincipal;
                totals.usdsInterest += coolerInterest;
            } else {
                // Unsupported debt token
                revert Params_InvalidCooler();
            }
        }

        // Set the Cooler V2 authorization signature, if provided
        // If the new owner cannot provide a signature (e.g. multisig), they can call `IMonoCooler.setAuthorization()` instead
        if (authorization_.account != address(0)) {
            // Validate that authorization provider and new owner matches
            if (authorization_.account != newOwner_) revert Params_InvalidNewOwner();

            // Authorize this contract to manage user Cooler V2 position
            COOLERV2.setAuthorizationWithSig(authorization_, signature_);
        }

        // Take flashloan
        // This will trigger the `onFlashLoan` function after the flashloan amount has been transferred to this contract
        {
            // Calculate the flashloan amount
            uint256 flashloanAmount = totals.daiPrincipal + totals.usdsPrincipal;
            // If the caller is not paying, then the interest is added to the flashloan amount
            if (!callerPays_) {
                flashloanAmount += totals.daiInterest + totals.usdsInterest;
            }
            // Otherwise transfer in the interest and fee from the caller
            // No change to the flashloan amount
            else {
                uint256 lenderFee = FLASH.flashFee(address(_DAI), flashloanAmount);
                _DAI.safeTransferFrom(
                    msg.sender,
                    address(this),
                    totals.daiInterest + totals.usdsInterest + lenderFee
                );
            }

            FLASH.flashLoan(
                this,
                address(_DAI),
                flashloanAmount,
                abi.encode(
                    FlashLoanData(
                        coolerData,
                        msg.sender,
                        newOwner_,
                        totals.usdsPrincipal + totals.usdsInterest, // The amount of DAI that will be migrated to USDS
                        callerPays_,
                        delegationRequests_
                    )
                )
            );
        }

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 usdsBalanceAfter = _USDS.balanceOf(address(this));
        if (usdsBalanceAfter > 0) {
            _USDS.safeTransfer(msg.sender, usdsBalanceAfter);
        }
        uint256 daiBalanceAfter = _DAI.balanceOf(address(this));
        if (daiBalanceAfter > 0) {
            _DAI.safeTransfer(msg.sender, daiBalanceAfter);
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
        // perform sanity checks
        if (msg.sender != address(FLASH)) revert OnlyLender();
        if (initiator_ != address(this)) revert OnlyThis();

        // Unpack param data
        FlashLoanData memory flashLoanData = abi.decode(params_, (FlashLoanData));
        CoolerData[] memory coolers = flashLoanData.coolers;

        // If there are loans in USDS, convert the required amount from DAI
        // The DAI can come from the flash loan or the caller
        if (flashLoanData.usdsRequired > 0) {
            _DAI.safeApprove(address(MIGRATOR), flashLoanData.usdsRequired);
            MIGRATOR.daiToUsds(address(this), flashLoanData.usdsRequired);
        }

        // Keep track of debt tokens out and collateral in
        uint256 totalPrincipal;
        uint256 totalInterest;
        uint256 totalCollateral;

        // Validate and repay loans for each cooler
        for (uint256 i; i < coolers.length; ++i) {
            CoolerData memory coolerData = coolers[i];

            (uint256 principal, uint256 interest, uint256 collateral) = _handleRepayments(
                coolerData.cooler,
                coolerData.debtToken,
                coolerData.numLoans
            );
            totalPrincipal += principal;
            totalInterest += interest;
            totalCollateral += collateral;
        }

        // Transfer the collateral from the cooler owner to this contract
        _GOHM.safeTransferFrom(flashLoanData.currentOwner, address(this), totalCollateral);

        // Approve the Cooler V2 to spend the collateral
        _GOHM.safeApprove(address(COOLERV2), totalCollateral);

        // Calculate the amount to borrow from Cooler V2
        // If the caller is not paying, then the interest and lender fee will be borrowed from Cooler V2
        uint256 borrowAmount = totalPrincipal;
        if (!flashLoanData.callerPays) {
            borrowAmount += totalInterest + lenderFee_;
        }

        // Add collateral and borrow spent flash loan from Cooler V2
        COOLERV2.addCollateral(
            totalCollateral.encodeUInt128(),
            flashLoanData.newOwner,
            flashLoanData.delegationRequests
        );
        COOLERV2.borrow(borrowAmount.encodeUInt128(), flashLoanData.newOwner, address(this));

        // Convert the USDS to DAI
        uint256 usdsBalance = _USDS.balanceOf(address(this));
        if (usdsBalance > 0) MIGRATOR.usdsToDai(address(this), usdsBalance);

        // Approve the flash loan provider to collect the flashloan amount and fee
        // The initiator will transfer any remaining DAI and USDS back to the caller
        _DAI.safeApprove(address(FLASH), amount_ + lenderFee_);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _handleRepayments(
        Cooler cooler_,
        ERC20 debtToken_,
        uint256 numLoans_
    ) internal returns (uint256 principal, uint256 interest, uint256 collateral) {
        // Provide upfront infinite approval to cooler
        // The consolidate() function is gated by a nonReentrant modifier, so there cannot be a reentrancy attack during the approval and revocation
        debtToken_.safeApprove(address(cooler_), type(uint256).max);

        // Iterate through and repay loans
        for (uint256 i; i < numLoans_; i++) {
            Cooler.Loan memory loan = cooler_.getLoan(i);

            // Only repay outstanding loans
            if (loan.principal > 0) {
                principal += loan.principal;
                interest += loan.interestDue;
                collateral += loan.collateral;

                cooler_.repayLoan(i, loan.principal + loan.interestDue);
            }
        }

        // Revoke approval
        debtToken_.safeApprove(address(cooler_), 0);

        return (principal, interest, collateral);
    }

    // ========= HELPER FUNCTIONS ========= //

    function _getDebtForCooler(
        Cooler cooler_
    )
        internal
        view
        returns (
            uint256 coolerPrincipal,
            uint256 coolerInterest,
            uint256 coolerCollateral,
            address debtToken,
            uint8 numLoans
        )
    {
        // Determine the debt token
        debtToken = address(cooler_.debt());

        // The Cooler contract does not expose the number of loans, so we iterate until the call reverts
        uint8 i;
        for (i; i < MAX_LOANS; i++) {
            try cooler_.getLoan(i) returns (Cooler.Loan memory loan) {
                // Interest is paid down first, so if the principal is 0, the loan has been paid off
                if (loan.principal > 0) {
                    coolerPrincipal += loan.principal;
                    coolerInterest += loan.interestDue;
                    coolerCollateral += loan.collateral;
                }
            } catch Panic(uint256 /*errorCode*/) {
                break;
            }
        }

        return (coolerPrincipal, coolerInterest, coolerCollateral, debtToken, i);
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
}
