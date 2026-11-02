// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {LoanPayouts} from "src/policies/burnerloans/libraries/LoanPayouts.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Kernel, Keycode, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @notice	Custodies received fees and seizure proceeds and tracks unpaid payout obligations.
/// @dev	Only the immutable Core may credit receipts. Routing, retries and recovery remain local
///      after Core selects a replacement Payout; failed optional transfers retain their reserves.
contract BurnerLoansPayout is
    Policy,
    PolicyEnablerV2,
    ConfigOperatorSingleStep,
    IBurnerLoansPayout,
    ReentrancyGuard,
    IBurnerLoansCoreBound,
    IVersioned
{
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @notice	Immutable authority that credits receipts and guards in-flight settlements.
    IBurnerLoansCore internal immutable _CORE;
    /// @notice	Selected optional RevenueDistributor for fee and direct-yield routing.
    address public override revenueDistributor;
    /// @notice	Whether fees route to RevenueDistributor rather than the current Treasury.
    bool public override sendFeesToDistributor;
    /// @notice	Whether DepositManager sends claimed yield directly to RevenueDistributor.
    bool public override sendYieldToDistributor;
    /// @notice	Pending fee, seized-collateral and keeper obligations with their token/recipient indexes.
    LoanPayouts.State internal _payouts;

    /// @notice	Creates payout custody and routing bound to Core's Kernel.
    /// @dev	Reverts if:
    ///      - The already-deployed Core lacks its interface or reports another Kernel.
    /// @param	kernel_	Kernel providing Treasury and governance roles.
    /// @param	core_	Permanent Core allowed to credit received fees and liquidation proceeds.
    constructor(Kernel kernel_, address core_) Policy(kernel_) {
        if (!ERC165Checker.supportsInterface(core_, type(IBurnerLoansCore).interfaceId))
            revert IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(core_);
        PolicyDependency.requireSameKernel(core_, address(kernel_));
        _CORE = IBurnerLoansCore(core_);
    }

    /// @inheritdoc	IBurnerLoansCoreBound
    /// @dev	Returns the immutable Core binding without external calls; does not revert.
    function core() public view override returns (address) {
        return address(_CORE);
    }

    /// @notice	Restricts receipt credits to Core on an active, enabled Payout.
    /// @dev Reverts if:
    ///      - Payout is Kernel-inactive.
    ///      - Payout is locally disabled.
    ///      - The caller is not the immutable Core (NotAuthorised).
    ///
    /// @dev Core's activity and enablement are not queried.
    modifier onlyCore() {
        _requireActive();
        _requireEnabled();
        if (msg.sender != address(_CORE)) revert NotAuthorised();
        _;
    }

    // Receipt-before-credit belongs to Core; direct recovery must wait until that settlement ends.
    /// @notice	Requires Core to be outside any guarded settlement.
    /// @dev Reverts if:
    ///      - Core is executing a guarded settlement (ReentrancyGuardReentrantCall).
    ///
    /// @dev Protects funds received before Core credits their payout reserves.
    modifier whenCoreNotSettling() {
        _CORE.requireNotReentrant();
        _;
    }

    /// @notice	Requires the selected config operator or governance ADMIN.
    /// @dev Reverts if:
    ///      - The caller is neither the selected config operator nor a Kernel ADMIN.
    ///
    /// @dev The operator's lifecycle is not queried.
    modifier onlyConfigOrAdmin() {
        _requireConfigOrAdmin();
        _;
    }

    /// @notice	Requires the locally selected controller address or governance ADMIN.
    /// @dev Reverts if:
    ///      - Payout is Kernel-inactive.
    ///      - The caller is neither configOperator nor ADMIN.
    ///      - A required ROLES read fails.
    function _requireConfigOrAdmin() private view {
        _requireActive();
        if (!_isConfigOperator(msg.sender) && !_isAdmin(msg.sender)) revert NotAuthorised();
    }

    /// @inheritdoc	Policy
    /// @dev Reverts if:
    ///      - ROLES or TRSRY is missing.
    ///      - The ROLES major version is not one.
    ///
    /// @dev Resolves ROLES and TRSRY; Kernel refreshes active policies on module upgrades.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TRSRY");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        // Only the module major version determines compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 major, ) = ROLES.VERSION();
        if (major != 1) revert Policy_WrongModuleVersion(abi.encode([uint8(1)]));
        getModuleAddress(dependencies[1]);
    }

    /// @inheritdoc	IConfigOperator
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - The caller lacks ADMIN.
    ///      - The selected operator is unchanged (ConfigOperator_Unchanged).
    ///
    /// @dev Zero revokes delegated authority. Rotation remains available while locally paused or replaced.
    function setConfigOperator(address operator_) public override nonReentrant whenCoreNotSettling {
        super.setConfigOperator(operator_);
    }

    /// @inheritdoc	ConfigOperatorSingleStep
    /// @dev Reverts if:
    ///      - Payout is Kernel-inactive.
    ///      - The caller lacks ADMIN (ROLES_RequireRole).
    ///      - A required ROLES read fails.
    function _authorizeSetConfigOperator() internal view override returns (bool) {
        _requireActive();
        _requireRole(msg.sender, ADMIN_ROLE);
        return true;
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - The TRSRY module is not installed.
    ///
    /// @dev Returns the current TRSRY module address from this Payout's Kernel.
    function treasury() public view override returns (address) {
        return getModuleAddress(toKeycode("TRSRY"));
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - The caller lacks ADMIN.
    ///      - The distributor pointer is unchanged.
    ///      - A nonzero candidate lacks IRevenueDistributor support.
    ///      - The candidate reports another Kernel.
    ///      - Required candidate lifecycle metadata is malformed.
    ///      - The compatible candidate is inactive or disabled.
    ///      - Either routing flag is true when clearing the distributor.
    ///
    /// @dev ADMIN may replace or clear the distributor while Payout is locally paused or replaced.
    function setRevenueDistributor(
        // Zero clears the distributor only after both routing flags are disabled.
        // forge-lint: disable-next-line(missing-zero-check)
        address distributor_
    ) external override nonReentrant whenCoreNotSettling {
        _requireActive();
        _requireRole(msg.sender, ADMIN_ROLE);
        if (distributor_ == revenueDistributor)
            revert IBurnerLoansErrors.BurnerLoans_UnchangedAddress(distributor_);
        if (distributor_ == address(0)) {
            if (sendFeesToDistributor || sendYieldToDistributor)
                revert BurnerLoans_RevenueDistributorRequired();
        } else validateRevenueDistributor(distributor_);
        revenueDistributor = distributor_;
        emit RevenueDistributorSet(distributor_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - The candidate is zero or lacks IRevenueDistributor support.
    ///      - The candidate reports another Kernel.
    ///      - Required Kernel or enabled-state metadata is malformed.
    ///      - The compatible candidate is inactive or disabled.
    function validateRevenueDistributor(address distributor_) public view override {
        if (distributor_ == address(0)) revert BurnerLoans_RevenueDistributorRequired();
        if (!ERC165Checker.supportsInterface(distributor_, type(IRevenueDistributor).interfaceId))
            revert BurnerLoans_InvalidRevenueDistributor(distributor_);
        PolicyDependency.requireActiveAndEnabled(distributor_, address(kernel));
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - The caller is neither configOperator nor ADMIN.
    ///      - The flag is being enabled and distributor validation fails.
    ///
    /// @dev The selected config operator or ADMIN may update the flag while Payout is locally paused or replaced.
    ///      Enabled requests revalidate the current distributor before the unchanged-value return.
    function setSendFeesToDistributor(
        bool enabled_
    ) external override nonReentrant whenCoreNotSettling onlyConfigOrAdmin {
        if (enabled_) validateRevenueDistributor(revenueDistributor);
        if (sendFeesToDistributor == enabled_) return;
        sendFeesToDistributor = enabled_;
        emit SendFeesToDistributorSet(enabled_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - The caller is neither configOperator nor ADMIN.
    ///      - The flag is being enabled and distributor validation fails.
    ///
    /// @dev The selected config operator or ADMIN may update the flag while Payout is locally paused or replaced.
    ///      Enabled requests revalidate the current distributor before the unchanged-value return.
    ///      Yield is sent directly by DepositManager and creates no Payout reserve.
    function setSendYieldToDistributor(
        bool enabled_
    ) external override nonReentrant whenCoreNotSettling onlyConfigOrAdmin {
        if (enabled_) validateRevenueDistributor(revenueDistributor);
        if (sendYieldToDistributor == enabled_) return;
        sendYieldToDistributor = enabled_;
        emit SendYieldToDistributorSet(enabled_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is Kernel-inactive.
    ///      - Payout is locally disabled.
    ///      - A required TRSRY lookup fails.
    function yieldRecipient() external view override returns (address) {
        _requireActive();
        _requireEnabled();
        return sendYieldToDistributor ? revenueDistributor : treasury();
    }

    /// @inheritdoc	IERC165
    /// @dev	Returns this contract's and inherited interface identifiers without external calls; does not revert.
    function supportsInterface(bytes4 interfaceId_) public view override(EnablerV2) returns (bool) {
        return
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IBurnerLoansPayout).interfaceId ||
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice	Checks that held tokens cover existing reserves plus the new receipt.
    /// @dev Reverts if:
    ///      - The reserves-plus-receipt sum overflows.
    ///      - The token balance read fails.
    ///      - The balance is below reserves plus the reported receipt.
    ///
    /// @param	token_	Token whose balance or payout accounting is used.
    /// @param	receipt_	New incoming receipt to reserve, in token units.
    function _requireBacked(address token_, uint256 receipt_) private view {
        uint256 expected = _sumAmounts(_payouts.totalPending[token_], receipt_);
        uint256 balance = IERC20(token_).balanceOf(address(this));
        if (balance < expected)
            revert BurnerLoansPayout_InsufficientBalance(token_, balance, expected);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Payout is Kernel-inactive.
    ///      - Payout is locally disabled.
    ///      - The caller is not the immutable Core.
    ///      - Reserves plus the receipt overflow.
    ///      - Reserves plus the receipt exceed the held token balance.
    ///      - A required token-balance, route or accounting read fails.
    ///
    /// @dev Reserves the receipt before attempting delivery to the current fee route; failed delivery remains pending.
    function creditFee(address token_, uint256 amount_) external nonReentrant onlyCore {
        // Core has already transferred the mandatory receipt. Reserve it before best-effort delivery;
        // LoanPayouts leaves the obligation pending if the destination cannot receive the transfer.
        _requireBacked(token_, amount_);
        LoanPayouts.creditFee(_payouts, token_, _feeRecipient(), amount_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Payout is Kernel-inactive.
    ///      - Payout is locally disabled.
    ///      - The caller is not the immutable Core.
    ///      - Allocation or reserve sums overflow.
    ///      - Reserves plus the combined receipt exceed the held token balance.
    ///      - A required token-balance, route or accounting read fails.
    ///
    /// @dev Reserves the combined receipt before attempting keeper and Treasury delivery.
    ///      Keeper entitlement stays with keeper_; protocol collateral follows the current Treasury.
    ///      Failed optional transfers retain the complete unpaid obligations.
    function creditSeizure(
        address token_,
        address keeper_,
        uint256 reward_,
        uint256 remainder_
    ) external nonReentrant onlyCore {
        // Reward and Treasury allocations share one receipt. Check their combined backing before
        // attempting either payment so an old pending obligation cannot fund a new credit.
        _requireBacked(token_, _sumAmounts(reward_, remainder_));
        LoanPayouts.queueSeizureReward(_payouts, token_, keeper_, reward_);
        LoanPayouts.queueSeizedCollateral(_payouts, token_, treasury(), remainder_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - A required route lookup fails.
    ///      - Payout accounting overflows.
    ///
    /// @dev Permissionless while locally paused or replaced; Core enablement does not gate retries.
    ///      Retries every bucket currently owed to recipient_; failed transfers remain fully reserved.
    function transferPendingPayout(
        address token_,
        address recipient_
    ) external nonReentrant whenCoreNotSettling returns (uint256 transferred) {
        _requireActive();
        // Fees and seized backing follow the current routing addresses; keeper rewards belong to
        // their original keeper. These independent buckets may all resolve to the same recipient.
        // Retries remain available after local pause or Core replacement while this policy stays active.
        if (recipient_ == _feeRecipient())
            transferred += LoanPayouts.transferPendingFee(_payouts, token_, recipient_);
        if (recipient_ == treasury())
            transferred += LoanPayouts.transferPendingSeizedCollateral(
                _payouts,
                token_,
                recipient_
            );
        transferred += LoanPayouts.transferPendingSeizureReward(_payouts, token_, recipient_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - The caller is neither configOperator nor ADMIN.
    ///      - The token has no code.
    ///      - The destination is zero, Core, Payout, token, configOperator or Kernel.
    ///      - A token balance read fails.
    ///      - The strict surplus transfer fails.
    ///
    /// @dev The selected config operator or ADMIN may recover surplus while Payout is locally paused or replaced.
    ///      Pending obligations are not consumed.
    function rescue(
        address token_,
        address destination_
    ) external nonReentrant whenCoreNotSettling onlyConfigOrAdmin {
        _validateCoreDestination(destination_);
        LoanPayouts.rescue(_payouts, token_, destination_, configOperator, address(kernel));
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///      - The caller is neither configOperator nor ADMIN.
    ///      - The token has no code.
    ///      - The destination is zero, Core, Payout, token, configOperator or Kernel.
    ///      - The recipient is zero.
    ///      - The amount is zero or exceeds the combined live entitlement.
    ///      - A required route lookup or entitlement sum fails.
    ///      - The strict transfer fails.
    ///
    /// @dev The selected config operator or ADMIN may redirect an obligation while Payout is locally paused or replaced.
    ///      Reserve and index changes roll back if the transfer fails.
    function rescuePendingPayout(
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external nonReentrant whenCoreNotSettling onlyConfigOrAdmin {
        _validateCoreDestination(destination_);
        LoanPayouts.rescuePendingPayout(
            _payouts,
            token_,
            recipient_,
            destination_,
            amount_,
            _feeRecipient(),
            treasury(),
            configOperator,
            address(kernel)
        );
    }

    /// @notice	Resolves the locally configured fee route.
    /// @dev Reverts if:
    ///      - The Treasury route is selected but TRSRY is not installed.
    ///
    /// @return	address	Locally selected Treasury or RevenueDistributor.
    function _feeRecipient() private view returns (address) {
        return sendFeesToDistributor ? revenueDistributor : treasury();
    }

    /// @notice	Rejects Core as a recovery destination.
    /// @dev Reverts if:
    ///      - The destination is the immutable Core (BurnerLoans_InvalidRescueDestination).
    ///
    /// @param	destination_	Recovery destination.
    function _validateCoreDestination(address destination_) private view {
        if (destination_ == address(_CORE))
            revert IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination(destination_);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is Kernel-inactive.
    ///      - The token has no code.
    ///      - A token balance read fails.
    ///      - The destination is forbidden.
    function previewRescue(address token_, address destination_) external view returns (uint256) {
        _requireActive();
        _validateCoreDestination(destination_);
        return
            LoanPayouts.previewRescue(
                _payouts,
                token_,
                destination_,
                configOperator,
                address(kernel)
            );
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - Payout is Kernel-inactive.
    ///      - The token has no code.
    ///      - The destination is zero, Core, Payout, token, configOperator or Kernel.
    ///      - The recipient is zero.
    ///      - The amount is zero or exceeds the combined live entitlement.
    ///      - A required route lookup or entitlement sum fails.
    ///
    /// @dev Permissionless while locally paused or replaced; caller authorization is not checked.
    function previewRescuePendingPayout(
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external view returns (uint256) {
        _requireActive();
        _validateCoreDestination(destination_);
        return
            LoanPayouts.previewRescuePendingPayout(
                _payouts,
                token_,
                recipient_,
                destination_,
                amount_,
                _feeRecipient(),
                treasury(),
                configOperator,
                address(kernel)
            );
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - A required Treasury lookup fails.
    ///
    /// @dev Available independently of lifecycle.
    function getPendingPayoutRecipients(
        address token_
    ) external view returns (address[] memory result) {
        address[] memory keepers = _payouts.pendingKeeperRecipients[token_].values();
        address feeRecipient = _feeRecipient();
        address treasuryRecipient = treasury();
        bool includeFee = _payouts.pendingFees[token_] != 0 && feeRecipient != address(0);
        bool includeTreasury = _payouts.pendingSeizedCollateral[token_] != 0 &&
            treasuryRecipient != address(0);
        // Present each address once even when a keeper is also the fee destination or Treasury.
        // pendingPayout still sums every entitlement held by that address across the separate buckets.
        for (uint256 i; i < keepers.length; ++i) {
            if (keepers[i] == feeRecipient) includeFee = false;
            if (keepers[i] == treasuryRecipient) includeTreasury = false;
        }
        if (includeFee && feeRecipient == treasuryRecipient) includeTreasury = false;
        result = new address[](keepers.length + (includeFee ? 1 : 0) + (includeTreasury ? 1 : 0));
        uint256 length;
        for (uint256 i; i < keepers.length; ++i) result[length++] = keepers[i];
        if (includeFee) result[length++] = feeRecipient;
        if (includeTreasury) result[length] = treasuryRecipient;
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev Reverts if:
    ///      - A required Treasury lookup fails.
    ///      - The checked entitlement sum overflows.
    ///
    /// @dev Available independently of lifecycle.
    function pendingPayout(address token_, address recipient_) external view returns (uint256) {
        return LoanPayouts.pendingAmount(_payouts, token_, recipient_, _feeRecipient(), treasury());
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev	Returns the tokens with unpaid obligations without external calls; does not revert.
    function getPendingPayoutTokens() external view returns (address[] memory) {
        return LoanPayouts.tokens(_payouts);
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev	Returns fee, seized-collateral and aggregate reserves without external calls; does not revert.
    function payoutReserves(address token_) external view returns (uint256, uint256, uint256) {
        return (
            _payouts.pendingFees[token_],
            _payouts.pendingSeizedCollateral[token_],
            _payouts.totalPending[token_]
        );
    }

    /// @inheritdoc	IBurnerLoansPayout
    /// @dev	Returns keeper addresses with unpaid rewards without external calls; does not revert.
    function getPendingKeepers(address token_) external view returns (address[] memory) {
        return _payouts.pendingKeeperRecipients[token_].values();
    }

    /// @notice	Adds reserve/allocation amounts with an informative overflow error.
    /// @dev Reverts if:
    ///      - The sum exceeds uint256 (BurnerLoansPayout_AmountOverflow).
    ///
    /// @param	existing_	Existing reserve or first allocation, in token units.
    /// @param	additional_	Incoming allocation, in token units.
    /// @return	uint256	Combined amount.
    function _sumAmounts(uint256 existing_, uint256 additional_) private pure returns (uint256) {
        if (additional_ > type(uint256).max - existing_)
            revert BurnerLoansPayout_AmountOverflow(existing_, additional_);
        return existing_ + additional_;
    }

    /// @notice	Requires Kernel membership before business actions, configuration and corresponding quotes.
    /// @dev Reverts if:
    ///      - Payout is inactive in its Kernel (BurnerLoans_PolicyNotActive).
    function _requireActive() private view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @inheritdoc	EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///      - Payout is Kernel-inactive.
    ///
    /// @dev Core is an immutable authority reference; its lifecycle does not gate enablement.
    function _beforeEnable(bytes calldata data_) internal view override {
        _checkTransition(data_);
        _requireActive();
    }

    /// @inheritdoc	EnablerV2
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      - Payout is reentered.
    ///      - Core is settling.
    ///
    /// @dev Own inactivity does not block pausing.
    function _beforeDisable(bytes calldata data_) internal view override {
        _checkTransition(data_);
    }

    /// @notice	Validates the empty lifecycle payload and both settlement guards.
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    ///      - Payout's settlement guard is entered.
    ///      - Core's settlement guard is entered.
    ///
    /// @param	data_	Unused lifecycle data; must be empty.
    function _checkTransition(bytes calldata data_) private view {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
        _CORE.requireNotReentrant();
    }

    /// @inheritdoc	IVersioned
    /// @dev	Returns the implementation version without external calls; does not revert.
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }
}
