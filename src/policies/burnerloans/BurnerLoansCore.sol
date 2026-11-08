// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-5.7.0/utils/structs/EnumerableSet.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {LoanToken} from "src/policies/burnerloans/libraries/LoanToken.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";
import {BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConfigOperatorSingleStep} from "src/policies/utils/ConfigOperatorSingleStep.sol";
import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @notice Permanent custody and complete settlement boundary. Economic algorithms live in replaceable Risk.
/// @dev Governance-admitted first-party actions authenticate the actual public caller, enforce
///      borrower authorization and approve economic rules. Core trusts their forwarded identities
///      and instructions; it does not repeat user authorization or health/maturity checks.
///      Core owns exact incoming receipt checks, transfers and canonical FLOAN settlement.
///      One guard covers settlement/configuration/token-moving paths. Local action pauses and
///      immutable Core binding are enforced by the action contracts, not queried again at settlement.
contract BurnerLoansCore is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    ReentrancyGuard,
    OperatorAuth,
    ConfigOperatorSingleStep,
    IBurnerLoansCore,
    IVersioned,
    IBurnerLoansErrors
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for ERC20;
    using SafeERC20Exact for ERC20;

    /// @dev Permanent principal token; token units use its declared decimals.
    IERC20 internal immutable _OHM;
    /// @dev Permanent collateral custodian; all liabilities and receipts use Core's operator namespace.
    IDepositManager internal immutable _DEPOSIT_MANAGER;
    /// @dev Current Kernel FLOAN module holding authoritative positions and aggregate principal.
    IFLOANv1 internal _FLOAN;
    /// @dev Selected funding contract retaining its own provider claims and principal provenance.
    IBurnerLoansInventory internal _INVENTORY;
    /// @notice Minimal local market identity and custody output mode; economic parameters live in FLOAN.
    struct MarketRecord {
        /// @dev Canonical FLOAN market identifier.
        uint32 id;
        /// @dev Whether principal and yield exits transfer shares rather than redeem underlying.
        bool withdrawAsShares;
        /// @dev Distinguishes an unregistered asset from market ID zero.
        bool registered;
    }
    /// @dev Stable collateral-asset to market mapping maintained by selected Config.
    mapping(address => MarketRecord) internal _MARKETS;
    /// @dev Append-only collateral registry used for market-manager handoff and bounded automation.
    EnumerableSet.AddressSet internal _ASSETS;
    /// @dev Selected proceeds/payout custody; retired contracts retain their own obligations.
    IBurnerLoansPayout internal _PAYOUT;
    /// @inheritdoc IBurnerLoansCore
    address public override risk;

    /// @notice Binds deployment dependencies and initializes the local contract state.
    /// @dev Reverts if:
    ///      - The supplied DepositManager does not implement the required interface.
    ///      - DepositManager's Kernel getter fails, returns malformed data or reports a different Kernel.
    ///      - OHM has no code, its decimals getter fails or returns malformed data, or its decimals exceed 36.
    /// @param kernel_ Kernel supplying modules and governance authority.
    /// @param ohm_ Principal token used by the facility.
    /// @param depositManager_ Permanent operator-namespaced collateral custodian.
    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        if (
            !ERC165Checker.supportsInterface(
                address(depositManager_),
                type(IDepositManagerV1_1).interfaceId
            )
        ) revert IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager(address(depositManager_));
        PolicyDependency.requireSameKernel(address(depositManager_), address(kernel_));
        _OHM = ohm_;
        (bool validOhm, ) = LoanToken.readDecimals(address(ohm_));
        if (!validOhm) revert BurnerLoansCore_InvalidOhm(address(ohm_));
        _DEPOSIT_MANAGER = depositManager_;
    }

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    modifier onlyActive() {
        _requireActive();
        _;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - Another guarded Core operation is executing.
    ///      - A declared module is missing.
    ///      - A declared module has an incompatible version.
    ///
    /// @dev Resolves the declared modules through this contract's Kernel; dependency errors propagate.
    function configureDependencies()
        external
        override
        nonReentrant
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("FLOAN");
        dependencies[1] = toKeycode("ROLES");
        _FLOAN = IFLOANv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));
        // Only the module major version determines compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 loanMajor, ) = Module(address(_FLOAN)).VERSION();
        // Only the module major version determines compatibility.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = ROLES.VERSION();
        if (loanMajor != 1 || rolesMajor != 1)
            revert IBurnerLoansErrors.BurnerLoans_InvalidModuleVersion();
    }

    /// @inheritdoc Policy
    /// @dev Declares only the listed module selectors; no dynamic permissions or token approvals.
    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode loan = toKeycode("FLOAN");
        requests = new Permissions[](8);
        requests[0] = Permissions(loan, IFLOANv1.addCollateral.selector);
        requests[1] = Permissions(loan, IFLOANv1.removeCollateral.selector);
        requests[2] = Permissions(loan, IFLOANv1.increaseDebt.selector);
        requests[3] = Permissions(loan, IFLOANv1.createPosition.selector);
        requests[4] = Permissions(loan, IFLOANv1.decreaseDebt.selector);
        requests[5] = Permissions(loan, IFLOANv1.extendMaturity.selector);
        requests[6] = Permissions(loan, IFLOANv1.defaultPosition.selector);
        requests[7] = Permissions(loan, IFLOANv1.setMarketManager.selector);
    }

    /// @notice Restricts the caller before executing the guarded operation.
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    /// @param role_ Governance role required for this operation.
    modifier onlyAction(bytes32 role_) {
        _requireOperational();
        _requireRole(msg.sender, role_);
        _;
    }

    /// @notice Restricts the caller before executing the guarded operation.
    /// @dev Reverts if:
    ///      - The caller is not Core’s selected Config.
    modifier onlyConfigurator() {
        if (!_isConfigOperator(msg.sender)) revert ConfigOperator_Unauthorized(msg.sender);
        _;
    }

    /// @notice Restricts the caller before executing the guarded operation.
    /// @dev Reverts if:
    ///      - The caller is neither selected Config nor ADMIN.
    modifier onlyConfiguratorOrAdmin() {
        if (!_isConfigOperator(msg.sender)) _onlyAdmin();
        _;
    }

    /// @notice Requires governance ADMIN authority.
    /// @dev Reverts if:
    ///      - The caller lacks the authority required by this operation.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _onlyAdmin() internal view {
        if (!_isAdmin(msg.sender)) revert NotAuthorised();
    }

    /// @notice Requires active Kernel membership.
    /// @dev Reverts if:
    ///      - Core is inactive in the required Kernel.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _requireActive() internal view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }

    /// @notice Requires active and enabled Core lifecycle state.
    /// @dev Reverts if:
    ///      - Core is Kernel-inactive.
    ///      - Core is locally disabled.
    function _requireOperational() internal view {
        _requireActive();
        _requireEnabled();
    }

    /// @notice Requires an operational Core before direct or signed grant creation.
    /// @dev Reverts if:
    ///      - Core is Kernel-inactive, before checking enablement or authorization inputs.
    ///      - Core is disabled, before checking authorization inputs or consuming a nonce.
    /// @dev Cancellation remains available in every lifecycle state.
    function _beforeSetAuthorization() internal view override {
        _requireOperational();
    }

    /// @notice Requires active membership and an explicitly matching Kernel.
    /// @dev Reverts if:
    ///      - The policy's Kernel getter fails or returns malformed data.
    ///      - The policy is inactive in Core’s Kernel.
    ///      - The policy reports a different Kernel.
    /// @param policy_ Policy whose live Kernel binding is checked.
    function _requireLinkedPolicy(address policy_) internal view {
        PolicyDependency.requireActive(policy_, address(kernel));
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The market is unregistered.
    ///      - Exact incoming transfer, receipt approval or DepositManager deposit fails.
    ///      - Actual credit is zero or exceeds uint128.
    ///      - FLOAN rejects collateral credit.
    function settleDeposit(
        address asset_,
        uint128 amount_,
        address payer_,
        address borrower_
    )
        external
        override
        nonReentrant
        onlyAction(BL_COLLATERAL_POLICY_ROLE)
        returns (uint128 credit, uint128 collateral)
    {
        uint32 market = marketId(asset_);
        ERC20 token = ERC20(asset_);
        // DepositManager determines actual vault-backed credit. Book it only after deposit returns;
        // nominal input is not a safe collateral estimate. The Core guard blocks nested settlement.
        token.safeTransferFromExact(payer_, address(this), amount_);
        token.forceApprove(address(_DEPOSIT_MANAGER), amount_);
        // FLOAN uses actual credited collateral; custody and receipt checks validate the token path.
        // This multiline operation needs a range; the suppression ends immediately after it.
        // forge-lint: disable-start(unused-return)
        (, uint256 raw) = _DEPOSIT_MANAGER.deposit(
            IDepositManager.DepositParams(
                IERC20(asset_),
                LoanParameters._DEPOSIT_PERIOD,
                address(this),
                amount_,
                false
            )
        );
        // forge-lint: disable-end(unused-return)
        credit = SafeCast.toUint128(raw);
        if (credit == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroCollateralCredit();
        _approveReceiptBurn(asset_);
        (bool exists, uint64 id) = LoanPositions.find(_FLOAN, market, borrower_);
        if (!exists) id = _FLOAN.createPosition(market, borrower_);
        collateral = _FLOAN.addCollateral(id, credit);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The market or collateral position is absent.
    ///      - FLOAN rejects the debit or DepositManager rejects the exit.
    ///      - The output token is unexpected or the output amount is zero.
    function settleWithdraw(
        address asset_,
        uint128 amount_,
        address borrower_,
        address recipient_
    )
        external
        override
        nonReentrant
        onlyAction(BL_COLLATERAL_POLICY_ROLE)
        returns (address token, uint256 output, uint128 remaining)
    {
        remaining = _FLOAN.removeCollateral(_positionId(asset_, borrower_), amount_);
        (token, output) = _withdrawPayout(asset_, amount_, recipient_);
        if (output == 0) revert IBurnerLoansCore.BurnerLoansCore_ZeroCollateralWithdrawal();
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The market or position is absent, or FLOAN rejects principal/maturity changes.
    ///      - The combined protocol and referral fee exceeds the uint256 maximum.
    ///      - Mandatory fee collection or Inventory funding fails.
    function settleBorrow(
        BorrowRequest calldata request_
    ) external override nonReentrant onlyAction(BL_DEBT_POLICY_ROLE) returns (uint128, uint48) {
        // The action has validated health, caps and maturity. Commit the canonical debt here;
        // a failed fee receipt or principal delivery below rolls back this FLOAN update too.
        IFLOANv1.Position memory afterPosition = _FLOAN.increaseDebt(
            _positionId(request_.asset, request_.borrower),
            request_.amount,
            0,
            request_.maturity
        );
        _collectFee(
            request_.asset,
            request_.payer,
            request_.protocolFee,
            request_.referrer,
            request_.referralFee
        );
        _INVENTORY.draw(request_.recipient, request_.amount);
        return (afterPosition.principalDue, afterPosition.maturity);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The market or position is absent, or FLOAN rejects repayment.
    ///      - Exact OHM collection or Inventory repayment settlement fails.
    function settleRepay(
        address asset_,
        uint128 amount_,
        address payer_,
        address borrower_
    ) external override nonReentrant onlyAction(BL_DEBT_POLICY_ROLE) returns (uint128) {
        IFLOANv1.Position memory afterPosition = _FLOAN.decreaseDebt(
            _positionId(asset_, borrower_),
            amount_,
            0
        );
        // Inventory must receive the exact repayment before it restores provider liquidity or burns
        // minted principal. Its balance check alone cannot distinguish a new receipt from surplus.
        ERC20(address(_OHM)).safeTransferFromExact(payer_, address(_INVENTORY), amount_);
        _INVENTORY.settleRepayment(amount_);
        return afterPosition.principalDue;
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The market or position is absent, or FLOAN rejects maturity extension.
    ///      - The combined protocol and referral fee exceeds the uint256 maximum.
    ///      - Mandatory fee collection fails.
    function settleExtend(
        address asset_,
        address borrower_,
        address payer_,
        uint48 maturity_,
        uint256 protocolFee_,
        address referrer_,
        uint256 referralFee_
    ) external override nonReentrant onlyAction(BL_DEBT_POLICY_ROLE) returns (uint48 maturity) {
        maturity = _FLOAN.extendMaturity(_positionId(asset_, borrower_), maturity_).maturity;
        _collectFee(asset_, payer_, protocolFee_, referrer_, referralFee_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The market or a position is absent, or FLOAN rejects default.
    ///      - DepositManager redemption fails or new Payout receipts mismatch returned proceeds.
    ///      - Risk allocates a reward larger than actual proceeds.
    ///      - Inventory principal reduction or Payout payout credit fails.
    function settleSeize(
        address asset_,
        address[] calldata borrowers_,
        address keeper_,
        IBurnerLoansCore.PriceSnapshot calldata snapshot
    )
        external
        override
        nonReentrant
        onlyAction(BL_LIQUIDATION_POLICY_ROLE)
        returns (IBurnerLoansCore.SeizePreview memory result)
    {
        IBurnerLoansRisk evaluator = IBurnerLoansRisk(risk);
        // Default every selected position before redeeming their combined collateral once. The
        // action validated the entire batch, and any mandatory settlement failure reverts all defaults.
        for (uint256 i; i < borrowers_.length; ++i) {
            // Only principal and collateral are settled; Burner Loans creates no interest debt.
            // Each selected position must pass validation and settle atomically with the batch.
            // This multiline operation needs a range; the suppression ends immediately after it.
            // forge-lint: disable-start(calls-loop,unused-return)
            (uint128 principal, , uint128 collateral) = _FLOAN.defaultPosition(
                _positionId(asset_, borrowers_[i])
            );
            // forge-lint: disable-end(calls-loop,unused-return)
            result.seizedDebtOhm += principal;
            result.seizedCollateral += collateral;
            emit IBurnerLoansCore.Seized(keeper_, asset_, borrowers_[i], principal, collateral);
        }
        uint256 output;
        (result.tokenOut, output) = _withdrawPayout(
            asset_,
            result.seizedCollateral,
            address(_PAYOUT)
        );
        // Price-based reward limits use the action's snapshot, but distribution uses actual redemption
        // output. This keeps keeper plus Treasury entitlements equal to the tokens received by Payout.
        bool protocolCaller = _hasRole(keeper_, BURNER_LOANS_SEIZER_ROLE) ||
            _hasRole(keeper_, HEART_ROLE);
        result.keeperReward = evaluator.keeperReward(
            snapshot,
            marketId(asset_),
            result.seizedDebtOhm,
            result.seizedCollateral,
            output,
            protocolCaller
        );
        if (result.keeperReward > output) revert BurnerLoansCore_InvalidSettlement();
        result.collateralToTreasury = output - result.keeperReward;
        _INVENTORY.settleDefault(SafeCast.toUint128(result.seizedDebtOhm));
        _PAYOUT.creditSeizure(
            result.tokenOut,
            keeper_,
            result.keeperReward,
            result.collateralToTreasury
        );
        emit IBurnerLoansCore.SeizureBatchSettled(
            keeper_,
            asset_,
            borrowers_.length,
            result.seizedDebtOhm,
            result.seizedCollateral,
            result.tokenOut,
            result.keeperReward,
            result.collateralToTreasury
        );
    }

    /// @notice Redeems operator collateral directly to its final recipient.
    /// @dev Reverts if:
    ///      - DepositManager's output-token lookup or withdrawal fails.
    ///      - The returned output token differs from DepositManager's selected withdrawal token.
    ///      - Payout's token balance cannot be read or its increase differs from the reported output.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param amount_ Token amount in the operation's documented token units.
    /// @param recipient_ Final output recipient or pending entitlement holder.
    /// @return token Final underlying/share output token.
    /// @return uint256 Actual DepositManager output in output-token units.
    function _withdrawPayout(
        address asset_,
        uint256 amount_,
        address recipient_
    ) private returns (address token, uint256) {
        bool shares_ = _MARKETS[asset_].withdrawAsShares;
        token = address(
            IAssetManagerV1_1(address(_DEPOSIT_MANAGER)).getAssetWithdrawalToken(
                IERC20(asset_),
                shares_
            )
        );
        if (amount_ == 0) return (token, 0);
        uint256 balance;
        if (recipient_ == address(_PAYOUT)) balance = ERC20(token).balanceOf(address(_PAYOUT));
        (IERC20 returnedToken, uint256 returnedAmount) = IDepositManagerV1_1(
            address(_DEPOSIT_MANAGER)
        ).withdraw(
                IDepositManager.WithdrawParams(
                    IERC20(asset_),
                    LoanParameters._DEPOSIT_PERIOD,
                    address(this),
                    recipient_,
                    amount_,
                    false
                ),
                shares_
            );
        if (address(returnedToken) != token) revert BurnerLoansCore_InvalidSettlement();
        if (recipient_ == address(_PAYOUT)) {
            // New seizure obligations must match new receipts. Old donated surplus must not hide
            // a short transfer; DepositManager solvency does not prove this recipient delta.
            uint256 afterBalance = ERC20(token).balanceOf(address(_PAYOUT));
            if (afterBalance < balance || afterBalance - balance != returnedAmount)
                revert BurnerLoansCore_InvalidSettlement();
        }
        return (token, returnedAmount);
    }

    /// @notice Collects a mandatory fee directly into selected Payout and credits it.
    /// @dev Reverts if:
    ///      - protocolFee_ + referralFee_ exceeds the uint256 maximum (BurnerLoansCore_FeeOverflow).
    ///      - The fee transfer fails or Payout receives an inexact amount.
    ///      - Payout rejects the new fee credit.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param payer_ Actual action caller funding this transfer.
    /// @param protocolFee_ Policy-approved protocol allocation in raw collateral units.
    /// @param referrer_ Fixed recipient of the referral allocation.
    /// @param referralFee_ Policy-approved referral allocation in raw collateral units.
    function _collectFee(
        address asset_,
        address payer_,
        uint256 protocolFee_,
        address referrer_,
        uint256 referralFee_
    ) private {
        if (referralFee_ > type(uint256).max - protocolFee_)
            revert BurnerLoansCore_FeeOverflow(protocolFee_, referralFee_);
        uint256 totalFee = protocolFee_ + referralFee_;
        if (totalFee == 0) return;
        // Core pulls the payer's tokens directly into Payout under Core's settlement guard.
        // Token callbacks can occur before creditFee enters Payout's local guard.
        // A blocked Payout reverts the entire borrow, including its debt/maturity changes.
        // A failed extension preserves the old maturity: that loan can still expire normally.
        // OCG may replace Payout; subsequent protocol and referral deliveries may defer.
        ERC20(asset_).safeTransferFromExact(payer_, address(_PAYOUT), totalFee);
        _PAYOUT.creditFee(asset_, protocolFee_, referrer_, referralFee_);
    }

    /// @notice Authorizes DepositManager to burn Core-owned collateral receipts.
    /// @dev Reverts if:
    ///      - DepositManager's receipt-token-manager lookup fails.
    ///      - Burner Loans could not approve the ReceiptTokenManager for collateral custody.
    /// @param asset_ Underlying collateral token identifying the market.
    function _approveReceiptBurn(address asset_) private {
        IReceiptTokenManager receipts = _DEPOSIT_MANAGER.getReceiptTokenManager();
        if (address(receipts) == address(0)) return;
        uint256 id = _DEPOSIT_MANAGER.getReceiptTokenId(
            IERC20(asset_),
            LoanParameters._DEPOSIT_PERIOD,
            address(this)
        );
        if (
            receipts.allowance(address(this), address(_DEPOSIT_MANAGER), id) != type(uint256).max &&
            !receipts.approve(address(_DEPOSIT_MANAGER), id, type(uint256).max)
        ) revert IBurnerLoansCore.BurnerLoansCore_ReceiptApprovalFailed(address(receipts));
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - The collateral asset is not registered by Burner Loans.
    /// @dev Reads the local market registry without external calls.
    function marketId(address asset_) public view override returns (uint32) {
        if (!_MARKETS[asset_].registered)
            // Each selected position must pass validation and settle atomically with the batch.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured(asset_);
        return _MARKETS[asset_].id;
    }

    /// @notice Resolves the canonical position for an asset and borrower.
    /// @dev Reverts if:
    ///      - The collateral asset is not registered.
    ///      - The borrower has no outstanding debt for the asset.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param borrower_ Account whose canonical position is queried or changed.
    /// @return uint64 Canonical FLOAN position identifier.
    function _positionId(address asset_, address borrower_) private view returns (uint64) {
        (bool exists, uint64 positionId_) = LoanPositions.find(_FLOAN, marketId(asset_), borrower_);
        // Each selected position must pass validation and settle atomically with the batch.
        // forge-lint: disable-next-line(require-revert-in-loop)
        if (!exists) revert IBurnerLoansCore.BurnerLoansCore_NoDebt();
        return positionId_;
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Returns the immutable token address without external calls.
    function ohm() external view override returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Returns the immutable custodian address without external calls.
    function depositManager() external view override returns (address) {
        return address(_DEPOSIT_MANAGER);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reads the selected Inventory address without external calls.
    function inventory() external view override returns (address) {
        return address(_INVENTORY);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reads the cached FLOAN module address without external calls.
    function floan() external view override returns (address) {
        return address(_FLOAN);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reads the local asset registry without external calls.
    function isAssetRegistered(address asset_) external view override returns (bool) {
        return _ASSETS.contains(asset_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reads the local asset count without external calls.
    function getAssetCount() external view override returns (uint256) {
        return _ASSETS.length();
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - index_ is greater than or equal to the registered asset count.
    function getAssetAt(uint256 index_) external view override returns (address) {
        return _ASSETS.at(index_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reads without state changes; errors from dependency views propagate.
    function totalActiveDebtOhm() public view override returns (uint256) {
        return _FLOAN.getFacilityPrincipalDue(address(this), address(_OHM));
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Another guarded Core operation is executing, Core is inactive or the caller lacks ADMIN.
    ///      - The replacement is the current nonzero Risk address.
    ///      - Risk lacks required interfaces, reports another Kernel or is bound to another Core.
    ///      - A required dependency getter fails or returns malformed data.
    ///      - Risk is inactive or disabled, or uses a different OHM token.
    /// @dev Install a preconfigured replacement; this function preserves its independent authority.
    function setRisk(address risk_) external override nonReentrant onlyActive onlyAdminRole {
        if (risk_ != address(0) && risk_ == risk) revert BurnerLoans_UnchangedAddress(risk_);
        if (
            !_validateDependency(
                risk_,
                type(IBurnerLoansRisk).interfaceId,
                BurnerLoansCore_InvalidRisk.selector
            )
        ) revert BurnerLoansCore_InvalidRisk(risk_);
        if (
            _readDependencyUint256(
                risk_,
                abi.encodeCall(IBurnerLoansRisk.ohm, ()),
                BurnerLoansCore_InvalidRisk.selector
            ) != uint256(uint160(address(_OHM)))
        ) revert BurnerLoansCore_InvalidRisk(risk_);
        IBurnerLoansRisk next = IBurnerLoansRisk(risk_);
        risk = address(next);
        emit RiskSet(risk_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Another guarded Core operation is executing, Core is inactive or the caller lacks ADMIN.
    ///      - The replacement is the current nonzero Inventory address.
    ///      - Inventory lacks required interfaces, reports another Kernel or is bound to another Core.
    ///      - A required dependency getter fails or returns malformed data.
    ///      - Inventory is inactive or disabled, or uses a different OHM token.
    ///      - Replacement principal differs from canonical FLOAN debt.
    ///      - Old and replacement principal or aggregate provider claims differ.
    function setInventory(
        address inventory_
    ) external override nonReentrant onlyActive onlyAdminRole {
        if (inventory_ != address(0) && inventory_ == address(_INVENTORY))
            revert BurnerLoans_UnchangedAddress(inventory_);
        if (
            !_validateDependency(
                inventory_,
                type(IBurnerLoansInventory).interfaceId,
                BurnerLoansCore_InvalidInventory.selector
            )
        ) revert BurnerLoansCore_InvalidInventory(inventory_);

        IBurnerLoansInventory next = IBurnerLoansInventory(inventory_);
        if (
            _readDependencyUint256(
                inventory_,
                abi.encodeCall(IBurnerLoansInventory.ohm, ()),
                BurnerLoansCore_InvalidInventory.selector
            ) !=
            uint256(uint160(address(_OHM))) ||
            next.activePrincipalOhm() != totalActiveDebtOhm()
        ) revert IBurnerLoansCore.BurnerLoansCore_InvalidInventory(inventory_);
        // Inventory owns provider claims: pointer replacement alone cannot migrate them.
        if (
            address(_INVENTORY) != address(0) &&
            (_INVENTORY.activePrincipalOhm() != next.activePrincipalOhm() ||
                _INVENTORY.suppliedOhm() != next.suppliedOhm())
        ) revert IBurnerLoansCore.BurnerLoansCore_InvalidInventory(inventory_);
        _INVENTORY = next;
        emit IBurnerLoansCore.InventorySet(inventory_);
    }

    /// @inheritdoc IConfigOperator
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN or a guarded Core operation is executing.
    ///      - Core is inactive or the new authority is zero/unchanged.
    ///      - FLOAN manager handoff fails.
    /// @dev Governance validates the upstream Config; Core stores only its authority address.
    ///      Payout and Inventory have independent controllers and are not changed here.
    function setConfigOperator(address operator_) public override nonReentrant {
        // Admit Core before authorization, validation or manager writes.
        _requireActive();
        _authorizeSetConfigOperator();
        if (operator_ == address(0)) revert BurnerLoans_ZeroAddress();
        if (operator_ == configOperator) revert ConfigOperator_Unchanged();
        // Core's controller and FLOAN's per-market manager must move together. A single rejected
        // market handoff reverts every earlier handoff and leaves the old controller selected.
        for (uint256 i; i < _ASSETS.length(); ++i)
            // Every registered market must hand off atomically to the same operator.
            // The external entry point holds nonReentrant across this call and subsequent state updates.
            // forge-lint: disable-next-line(calls-loop,reentrancy-no-eth)
            _FLOAN.setMarketManager(_MARKETS[_ASSETS.at(i)].id, operator_);
        super.setConfigOperator(operator_);
    }

    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    ///
    /// @dev Also called before the public setter's handoff work.
    function _authorizeSetConfigOperator() internal view override onlyAdminRole returns (bool) {
        return true;
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller is not the selected Config address.
    ///      - A guarded Core operation is executing.
    ///      - An existing asset is assigned a different market ID.
    function registerMarket(
        address asset_,
        uint32 market_,
        bool shares_
    ) external override nonReentrant onlyActive givenEnabled onlyConfigurator {
        // Config creates/updates the market first. Its manager and Core facility identities are fixed there.
        // Registry entries are never removed: task cursors keep a stable index as new assets are added.
        if (!_MARKETS[asset_].registered) {
            _ASSETS.add(asset_);
            emit IBurnerLoansCore.AssetRegistered(asset_);
        } else {
            if (_MARKETS[asset_].id != market_)
                revert BurnerLoansCore_MarketMismatch(asset_, _MARKETS[asset_].id, market_);
            if (_MARKETS[asset_].withdrawAsShares == shares_) return;
        }
        _MARKETS[asset_] = MarketRecord(market_, shares_, true);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is inactive or disabled.
    ///      - The caller lacks this operation’s settlement role.
    ///      - Another guarded Core operation is executing.
    ///      - The asset is unregistered.
    ///      - DepositManager rejects the claim or recipient transfer.
    function settleYield(
        address asset_,
        uint256 requested_,
        address recipient_
    )
        external
        override
        nonReentrant
        onlyAction(BL_YIELD_CLAIMER_ROLE)
        returns (address tokenOut, uint256 amountOut)
    {
        marketId(asset_);
        IERC20 output;
        (output, amountOut) = IDepositManagerV1_1(address(_DEPOSIT_MANAGER)).claimYield(
            IERC20(asset_),
            recipient_,
            requested_,
            _MARKETS[asset_].withdrawAsShares
        );
        tokenOut = address(output);
        if (amountOut != 0)
            emit IBurnerLoansYieldClaim.YieldClaimed(
                asset_,
                requested_,
                tokenOut,
                amountOut,
                recipient_
            );
    }

    /// @notice Validates the enable payload, then delegates settlement and dependency checks.
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    /// @dev Then calls _requireNotReentrant() and _validateLifecycle(); their errors propagate.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _requireNotReentrant();
        _validateLifecycle();
    }

    /// @notice Checks that a lifecycle transition cannot interrupt settlement.
    /// @dev Reverts if:
    ///      - Lifecycle data is nonempty.
    /// @dev Calls _requireNotReentrant() before checking the payload; its errors propagate.
    function _beforeDisable(bytes calldata data_) internal view override {
        _requireNotReentrant();
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @notice Revalidates the grace window and current dependency graph.
    /// @dev Reverts if:
    ///      - Core is settling.
    ///      - The re-enable grace deadline exceeds uint48 or has passed.
    ///      - Current lifecycle dependencies fail validation.
    function _beforeReEnable() internal override {
        _requireNotReentrant();
        super._beforeReEnable();
        _validateLifecycle();
    }

    /// @notice Checks authority for fast re-enablement.
    /// @dev Reverts if:
    ///      - The caller lacks the authority required by this operation.
    /// @dev Reads without state changes; errors from dependency views propagate.
    function _authorizeReEnable() internal view override {
        if (!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE))
            revert NotAuthorised();
    }

    /// @inheritdoc ReEnablerGracePeriod
    /// @dev Reverts if:
    ///      - Another guarded operation is executing.
    ///      - This policy is Kernel-inactive.
    ///      - This policy is locally disabled.
    ///      - The caller lacks ADMIN.
    ///      - The requested period is zero.
    function setGracePeriod(uint32 period_) public override nonReentrant onlyActive {
        super.setGracePeriod(period_);
    }

    /// @dev The public setter first applies settlement, activity and local enablement checks.
    /// @dev Reverts if:
    ///      - The caller lacks ADMIN.
    function _authorizeSetGracePeriod() internal view override onlyAdminRole {}

    /// @notice Requires the complete Core settlement guard to be idle.
    /// @dev Reverts if:
    ///      - A guarded Core operation is executing (ReentrancyGuardReentrantCall).
    function _requireNotReentrant() private view {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardReentrantCall();
    }

    /// @notice Validates the selected dependencies before enabling Core.
    /// @dev Reverts if:
    ///      - Core is Kernel-inactive.
    ///      - Inventory, Payout or Risk is unset.
    ///      - A selected dependency has invalid interfaces, metadata or system binding.
    ///      - A selected dependency reports a different Kernel.
    ///      - DepositManager, Inventory, Payout or Risk is Kernel-inactive.
    ///      - DepositManager, Inventory, Payout or Risk is locally disabled.
    function _validateLifecycle() private view {
        _requireActive();
        if (address(_INVENTORY) == address(0)) revert BurnerLoansCore_InvalidInventory(address(0));
        if (address(_PAYOUT) == address(0)) revert BurnerLoansCore_InvalidPayout(address(0));
        if (risk == address(0)) revert BurnerLoansCore_InvalidRisk(address(0));
        _requireLinkedPolicy(address(_DEPOSIT_MANAGER));
        if (!IEnabler(address(_DEPOSIT_MANAGER)).isEnabled())
            revert PolicyDependency.PolicyDependency_NotActive(address(_DEPOSIT_MANAGER));
        if (
            !_validateDependency(
                address(_INVENTORY),
                type(IBurnerLoansInventory).interfaceId,
                BurnerLoansCore_InvalidInventory.selector
            )
        ) revert PolicyDependency.PolicyDependency_NotActive(address(_INVENTORY));
        if (
            !_validateDependency(
                address(_PAYOUT),
                type(IBurnerLoansPayout).interfaceId,
                BurnerLoansCore_InvalidPayout.selector
            )
        ) revert PolicyDependency.PolicyDependency_NotActive(address(_PAYOUT));
        if (
            !_validateDependency(
                risk,
                type(IBurnerLoansRisk).interfaceId,
                BurnerLoansCore_InvalidRisk.selector
            )
        ) revert PolicyDependency.PolicyDependency_NotActive(risk);
    }

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @notice Advertises implemented interfaces and inherited lifecycle support.
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    /// @param interfaceId_ ERC-165 interface identifier.
    /// @return bool Whether the interface identifier is supported.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansCore).interfaceId ||
            interfaceId_ == type(IOperatorAuth).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reads the selected Payout address without external calls.
    function payout() external view override returns (address) {
        return address(_PAYOUT);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Another guarded Core operation is executing, Core is inactive or the caller lacks ADMIN.
    ///      - The replacement is the current nonzero Payout address.
    ///      - Payout lacks required interfaces, reports another Kernel or is bound to another Core.
    ///      - A required dependency getter fails or returns malformed data.
    ///      - Payout is inactive or disabled.
    function setPayout(address payout_) external override nonReentrant onlyActive onlyAdminRole {
        if (payout_ != address(0) && payout_ == address(_PAYOUT))
            revert BurnerLoans_UnchangedAddress(payout_);
        if (
            !_validateDependency(
                payout_,
                type(IBurnerLoansPayout).interfaceId,
                BurnerLoansCore_InvalidPayout.selector
            )
        ) revert BurnerLoansCore_InvalidPayout(payout_);
        address previous = address(_PAYOUT);
        // Replacement directs new receipts only. Pending obligations remain backed and recoverable
        // in the previous Payout; changing this pointer does not migrate its balances or ledger.
        _PAYOUT = IBurnerLoansPayout(payout_);
        emit PayoutSet(previous, payout_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Payout uses this check to protect incoming funds before Core-only credit reserves them.
    /// @dev Reverts if:
    ///      - Core's settlement guard is entered.
    function requireNotReentrant() external view override {
        _requireNotReentrant();
    }

    /// @dev Common compatibility boundary for selected services. Availability is returned so
    ///      replacement setters and lifecycle transitions retain their specified errors.
    /// @dev Reverts if:
    ///      - The candidate lacks a required interface or returns a value other than true for its interface check.
    ///      - A required dependency getter fails or returns malformed data.
    ///      - The candidate reports a different Kernel or is bound to another Core.
    function _validateDependency(
        address candidate_,
        bytes4 service_,
        bytes4 invalid_
    ) private view returns (bool) {
        bytes4[] memory ids = new bytes4[](4);
        ids[0] = service_;
        ids[1] = type(IBurnerLoansCoreBound).interfaceId;
        ids[2] = type(IEnabler).interfaceId;
        ids[3] = type(IVersioned).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(candidate_, ids))
            _invalidDependency(candidate_, invalid_);
        // ERC165Checker accepts any nonzero response. Repeat the reads to require canonical true
        // words and bounded ABI responses before trusting the service's identity getters.
        for (uint256 i; i < ids.length; ++i) {
            if (
                _readDependencyUint256(
                    candidate_,
                    abi.encodeCall(IERC165.supportsInterface, (ids[i])),
                    invalid_
                ) != 1
            ) _invalidDependency(candidate_, invalid_);
        }
        PolicyDependency.requireSameKernel(candidate_, address(kernel));
        if (
            _readDependencyUint256(
                candidate_,
                abi.encodeCall(IBurnerLoansCoreBound.core, ()),
                invalid_
            ) != uint256(uint160(address(this)))
        ) _invalidDependency(candidate_, invalid_);
        bool enabled = PolicyDependency.readEnabled(candidate_);
        // Compatibility errors above are distinct from temporary unavailability. The caller maps
        // this readiness result to the error appropriate for replacement or lifecycle admission.
        return kernel.isPolicyActive(Policy(candidate_)) && enabled;
    }

    /// @dev Reads dependency metadata and requires a return value of exactly 32 bytes.
    /// @dev Reverts if:
    ///      - The dependency call fails.
    ///      - The dependency does not return exactly 32 bytes.
    function _readDependencyUint256(
        address candidate_,
        bytes memory data_,
        bytes4 invalid_
    ) private view returns (uint256) {
        (bool success, bytes memory result) = SafeCall.safeStaticCall(
            candidate_,
            gasleft(),
            33,
            data_
        );
        if (!success || result.length != 32) _invalidDependency(candidate_, invalid_);
        return abi.decode(result, (uint256));
    }

    /// @dev Reverts if:
    ///      - This helper is called; it always raises the selected component-owned invalid-dependency error.
    function _invalidDependency(address candidate_, bytes4 invalid_) private pure {
        if (invalid_ == BurnerLoansCore_InvalidDepositManager.selector)
            // Reject this batch component with its own typed dependency error.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert BurnerLoansCore_InvalidDepositManager(candidate_);
        if (invalid_ == BurnerLoansCore_InvalidRisk.selector)
            // Reject this batch component with its own typed dependency error.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert BurnerLoansCore_InvalidRisk(candidate_);
        if (invalid_ == BurnerLoansCore_InvalidInventory.selector)
            // Reject this batch component with its own typed dependency error.
            // forge-lint: disable-next-line(require-revert-in-loop)
            revert BurnerLoansCore_InvalidInventory(candidate_);
        // Reject this batch component with its own typed dependency error.
        // forge-lint: disable-next-line(require-revert-in-loop)
        revert BurnerLoansCore_InvalidPayout(candidate_);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Another guarded Core operation is executing.
    ///      - Core is Kernel-inactive.
    ///      - The caller lacks recovery authority.
    ///      - The token or destination is invalid.
    ///      - The token balance read or surplus transfer fails.
    ///
    /// @dev Recovery transfers only surplus; rejection rolls back the complete operation.
    function rescue(
        address token_,
        address destination_
    ) external override nonReentrant onlyActive onlyConfiguratorOrAdmin {
        uint256 surplus = _rescueAmount(token_, destination_);
        if (surplus != 0) {
            ERC20(token_).safeTransfer(destination_, surplus);
            emit IBurnerLoansCore.AssetRescued(token_, destination_, surplus);
        }
    }

    /// @notice Uses widened deadline arithmetic without changing the shared ReEnabler.
    /// @dev Reverts if:
    ///      - The deadline overflows uint48 or the inclusive grace window expired.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @inheritdoc IBurnerLoansCore
    /// @dev Reverts if:
    ///      - Core is settling.
    ///      - Core is Kernel-inactive.
    ///      - The token has no code.
    ///      - The destination is forbidden.
    ///      - The token balance read fails.
    ///
    /// @dev Permissionless; local disablement does not block recovery quotes.
    function previewRescue(address token_, address destination_) public view returns (uint256) {
        _requireNotReentrant();
        return _rescueAmount(token_, destination_);
    }

    /// @dev The execution entry point already holds the settlement guard.
    /// @dev Reverts if:
    ///      - Core is Kernel-inactive.
    ///      - The token address has no deployed code.
    ///      - The destination is zero, Core, the token, Payout, the current Config operator or Kernel.
    ///      - The token balance getter fails or cannot be ABI-decoded.
    function _rescueAmount(address token_, address destination_) private view returns (uint256) {
        _requireActive();
        if (token_.code.length == 0) revert IBurnerLoansErrors.BurnerLoans_InvalidAsset(token_);
        if (
            destination_ == address(0) ||
            destination_ == address(this) ||
            destination_ == token_ ||
            destination_ == address(_PAYOUT) ||
            destination_ == configOperator ||
            destination_ == address(kernel)
        ) revert IBurnerLoansErrors.BurnerLoans_InvalidRescueDestination(destination_);
        // Collateral belongs to DepositManager, funding to Inventory and pending payouts to Payout.
        // Core retains no reserved ERC20 balance between settlements; its guard excludes in-flight funds.
        return ERC20(token_).balanceOf(address(this));
    }
}
