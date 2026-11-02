// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IBurnerLoansYieldClaimerTask} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaimerTask.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeCall} from "src/libraries/SafeCall.sol";
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanCustody} from "src/policies/burnerloans/libraries/LoanCustody.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {BURNER_LOANS_ADMIN_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";
import {ReEnablerGracePeriod} from "src/bases/ReEnablerGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnablerV2} from "src/policies/utils/PolicyEnablerV2.sol";

/// @title Burner Loans Yield Claimer Task
/// @notice Heart task that resumes registered-asset claims within a complete-task gas limit.
/// @dev The task reads Burner Loans' append-only registry inside a gas-bounded external self-call.
///      Each claim is separately gas-bounded so its cursor and earlier claims remain committed when
///      one registered asset fails or exhausts its forwarded gas.
contract BurnerLoansYieldClaimerTask is
    Policy,
    ReEnablerGracePeriod,
    PolicyEnablerV2,
    IBurnerLoansYieldClaimerTask,
    IBurnerLoansCoreBound,
    IBurnerLoansYieldClaim,
    IPeriodicTask,
    IVersioned
{
    using SafeCall for address;

    uint16 internal constant _ABI_WORD_BYTES = 32;
    // The extra byte distinguishes oversized responses from a canonical ABI word.
    uint16 internal constant _MAX_METADATA_RETURN_BYTES = _ABI_WORD_BYTES + 1;

    /// @dev Maximum revert data copied from the Burner Loans claim call.
    uint16 internal constant _MAX_RETURN_DATA_BYTES = 4;
    /// @dev Minimum supported gas retained for failure reporting and task cleanup.
    uint32 internal constant _DEFAULT_GAS_RESERVE = 100_000;
    /// @dev Gas budgeted for cursor arithmetic and a cold zero-to-nonzero cursor write.
    uint32 internal constant _CURSOR_UPDATE_GAS_BUFFER = 50_000;
    /// @dev Default minimum gas required before attempting another registered asset.
    uint32 internal constant _DEFAULT_MINIMUM_GAS_TO_ATTEMPT = 250_000;

    /// @dev Permanent Core custody authority and append-only registry. Claims execute through this policy.
    address internal immutable _CORE;

    /// @inheritdoc IBurnerLoansYieldClaimerTask
    uint32 public override executionGasLimit;
    /// @inheritdoc IBurnerLoansYieldClaimerTask
    uint32 public override minimumGasToAttempt;
    /// @inheritdoc IBurnerLoansYieldClaimerTask
    uint32 public override gasReserve;
    /// @dev Index of the first unattempted registered asset after execution pauses.
    uint256 internal _nextAssetIndex;

    /// @notice Deploys a Heart task for a same-Kernel Burner Loans policy.
    /// @dev Reverts if:
    ///      - `burnerLoans_` is zero, lacks Core/lifecycle support, or has unreadable metadata.
    ///      - `burnerLoans_` reports a Kernel different from `kernel_`.
    ///      - `executionGasLimit_` is zero.
    /// @param kernel_ Kernel shared with the Burner Loans target.
    /// @param burnerLoans_ Burner Loans policy whose registered assets are claimed.
    /// @param executionGasLimit_ Complete task self-call gas budget.
    constructor(
        Kernel kernel_,
        address burnerLoans_,
        uint32 executionGasLimit_
    ) Policy(kernel_) ReEnablerGracePeriod(LoanParameters._REENABLE_GRACE_PERIOD) {
        if (burnerLoans_ == address(0)) revert BurnerLoansYieldClaimer_InvalidCore(burnerLoans_);
        _requireCoreInterfaces(burnerLoans_);
        // Construction permits an inactive Core; enable and reEnable require readiness.
        PolicyDependency.requireSameKernel(burnerLoans_, address(kernel_));

        _CORE = burnerLoans_;
        _setExecutionGasLimit(executionGasLimit_);
        _setMinimumGasToAttempt(_DEFAULT_MINIMUM_GAS_TO_ATTEMPT);
        _setGasReserve(_DEFAULT_GAS_RESERVE);
    }

    /// @dev Reverts if:
    ///      - This policy is Kernel-inactive.
    modifier onlyActive() {
        _requireOwnPolicyActive();
        _;
    }

    /// @inheritdoc Policy
    /// @dev Reverts if:
    ///      - The installed ROLES module does not use major version 1.
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");
        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        // ROLES compatibility depends only on its major version.
        // forge-lint: disable-next-line(unused-return)
        (uint8 rolesMajor, ) = Module(address(ROLES)).VERSION();
        if (rolesMajor != 1) revert Policy_WrongModuleVersion(abi.encode([1]));
    }

    /// @inheritdoc Policy
    /// @dev This task does not call permissioned modules.
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    /// @inheritdoc IVersioned
    /// @dev Reports this implementation's interface version; does not query dependencies or alter lifecycle.
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Reverts if:
    ///      - This task is Kernel-inactive, including while locally disabled.
    ///      - The caller lacks HEART_ROLE.
    ///
    /// @dev An authorized active but disabled task returns before any registry read.
    ///      An enabled task runs its complete body in a gas-bounded external self-call.
    ///      Individual asset failures report bounded revert-data prefixes. Cleanup gas is retained;
    ///      the task resumes from its cursor when the remaining budget cannot cover another asset.
    function execute() external override onlyActive onlyRole(HEART_ROLE) {
        if (!isEnabled) return;

        (bool success, bytes memory reason) = address(this).safeCall(
            executionGasLimit,
            0,
            _MAX_RETURN_DATA_BYTES,
            abi.encodeCall(this.selfExecuteTask, ())
        );
        // The event intentionally reports only the first four bytes of bounded revert data.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (!success) emit ExecutionFailed(bytes4(reason));
    }

    /// @notice Runs the gas-bounded task body through an external self-call.
    /// @dev Reverts if:
    ///      - The gas-bounded task body was called by an account other than this contract.
    function selfExecuteTask() external {
        if (msg.sender != address(this)) revert BurnerLoansYieldClaimer_OnlySelf();
        if (!kernel.isPolicyActive(Policy(_CORE)) || !IEnabler(_CORE).isEnabled()) return;

        IBurnerLoansCore facility = IBurnerLoansCore(_CORE);
        // Take one registry length for this run. Assets appended during an external call are picked
        // up on a later run, and this tick attempts each entry in the captured registry at most once.
        uint256 assetCount = facility.getAssetCount();
        if (assetCount == 0) return;
        uint256 index = _nextAssetIndex % assetCount;
        for (uint256 attempted; attempted < assetCount; ++attempted) {
            if (gasleft() <= minimumGasToAttempt) break;
            // forge-lint: disable-next-line(calls-loop)
            address asset = facility.getAssetAt(index);
            bytes memory callData = abi.encodeCall(IBurnerLoansYieldClaim.claimYield, (asset));
            // Stop before changing the cursor when the indexed lookup has consumed the budget
            // needed to persist progress while preserving the cleanup reserve.
            if (gasleft() <= uint256(gasReserve) + _CURSOR_UPDATE_GAS_BUFFER) break;
            // Advance before the isolated call so a failing or gas-burning asset does not starve
            // later registry entries on subsequent Heart beats.
            index = (index + 1) % assetCount;
            // forge-lint: disable-next-line(costly-loop)
            _nextAssetIndex = index;
            // Measure after persisting the cursor so that storage cost cannot consume the amount
            // intentionally retained from the isolated claim call.
            uint256 availableGas = gasleft();
            (bool success, bytes memory returnData) = address(this).safeCall(
                availableGas - gasReserve,
                0,
                _MAX_RETURN_DATA_BYTES,
                callData
            );
            if (success) continue;

            // This individual claim rolled back, while the cursor write and earlier successful
            // claims remain in the outer task call. A whole-task failure still reverts that inner run.
            // Casting is safe because SafeCall caps returnData at four bytes.
            // forge-lint: disable-next-line(unsafe-typecast)
            emit YieldAssetClaimFailed(asset, bytes4(returnData));
        }
    }

    /// @inheritdoc IBurnerLoansYieldClaim
    /// @dev Reverts if:
    ///      - The claimer or Core is inactive, or either is locally disabled.
    ///      - The collateral custody is insolvent or the market is unregistered.
    ///      - The configured withdrawal mode is unsupported.
    ///      - A positive claim fails Core admission, DepositManager accounting or the mandatory output transfer.
    function claimYield(
        address asset_
    ) external override onlyActive givenEnabled returns (address, uint256) {
        (uint256 requested, bool withdrawAsShares) = _prepareYieldClaim(asset_);
        IBurnerLoansCore facilityCore = IBurnerLoansCore(_CORE);
        if (requested == 0) {
            // Report a valid zero-output result without requiring settlement authority or Payout.
            // Output-mode validation still runs so an unsupported exit is not disguised as no yield.
            IAssetManagerV1_1 manager = IAssetManagerV1_1(facilityCore.depositManager());
            manager.validateAssetWithdrawAsShares(IERC20(asset_), withdrawAsShares);
            return (address(manager.getAssetWithdrawalToken(IERC20(asset_), withdrawAsShares)), 0);
        }
        // Payout selects the current beneficiary, but yield is sent there directly by DepositManager.
        // No local payout credit is created here; a failed yield delivery reverts this asset's claim.
        return
            facilityCore.settleYield(
                asset_,
                requested,
                IBurnerLoansPayout(facilityCore.payout()).yieldRecipient()
            );
    }

    /// @notice	Validates custody and calculates the asset amount available for a yield claim.
    /// @dev Reverts if:
    ///      - This task or Core is unavailable.
    ///      - Custody is insolvent.
    ///      - The market is unregistered.
    ///      - A positive claim lacks this task's settlement role.
    ///      - A positive claim uses a DepositManager with a different Kernel or inactive membership.
    ///      - A required dependency view fails.
    ///
    /// @param	asset_	Underlying collateral token identifying the market.
    /// @return	requested	Yield request in native asset units, after the custody rounding buffer.
    /// @return	withdrawAsShares	Configured withdrawal mode for this market.
    function _prepareYieldClaim(
        address asset_
    ) private view returns (uint256 requested, bool withdrawAsShares) {
        _requireCoreReady();
        IBurnerLoansCore facilityCore = IBurnerLoansCore(_CORE);
        IBurnerLoansCore.AssetCollateralStatus memory status = LoanCustody.getAssetCollateralStatus(
            IDepositManager(facilityCore.depositManager()),
            asset_,
            address(facilityCore)
        );
        if (!status.solvent)
            revert IBurnerLoansCore.BurnerLoansCore_Insolvent(
                asset_,
                status.liabilities,
                status.assets,
                status.borrowed
            );
        (, IBurnerLoansCore.AssetConfig memory cfg, ) = LoanMarket.configuration(
            facilityCore,
            asset_
        );
        withdrawAsShares = cfg.withdrawAsShares;
        requested = LoanCustody.claimableYieldRequest(status, withdrawAsShares);
        if (requested != 0) {
            _requireRole(address(this), BL_YIELD_CLAIMER_ROLE);
            PolicyDependency.requireActive(facilityCore.depositManager(), address(kernel));
        }
    }

    /// @inheritdoc IBurnerLoansYieldClaimerTask
    /// @dev Reverts if:
    ///      - This task is Kernel-inactive, the caller holds neither ADMIN nor burner_loans_admin,
    ///        or `gasLimit_` is zero. Callable while locally disabled.
    function setExecutionGasLimit(uint32 gasLimit_) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        _setExecutionGasLimit(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimerTask
    /// @dev Reverts if:
    ///      - This task is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    ///      - The threshold does not exceed the cleanup reserve.
    ///
    /// @dev Callable while locally disabled.
    function setMinimumGasToAttempt(uint32 gasLimit_) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        _setMinimumGasToAttempt(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimerTask
    /// @dev Reverts if:
    ///      - This task is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    ///      - The reserve is below the supported minimum.
    ///      - The reserve reaches or exceeds the attempt threshold.
    ///
    /// @dev Callable while locally disabled.
    function setGasReserve(uint32 gasLimit_) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        _setGasReserve(gasLimit_);
    }

    /// @inheritdoc IBurnerLoansYieldClaimerTask
    /// @dev Reverts if:
    ///      - This task is Kernel-inactive.
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    ///      - A nonzero index is outside the live asset registry.
    ///
    /// @dev Callable while locally disabled.
    function setNextAssetIndex(uint256 index_) external override {
        _requireOwnPolicyActive();

        _requireAdminOrBurnerLoansAdmin();
        if (index_ == 0) {
            if (_nextAssetIndex == 0) return;
            _nextAssetIndex = 0;
            emit NextAssetIndexSet(0);
            return;
        }
        uint256 assetCount = IBurnerLoansCore(_CORE).getAssetCount();
        if (index_ >= assetCount) {
            revert BurnerLoansYieldClaimer_InvalidAssetIndex(index_, assetCount);
        }
        if (index_ == _nextAssetIndex) return;
        _nextAssetIndex = index_;
        emit NextAssetIndexSet(index_);
    }

    /// @inheritdoc IBurnerLoansCoreBound
    /// @dev Returns the stored binding without probing Core or its lifecycle.
    function core() external view override returns (address) {
        return _CORE;
    }

    /// @inheritdoc IBurnerLoansYieldClaimerTask
    /// @dev Reads without state changes; errors from dependency views propagate.
    function nextAssetIndex() external view override returns (uint256) {
        return _nextAssetIndex;
    }

    /// @notice Authorizes a re-enable transition during the grace period.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    function _authorizeReEnable() internal view override {
        _requireAdminOrBurnerLoansAdmin();
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

    /// @dev Revalidates the constructor-bound Burner Loans policy before operational enablement.
    function _beforeEnable(bytes calldata data_) internal view override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();

        _requireBurnerLoansPolicyActive();
    }

    /// @dev Preserves the grace-period gate and revalidates Burner Loans before re-enabling.
    function _beforeReEnable() internal override {
        super._beforeReEnable();
        _requireBurnerLoansPolicyActive();
    }

    /// @dev Reverts if:
    ///      - The immutable Core policy is inactive in this Kernel.
    function _requireBurnerLoansPolicyActive() internal view {
        _requireCoreReady();
        _requireRole(address(this), BL_YIELD_CLAIMER_ROLE);
    }

    /// @dev Compatibility is checked before readiness; malformed metadata is owned by this consumer.
    function _requireCoreReady() internal view {
        _requireOwnPolicyActive();
        _requireCoreInterfaces(_CORE);
        PolicyDependency.requireActiveAndEnabled(_CORE, address(kernel));
    }

    /// @dev Reverts if:
    ///      - The candidate lacks canonical Core interface support.
    ///
    /// @dev Callers separately check Kernel binding and readiness.
    function _requireCoreInterfaces(address candidate_) private view {
        bytes4[] memory ids = new bytes4[](2);
        ids[0] = type(IBurnerLoansCore).interfaceId;
        ids[1] = type(IEnabler).interfaceId;
        if (!ERC165Checker.supportsAllInterfaces(candidate_, ids))
            revert BurnerLoansYieldClaimer_InvalidCore(candidate_);
        // ERC165Checker accepts any nonzero response word. Required ABI booleans must be
        // canonical so malformed candidate metadata gets this consumer's dependency error.
        if (
            _readCoreMetadataWord(
                candidate_,
                abi.encodeCall(IERC165.supportsInterface, (ids[0]))
            ) !=
            1 ||
            _readCoreMetadataWord(
                candidate_,
                abi.encodeCall(IERC165.supportsInterface, (ids[1]))
            ) !=
            1
        ) revert BurnerLoansYieldClaimer_InvalidCore(candidate_);
    }

    /// @notice Reads exactly one ABI word from a bounded Core metadata call.
    /// @dev Reverts if:
    ///      - The metadata call fails.
    ///      - The metadata result is not exactly one ABI word.
    ///
    /// @param candidate_ Core candidate supplying the metadata.
    /// @param data_ ABI-encoded metadata getter call.
    /// @return uint256 Canonical-length metadata word; callers validate its value.
    function _readCoreMetadataWord(
        address candidate_,
        bytes memory data_
    ) private view returns (uint256) {
        (bool success, bytes memory result) = SafeCall.safeStaticCall(
            candidate_,
            gasleft(),
            _MAX_METADATA_RETURN_BYTES,
            data_
        );
        if (!success || result.length != _ABI_WORD_BYTES)
            revert BurnerLoansYieldClaimer_InvalidCore(candidate_);
        return abi.decode(result, (uint256));
    }

    /// @notice Requires governance ADMIN or delegated Burner Loans administration.
    /// @dev Reverts if:
    ///      - The caller holds neither ADMIN nor burner_loans_admin.
    function _requireAdminOrBurnerLoansAdmin() internal view {
        _requireAuthorized(!_isAdmin(msg.sender) && !_hasRole(msg.sender, BURNER_LOANS_ADMIN_ROLE));
    }

    /// @inheritdoc IPeriodicTask
    /// @dev Pure interface identifiers or inherited lifecycle identifiers only; no dependency calls.
    function supportsInterface(
        bytes4 interfaceId_
    ) public view override(EnablerV2, ReEnablerGracePeriod, IPeriodicTask) returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaim).interfaceId ||
            interfaceId_ == type(IPeriodicTask).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaimerTask).interfaceId ||
            interfaceId_ == type(IVersioned).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @notice Stores and emits a changed nonzero complete-task gas limit.
    /// @dev Reverts if:
    ///      - The configured gas limit for one complete task execution is zero.
    /// @param gasLimit_ Gas budget in EVM gas units.
    function _setExecutionGasLimit(uint32 gasLimit_) private {
        if (gasLimit_ == 0) revert BurnerLoansYieldClaimer_InvalidExecutionGasLimit();
        if (gasLimit_ == executionGasLimit) return;
        executionGasLimit = gasLimit_;
        emit ExecutionGasLimitSet(gasLimit_);
    }

    /// @dev Stores a changed attempt threshold that strictly exceeds the cleanup reserve.
    /// @param gasLimit_ Gas budget in EVM gas units.
    function _setMinimumGasToAttempt(uint32 gasLimit_) private {
        if (gasLimit_ <= gasReserve) {
            revert BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt();
        }
        if (gasLimit_ == minimumGasToAttempt) return;
        minimumGasToAttempt = gasLimit_;
        emit MinimumGasToAttemptSet(gasLimit_);
    }

    /// @dev Stores a changed supported cleanup reserve below the attempt threshold.
    /// @param gasLimit_ Gas budget in EVM gas units.
    function _setGasReserve(uint32 gasLimit_) private {
        if (gasLimit_ < _DEFAULT_GAS_RESERVE || gasLimit_ >= minimumGasToAttempt) {
            revert BurnerLoansYieldClaimer_InvalidGasReserve();
        }
        if (gasLimit_ == gasReserve) return;
        gasReserve = gasLimit_;
        emit GasReserveSet(gasLimit_);
    }

    /// @notice Quotes direct DepositManager yield output and Custody-selected recipient.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @return result Direct yield token/amount, asset request and recipient (zero for a zero request).
    function previewClaimYield(
        address asset_
    )
        external
        view
        override
        onlyActive
        givenEnabled
        returns (IBurnerLoansYieldClaim.ClaimYieldPreview memory result)
    {
        bool withdrawAsShares;
        (result.requestedAssetAmount, withdrawAsShares) = _prepareYieldClaim(asset_);
        IBurnerLoansCore facilityCore = IBurnerLoansCore(_CORE);
        (result.tokenOut, result.amountOut) = LoanCustody.previewWithdrawAmount(
            IDepositManager(facilityCore.depositManager()),
            asset_,
            result.requestedAssetAmount,
            withdrawAsShares
        );
        // Zero requests make no delivery and, like claimYield, do not need Payout.
        if (result.requestedAssetAmount != 0)
            result.recipient = IBurnerLoansPayout(facilityCore.payout()).yieldRecipient();
        result.executable = true; // Preparation rejects insolvent custody.
    }

    /// @notice Validates a local pause payload without requiring downstream readiness.
    /// @dev Reverts if:
    ///      - Data is nonempty; Kernel inactivity does not prevent disable.
    function _beforeDisable(bytes calldata data_) internal pure override {
        if (data_.length != 0) revert IBurnerLoansErrors.BurnerLoans_InvalidEnablerData();
    }

    /// @notice Applies checked narrowing to the product's inclusive grace deadline.
    /// @dev Reverts if:
    ///      - The deadline overflows uint48 or the grace window has expired.
    function _requireGrace() internal view override {
        uint48 deadline = SafeCast.toUint48(uint256(lastTransitionAt) + gracePeriod);
        if (_getBlockTimestamp() > deadline) revert GracePeriod_Expired(deadline);
    }

    /// @notice Checks this policy's own Kernel membership before mutation/activation.
    /// @dev Reverts if:
    ///      - This subject policy is inactive.
    function _requireOwnPolicyActive() private view {
        if (!kernel.isPolicyActive(this))
            revert IBurnerLoansErrors.BurnerLoans_PolicyNotActive(address(this));
    }
}
