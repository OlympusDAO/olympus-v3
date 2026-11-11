// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_INVENTORY_PROVIDER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title Burner Loans Inventory
/// @notice Custodies protocol-supplied OHM and funds one authenticated fixed-term loan facility.
/// @dev Burner Loans Inventory deliberately does not read FLOAN. Its active-principal ledger changes only
///      through atomic deltas submitted by the immutable Core address. The immutable OHM
///      dependency is assumed to be a standard, non-fee-on-transfer token.
contract BurnerLoansInventory is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ReentrancyGuardTransient,
    ConfigOperatorSingleStep,
    IBurnerLoansInventory,
    IBurnerLoansCoreBound,
    IVersioned
{
    using SafeERC20 for ERC20;

    /// @notice OHM token funded and custodied by Burner Loans Inventory.
    IERC20 internal immutable _OHM;

    /// @notice Minter module used to mint, burn, and manage approval.
    MINTRv1 internal _MINTR;

    /// @notice Treasury module that receives rescued surplus.
    TRSRYv1 internal _TRSRY;

    /// @notice Immutable Burner Loans policy authorized to change principal accounting.
    address internal immutable _CORE;

    /// @notice Maximum active OHM principal funded by Burner Loans Inventory.
    uint128 internal _globalDebtCapOhm;

    /// @notice Aggregate principal currently outstanding.
    uint128 internal _activePrincipalOhm;

    /// @notice Supplied OHM held by Burner Loans Inventory and available for funding or withdrawal.
    uint128 internal _suppliedIdleOhm;

    /// @notice All providers' aggregate outstanding claim on supplied OHM.
    uint128 internal _suppliedOhm;

    /// @notice Outstanding supplied-OHM claim belonging to each authorized provider.
    mapping(address provider => uint128 claimOhm) internal _providerClaimOhm;

    /// @notice Constructs Burner Loans Inventory for one immutable Burner Loans Core.
    /// @dev Reverts if:
    ///      - OHM is zero.
    ///      - Core is zero, lacks IBurnerLoansCore, reports another Kernel or has unreadable Kernel metadata.
    /// @dev Core validates Inventory compatibility and readiness when selecting and activating it.
    /// @param kernel_ Kernel providing Inventory modules and governance roles.
    /// @param ohm_ OHM token funded by Burner Loans Inventory and burned through MINTR.
    /// @param core_ Permanent Core authorized to draw OHM and report principal changes.
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        address core_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        if (address(ohm_) == address(0)) revert BurnerLoansInventory_ZeroAddress();
        if (core_ == address(0)) revert BurnerLoansInventory_InvalidCore(core_);
        _validateCore(core_);
        _OHM = ohm_;
        _CORE = core_;
    }

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    modifier onlyActive() {
        _requireOwnActive();
        _;
    }

    /// @dev Reverts if:
    ///      - Core is executing a guarded settlement.
    ///
    /// @dev The Core settlement guard is checked before local lifecycle and authorization.
    modifier whenCoreNotSettling() {
        IBurnerLoansCore(_CORE).requireNotReentrant();
        _;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - A declared module is missing.
    ///      - A declared module has an incompatible version.
    ///
    /// @dev Resolves the declared modules through this contract's Kernel; dependency errors propagate.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");
        dependencies[2] = toKeycode("TRSRY");

        MINTRv1 priorMintr = _MINTR;
        _MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        _TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));

        // MINTR compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 mintrMajor, ) = _MINTR.VERSION();
        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = ROLES.VERSION();
        // TRSRY compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 trsryMajor, ) = _TRSRY.VERSION();
        if (mintrMajor != 1 || rolesMajor != 1 || trsryMajor != 1) {
            revert BurnerLoansInventory_InvalidModuleVersion();
        }
        address mintrOhm = address(_MINTR.ohm());
        if (mintrOhm != address(_OHM)) {
            revert BurnerLoansInventory_InvalidOhm(address(_OHM), mintrOhm);
        }

        // MINTR burns repayment OHM through `OHM.burnFrom(BurnerLoansInventory, amount)`, so it
        // needs a standing token allowance. A MINTR upgrade first revokes the obsolete module's
        // allowance, then grants the current module the burn allowance. Mint approval is separate
        // MINTR accounting and is reconciled to the global-cap-derived target below.
        ERC20 token = ERC20(address(_OHM));
        if (address(priorMintr) != address(0) && address(priorMintr) != address(_MINTR)) {
            token.forceApprove(address(priorMintr), 0);
        }
        token.forceApprove(address(_MINTR), type(uint256).max);
        if (address(priorMintr) != address(0) && address(priorMintr) != address(_MINTR)) {
            _restoreApproval(_globalDebtCapOhm);
        }
    }

    /// @inheritdoc Policy
    /// @dev Declares only the listed module selectors; no dynamic permissions or token approvals.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode mintr = toKeycode("MINTR");
        requests = new Permissions[](4);
        requests[0] = Permissions({keycode: mintr, funcSelector: MINTRv1.mintOhm.selector});
        requests[1] = Permissions({keycode: mintr, funcSelector: MINTRv1.burnOhm.selector});
        requests[2] = Permissions({
            keycode: mintr,
            funcSelector: MINTRv1.increaseMintApproval.selector
        });
        requests[3] = Permissions({
            keycode: mintr,
            funcSelector: MINTRv1.decreaseMintApproval.selector
        });
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - Inventory is locally disabled, or the caller lacks ADMIN.
    ///      - The cap is below active principal or MINTR rejects approval reconciliation.
    ///      - Another Inventory operation is executing.
    ///      Core settlement must be idle before local lifecycle and authorization checks.
    function setGlobalDebtCap(
        uint128 capOhm_
    ) external nonReentrant whenCoreNotSettling onlyActive givenEnabled onlyAdminRole {
        if (capOhm_ < _activePrincipalOhm) {
            revert BurnerLoansInventory_InvalidCap(capOhm_, _activePrincipalOhm);
        }
        bool changed = _globalDebtCapOhm != capOhm_;
        if (changed) _globalDebtCapOhm = capOhm_;
        // Reconcile even when the cap is unchanged: MINTR approval may have drifted independently.
        // Only an actual cap change emits the cap event; provider accounting is untouched either way.
        _syncMintApproval();
        if (changed) emit GlobalDebtCapSet(capOhm_);
    }

    /// @inheritdoc IConfigOperator
    /// @dev Reverts if:
    ///      - Inventory or Core is executing a guarded operation.
    ///      - Inventory is Kernel-inactive.
    ///      - The caller lacks ADMIN.
    ///      - The selected operator is unchanged (ConfigOperator_Unchanged).
    ///
    /// @dev ADMIN may rotate the independent recovery operator while Inventory is locally paused.
    function setConfigOperator(address operator_) public override nonReentrant whenCoreNotSettling {
        super.setConfigOperator(operator_);
    }

    /// @inheritdoc ConfigOperatorSingleStep
    /// @dev The public setter applies both settlement guards before own activity and ADMIN admission.
    function _authorizeSetConfigOperator()
        internal
        view
        override
        onlyActive
        onlyAdminRole
        returns (bool)
    {
        return true;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - Another guarded Inventory operation is executing.
    ///      - Inventory is Kernel-inactive.
    ///      - Inventory is locally disabled.
    ///      - The caller lacks the provider role.
    ///      - The amount is zero.
    ///      - A provider, idle or aggregate sum does not fit uint128 (SafeCast error).
    ///      - The OHM transfer fails or delivers an inexact amount.
    ///      - MINTR approval reduction fails.
    function supply(uint128 amount_) external nonReentrant onlyActive givenEnabled {
        _requireRole(msg.sender, BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        // Provider claims include both idle and lent OHM. Only the idle portion can be withdrawn;
        // the exact transfer below must succeed or every claim and aggregate update rolls back.
        _providerClaimOhm[msg.sender] = SafeCast.toUint128(
            uint256(_providerClaimOhm[msg.sender]) + amount_
        );
        _suppliedIdleOhm = SafeCast.toUint128(uint256(_suppliedIdleOhm) + amount_);
        _suppliedOhm = SafeCast.toUint128(uint256(_suppliedOhm) + amount_);
        SafeERC20Exact.safeTransferFromExact(
            ERC20(address(_OHM)),
            msg.sender,
            address(this),
            amount_
        );
        _reduceUnsafeApproval();
        emit OhmSupplied(msg.sender, amount_, _providerClaimOhm[msg.sender], _suppliedOhm);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - Inventory is locally disabled or the caller lacks the provider role.
    ///      - The amount is zero or the recipient is zero.
    ///      - The amount exceeds the caller’s claim or available supplied idle OHM.
    ///      - The transfer or strict approval reduction fails.
    ///      - Another guarded Inventory operation is executing.
    function withdraw(
        uint128 amount_,
        address recipient_
    ) external nonReentrant onlyActive givenEnabled {
        _requireRole(msg.sender, BURNER_LOANS_INVENTORY_PROVIDER_ROLE);
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        if (recipient_ == address(0)) revert BurnerLoansInventory_ZeroAddress();
        uint128 providerClaim = _providerClaimOhm[msg.sender];
        if (amount_ > providerClaim) {
            revert BurnerLoansInventory_InsufficientClaim(amount_, providerClaim);
        }
        if (amount_ > _suppliedIdleOhm) {
            revert BurnerLoansInventory_InsufficientIdle(amount_, _suppliedIdleOhm);
        }
        _providerClaimOhm[msg.sender] = providerClaim - amount_;
        _suppliedOhm -= amount_;
        _suppliedIdleOhm -= amount_;
        _restoreApproval(amount_);
        ERC20(address(_OHM)).safeTransfer(recipient_, amount_);
        emit OhmWithdrawn(msg.sender, amount_, _providerClaimOhm[msg.sender], _suppliedOhm);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - Inventory is locally disabled or the caller is not the immutable Core.
    ///      - The amount or recipient is zero.
    ///      - The amount exceeds available funding capacity.
    ///      - MINTR minting or the OHM transfer fails.
    ///      - Another guarded Inventory operation is executing.
    function draw(
        address recipient_,
        uint128 amount_
    ) external nonReentrant onlyActive givenEnabled {
        _onlyFacility();
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        if (recipient_ == address(0)) revert BurnerLoansInventory_ZeroAddress();
        uint256 capacity = availableCapacity();
        if (amount_ > capacity) {
            revert BurnerLoansInventory_InsufficientCapacity(amount_, capacity);
        }

        _activePrincipalOhm += amount_;
        // Spend provider liquidity first and mint only the shortfall. Lending idle OHM reduces its
        // withdrawable balance but preserves the provider's claim until repayment replenishes it.
        uint128 suppliedAmount = amount_ < _suppliedIdleOhm ? amount_ : _suppliedIdleOhm;
        _suppliedIdleOhm -= suppliedAmount;
        uint128 mintedAmount = amount_ - suppliedAmount;
        if (mintedAmount != 0) _MINTR.mintOhm(address(this), mintedAmount);
        ERC20(address(_OHM)).safeTransfer(recipient_, amount_);
        emit OhmDrawn(recipient_, amount_, suppliedAmount, mintedAmount);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - Inventory is locally disabled or the caller is not the immutable Core.
    ///      - The amount is zero, exceeds active principal or lacks received OHM backing.
    ///      - Required MINTR approval reduction fails; a failed burn itself is caught.
    ///      - Another guarded Inventory operation is executing.
    ///      Core pulls from the payer directly to Inventory under Core's guard, using the payer's
    ///      Core allowance. Pulling from Core here would add a second transfer and allowance.
    function settleRepayment(uint128 amount_) external nonReentrant onlyActive givenEnabled {
        _onlyFacility();
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        uint256 requiredBalance = uint256(_suppliedIdleOhm) + amount_;
        uint256 balance = _OHM.balanceOf(address(this));
        if (balance < requiredBalance) {
            revert BurnerLoansInventory_InsufficientBalance(requiredBalance, balance);
        }

        _decreaseActivePrincipal(amount_);
        // Principal can exceed the aggregate supplied claim because Burner Loans Inventory may
        // have funded the loan with minted OHM. Retain only the claim deficit and burn the excess.
        uint128 deficit = _suppliedOhm - _suppliedIdleOhm;
        uint128 retained = amount_ < deficit ? amount_ : deficit;
        _suppliedIdleOhm += retained;
        uint128 burnAmount = amount_ - retained;
        uint128 burned;
        if (burnAmount != 0) {
            try _MINTR.burnOhm(address(this), burnAmount) {
                burned = burnAmount;
                _restoreApproval(burnAmount);
            } catch (bytes memory failureData) {
                // A failed burn must not undo a valid borrower repayment. The excess remains surplus;
                // mint approval is restored only after a successful burn, or by explicit synchronization.
                emit OhmBurnFailed(burnAmount, failureData);
            }
        }
        emit RepaymentSettled(amount_, retained, burned);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - Inventory is locally disabled or the caller is not the immutable Core.
    ///      - The amount is zero or exceeds active principal.
    ///      - Strict MINTR approval reduction fails; restoration increases are fail-soft.
    ///      - Another guarded Inventory operation is executing.
    function settleDefault(uint128 amount_) external nonReentrant onlyActive givenEnabled {
        _onlyFacility();
        if (amount_ == 0) revert BurnerLoansInventory_ZeroAmount();
        // Default releases debt-cap room without receiving repayment tokens. Provider claims remain
        // outstanding; _restoreApproval is best-effort so approval failure cannot block default closure.
        _decreaseActivePrincipal(amount_);
        _restoreApproval(amount_);
        emit PrincipalDefaulted(amount_);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - This contract is locally disabled or Kernel-inactive.
    ///      - The caller lacks the Burner Loans admin role or MINTR reconciliation fails.
    ///      - Another guarded operation is executing.
    function syncMintApproval()
        external
        nonReentrant
        onlyActive
        givenEnabled
        returns (uint256 approval_)
    {
        _requireRole(msg.sender, BURNER_LOANS_ADMIN_ROLE);
        approval_ = _syncMintApproval();
        emit MintApprovalSynchronized(approval_);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - This contract is locally disabled or Kernel-inactive.
    ///      - The caller is neither the nonzero selected config operator nor governance ADMIN.
    ///      - Another guarded operation is executing.
    ///      Retries repayment burns that were caught as failures. Supplied idle remains protected;
    ///      unlike rescueSurplus, a successful burn reduces OHM supply. Approval sync is separate.
    function burnSurplus() external nonReentrant whenCoreNotSettling onlyActive givenEnabled {
        _requireConfigOperatorOrAdmin();

        uint256 surplus = surplusOhm();
        if (surplus == 0) return;
        _MINTR.burnOhm(address(this), surplus);
        emit SurplusBurned(surplus);
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reverts if:
    ///      - This contract is Kernel-inactive; local disablement does not prevent recovery.
    ///      - The caller is neither the nonzero selected config operator nor governance ADMIN.
    ///      - Another guarded operation is executing.
    function rescueSurplus() external nonReentrant whenCoreNotSettling onlyActive {
        _requireConfigOperatorOrAdmin();

        uint256 surplus = surplusOhm();
        if (surplus == 0) return;
        ERC20(address(_OHM)).safeTransfer(address(_TRSRY), surplus);
        emit SurplusRescued(surplus);
    }

    /// @dev Reverts if:
    ///      - The caller is neither the stored nonzero config operator nor governance ADMIN (NotAuthorised).
    ///
    /// @dev Controller contracts are not queried.
    function _requireConfigOperatorOrAdmin() private view {
        _requireAuthorized(!_isConfigOperator(msg.sender) && !_isAdmin(msg.sender));
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function ohm() external view returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoansCoreBound
    /// @dev Returns the stored binding without probing Core or its lifecycle.
    function core() external view override returns (address) {
        return _CORE;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function globalDebtCapOhm() external view returns (uint128) {
        return _globalDebtCapOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function activePrincipalOhm() external view returns (uint128) {
        return _activePrincipalOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function suppliedIdleOhm() external view returns (uint128) {
        return _suppliedIdleOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function suppliedOhm() external view returns (uint128) {
        return _suppliedOhm;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function providerClaimOhm(address provider_) external view returns (uint128) {
        return _providerClaimOhm[provider_];
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function desiredMintApproval() public view returns (uint256) {
        // Debt already occupies cap room, and idle provider OHM can fund the next loans without
        // minting. Approval should cover only the remaining unfunded room, in native OHM units.
        uint256 committed = uint256(_activePrincipalOhm) + _suppliedIdleOhm;
        return _globalDebtCapOhm > committed ? _globalDebtCapOhm - committed : 0;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function availableCapacity() public view returns (uint256) {
        uint256 capRoom = _globalDebtCapOhm - _activePrincipalOhm;
        uint256 idle = _suppliedIdleOhm;
        if (idle >= capRoom) return capRoom;

        // Use MINTR's actual approval rather than its desired target: a failed restoration or an
        // external approval reduction must reduce quoted capacity before another draw is accepted.
        uint256 approval = _MINTR.mintApproval(address(this));
        uint256 requiredApproval = capRoom - idle;
        return approval < requiredApproval ? idle + approval : capRoom;
    }

    /// @inheritdoc IBurnerLoansInventory
    /// @dev Reads without state changes; errors from dependency views propagate.
    function surplusOhm() public view returns (uint256) {
        uint256 balance = _OHM.balanceOf(address(this));
        uint256 idle = _suppliedIdleOhm;
        return balance > idle ? balance - idle : 0;
    }

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc EnablerV2
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansInventory).interfaceId ||
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @dev Reverts if:
    ///      - The caller is not the immutable Core.
    function _onlyFacility() internal view {
        if (msg.sender != _CORE) revert NotAuthorised();
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    function _authorizeReEnable() internal view override {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override onlyActive {
        super.setGracePeriod(period_);
    }

    /// @dev The public setter applies activity and local enablement before authorization.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @dev Checks Inventory settlement safety and own Kernel activity before enablement.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _validateActivation();
    }

    /// @dev Preserves the grace-period gate and repeats the activation checks.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _validateActivation();
    }

    /// @dev Reverts if:
    ///      - Inventory is busy or Kernel-inactive.
    ///      - Core lacks its required interface or reports another Kernel.
    ///      Core activity and enablement do not gate Inventory activation.
    function _validateActivation() private view {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();

        _requireOwnActive();
        _validateCore(_CORE);
    }

    /// @dev Configuration and surplus recovery call Core.requireNotReentrant().
    function _validateCore(address core_) private view {
        if (!ERC165Checker.supportsInterface(core_, type(IBurnerLoansCore).interfaceId))
            revert BurnerLoansInventory_InvalidCore(core_);
        PolicyDependency.requireSameKernel(core_, address(kernel));
    }

    /// @dev Reverts if:
    ///      - This Inventory policy is inactive in its Kernel.
    function _requireOwnActive() internal view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @dev Reverts if:
    ///      - `amount_` exceeds active principal; otherwise decrements it exactly.
    /// @param amount_ Token amount in the operation's documented token units.
    function _decreaseActivePrincipal(uint128 amount_) internal {
        uint128 activePrincipal = _activePrincipalOhm;
        if (amount_ > activePrincipal) {
            revert BurnerLoansInventory_ExcessivePrincipal(amount_, activePrincipal);
        }
        _activePrincipalOhm = activePrincipal - amount_;
    }

    /// @dev Reduces unsafe over-approval.
    function _reduceUnsafeApproval() internal {
        uint256 desired = desiredMintApproval();
        uint256 current = _MINTR.mintApproval(address(this));
        if (current > desired) _MINTR.decreaseMintApproval(address(this), current - desired);
    }

    /// @dev Best-effort restores capacity. A failed restoration requires an admin sync.
    /// @param amount_ Token amount in the operation's documented token units.
    function _restoreApproval(uint128 amount_) internal {
        if (amount_ == 0) return;
        uint256 current = _MINTR.mintApproval(address(this));
        uint256 desired = desiredMintApproval();
        if (current > desired) {
            _MINTR.decreaseMintApproval(address(this), current - desired);
            return;
        }
        uint256 gap = desired > current ? desired - current : 0;
        uint256 restorable = amount_ < gap ? amount_ : gap;
        if (restorable == 0) return;
        try _MINTR.increaseMintApproval(address(this), restorable) {} catch (
            bytes memory failureData
        ) {
            emit ApprovalRestorationFailed(restorable, failureData);
        }
    }

    /// @dev Strictly reconciles MINTR approval to the current cap-derived target.
    /// @return approval_ Current MINTR mint approval in OHM units.
    function _syncMintApproval() internal returns (uint256 approval_) {
        approval_ = _MINTR.mintApproval(address(this));
        uint256 desired = desiredMintApproval();
        if (approval_ > desired) {
            _MINTR.decreaseMintApproval(address(this), approval_ - desired);
            return desired;
        }
        if (approval_ < desired) {
            _MINTR.increaseMintApproval(address(this), desired - approval_);
            return desired;
        }
    }

    /// @notice Rejects unused lifecycle payloads without requiring Core readiness.
    /// @dev Reverts if:
    ///      - Data is nonempty or Inventory is executing a token operation.
    function _beforeDisable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
    }

    /// @notice Checks the widened product-local grace deadline.
    /// @dev Reverts if:
    ///      - There is uint48 overflow or expiry; shared ReEnabler remains unchanged.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }
}
