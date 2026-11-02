// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @notice Shared action admission, version/lifecycle support and time-bound user authentication.
/// @dev State-changing public callers are checked against Core's authorization registry. Core trusts
///      these checks when settling and never authenticates the forwarded borrower a second time.
///      The base owns no custody or position state. Local guards enforce pauses at public entry.
abstract contract BaseBurnerLoansAction is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IBurnerLoansCoreBound,
    IVersioned
{
    /// @dev Permanent accounting and custody Core shared by this action.
    IBurnerLoansCore internal immutable _CORE;
    /// @dev Capability granted by governance for this action's typed Core settlement methods.
    bytes32 internal immutable _ACTION_ROLE;

    /// @notice Binds deployment dependencies and initializes the local contract state.
    /// @dev Reverts if:
    ///      - Core does not advertise IBurnerLoansCore, IEnabler and IOperatorAuth through ERC165.
    ///      - Core reports a Kernel different from this action’s Kernel.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    /// @param role_ Governance role required for this operation.
    constructor(
        Kernel kernel_,
        IBurnerLoansCore core_,
        bytes32 role_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        bytes4[] memory interfaces = new bytes4[](3);
        interfaces[0] = type(IBurnerLoansCore).interfaceId;
        interfaces[1] = type(IEnabler).interfaceId;
        interfaces[2] = type(IOperatorAuth).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(address(core_), interfaces))
            revert BurnerLoansAction_InvalidCore(address(core_));
        _requireCoreSameKernel(core_);
        _CORE = core_;
        _ACTION_ROLE = role_;
    }

    /// @inheritdoc IBurnerLoansCoreBound
    function core() public view override returns (address) {
        return address(_CORE);
    }

    /// @notice Restricts the caller before executing the guarded operation.
    /// @dev Reverts if:
    ///      - This action or Core is inactive.
    ///      - This action or Core is disabled.
    modifier onlyOperational() {
        _requireOperational();
        _;
    }

    /// @notice Requires active and enabled action/Core lifecycle state.
    /// @dev Reverts if:
    ///      - Core or the calling action is inactive in the required Kernel.
    ///      - This contract or a required dependency is disabled.
    ///      Reads without state changes; errors from dependency views propagate.
    function _requireOperational() internal view {
        // Subject admission precedes dependency checks so a local pause or Kernel removal reports
        // this action first. Core is checked again on each call because either policy can drift later.
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
        _requireEnabled();
        // This action's Kernel is the local pointer already used for membership; no self-call is needed.
        _requireCoreOperational();
    }

    /// @notice Validates the position owner independently of quote or execution caller authority.
    /// @dev Reverts if:
    ///      - The borrower is zero (BurnerLoans_ZeroAddress).
    ///
    /// @param onBehalfOf_ Nonzero borrower whose canonical position is queried or changed.
    function _validateBorrower(address onBehalfOf_) internal pure {
        if (onBehalfOf_ == address(0)) revert IBurnerLoansErrors.BurnerLoans_ZeroAddress();
    }

    /// @notice Authenticates the actual public caller for a borrower.
    /// @dev Reverts if:
    ///      - The borrower is zero.
    ///      - The actual caller is neither the borrower nor a currently authorized operator.
    /// @param borrower_ Account whose canonical position is queried or changed.
    function _authorizeBorrower(address borrower_) internal view {
        // Grants are stored by Core for all actions. Forward the actual caller, never tx.origin or
        // a keeper/recipient supplied as a parameter, so delegated borrower authority stays consistent.
        _validateBorrower(borrower_);
        if (!IOperatorAuth(address(_CORE)).isSenderAuthorized(msg.sender, borrower_))
            revert IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf();
    }

    /// @notice Resolves this policy's declared Kernel module dependencies.
    /// @dev Reverts if:
    ///      - A declared module is missing.
    ///
    /// @dev Resolves the declared modules through this contract's Kernel; dependency errors propagate.
    ///
    /// @return dependencies Kernel keycodes required by this policy.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
    }

    /// @notice Declares the module selectors requested on Kernel activation.
    /// @dev Declares only the listed module selectors; no dynamic permissions or token approvals.
    /// @return Permissions[] Exact module selector permissions required by this policy.
    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - The unused lifecycle payload is nonempty.
    ///      - Activation dependencies or the settlement role fail validation.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
        _validateActivation();
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - The unused lifecycle payload is nonempty.
    ///      Own Kernel inactivity and unavailable dependencies do not prevent a local pause.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Rechecks the grace window and all current admission dependencies.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateActivation();
    }

    /// @notice Checks the inclusive grace deadline using checked uint48 narrowing.
    /// @dev Reverts if:
    ///      - The widened deadline cannot be represented as uint48.
    ///      - The current timestamp is strictly after that deadline.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @notice Restricts fast re-enablement to ADMIN or the Burner Loans admin role.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    function _authorizeReEnable() internal view override {
        if (!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE))
            revert NotAuthorised();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
        super.setGracePeriod(period_);
    }

    /// @dev Own activity and local enablement precede governance authorization.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @notice Validates the current activation graph and settlement role.
    /// @dev Reverts if:
    ///      - Core reports another Kernel.
    ///      - The action or Core is inactive.
    ///      - Core is disabled.
    ///      - The action lacks its settlement role.
    function _validateActivation() internal view virtual {
        _requireCoreSameKernel(_CORE);
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
        _requireCoreOperational();
        _requireRole(address(this), _ACTION_ROLE);
    }

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @notice Advertises the shared binding and inherited lifecycle interfaces.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param id_ Canonical interface or position identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(
        bytes4 id_
    ) public view virtual override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            id_ == type(IBurnerLoansCoreBound).interfaceId ||
            id_ == type(IVersioned).interfaceId ||
            super.supportsInterface(id_);
    }

    /// @notice Requires the Core service used by actions and executable quotes.
    /// @dev Reverts if:
    ///      - Core reports another Kernel.
    ///      - Core is inactive or disabled in this action's Kernel.
    function _requireCoreOperational() internal view {
        PolicyDependency.requireActiveAndEnabled(address(_CORE), address(kernel));
    }

    /// @notice Requires a Core to report this action's Kernel.
    /// @dev Migration leaves old membership entries intact, so activity cannot establish binding.
    ///      Reverts if:
    ///      - The Core reports a different Kernel (PolicyDependency_KernelMismatch).
    /// @param core_ Core whose current Kernel binding is checked.
    function _requireCoreSameKernel(IBurnerLoansCore core_) private view {
        PolicyDependency.requireSameKernel(address(core_), address(kernel));
    }

    /// @notice Applies action and Core settlement admission to a read-only operation quote.
    /// @dev Core remains the authority for execution; previews cannot call a mutating settlement.
    ///      Reverts if:
    ///      - The subject or Core is unavailable.
    ///      - This action has lost its settlement authority.
    function _requirePreviewOperational() internal view {
        _requireOperational();
        // Execution reaches Core's onlyAction role check; a read-only preview cannot enter settlement,
        // so reproduce that admission here before advertising an executable quote.
        _requireRole(address(this), _ACTION_ROLE);
    }

    /// @notice Requires the independently operated funding/default ledger used by Debt and Seize.
    /// @dev _requireOperational separately checks Core's Kernel and lifecycle.
    ///      Reverts if:
    ///      - Inventory is inactive, disabled or reports another Kernel.
    function _requireInventoryOperational() internal view {
        PolicyDependency.requireActiveAndEnabled(_CORE.inventory(), address(kernel));
    }

    /// @notice Requires the selected payout service for an operation that creates a payout obligation.
    /// @dev _requireOperational separately checks Core's Kernel and lifecycle.
    ///      Reverts if:
    ///      - Payout is inactive, paused or reports another Kernel.
    function _requirePayoutOperational() internal view {
        PolicyDependency.requireActiveAndEnabled(_CORE.payout(), address(kernel));
    }
}
