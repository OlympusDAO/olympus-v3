// SPDX-License-Identifier: GLP-3.0
pragma solidity ^0.8.15;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";

// Libraries
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";

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
    using SafeCast for uint256;

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
        Cooler cooler;
        IERC20 debtToken;
        uint256 numLoans;
    }

    /// @notice Data structure used for flashloan parameters
    struct FlashLoanData {
        CoolerData[] coolers;
        address currentOwner;
        address newOwner;
        uint256 usdsRequired;
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

    // ========= CONSTRUCTOR ========= //

    constructor(address kernel_, address coolerV2_) Policy(Kernel(kernel_)) {
        COOLERV2 = IMonoCooler(coolerV2_);
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

    // TODO add requiredApprovals() function

    /// @notice Consolidate Cooler V1 loans into Cooler V2
    ///
    ///         This function supports consolidation of loans from multiple Clearinghouses and Coolers, provided that the caller is the owner.
    ///
    ///         As Cooler V2 has a higher LTV than Cooler V1, the additional funds required to pay for the interest and fees do not need to be provided by the caller, and will be borrowed from Cooler V2.
    ///
    ///         It is expected that the caller will have already provided approval for this contract to spend the required tokens. See `requiredApprovals()` for more details.
    ///
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
    ///
    /// @param  coolers_            The Coolers from which the loans will be migrated.
    /// @param  clearinghouses_     The respective Clearinghouses that created and issued the loans in `coolers_`. This array must be the same length as `coolers_`.
    /// @param  newOwner_           Address of the owner of the Cooler V2 position. This can be the same as the caller, or a different address.
    /// @param  authorization_      Authorization parameters for the new owner. Set the `account` field to the zero address to indicate that authorization has already been provided through `IMonoCooler.setAuthorization()`.
    /// @param  signature_          Authorization signature for the new owner. Ignored if `authorization_.account` is the zero address.
    /// @param  delegationRequests_ Delegation requests for the new owner.
    function consolidate(
        address[] memory coolers_,
        address[] memory clearinghouses_,
        address newOwner_,
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
        uint256 daiRequired;
        uint256 usdsRequired;
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
                address debtToken,
                uint256 numLoans
            ) = _getDebtForCooler(cooler);
            coolerData[i] = CoolerData({
                cooler: cooler,
                debtToken: IERC20(debtToken),
                numLoans: numLoans
            });

            if (debtToken == address(DAI)) {
                daiRequired += coolerPrincipal;
                daiRequired += coolerInterest;
            } else if (debtToken == address(USDS)) {
                usdsRequired += coolerPrincipal;
                usdsRequired += coolerInterest;
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
        FLASH.flashLoan(
            this,
            address(DAI),
            daiRequired + usdsRequired,
            abi.encode(
                FlashLoanData(coolerData, msg.sender, newOwner_, usdsRequired, delegationRequests_)
            )
        );

        // This shouldn't happen, but transfer any leftover funds back to the sender
        uint256 usdsBalanceAfter = USDS.balanceOf(address(this));
        if (usdsBalanceAfter > 0) {
            USDS.transfer(msg.sender, usdsBalanceAfter);
        }
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

        // If there are loans in USDS, convert the required amount to DAI
        if (flashLoanData.usdsRequired > 0) {
            DAI.approve(address(MIGRATOR), flashLoanData.usdsRequired);
            MIGRATOR.daiToUsds(address(this), flashLoanData.usdsRequired);
        }

        // Keep track of debt tokens out and collateral in
        uint256 totalRepaid;
        uint256 totalCollateral;

        // Validate and repay loans for each cooler
        for (uint256 i; i < coolers.length; ++i) {
            CoolerData memory coolerData = coolers[i];

            (uint256 repaid, uint256 collateral) = _handleRepayments(
                coolerData.cooler,
                coolerData.debtToken,
                coolerData.numLoans
            );
            totalRepaid += repaid;
            totalCollateral += collateral;
        }

        // Transfer the collateral from the cooler owner to this contract
        GOHM.transferFrom(flashLoanData.currentOwner, address(this), totalCollateral);

        // Add collateral and borrow spent flash loan from Cooler V2
        COOLERV2.addCollateral(
            totalCollateral.encodeUInt128(),
            flashLoanData.newOwner,
            flashLoanData.delegationRequests
        );
        COOLERV2.borrow(
            (totalRepaid + lenderFee_).encodeUInt128(),
            flashLoanData.newOwner,
            address(this)
        );

        // Convert the USDS to DAI
        uint256 usdsBalance = USDS.balanceOf(address(this));
        if (usdsBalance > 0) MIGRATOR.usdsToDai(address(this), usdsBalance);

        // Approve the flash loan provider to collect the flashloan amount and fee
        // The initiator will transfer any remaining DAI and USDS back to the caller
        DAI.approve(address(FLASH), amount_ + lenderFee_);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _handleRepayments(
        Cooler cooler_,
        IERC20 debtToken_,
        uint256 numLoans_
    ) internal returns (uint256 repaid, uint256 collateral) {
        // Provide upfront infinite approval to cooler
        // The consolidate() function is gated by a nonReentrant modifier, so there cannot be a reentrancy attack during the approval and revocation
        debtToken_.approve(address(cooler_), type(uint256).max);

        // Iterate through and repay loans
        for (uint256 i; i < numLoans_; i++) {
            Cooler.Loan memory loan = cooler_.getLoan(i);

            // Only repay outstanding loans
            if (loan.principal > 0) {
                uint256 amount = loan.principal + loan.interestDue;

                repaid += amount;
                collateral += loan.collateral;

                cooler_.repayLoan(i, amount);
            }
        }

        // Revoke approval
        debtToken_.approve(address(cooler_), 0);
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
            address debtToken,
            uint256 numLoans
        )
    {
        // Determine the debt token
        debtToken = address(cooler_.debt());

        // The Cooler contract does not expose the number of loans, so we iterate until the call reverts
        uint256 i;
        while (true) {
            try cooler_.loans(i) returns (
                Cooler.Request memory,
                uint256 principal,
                uint256 interestDue,
                uint256,
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

        return (coolerPrincipal, coolerInterest, debtToken, i);
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
