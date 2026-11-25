// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.34;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IDaiUsdsMigrator} from "src/interfaces/maker-dao/IDaiUsdsMigrator.sol";
import {IERC3156FlashBorrower} from "src/interfaces/maker-dao/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "src/interfaces/maker-dao/IERC3156FlashLender.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {TransientSlot} from "@openzeppelin-5.7.0/utils/TransientSlot.sol";
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin-5.7.0/utils/math/Math.sol";
import {Memory} from "@openzeppelin-5.7.0/utils/Memory.sol";
import {SafeCallDecoder} from "src/libraries/SafeCallDecoder.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_ACTION_DEPOSIT, BL_ACTION_BORROW, BL_ACTION_WITHDRAW, BL_ACTION_EXTEND} from "src/policies/burnerloans/libraries/LoanActions.sol";

// Contracts
import {Ownable} from "@openzeppelin-5.7.0/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin-5.7.0/access/Ownable2Step.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {EnablerV2} from "src/bases/EnablerV2.sol";

/// @notice Executes Burner Loans operations for the submitting account.
/// @dev The owner controls whether execution is enabled. Underlying lending admission remains
///      authoritative. Inexact-transfer and rebasing tokens are unsupported.
contract BurnerLoansComposites is
    IBurnerLoansComposites,
    IERC3156FlashBorrower,
    IERC165,
    IVersioned,
    Ownable2Step,
    ReentrancyGuardTransient,
    EnablerV2
{
    using SafeERC20 for IERC20;
    using SafeERC20Exact for IERC20;
    using Math for uint256;
    using TransientSlot for *;

    IBurnerLoansCore internal immutable _CORE;
    IBurnerLoansCollateral internal immutable _COLLATERAL;
    IBurnerLoansDebt internal immutable _DEBT;
    IERC20 internal immutable _OHM;
    IDaiUsdsMigrator internal immutable _MIGRATOR;
    IBurnerLoansSwapAdapter internal immutable _SWAP_ADAPTER;
    IERC3156FlashLender internal immutable _FLASH_LENDER;
    address internal immutable _DAI;
    address internal immutable _USDS;

    enum FlashPhase {
        Idle,
        AwaitingCallback,
        InCallback,
        AwaitingRepayment
    }

    bytes32 internal constant _FLASH_PHASE_SLOT = keccak256("BurnerLoansComposites.flashPhase.v1");
    bytes32 internal constant _FLASH_COMMITMENT_SLOT =
        keccak256("BurnerLoansComposites.flashCommitment.v1");
    bytes32 internal constant _FLASH_DAI_BALANCE_SLOT =
        keccak256("BurnerLoansComposites.flashDaiBalance.v1");
    bytes32 internal constant _FLASH_RESULT_COUNT_SLOT =
        keccak256("BurnerLoansComposites.flashResultWordCount.v1");

    bytes32 internal constant _FLASH_RESULT_SLOT =
        keccak256("BurnerLoansComposites.flashResults.v1");
    bytes32 internal constant _FLASH_CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 internal constant _ABI_WORD_BYTES = 32;

    /// @notice Token balance protected from spending by the current execution.
    /// @param token Token included in the prepared execution.
    /// @param startingBalance Raw balance held before grant acceptance or funding.
    struct TokenBalance {
        address token;
        uint256 startingBalance;
    }

    /// @dev The outer call commits this context before requesting the loan. The callback uses
    ///      its stored account for every action. The lender supplies only the fee.
    struct FlashBatch {
        address account;
        uint256 daiBefore;
        FlashLoan loan;
        uint48 deadline;
        TokenBalance[] balances;
        Operation[] operations;
    }

    /// @notice Caller settlement requirement with a baseline that excludes explicit wallet funding.
    /// @param token Required output token.
    /// @param minimum Minimum returned amount in raw token units.
    /// @param retainedBalance Caller entry balance less the listed funding amount for this token.
    struct OutputBalance {
        address token;
        uint256 minimum;
        uint256 retainedBalance;
    }

    /// @notice Original lending authority that must remain valid throughout execution.
    /// @param auth Auth selected by Core, or zero for execution that needs no grant.
    /// @param epoch Core's Auth installation epoch.
    /// @param actions Union of the lending action bits required by the operations.
    /// @param stamps Original authorization stamp for each of the four lending action bits.
    struct Authority {
        address auth;
        uint256 epoch;
        uint8 actions;
        bytes32[4] stamps;
    }

    /// @notice Balance snapshots and lending authority prepared before any execution effects.
    /// @param balances Tracked tokens and their protected starting balances.
    /// @param authority Auth installation and required actions. Stamps are captured before funding.
    /// @param outputs Caller output requirements with their retained-wallet baselines.
    struct PreparedExecution {
        TokenBalance[] balances;
        Authority authority;
        OutputBalance[] outputs;
    }

    /// @notice Binds a compatible Core and its collateral/debt action contracts and starts disabled.
    /// @dev Reverts if:
    ///      - The owner is the zero address.
    ///      - Core lacks the required interface.
    ///      - Collateral or Debt lacks a required interface, or its Core getter fails, returns
    ///        malformed data or reports another Core.
    ///      - Core's OHM getter fails, returns malformed data or returns an address with no code.
    ///      - Either migrator asset getter fails or returns malformed data.
    ///      - The migrator returns the same token for DAI and USDS.
    ///      - Either migrator asset has no code.
    ///      - The swap adapter lacks the required interface.
    ///      - The flash lender has no code.
    /// @param core_ Core that settles every lending operation.
    /// @param collateral_ Collateral action bound to core_.
    /// @param debt_ Debt action bound to core_.
    /// @param owner_ Initial owner authorized to enable or disable execution.
    /// @param integrations_ Required immutable exchange and flash services.
    constructor(
        address core_,
        address collateral_,
        address debt_,
        address owner_,
        Integrations memory integrations_
    ) Ownable(owner_) {
        if (!ERC165Checker.supportsInterface(core_, type(IBurnerLoansCore).interfaceId))
            revert BurnerLoansComposites_InvalidDependency(core_);
        _validateAction(collateral_, type(IBurnerLoansCollateral).interfaceId, core_);
        _validateAction(debt_, type(IBurnerLoansDebt).interfaceId, core_);
        address ohm = _readAddress(core_, IBurnerLoansCore.ohm.selector);
        if (ohm.code.length == 0) revert BurnerLoansComposites_InvalidDependency(core_);
        _CORE = IBurnerLoansCore(core_);
        _COLLATERAL = IBurnerLoansCollateral(collateral_);
        _DEBT = IBurnerLoansDebt(debt_);
        _OHM = IERC20(ohm);
        address dai = _readAddress(integrations_.migrator, IDaiUsdsMigrator.dai.selector);
        address usds = _readAddress(integrations_.migrator, IDaiUsdsMigrator.usds.selector);
        if (dai == usds || dai.code.length == 0 || usds.code.length == 0)
            revert BurnerLoansComposites_InvalidDependency(integrations_.migrator);
        if (
            !ERC165Checker.supportsInterface(
                integrations_.swapAdapter,
                type(IBurnerLoansSwapAdapter).interfaceId
            )
        ) revert BurnerLoansComposites_InvalidDependency(integrations_.swapAdapter);
        if (integrations_.flashLender.code.length == 0)
            revert BurnerLoansComposites_InvalidDependency(integrations_.flashLender);
        _DAI = dai;
        _USDS = usds;
        _MIGRATOR = IDaiUsdsMigrator(integrations_.migrator);
        _SWAP_ADAPTER = IBurnerLoansSwapAdapter(integrations_.swapAdapter);
        _FLASH_LENDER = IERC3156FlashLender(integrations_.flashLender);
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - The caller is not the owner.
    ///      - An execution is in progress.
    ///      - The payload is nonempty.
    function _authorizeEnable(
        bytes calldata data_
    ) internal view override onlyOwner nonReentrantView {
        _checkEnablerData(data_);
    }

    /// @inheritdoc EnablerV2
    /// @dev Reverts if:
    ///      - The caller is not the owner.
    ///      - An execution is in progress.
    ///      - The payload is nonempty.
    function _authorizeDisable(
        bytes calldata data_
    ) internal view override onlyOwner nonReentrantView {
        _checkEnablerData(data_);
    }

    function _checkEnablerData(bytes calldata data_) private pure {
        if (data_.length != 0) revert BurnerLoansComposites_InvalidEnablerData();
    }

    /// @inheritdoc IBurnerLoansComposites
    /// @dev Captures all token baselines before effects. Positions and wallet inputs belong to msg.sender.
    ///      Grant-dependent operations require the caller to have already granted this executor
    ///      authority in Auth. A temporary grant must have been installed in the same transaction;
    ///      a reusable grant may have been approved earlier. Repayment alone requires no grant.
    ///      Reverts if:
    ///      - Another execution is already executing, including during funding or refunds.
    ///      - The owner has not enabled the executor.
    ///      - The operation list is empty.
    ///      - The batch deadline has passed.
    ///      - Funding entries duplicate a token, reference an invalid token or have malformed inputs.
    ///      - Exchange inputs are invalid or a flash loan
    ///        violates admission, continuation or repayment requirements.
    ///      - Final output entries duplicate a token or reference an invalid token.
    ///      - Auth rejects the existing lending authority, including its expiry or constraints.
    ///      - Mandatory token collection fails or does not deliver the exact input amount.
    ///      - An operation lacks available funds, consumes protected starting funds or fails downstream.
    ///      - A withdrawal returns an unexpected token or less than the required output minimum.
    ///      - A mandatory refund fails or any tracked token ends above or below its protected balance.
    ///      - The selected Auth/installation epoch or original lending authority changes during effects.
    ///      - The caller's final returned tokens do not satisfy every declared output requirement.
    function execute(
        Funding[] calldata funding_,
        Operation[] calldata operations_,
        Output[] calldata outputs_,
        FlashLoan calldata flash_,
        uint48 deadline_
    ) external override nonReentrant givenEnabled returns (bytes[] memory results) {
        PreparedExecution memory prepared = _prepareExecution(
            funding_,
            operations_,
            outputs_,
            flash_.amount != 0,
            false,
            deadline_
        );
        return _executePrepared(funding_, operations_, prepared, flash_, deadline_);
    }

    /// @inheritdoc IBurnerLoansComposites
    /// @dev Uses the same funding, operation, refund and reentrancy boundaries as execute.
    ///      Reverts if:
    ///      - Any execute admission, operation, funding or settlement condition fails.
    ///      - The supplied grant names another account or operator.
    ///      - Auth rejects the complete grant, its signature data or its signature.
    ///      - Auth's selected installation changes during acceptance or subsequent effects.
    function executeWithGrant(
        Funding[] calldata funding_,
        Operation[] calldata operations_,
        Output[] calldata outputs_,
        FlashLoan calldata flash_,
        uint48 deadline_,
        SignedGrant calldata signedGrant_
    ) external override nonReentrant givenEnabled returns (bytes[] memory results) {
        PreparedExecution memory prepared = _prepareExecution(
            funding_,
            operations_,
            outputs_,
            flash_.amount != 0,
            true,
            deadline_
        );
        // Auth authenticates the named operator; only this entry can bind the outer submitting account.
        if (signedGrant_.grant.account != msg.sender) revert BurnerLoansComposites_InvalidGrant();
        IOperatorAuth(prepared.authority.auth).acceptGrant(
            signedGrant_.grant,
            signedGrant_.signatureData,
            signedGrant_.signature
        );
        _validateInstallation(prepared.authority);
        // Even a repayment-only batch must preserve the grant it explicitly accepted.
        if (prepared.authority.actions == 0)
            prepared.authority.actions = signedGrant_.grant.actions;
        return _executePrepared(funding_, operations_, prepared, flash_, deadline_);
    }

    /// @notice Executes and settles a prepared operation list for the submitting account.
    /// @dev Both guarded entries use this path. Any failed transfer, operation or final authority
    ///      check rolls back funding, earlier operations and any signed grant acceptance.
    /// @param funding_ Explicit wallet inputs collected once.
    /// @param operations_ Operations executed in caller-supplied order.
    /// @param prepared_ Protected balances, selected authority and caller output requirements.
    /// @param flash_ Optional flash financing for the operation list.
    /// @param deadline_ Inclusive batch deadline in seconds.
    /// @return results ABI-encoded downstream results in operation order.
    function _executePrepared(
        Funding[] calldata funding_,
        Operation[] calldata operations_,
        PreparedExecution memory prepared_,
        FlashLoan calldata flash_,
        uint48 deadline_
    ) private returns (bytes[] memory results) {
        address account = msg.sender;
        _captureAuthority(account, prepared_.authority);
        _collectFunding(account, funding_);
        results = flash_.amount == 0
            ? _runOperations(account, operations_, prepared_.balances, deadline_, 0)
            : _runFlash(account, operations_, prepared_.balances, flash_, deadline_);
        _refund(account, prepared_.balances);
        // Refunds can invoke callbacks, so validate the original authority after they complete.
        _validateAuthority(account, prepared_.authority);
        _validateOutputs(prepared_.outputs);
        emit OperationsExecuted(account, operations_.length);
    }

    // These caller-sized batches intentionally call fixed lending dependencies and token contracts.
    // Each invalid entry must revert the entire execution; the entry guard remains held throughout.
    // forge-lint: disable-start(calls-loop,require-revert-in-loop)
    /// @notice Collects the caller's explicit wallet inputs exactly once.
    /// @dev Zero amounts trigger no transfer. Operation outputs can fund later steps.
    ///      Reverts if:
    ///      - A mandatory incoming transfer fails.
    ///      - An incoming transfer delivers less or more than requested.
    /// @param account_ Submitting account that supplies every wallet input.
    /// @param funding_ Validated unique token inputs and raw amounts.
    function _collectFunding(address account_, Funding[] calldata funding_) private {
        for (uint256 i; i < funding_.length; ++i) {
            if (funding_[i].amount != 0)
                IERC20(funding_[i].token).safeTransferFromExact(
                    account_,
                    address(this),
                    funding_[i].amount
                );
        }
    }

    /// @notice Dispatches every operation once in order and records its result.
    /// @dev Reverts if:
    ///      - Any operation fails.
    /// @param account_ Submitting account that owns the lending positions.
    /// @param operations_ Ordered typed operations.
    /// @param balances_ Complete token set and protected starting balances.
    /// @param deadline_ Inclusive batch deadline passed to the swap adapter.
    /// @param flashRepaymentAmount_ Flash principal plus the actual fee in raw DAI units,
    ///        or zero when the batch uses no flash loan.
    /// @return results ABI-encoded downstream results in operation order.
    function _runOperations(
        address account_,
        Operation[] memory operations_,
        TokenBalance[] memory balances_,
        uint48 deadline_,
        uint256 flashRepaymentAmount_
    ) private returns (bytes[] memory results) {
        results = new bytes[](operations_.length);
        for (uint256 i; i < operations_.length; ++i) {
            results[i] = _dispatch(
                account_,
                operations_[i],
                balances_,
                deadline_,
                flashRepaymentAmount_
            );
            emit OperationExecuted(account_, i, operations_[i].kind, results[i]);
        }
    }

    /// @dev Commits the request and settles the lender's debit before allowing refunds.
    ///      Reverts if:
    ///      - The requested principal exceeds lender capacity.
    ///      - The lender reverts, returns false, or fails to complete the callback.
    ///      - The lender's collection does not debit the exact principal and fee.
    function _runFlash(
        address account_,
        Operation[] calldata operations_,
        TokenBalance[] memory balances_,
        FlashLoan calldata loan_,
        uint48 deadline_
    ) private returns (bytes[] memory results) {
        uint256 capacity = _FLASH_LENDER.maxFlashLoan(_DAI);
        if (loan_.amount > capacity)
            revert BurnerLoansComposites_InvalidFlashAmount(loan_.amount, capacity);
        bytes memory data = abi.encode(
            FlashBatch({
                account: account_,
                daiBefore: IERC20(_DAI).balanceOf(address(this)),
                loan: loan_,
                deadline: deadline_,
                balances: balances_,
                operations: operations_
            })
        );
        _FLASH_COMMITMENT_SLOT.asBytes32().tstore(keccak256(data));
        _FLASH_PHASE_SLOT.asUint256().tstore(uint256(FlashPhase.AwaitingCallback));
        // The lender transfers DAI, runs the callback and collects repayment before returning.
        bool completed = _FLASH_LENDER.flashLoan(this, _DAI, loan_.amount, data);
        if (
            !completed ||
            _FLASH_PHASE_SLOT.asUint256().tload() != uint256(FlashPhase.AwaitingRepayment)
        ) revert BurnerLoansComposites_IncompleteFlashLoan();
        // Repayment must debit the exact due amount from the captured balance.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        if (IERC20(_DAI).balanceOf(address(this)) != _FLASH_DAI_BALANCE_SLOT.asUint256().tload())
            revert BurnerLoansComposites_InexactFlashRepayment();
        IERC20(_DAI).forceApprove(address(_FLASH_LENDER), 0);
        uint256 fee;
        (results, fee) = _readFlashResults();
        _FLASH_RESULT_COUNT_SLOT.asUint256().tstore(0);
        _FLASH_DAI_BALANCE_SLOT.asUint256().tstore(0);
        _FLASH_COMMITMENT_SLOT.asBytes32().tstore(bytes32(0));
        _FLASH_PHASE_SLOT.asUint256().tstore(uint256(FlashPhase.Idle));
        emit FlashLoanSettled(account_, loan_.amount, fee);
    }

    /// @inheritdoc IERC3156FlashBorrower
    /// @dev Only the configured lender may continue the committed active request. The outer
    ///      entry lock remains held. The phase advances before any external continuation call.
    ///      Reverts if:
    ///      - The callback phase, lender, initiator, token, data, or principal does not match the request.
    ///      - The fee exceeds the caller's cap.
    ///      - Principal plus fee exceeds uint256.
    ///      - The received principal differs from the committed amount.
    ///      - An operation fails.
    ///      - Spendable DAI is below the total repayment.
    ///      - The lender approval fails.
    function onFlashLoan(
        address initiator_,
        address token_,
        uint256 amount_,
        uint256 fee_,
        bytes calldata data_
    ) external override returns (bytes32) {
        if (
            _FLASH_PHASE_SLOT.asUint256().tload() != uint256(FlashPhase.AwaitingCallback) ||
            msg.sender != address(_FLASH_LENDER) ||
            initiator_ != address(this) ||
            token_ != _DAI ||
            keccak256(data_) != _FLASH_COMMITMENT_SLOT.asBytes32().tload()
        ) revert BurnerLoansComposites_InvalidFlashCallback();
        FlashBatch memory flashBatch = abi.decode(data_, (FlashBatch));
        if (amount_ != flashBatch.loan.amount) revert BurnerLoansComposites_InvalidFlashCallback();
        if (fee_ > flashBatch.loan.maxFee)
            revert BurnerLoansComposites_FlashFeeTooHigh(flashBatch.loan.maxFee, fee_);
        if (fee_ > type(uint256).max - amount_)
            revert BurnerLoansComposites_FlashRepaymentOverflow();
        _FLASH_PHASE_SLOT.asUint256().tstore(uint256(FlashPhase.InCallback));
        uint256 current = IERC20(_DAI).balanceOf(address(this));
        if (current < flashBatch.daiBefore || current - flashBatch.daiBefore != amount_)
            revert BurnerLoansComposites_InexactFlashReceipt();

        uint256 flashRepaymentAmount = amount_ + fee_;
        _storeFlashResults(
            _runOperations(
                flashBatch.account,
                flashBatch.operations,
                flashBatch.balances,
                flashBatch.deadline,
                flashRepaymentAmount
            ),
            fee_
        );
        _FLASH_DAI_BALANCE_SLOT.asUint256().tstore(
            _balanceAfterSpend(flashBatch.balances, _DAI, flashRepaymentAmount)
        );
        IERC20(_DAI).forceApprove(address(_FLASH_LENDER), flashRepaymentAmount);
        _FLASH_PHASE_SLOT.asUint256().tstore(uint256(FlashPhase.AwaitingRepayment));
        return _FLASH_CALLBACK_SUCCESS;
    }

    /// @dev ERC-3156 returns only a magic value. Save the operation results for the outer entry.
    function _storeFlashResults(bytes[] memory results_, uint256 fee_) private {
        Memory.Slice encoded = Memory.asSlice(abi.encode(results_, fee_));
        uint256 count = Memory.length(encoded) / _ABI_WORD_BYTES;
        uint256 firstSlot = uint256(_FLASH_RESULT_SLOT);
        _FLASH_RESULT_COUNT_SLOT.asUint256().tstore(count);
        // ABI encoding is word aligned. Each callback overwrites the words in its range.
        for (uint256 i; i < count; ++i) {
            bytes32(firstSlot + i).asBytes32().tstore(Memory.load(encoded, i * _ABI_WORD_BYTES));
        }
    }

    /// @dev Reads only the words saved by the authenticated callback for the active execution.
    function _readFlashResults() private view returns (bytes[] memory, uint256) {
        bytes32[] memory words = new bytes32[](_FLASH_RESULT_COUNT_SLOT.asUint256().tload());
        uint256 firstSlot = uint256(_FLASH_RESULT_SLOT);
        for (uint256 i; i < words.length; ++i) {
            words[i] = bytes32(firstSlot + i).asBytes32().tload();
        }
        return abi.decode(abi.encodePacked(words), (bytes[], uint256));
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 id_) public view override(IERC165, EnablerV2) returns (bool) {
        return
            id_ == type(IBurnerLoansComposites).interfaceId ||
            id_ == type(IERC3156FlashBorrower).interfaceId ||
            id_ == type(IVersioned).interfaceId ||
            super.supportsInterface(id_);
    }

    /// @inheritdoc IBurnerLoansComposites
    /// @dev Reverts if:
    ///      - A guarded operation is in progress.
    ///      - The caller is not the owner.
    ///      - The token address has no code.
    ///      - The token balance cannot be read or the transfer fails.
    function rescue(address token_) external override nonReentrant onlyOwner {
        if (token_.code.length == 0) revert BurnerLoansComposites_InvalidToken(token_);
        IERC20 token = IERC20(token_);
        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) return;
        address recipient = owner();
        token.safeTransfer(recipient, amount);
        emit TokenRescued(token_, recipient, amount);
    }

    /// @notice Derives the complete token set and required lending action mask.
    /// @dev All balance reads precede grant acceptance and token transfers.
    ///      Reverts if:
    ///      - A funding token appears more than once.
    ///      - A tracked token is invalid.
    ///      - An operation kind, payload, or exchange parameter is invalid.
    /// @param funding_ Unique wallet input tokens and raw amounts.
    /// @param operations_ Typed operations whose input/output tokens must be tracked.
    /// @param hasFlash_ Whether the batch requests a nonzero DAI flash loan.
    /// @return balances Tracked tokens and their protected starting balances.
    /// @return actions Union of grant-dependent action bits; repayment adds no bit.
    function _prepare(
        Funding[] calldata funding_,
        Operation[] calldata operations_,
        bool hasFlash_
    ) private view returns (TokenBalance[] memory balances, uint8 actions) {
        uint256 trackedTokenCount;
        (address[][] memory intermediates, uint256 intermediateCount) = _swapIntermediates(
            operations_
        );
        // Operations use up to two endpoints plus any intermediates reported by the adapter.
        balances = new TokenBalance[](
            funding_.length + operations_.length * 2 + intermediateCount + (hasFlash_ ? 1 : 0)
        );
        if (hasFlash_) trackedTokenCount = _snapshotTokenBalance(balances, trackedTokenCount, _DAI);
        for (uint256 i; i < funding_.length; ++i) {
            for (uint256 j; j < i; ++j) {
                if (funding_[j].token == funding_[i].token)
                    revert BurnerLoansComposites_DuplicateFunding(funding_[i].token);
            }
            trackedTokenCount = _snapshotTokenBalance(
                balances,
                trackedTokenCount,
                funding_[i].token
            );
        }
        for (uint256 i; i < operations_.length; ++i) {
            uint8 operationAction;
            (trackedTokenCount, operationAction) = _prepareOperation(
                operations_[i],
                balances,
                trackedTokenCount,
                hasFlash_ && i + 1 == operations_.length
            );
            actions |= operationAction;
            address[] memory tokens = intermediates[i];
            for (uint256 j; j < tokens.length; ++j) {
                trackedTokenCount = _snapshotTokenBalance(balances, trackedTokenCount, tokens[j]);
            }
        }
        TokenBalance[] memory tracked = new TokenBalance[](trackedTokenCount);
        for (uint256 i; i < trackedTokenCount; ++i) {
            tracked[i] = balances[i];
        }
        return (tracked, actions);
    }

    /// @dev Decodes an operation, snapshots its endpoint tokens, and returns its grant action bit.
    function _prepareOperation(
        Operation calldata operation_,
        TokenBalance[] memory balances_,
        uint256 count_,
        bool canTargetRepayment_
    ) private view returns (uint256 count, uint8 action) {
        OperationKind kind = operation_.kind;
        address token;
        if (kind == OperationKind.Deposit) {
            token = abi.decode(operation_.data, (Deposit)).asset;
            action = BL_ACTION_DEPOSIT;
        } else if (kind == OperationKind.Borrow) {
            token = abi.decode(operation_.data, (Borrow)).asset;
            action = BL_ACTION_BORROW;
        } else if (kind == OperationKind.Repay) {
            // Decode here as well so malformed payloads fail before collecting inputs.
            abi.decode(operation_.data, (Repay));
            token = address(_OHM);
        } else if (kind == OperationKind.Withdraw) {
            token = abi.decode(operation_.data, (Withdraw)).tokenOut;
            action = BL_ACTION_WITHDRAW;
        } else if (kind == OperationKind.Extend) {
            token = abi.decode(operation_.data, (Extend)).asset;
            action = BL_ACTION_EXTEND;
        } else {
            (address tokenIn, address tokenOut) = _exchangeTokens(operation_, canTargetRepayment_);
            count_ = _snapshotTokenBalance(balances_, count_, tokenIn);
            return (_snapshotTokenBalance(balances_, count_, tokenOut), 0);
        }

        count = _snapshotTokenBalance(balances_, count_, token);
        if (kind == OperationKind.Borrow) {
            count = _snapshotTokenBalance(balances_, count, address(_OHM));
        }
    }

    /// @dev Validates exchange parameters before their endpoint balances are read.
    function _exchangeTokens(
        Operation calldata operation_,
        bool canTargetRepayment_
    ) private view returns (address, address) {
        if (operation_.kind == OperationKind.ConvertDaiUsds) {
            ConvertDaiUsds memory p = abi.decode(operation_.data, (ConvertDaiUsds));
            _validateExactInputExchange(p.tokenIn, p.tokenOut, p.amountIn, p.minAmountOut);
            if (
                !((p.tokenIn == _DAI && p.tokenOut == _USDS) ||
                    (p.tokenIn == _USDS && p.tokenOut == _DAI))
            ) revert BurnerLoansComposites_InvalidExchangePair(p.tokenIn, p.tokenOut);
            return (p.tokenIn, p.tokenOut);
        }
        if (operation_.kind == OperationKind.SwapExactInput) {
            SwapExactInput memory p = abi.decode(operation_.data, (SwapExactInput));
            _validateExactInputExchange(p.tokenIn, p.tokenOut, p.amountIn, p.minAmountOut);
            return (p.tokenIn, p.tokenOut);
        }
        if (operation_.kind == OperationKind.SwapExactOutput) {
            SwapExactOutput memory p = abi.decode(operation_.data, (SwapExactOutput));
            _validateExactOutputExchange(p, canTargetRepayment_);
            return (p.tokenIn, p.tokenOut);
        }
        revert BurnerLoansComposites_UnsupportedOperation(operation_.kind);
    }

    /// @notice Discovers route tokens before funding so their starting balances can be protected.
    /// @param operations_ Ordered batch operations.
    /// @return tokens Intermediate token addresses indexed by operation.
    /// @return count Total number of intermediate positions across the batch.
    function _swapIntermediates(
        Operation[] calldata operations_
    ) private view returns (address[][] memory tokens, uint256 count) {
        tokens = new address[][](operations_.length);
        for (uint256 i; i < operations_.length; ++i) {
            Operation calldata operation = operations_[i];
            if (operation.kind == OperationKind.SwapExactInput) {
                tokens[i] = _SWAP_ADAPTER.intermediateTokens(
                    abi.decode(operation.data, (SwapExactInput)).route
                );
            } else if (operation.kind == OperationKind.SwapExactOutput) {
                tokens[i] = _SWAP_ADAPTER.intermediateTokens(
                    abi.decode(operation.data, (SwapExactOutput)).route
                );
            }
            count += tokens[i].length;
        }
    }

    /// @notice Captures each required caller balance before accepting a grant or collecting tokens.
    /// @dev Subtracts explicit funding from the wallet baseline so returning unused inputs counts
    ///      without including existing holdings.
    ///      An unfundable wallet input still fails mandatory collection; clamping avoids underflow
    ///      during preparation. Amounts and baselines retain each token's raw decimal scale.
    ///      Reverts if:
    ///      - An output token is invalid.
    ///      - An output token appears more than once.
    /// @param funding_ Validated unique wallet inputs.
    /// @param outputs_ Unique final token minima; an empty list is valid.
    /// @return balances Caller output requirements with their retained-wallet baselines.
    function _prepareOutputs(
        Funding[] calldata funding_,
        Output[] calldata outputs_
    ) private view returns (OutputBalance[] memory balances) {
        balances = new OutputBalance[](outputs_.length);
        for (uint256 i; i < outputs_.length; ++i) {
            address token = outputs_[i].token;
            if (token.code.length == 0) revert BurnerLoansComposites_InvalidToken(token);
            for (uint256 j; j < i; ++j) {
                if (outputs_[j].token == token) revert BurnerLoansComposites_DuplicateOutput(token);
            }
            uint256 retained = IERC20(token).balanceOf(msg.sender);
            for (uint256 j; j < funding_.length; ++j) {
                if (funding_[j].token == token) {
                    uint256 funded = funding_[j].amount;
                    retained = retained.saturatingSub(funded);
                    break;
                }
            }
            balances[i] = OutputBalance({
                token: token,
                minimum: outputs_[i].minReturned,
                retainedBalance: retained
            });
        }
    }

    /// @notice Enforces all final caller settlement minima after refunds and authority validation.
    /// @dev Counts actual wallet receipts above the retained baseline, including direct payouts
    ///      and returned funding. Existing holdings and other recipients cannot mask a shortfall.
    ///      Reverts if:
    ///      - The actual returned amount for any token falls below its minimum.
    /// @param outputs_ Requirements and baselines captured before execution effects.
    function _validateOutputs(OutputBalance[] memory outputs_) private view {
        for (uint256 i; i < outputs_.length; ++i) {
            OutputBalance memory output = outputs_[i];
            uint256 balance = IERC20(output.token).balanceOf(msg.sender);
            uint256 returned = balance.saturatingSub(output.retainedBalance);
            if (returned < output.minimum)
                revert BurnerLoansComposites_InsufficientReturn(
                    output.token,
                    output.minimum,
                    returned
                );
        }
    }

    /// @notice Records a token's starting balance before the batch collects any funds.
    /// @dev Spending and refunds use this baseline to protect existing funds. Only the first
    ///      occurrence of each token checks for code and reads its balance. The caller provides
    ///      enough array capacity.
    /// @param balances_ Mutable in-memory token set.
    /// @param trackedTokenCount_ Number of populated entries before this token.
    /// @param token_ Token whose raw executor balance is protected.
    /// @return Number of populated entries after this token.
    function _snapshotTokenBalance(
        TokenBalance[] memory balances_,
        uint256 trackedTokenCount_,
        address token_
    ) private view returns (uint256) {
        for (uint256 i; i < trackedTokenCount_; ++i) {
            if (balances_[i].token == token_) return trackedTokenCount_;
        }
        if (token_.code.length == 0) revert BurnerLoansComposites_InvalidToken(token_);
        balances_[trackedTokenCount_] = TokenBalance({
            token: token_,
            startingBalance: IERC20(token_).balanceOf(address(this))
        });
        return trackedTokenCount_ + 1;
    }

    /// @notice Prepares balances and resolves the Auth installation needed by an execution.
    /// @dev Reads Core's Auth only for grant-dependent actions or fresh signed acceptance.
    ///      Reverts if:
    ///      - The batch is empty.
    ///      - The deadline has passed.
    ///      - Funding, operation, or output preparation fails.
    /// @param funding_ Explicit wallet inputs.
    /// @param operations_ Ordered typed operations.
    /// @param outputs_ Caller output requirements.
    /// @param hasFlash_ Whether the batch requests a nonzero DAI flash loan.
    /// @param acceptsGrant_ Whether the entry will accept a fresh signed grant.
    /// @param deadline_ Inclusive latest timestamp for the batch.
    /// @return prepared The balance snapshots and selected authority before stamp capture.
    function _prepareExecution(
        Funding[] calldata funding_,
        Operation[] calldata operations_,
        Output[] calldata outputs_,
        bool hasFlash_,
        bool acceptsGrant_,
        uint48 deadline_
    ) private view returns (PreparedExecution memory prepared) {
        if (operations_.length == 0) revert BurnerLoansComposites_EmptyOperations();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline_) revert BurnerLoansComposites_BatchExpired(deadline_);
        (prepared.balances, prepared.authority.actions) = _prepare(
            funding_,
            operations_,
            hasFlash_
        );
        if (prepared.authority.actions != 0 || acceptsGrant_)
            (prepared.authority.auth, prepared.authority.epoch) = _CORE.authConfig();
        prepared.outputs = _prepareOutputs(funding_, outputs_);
    }

    /// @notice Captures the original authorization stamp for each required lending action.
    /// @dev Stores the captured stamps in memory.
    ///      Reverts if:
    ///      - Auth rejects authority for any required action, including absent or expired grants.
    /// @param account_ Submitting account whose grant is used.
    /// @param authority_ Mutable prepared authority record populated with captured stamps.
    function _captureAuthority(address account_, Authority memory authority_) private view {
        for (uint8 i; i < authority_.stamps.length; ++i) {
            uint8 action = uint8(1) << i;
            if ((authority_.actions & action) != 0)
                authority_.stamps[i] = IOperatorAuth(authority_.auth).captureAuthorization(
                    account_,
                    address(this),
                    action
                );
        }
    }

    /// @notice Checks that Core still selects the original Auth installation.
    /// @dev Reverts if:
    ///      - The selected Auth address or its installation epoch has changed.
    /// @param authority_ Original Auth address and installation epoch.
    function _validateInstallation(Authority memory authority_) private view {
        (address auth, uint256 epoch) = _CORE.authConfig();
        if (auth != authority_.auth || epoch != authority_.epoch)
            revert BurnerLoansComposites_AuthorityChanged();
    }

    /// @notice Revalidates the original lending authority after all external effects.
    /// @dev Skips grant-free execution.
    ///      Reverts if:
    ///      - The selected Auth address or its installation epoch has changed.
    ///      - Auth rejects any captured authorization stamp.
    /// @param account_ Submitting account whose original grant must remain valid.
    /// @param authority_ Original installation, action mask and authorization stamps.
    function _validateAuthority(address account_, Authority memory authority_) private view {
        // A protected action must capture its stamp before funding. An absent Auth fails there.
        if (authority_.auth == address(0)) return;
        _validateInstallation(authority_);
        for (uint8 i; i < authority_.stamps.length; ++i) {
            uint8 action = uint8(1) << i;
            if ((authority_.actions & action) != 0) {
                // Revalidation pins the original grant, including across funding and refund callbacks.
                // Permission data is enforced by lending actions; only stamp validity is used here.
                // forge-lint: disable-start(unused-return)
                IOperatorAuth(authority_.auth).validateAuthorization(
                    account_,
                    address(this),
                    action,
                    authority_.stamps[i]
                );
                // forge-lint: disable-end(unused-return)
            }
        }
    }

    /// @notice Executes one batch operation for the submitting account.
    /// @dev Spending approvals are bounded by available funds and cleared after each action.
    ///      Reverts if:
    ///      - The operation kind or payload is invalid.
    ///      - The action needs more than the available execution funds.
    ///      - A lending, exchange, or token call fails.
    ///      - A withdrawal returns the wrong token or less than the declared minimum.
    /// @param account_ Position owner forwarded to the lending action.
    /// @param operation_ Typed action parameters, excluding any borrower or payer override.
    /// @param balances_ Complete token set and protected starting balances.
    /// @param deadline_ Inclusive batch deadline passed to the swap adapter.
    /// @param flashRepaymentAmount_ Flash principal plus the actual fee, or zero without a loan.
    /// @return ABI encoding of the operation's result.
    function _dispatch(
        address account_,
        Operation memory operation_,
        TokenBalance[] memory balances_,
        uint48 deadline_,
        uint256 flashRepaymentAmount_
    ) private returns (bytes memory) {
        if (operation_.kind == OperationKind.Deposit) {
            Deposit memory p = abi.decode(operation_.data, (Deposit));
            _approve(balances_, p.asset, p.amount);
            (uint128 credit, uint128 collateral) = _COLLATERAL.depositCollateral(
                p.asset,
                p.amount,
                account_
            );
            IERC20(p.asset).forceApprove(address(_CORE), 0);
            return abi.encode(credit, collateral);
        }
        if (operation_.kind == OperationKind.Borrow) {
            Borrow memory p = abi.decode(operation_.data, (Borrow));
            uint256 cap = _feeApproval(balances_, p.asset, p.maxFee);
            IBurnerLoansDebt.BorrowPreview memory result = _DEBT.borrow(
                p.asset,
                p.amount,
                account_,
                p.recipient,
                cap,
                p.referrer
            );
            IERC20(p.asset).forceApprove(address(_CORE), 0);
            return abi.encode(result);
        }
        if (operation_.kind == OperationKind.Repay) {
            Repay memory p = abi.decode(operation_.data, (Repay));
            _approve(balances_, address(_OHM), p.amount);
            uint128 principal = _DEBT.repay(p.asset, p.amount, account_);
            _OHM.forceApprove(address(_CORE), 0);
            return abi.encode(principal);
        }
        if (operation_.kind == OperationKind.Withdraw) {
            return abi.encode(_withdraw(account_, abi.decode(operation_.data, (Withdraw))));
        }
        if (operation_.kind == OperationKind.Extend) {
            Extend memory p = abi.decode(operation_.data, (Extend));
            uint256 cap = _feeApproval(balances_, p.asset, p.maxFee);
            IBurnerLoansDebt.ExtendPreview memory result = _DEBT.extend(
                p.asset,
                account_,
                p.terms,
                cap,
                p.referrer
            );
            IERC20(p.asset).forceApprove(address(_CORE), 0);
            return abi.encode(result);
        }
        if (operation_.kind == OperationKind.ConvertDaiUsds) {
            return
                abi.encode(
                    _convertDaiUsds(abi.decode(operation_.data, (ConvertDaiUsds)), balances_)
                );
        }
        if (operation_.kind == OperationKind.SwapExactInput) {
            return
                abi.encode(
                    _swapExactInput(
                        abi.decode(operation_.data, (SwapExactInput)),
                        balances_,
                        deadline_
                    )
                );
        }
        if (operation_.kind == OperationKind.SwapExactOutput) {
            return
                abi.encode(
                    _swapExactOutput(
                        abi.decode(operation_.data, (SwapExactOutput)),
                        balances_,
                        deadline_,
                        flashRepaymentAmount_
                    )
                );
        }
        revert BurnerLoansComposites_UnsupportedOperation(operation_.kind);
    }

    /// @dev Checks the withdrawal token and minimum receipt for the selected recipient.
    function _withdraw(
        address account_,
        Withdraw memory p_
    ) private returns (IBurnerLoansCollateral.WithdrawPreview memory result) {
        uint256 beforeBalance;
        if (p_.recipient == address(this))
            beforeBalance = IERC20(p_.tokenOut).balanceOf(address(this));
        result = _COLLATERAL.withdrawCollateral(p_.asset, p_.amount, account_, p_.recipient);
        if (result.returnToken != p_.tokenOut)
            revert BurnerLoansComposites_UnexpectedOutput(p_.tokenOut, result.returnToken);
        if (p_.recipient == address(this)) {
            _checkOutputReceipt(p_.tokenOut, beforeBalance, p_.minAmountOut);
        } else if (result.returnAmount < p_.minAmountOut) {
            revert BurnerLoansComposites_InsufficientOutput(p_.minAmountOut, result.returnAmount);
        }
    }

    /// @dev Reverts if:
    ///      - Input and output are the same token.
    ///      - The input amount or minimum output is zero.
    function _validateExactInputExchange(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 minAmountOut_
    ) private pure {
        if (tokenIn_ == tokenOut_)
            revert BurnerLoansComposites_InvalidExchangePair(tokenIn_, tokenOut_);
        if (amountIn_ == 0 || minAmountOut_ == 0)
            revert BurnerLoansComposites_InvalidExchangeAmount();
    }

    /// @dev Only the final swap in a flash-funded batch can derive its output from repayment.
    function _validateExactOutputExchange(
        SwapExactOutput memory p_,
        bool canTargetRepayment_
    ) private view {
        if (p_.tokenIn == p_.tokenOut)
            revert BurnerLoansComposites_InvalidExchangePair(p_.tokenIn, p_.tokenOut);
        if (p_.maxAmountIn == 0) revert BurnerLoansComposites_InvalidExchangeAmount();
        if (p_.outputTarget == OutputTarget.FlashRepayment) {
            if (!canTargetRepayment_ || p_.tokenOut != _DAI || p_.amountOut != 0)
                revert BurnerLoansComposites_InvalidRepaymentTarget();
        } else if (p_.outputTarget == OutputTarget.Amount && p_.amountOut == 0) {
            revert BurnerLoansComposites_InvalidExchangeAmount();
        }
    }

    /// @dev Converts the admitted stablecoin pair and measures actual input and output deltas.
    function _convertDaiUsds(
        ConvertDaiUsds memory p_,
        TokenBalance[] memory balances_
    ) private returns (uint256) {
        uint256 expectedInputBalance = _balanceAfterSpend(balances_, p_.tokenIn, p_.amountIn);
        uint256 outputBefore = IERC20(p_.tokenOut).balanceOf(address(this));
        IERC20(p_.tokenIn).forceApprove(address(_MIGRATOR), p_.amountIn);
        if (p_.tokenIn == _DAI) _MIGRATOR.daiToUsds(address(this), p_.amountIn);
        else _MIGRATOR.usdsToDai(address(this), p_.amountIn);
        IERC20(p_.tokenIn).forceApprove(address(_MIGRATOR), 0);
        return
            _settleExactInput(
                p_.tokenIn,
                p_.tokenOut,
                expectedInputBalance,
                outputBefore,
                p_.minAmountOut
            );
    }

    /// @dev Forwards opaque path data to the fixed adapter and checks actual token settlement.
    function _swapExactInput(
        SwapExactInput memory p_,
        TokenBalance[] memory balances_,
        uint48 deadline_
    ) private returns (uint256) {
        uint256 minimumInputBalance = _balanceAfterSpend(balances_, p_.tokenIn, p_.amountIn);
        uint256 outputBefore = IERC20(p_.tokenOut).balanceOf(address(this));
        IERC20(p_.tokenIn).forceApprove(address(_SWAP_ADAPTER), p_.amountIn);
        // The actual receipt below is the authoritative exchange result.
        // forge-lint: disable-start(unused-return)
        _SWAP_ADAPTER.swapExactInput(
            IBurnerLoansSwapAdapter.ExactInputParams({
                tokenIn: p_.tokenIn,
                tokenOut: p_.tokenOut,
                amountIn: p_.amountIn,
                minAmountOut: p_.minAmountOut,
                deadline: deadline_,
                route: p_.route
            })
        );
        // forge-lint: disable-end(unused-return)
        IERC20(p_.tokenIn).forceApprove(address(_SWAP_ADAPTER), 0);
        uint256 inputAfter = IERC20(p_.tokenIn).balanceOf(address(this));
        if (inputAfter < minimumInputBalance)
            revert BurnerLoansComposites_ExchangeInputLimitExceeded(
                p_.tokenIn,
                p_.amountIn,
                p_.amountIn + (minimumInputBalance - inputAfter)
            );
        return _checkOutputReceipt(p_.tokenOut, outputBefore, p_.minAmountOut);
    }

    /// @dev Resolves the amount at execution time and verifies actual debit and receipt.
    function _swapExactOutput(
        SwapExactOutput memory p_,
        TokenBalance[] memory balances_,
        uint48 deadline_,
        uint256 flashRepaymentAmount_
    ) private returns (uint256 spent) {
        uint256 amount = p_.amountOut;
        if (p_.outputTarget != OutputTarget.Amount) {
            amount = _outputShortfall(
                balances_,
                p_.tokenOut,
                p_.outputTarget == OutputTarget.FlashRepayment ? flashRepaymentAmount_ : amount
            );
            if (amount == 0) return 0;
        }

        (uint256 inputBefore, uint256 available) = _tokenFunds(balances_, p_.tokenIn);
        uint256 limit = Math.min(p_.maxAmountIn, available);
        if (limit == 0) revert BurnerLoansComposites_InsufficientFunds(p_.tokenIn, 1, 0);
        uint256 outputBefore = IERC20(p_.tokenOut).balanceOf(address(this));
        IERC20(p_.tokenIn).forceApprove(address(_SWAP_ADAPTER), limit);
        // forge-lint: disable-start(unused-return)
        _SWAP_ADAPTER.swapExactOutput(
            IBurnerLoansSwapAdapter.ExactOutputParams({
                tokenIn: p_.tokenIn,
                tokenOut: p_.tokenOut,
                amountOut: amount,
                maxAmountIn: limit,
                deadline: deadline_,
                route: p_.route
            })
        );
        // forge-lint: disable-end(unused-return)
        IERC20(p_.tokenIn).forceApprove(address(_SWAP_ADAPTER), 0);

        uint256 inputAfter = IERC20(p_.tokenIn).balanceOf(address(this));
        if (inputAfter > inputBefore) revert BurnerLoansComposites_InexactExchangeInput(p_.tokenIn);
        spent = inputBefore - inputAfter;
        if (spent > limit)
            revert BurnerLoansComposites_ExchangeInputLimitExceeded(p_.tokenIn, limit, spent);
        _checkOutputReceipt(p_.tokenOut, outputBefore, amount);
    }

    /// @dev Computes a target shortfall against execution funds, excluding protected balances.
    function _outputShortfall(
        TokenBalance[] memory balances_,
        address token_,
        uint256 target_
    ) private view returns (uint256) {
        (, uint256 available) = _tokenFunds(balances_, token_);
        return target_.saturatingSub(available);
    }

    /// @dev Checks spendable input and returns the exact expected input balance after spending.
    function _balanceAfterSpend(
        TokenBalance[] memory balances_,
        address token_,
        uint256 amount_
    ) private view returns (uint256) {
        (uint256 current, uint256 available) = _tokenFunds(balances_, token_);
        if (amount_ > available)
            revert BurnerLoansComposites_InsufficientFunds(token_, amount_, available);
        return current - amount_;
    }

    /// @dev Checks the input token's exact debit and the output token's minimum receipt.
    function _settleExactInput(
        address input_,
        address output_,
        uint256 expectedInputBalance_,
        uint256 outputBefore_,
        uint256 minimum_
    ) private view returns (uint256 received) {
        // The stablecoin migrator must spend precisely the approved amount.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        if (IERC20(input_).balanceOf(address(this)) != expectedInputBalance_)
            revert BurnerLoansComposites_InexactExchangeInput(input_);
        return _checkOutputReceipt(output_, outputBefore_, minimum_);
    }

    /// @dev Reverts if:
    ///      - The received balance increase falls below the minimum.
    function _checkOutputReceipt(
        address output_,
        uint256 outputBefore_,
        uint256 minimum_
    ) private view returns (uint256 received) {
        uint256 outputAfter = IERC20(output_).balanceOf(address(this));
        received = outputAfter.saturatingSub(outputBefore_);
        if (received < minimum_)
            revert BurnerLoansComposites_InsufficientOutput(minimum_, received);
    }

    /// @dev Finds a prepared token and reports its current and spendable balances.
    function _tokenFunds(
        TokenBalance[] memory balances_,
        address token_
    ) private view returns (uint256 current, uint256 available) {
        for (uint256 i; i < balances_.length; ++i) {
            if (balances_[i].token == token_) return _trackedFunds(balances_[i]);
        }
        revert BurnerLoansComposites_InvalidToken(token_);
    }

    /// @dev Checks a known token against its protected starting balance.
    function _trackedFunds(
        TokenBalance memory token_
    ) private view returns (uint256 current, uint256 available) {
        current = IERC20(token_.token).balanceOf(address(this));
        if (current < token_.startingBalance)
            revert BurnerLoansComposites_ProtectedBalance(token_.token);
        available = current - token_.startingBalance;
    }

    /// @notice Approves Core to collect one explicitly sized lending input.
    /// @dev Reverts if:
    ///      - The amount exceeds available funds or the token's protected balance has fallen.
    ///      - The token approval fails.
    /// @param balances_ Complete token set and protected starting balances.
    /// @param token_ Lending input token.
    /// @param amount_ Exact raw spending allowance; may be zero.
    function _approve(TokenBalance[] memory balances_, address token_, uint256 amount_) private {
        _balanceAfterSpend(balances_, token_, amount_);
        IERC20(token_).forceApprove(address(_CORE), amount_);
    }

    /// @notice Caps Core's fee allowance by both the caller's ceiling and available funds.
    /// @dev The downstream lending action enforces the cap against the actual fee.
    ///      Reverts if:
    ///      - The token's protected balance has fallen.
    ///      - The token approval fails.
    /// @param balances_ Complete token set and protected starting balances.
    /// @param token_ Collateral token in which the fee is charged.
    /// @param maxFee_ Caller-selected ceiling in raw token units.
    /// @return cap Raw fee ceiling forwarded to the lending action and approved to Core.
    function _feeApproval(
        TokenBalance[] memory balances_,
        address token_,
        uint256 maxFee_
    ) private returns (uint256 cap) {
        (, uint256 available) = _tokenFunds(balances_, token_);
        cap = maxFee_ < available ? maxFee_ : available;
        IERC20(token_).forceApprove(address(_CORE), cap);
    }

    /// @notice Returns every tracked token's unspent execution balance to the submitting account.
    /// @dev Reverts if:
    ///      - A tracked token's protected balance has fallen.
    ///      - A mandatory refund transfer fails.
    ///      - A tracked balance differs from its starting balance after refunds.
    /// @param account_ Submitting account that receives its unused inputs and operation proceeds.
    /// @param balances_ Complete token set and protected starting balances.
    function _refund(address account_, TokenBalance[] memory balances_) private {
        for (uint256 i; i < balances_.length; ++i) {
            (, uint256 amount) = _trackedFunds(balances_[i]);
            if (amount != 0) {
                IERC20(balances_[i].token).safeTransfer(account_, amount);
                emit Refunded(account_, balances_[i].token, amount);
            }
        }
        // Check the entire set after the last transfer, which can change earlier balances.
        for (uint256 i; i < balances_.length; ++i) {
            address token = balances_[i].token;
            (, uint256 remainder) = _trackedFunds(balances_[i]);
            if (remainder != 0) revert BurnerLoansComposites_UnsettledBalance(token, remainder);
        }
    }

    // forge-lint: disable-end(calls-loop,require-revert-in-loop)

    /// @notice Checks that an action exposes its required interfaces and binds the expected Core.
    /// @dev Reverts if:
    ///      - The action lacks one of the required interfaces.
    ///      - Its Core getter fails, returns malformed data, or reports the wrong Core.
    /// @param action_ Proposed collateral or debt action.
    /// @param interfaceId_ Required public lending action interface identifier.
    /// @param core_ Core that the action must report.
    function _validateAction(address action_, bytes4 interfaceId_, address core_) private view {
        if (
            !ERC165Checker.supportsInterface(action_, interfaceId_) ||
            !ERC165Checker.supportsInterface(action_, type(IBurnerLoansCoreBound).interfaceId) ||
            _readAddress(action_, IBurnerLoansCoreBound.core.selector) != core_
        ) revert BurnerLoansComposites_InvalidDependency(action_);
    }

    /// @notice Reads a dependency's no-argument address getter through the shared safe decoder.
    /// @dev Copies at most 33 bytes.
    ///      Reverts if:
    ///      - The getter call fails.
    ///      - The response is not exactly one ABI word.
    ///      - The address word has nonzero upper bits.
    /// @param target_ Dependency that must expose the getter.
    /// @param selector_ No-argument address getter selector.
    /// @return value Canonical address returned by the dependency.
    function _readAddress(address target_, bytes4 selector_) private view returns (address value) {
        bool success;
        (success, value) = SafeCallDecoder.safeReadAddress(target_, selector_);
        if (!success) revert BurnerLoansComposites_InvalidDependency(target_);
    }
}
