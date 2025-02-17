// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

// Libraries
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";

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
contract CoolerV2Migrator is IERC3156FlashBorrower, ReentrancyGuard, Policy, PolicyEnabler {
    // ========= ERRORS ========= //

    /// @notice Thrown when the caller is not the contract itself.
    error OnlyThis();

    /// @notice Thrown when the caller is not the flash lender.
    error OnlyLender();

    /// @notice Thrown when the Cooler is not owned by the caller
    error Only_CoolerOwner();

    /// @notice Thrown when the number of Clearinghouses does not equal the number of Coolers
    error Params_InvalidArrays();

    /// @notice Thrown when the Clearinghouse is not valid
    error Params_InvalidClearinghouse();

    /// @notice Thrown when the Cooler is not valid
    error Params_InvalidCooler();

    /// @notice Thrown when the new owner address provided does not match the authorization
    error Params_InvalidNewOwner();

    /// @notice Thrown when the Cooler is duplicated
    error Params_DuplicateCooler();

    // ========= DATA STRUCTURES ========= //

    struct CoolerData {
        address cooler;
        uint256 numLoans;
    }

    /// @notice Data structure used for flashloan parameters
    struct FlashLoanData {
        address[] clearinghouses;
        address[] coolers;
        address currentOwner;
        address newOwner;
        uint256 toDAI;
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

    /// @notice The Cooler V2 contract
    /// @dev    The value is set when the policy is activated
    IMonoCooler internal COOLERV2;

    /// @notice A mapping to validate clearinghouses
    // TODO use CHREG
    mapping(address => bool) public isCHV1;

    // ========= CONSTRUCTOR ========= //

    // TODO add PolicyEnabler

    constructor(
        address kernel_,
        address coolerV2_,
        address[] memory chV1s
    ) Policy(Kernel(kernel_)) {
        COOLERV2 = IMonoCooler(coolerV2_);

        for (uint256 i; i < chV1s.length; ++i) {
            isCHV1[chV1s[i]] = true;
        }
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

    // TODO extract interface

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
    function consolidate(
        address[] memory clearinghouses,
        address[] memory coolers,
        uint256 flashBorrow,
        uint256 toDAI,
        address newOwner,
        IMonoCooler.Authorization memory authorization,
        IMonoCooler.Signature calldata signature
    ) external onlyEnabled nonReentrant {
        // Validate that the number of clearinghouses and coolers are the same
        if (clearinghouses.length != coolers.length) revert Params_InvalidArrays();

        // Validate that the Clearinghouses and Coolers are protocol-owned
        // Also calculate the principal and interest for each cooler
        CoolerData[] memory coolerData = new CoolerData[](clearinghouses.length);
        uint256 totalPrincipal;
        uint256 totalInterest;
        for (uint256 i; i < clearinghouses.length; i++) {
            // Check that the Clearinghouse is owned by the protocol
            if (!_isValidClearinghouse(clearinghouses[i])) revert Params_InvalidClearinghouse();

            // Check that the Clearinghouse's CoolerFactory created the Cooler
            if (!_isValidCooler(clearinghouses[i], coolers[i])) revert Params_InvalidCooler();

            // Check that the Cooler is owned by the caller
            if (Cooler(coolers[i]).owner() != msg.sender) revert Only_CoolerOwner();

            // Check that the Cooler is not already in the array
            for (uint256 j; j < coolerData.length; j++) {
                if (coolerData[j].cooler == coolers[i]) revert Params_DuplicateCooler();
            }

            // Determine the total principal and interest for the cooler
            (uint256 coolerPrincipal, uint256 coolerInterest, uint256 numLoans) = _getDebtForCooler(Cooler(coolers[i]));
            coolerData[i] = CoolerData({
                cooler: coolers[i],
                numLoans: numLoans
            });
            totalPrincipal += coolerPrincipal;
            totalInterest += coolerInterest;
        }

        // Validate that authorization has been provided by the new owner
        if (authorization.account != newOwner) revert Params_InvalidNewOwner();

        // Authorize this contract to manage user Cooler V2 position
        COOLERV2.setAuthorizationWithSig(authorization, signature);

        // TODO Transfer in interest and fees from the caller
        // vs taking from Cooler V2?

        // Take flashloan
        // This will trigger the `onFlashLoan` function after the flashloan amount has been transferred to this contract
        // TODO change to DAI
        FLASH.flashLoan(
            this,
            address(USDS),
            flashBorrow,
            abi.encode(FlashLoanData(clearinghouses, coolers, msg.sender, newOwner, toDAI))
        );

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 usdsBalanceAfter = USDS.balanceOf(address(this));
        if (usdsBalanceAfter > 0) {
            USDS.transfer(msg.sender, usdsBalanceAfter);
        }

        // TODO transfer out DAI
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

        // TODO Add delegation requests
        IDLGTEv1.DelegationRequest[] memory delegationRequests = new IDLGTEv1.DelegationRequest[](
            0
        );

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

    // TODO add gohm/usds/DAI approvals

    function _handleRepayments(
        Cooler cooler
    ) internal returns (uint256 repaid, uint256 collateral) {
        // provide upfront infinite approval to cooler
        cooler.debt().approve(cooler, type(uint256).max);

        // iterate through and repay loans
        Cooler.Loan[] memory loans = cooler.loans();
        for (uint256 i; i < loans.length; ++i) {
            Cooler.Loan memory loan = loans[i];

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

    // ========= HELPER FUNCTIONS ========= //

    function _getDebtForCooler(Cooler cooler_) internal view returns (uint256 coolerPrincipal, uint256 coolerInterest, uint256 numLoans) {
        uint256 i;

        // The Cooler contract does not expose the number of loans, so we iterate until the call reverts
        while (true) {
            try cooler_.loans(i) returns (
                Cooler.Request memory,
                uint256 principal,
                uint256 interestDue,
                uint256 ,
                uint256,
                address,
                address,
                bool
            ) {
                // Interest is paid down first, so if the principal is 0, the loan has been paid off
                if (principal > 0) {
                    coolerPrincipal += principal;
                    coolerInterest += interestDue;
                }
                i++;
            } catch {
                break;
            }
        }

        return (coolerPrincipal, coolerInterest, i);
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
