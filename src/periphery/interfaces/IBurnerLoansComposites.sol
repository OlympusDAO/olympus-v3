// SPDX-License-Identifier: MIT
pragma solidity >=0.8.34;

// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

/// @title Burner Loans Composites
/// @notice Atomic Burner Loans operations submitted and funded by the position owner.
/// @dev Amounts are raw token units: OHM uses 9 decimals; collateral uses its token's decimals.
///      Operation inputs omit borrower/payer fields because the submitting account supplies both
///      identities. Existing public lending action types define the returned results.
///      Borrow and Extend cap combined protocol and referral fees in the selected collateral
///      token. The batch's flash fee has a separate DAI cap. Exact-input exchanges set a minimum
///      output, and exact-output exchanges cap input spend. Output.minReturned applies after
///      lender collection and refunds.
interface IBurnerLoansComposites {
    // ========== EVENTS ========== //

    /// @notice Records the downstream action's ABI-encoded result.
    ///
    /// @param account Submitting position owner.
    /// @param index Zero-based operation index.
    /// @param kind Executed operation type.
    /// @param result ABI encoding of the result for the operation kind.
    event OperationExecuted(
        address indexed account,
        uint256 indexed index,
        OperationKind kind,
        bytes result
    );

    /// @notice Records a flash loan after exact repayment.
    ///
    /// @param account Submitting account.
    /// @param amount DAI principal in raw units.
    /// @param fee Actual lender fee in raw DAI units.
    event FlashLoanSettled(address indexed account, uint256 amount, uint256 fee);

    /// @notice Records unused available funds returned to the submitting account.
    ///
    /// @param account Account receiving its remaining available funds.
    /// @param token Token refunded.
    /// @param amount Refunded amount in token raw units.
    event Refunded(address indexed account, address indexed token, uint256 amount);

    /// @notice Records a token balance recovered by the owner outside execution.
    ///
    /// @param token Rescued ERC-20 token.
    /// @param recipient Owner receiving the token.
    /// @param amount Rescued amount in raw token units.
    event TokenRescued(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Records completion after all operations, refunds, authority and final output checks.
    ///
    /// @param account Submitting position owner.
    /// @param operationCount Number of executed operations.
    event OperationsExecuted(address indexed account, uint256 operationCount);

    // ========== ERRORS ========== //

    /// @notice A lending, exchange, or flash dependency failed constructor validation.
    ///
    /// @param dependency Address of the rejected dependency.
    error BurnerLoansComposites_InvalidDependency(address dependency);

    /// @notice Enable and disable take empty data.
    error BurnerLoansComposites_InvalidEnablerData();

    /// @notice The submitted operation list is empty.
    error BurnerLoansComposites_EmptyOperations();

    /// @notice A funding or operation token is invalid or absent from the prepared token set.
    ///
    /// @param token Rejected token address.
    error BurnerLoansComposites_InvalidToken(address token);

    /// @notice The same token appears more than once in the funding list.
    ///
    /// @param token Duplicated input token, including zero-amount entries.
    error BurnerLoansComposites_DuplicateFunding(address token);

    /// @notice The same token appears more than once in the final output requirements.
    ///
    /// @param token Duplicated output token, including zero-minimum entries.
    error BurnerLoansComposites_DuplicateOutput(address token);

    /// @notice The operation kind is unsupported in this execution phase.
    ///
    /// @param kind Rejected operation kind.
    error BurnerLoansComposites_UnsupportedOperation(OperationKind kind);

    /// @notice The caller received less than a required final token amount.
    ///
    /// @param token Required output token.
    /// @param minimum Minimum returned amount, in raw token units.
    /// @param actual Actual amount returned, including unused explicit funding, in raw token units.
    error BurnerLoansComposites_InsufficientReturn(address token, uint256 minimum, uint256 actual);

    /// @notice A supplied signed grant names an account other than the submitting caller.
    error BurnerLoansComposites_InvalidGrant();

    /// @notice Core's selected Auth or its installation epoch changed during execution.
    error BurnerLoansComposites_AuthorityChanged();

    /// @notice An operation requests more tokens than its current available funds provide.
    ///
    /// @param token Token required by the operation.
    /// @param requested Requested spending amount in token raw units.
    /// @param available Available amount above the protected starting balance, in token raw units.
    error BurnerLoansComposites_InsufficientFunds(
        address token,
        uint256 requested,
        uint256 available
    );

    /// @notice A token balance fell below its protected balance at execution entry.
    ///
    /// @param token Token whose starting balance was consumed.
    error BurnerLoansComposites_ProtectedBalance(address token);

    /// @notice A tracked token has execution funds remaining after final refunds.
    ///
    /// @param token Token that still has an unsettled balance.
    /// @param amount Amount remaining above the protected balance, in raw token units.
    error BurnerLoansComposites_UnsettledBalance(address token, uint256 amount);

    /// @notice An exchange has equal endpoints or is outside the configured migration pair.
    ///
    /// @param tokenIn Submitted input token.
    /// @param tokenOut Submitted output token.
    error BurnerLoansComposites_InvalidExchangePair(address tokenIn, address tokenOut);

    /// @notice An exchange has a zero amount or limit where a positive value is required.
    error BurnerLoansComposites_InvalidExchangeAmount();

    /// @notice The batch's inclusive execution deadline has passed.
    ///
    /// @param deadline Inclusive batch deadline as a Unix timestamp, in seconds.
    error BurnerLoansComposites_BatchExpired(uint48 deadline);

    /// @notice The exchange's input balance changed in an unexpected way.
    ///
    /// @param token Input token whose balance changed unexpectedly.
    error BurnerLoansComposites_InexactExchangeInput(address token);

    /// @notice The actual input debit exceeds the available or permitted input.
    ///
    /// @param token Input token.
    /// @param maximum Maximum permitted input in raw input token units.
    /// @param actual Observed input debit in raw input token units.
    error BurnerLoansComposites_ExchangeInputLimitExceeded(
        address token,
        uint256 maximum,
        uint256 actual
    );

    /// @notice A flash repayment target requires the final operation of a flash-funded batch.
    error BurnerLoansComposites_InvalidRepaymentTarget();

    /// @notice The requested flash principal exceeds the lender's current capacity.
    ///
    /// @param amount Requested DAI principal in raw units.
    /// @param capacity DAI available from the lender in raw units.
    error BurnerLoansComposites_InvalidFlashAmount(uint256 amount, uint256 capacity);

    /// @notice A flash callback does not match the active loan request.
    error BurnerLoansComposites_InvalidFlashCallback();

    /// @notice The actual fee exceeds the supplied maximum.
    ///
    /// @param maximum Caller-specified fee cap in raw DAI units.
    /// @param actual Actual lender fee in raw DAI units.
    error BurnerLoansComposites_FlashFeeTooHigh(uint256 maximum, uint256 actual);

    /// @notice Principal plus fee does not fit in uint256.
    error BurnerLoansComposites_FlashRepaymentOverflow();

    /// @notice The flash principal received differs from the principal requested.
    error BurnerLoansComposites_InexactFlashReceipt();

    /// @notice The lender failed or did not complete the authenticated continuation.
    error BurnerLoansComposites_IncompleteFlashLoan();

    /// @notice The lender did not collect exactly principal plus the accepted fee.
    error BurnerLoansComposites_InexactFlashRepayment();

    /// @notice A withdrawal returned a different token from its declared output.
    ///
    /// @param expected Expected underlying or vault-share token.
    /// @param actual Token reported by the collateral action.
    error BurnerLoansComposites_UnexpectedOutput(address expected, address actual);

    /// @notice A withdrawal or exchange produced less than the accepted output minimum.
    ///
    /// @param minimum Caller-selected minimum in output-token raw units.
    /// @param actual Actual received or action-settled output in output-token raw units.
    error BurnerLoansComposites_InsufficientOutput(uint256 minimum, uint256 actual);

    // ========== ENUMS ========== //

    /// @notice Typed operations, dispatched without arbitrary targets or selectors.
    /// @dev Each value selects the correspondingly named input struct in this interface.
    ///      Conversion and swap operations use immutable services.
    enum OperationKind {
        /// @notice Deposits collateral for the submitting account.
        Deposit,
        /// @notice Borrows OHM and pays fees in the selected collateral token.
        Borrow,
        /// @notice Repays the submitting account's OHM principal.
        Repay,
        /// @notice Withdraws collateral as underlying tokens or vault shares.
        Withdraw,
        /// @notice Extends maturity by whole configured terms.
        Extend,
        /// @notice Converts DAI/USDS through the configured migrator.
        ConvertDaiUsds,
        /// @notice Funds a swap through the configured adapter and accepts a minimum output.
        SwapExactInput,
        /// @notice Buys an exact amount or a balance shortfall through the adapter.
        SwapExactOutput
    }

    /// @notice Determines the output amount for an exact-output swap at execution time.
    enum OutputTarget {
        /// @notice Buy the specified output amount.
        Amount,
        /// @notice Buy enough to reach the specified available output balance.
        Balance,
        /// @notice Buy enough DAI to repay the current flash loan after the operation list.
        FlashRepayment
    }

    // ========== STRUCTS ========== //

    /// @notice Explicit wallet input; the payer is always the submitting account.
    ///
    /// @param token ERC-20 token to collect.
    /// @param amount Exact amount to collect once, in raw token units; zero collects nothing.
    struct Funding {
        address token;
        uint256 amount;
    }

    /// @notice Required immutable integrations supplied at deployment.
    ///
    /// @param migrator Sky DAI/USDS migrator. Its token getters bind the migration and flash DAI.
    /// @param swapAdapter Exchange adapter supporting both exact-input and exact-output swaps.
    /// @param flashLender ERC-3156 lender for the migrator's DAI token.
    struct Integrations {
        address migrator;
        address swapAdapter;
        address flashLender;
    }

    /// @notice Minimum final token settlement to the submitting account.
    /// @dev Counts direct payouts and refunds, including unused explicit funding. Existing caller
    ///      holdings, protected executor balances and payments to other recipients do not count.
    ///      All listed requirements must hold after settlement. An empty list imposes no minimum.
    ///
    /// @param token ERC-20 token required at the caller; each token may appear only once.
    /// @param minReturned Minimum returned amount in raw token units; zero accepts any amount.
    struct Output {
        address token;
        uint256 minReturned;
    }

    /// @notice A typed operation encoded with abi.encode of its corresponding parameter struct.
    ///
    /// @param kind Selects the operation and its parameter struct.
    /// @param data ABI-encoded parameters using the struct corresponding to kind.
    struct Operation {
        OperationKind kind;
        bytes data;
    }

    /// @notice Complete caller-supplied lending authority and its authentication data.
    /// @dev Forwarded to the selected Auth without changing any grant field or permission bytes.
    ///      The grant defines action/asset limits and recipients; the signature authenticates it.
    ///      signatureData is Auth's separate acceptance-only hook, also covered by the signature.
    ///      Current BurnerLoansAuth requires signatureData to be empty. For an EOA deposit:
    ///      SignedGrant({grant: userGrant, signatureData: hex"", signature: accountSignature}),
    ///      where userGrant names the EOA, this executor and the chosen collateral/deposit ceiling,
    ///      and accountSignature signs Auth's EIP-712 payload with keccak256(hex"") as its data hash.
    ///
    /// @param grant Existing operator-auth grant type, including actions, expiry and constraints.
    /// @param signatureData Acceptance-only data defined by Auth; empty for current BurnerLoansAuth.
    /// @param signature Account's EOA or ERC-1271 signature over the complete grant payload.
    struct SignedGrant {
        IOperatorAuth.Grant grant;
        bytes signatureData;
        bytes signature;
    }

    /// @notice Deposit collateral for the submitting account.
    /// @dev The result encodes the credited amount and resulting collateral as two uint128 values.
    ///
    /// @param asset Admitted underlying collateral token.
    /// @param amount Underlying units to deposit from current available funds.
    struct Deposit {
        address asset;
        uint128 amount;
    }

    /// @notice Borrow OHM for the submitting account; fees are paid in collateral units.
    ///
    /// @param asset Collateral market securing the loan.
    /// @param amount OHM principal in 9-decimal units.
    /// @param recipient Grant-permitted principal recipient; use the executor to reuse proceeds.
    /// @param maxFee Maximum combined protocol/referral fee for this operation, in raw asset units.
    /// @param referrer Referrer for this operation, or zero.
    struct Borrow {
        address asset;
        uint128 amount;
        address recipient;
        uint256 maxFee;
        address referrer;
    }

    /// @notice Repay the submitting account's OHM principal without requiring a grant.
    ///
    /// @param asset Collateral market identifying the position.
    /// @param amount OHM principal in 9-decimal units, paid from current available funds.
    struct Repay {
        address asset;
        uint128 amount;
    }

    /// @notice Withdraw collateral, specifying the expected underlying or vault-share output.
    /// @dev The public collateral action accepts flat arguments. Core's WithdrawRequest additionally
    ///      includes a borrower identity that this caller-bound API does not accept from input.
    ///      Output uses the existing IBurnerLoansCollateral.WithdrawPreview type.
    ///
    /// @param asset Underlying collateral market identifying the position.
    /// @param amount Collateral credit to withdraw, in underlying units.
    /// @param recipient Grant-permitted output recipient; use the executor to reuse proceeds.
    /// @param tokenOut Expected underlying token or vault share token.
    /// @param minAmountOut Minimum output in tokenOut raw units; zero accepts any amount.
    struct Withdraw {
        address asset;
        uint128 amount;
        address recipient;
        address tokenOut;
        uint256 minAmountOut;
    }

    /// @notice Extend the submitting account's maturity, paying fees in collateral units.
    ///
    /// @param asset Collateral market identifying the position.
    /// @param terms Number of configured terms to add to maturity.
    /// @param maxFee Maximum combined protocol/referral fee for this operation, in raw asset units.
    /// @param referrer Referrer for this operation, or zero.
    struct Extend {
        address asset;
        uint16 terms;
        uint256 maxFee;
        address referrer;
    }

    /// @notice DAI/USDS conversion through the configured migrator.
    ///
    /// @param tokenIn Input token identifying the conversion direction.
    /// @param tokenOut Expected output token.
    /// @param amountIn Exact input to spend from available execution funds, in raw token units.
    /// @param minAmountOut Minimum actual received output, in tokenOut raw units.
    struct ConvertDaiUsds {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    /// @notice Swap an exact input amount through the configured external adapter.
    ///
    /// @param tokenIn Input token.
    /// @param tokenOut Expected output token.
    /// @param amountIn Input to fund from available execution funds, in raw token units.
    ///                 Unspent input remains available for later operations or final refund.
    /// @param minAmountOut Minimum actual received output enforced by Composites, in raw units.
    /// @param route Opaque route bytes forwarded unchanged to the configured adapter.
    struct SwapExactInput {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        bytes route;
    }

    /// @notice Exact-output swap using the configured adapter.
    ///
    /// @param tokenIn Token to spend from execution funds.
    /// @param tokenOut Token to purchase.
    /// @param outputTarget Selects how the executor calculates the amount of tokenOut to buy.
    /// @param amountOut Raw output amount or target balance. Must be zero for FlashRepayment.
    /// @param maxAmountIn Positive maximum input spend in raw token units for every output target.
    ///                    A satisfied Balance or FlashRepayment target still requires a positive cap,
    ///                    and spends zero.
    /// @param route Adapter-specific route bytes forwarded unchanged.
    struct SwapExactOutput {
        address tokenIn;
        address tokenOut;
        OutputTarget outputTarget;
        uint256 amountOut;
        uint256 maxAmountIn;
        bytes route;
    }

    /// @notice Optional DAI flash financing through the configured lender.
    ///
    /// @param amount DAI principal in raw units. Zero runs the list directly without a lender call.
    /// @param maxFee Maximum lender fee in raw DAI units. Set zero to require a fee-free loan.
    ///        Ignored when amount is zero.
    struct FlashLoan {
        uint256 amount;
        uint256 maxFee;
    }

    // ========== FUNCTIONS ========== //

    /// @notice Runs ordered operations using authority already granted to this executor by the caller.
    /// @dev Execution requires the executor to be enabled. Auth enforces the existing grant's
    ///      expiry and constraints. A reusable grant can be
    ///      approved earlier; a temporary grant must be installed in the same transaction.
    ///      Repayment-only servicing does not require a lending grant.
    ///
    /// @param funding Unique input tokens and exact wallet amounts to collect from msg.sender.
    ///        Multiple tokens can fund OHM repayment and collateral-denominated deposits or fees.
    ///        An empty list is valid when earlier outputs or the operation itself require no input.
    /// @param operations Ordered operations; the borrower is always msg.sender.
    /// @param outputs Unique final token requirements for msg.sender, including unused input refunds.
    /// @param flash Optional DAI flash financing for the complete operation list.
    /// @param deadline Inclusive latest timestamp for the entire batch, in seconds.
    ///        Use type(uint48).max for the latest representable batch deadline.
    /// @return results One result for each operation in order. Lending returns the corresponding
    ///         downstream data. ConvertDaiUsds and SwapExactInput return actual
    ///         output as uint256. SwapExactOutput returns actual input spent as uint256.
    ///         A satisfied balance or repayment target returns zero.
    function execute(
        Funding[] calldata funding,
        Operation[] calldata operations,
        Output[] calldata outputs,
        FlashLoan calldata flash,
        uint48 deadline
    ) external returns (bytes[] memory results);

    /// @notice Accepts the caller's complete signed grant and executes ordered operations atomically.
    /// @dev Execution requires the executor to be enabled. The grant names msg.sender as account
    ///      and this contract as operator. Auth authenticates
    ///      all supplied fields, including permission bytes, expiry, epochs and context. A grant
    ///      authorizes lending actions; token collection still uses the caller's explicit funding.
    ///
    /// @param funding Unique tokens and exact wallet amounts to collect from msg.sender.
    /// @param operations Ordered operations for msg.sender.
    /// @param outputs Unique final token requirements for msg.sender, including unused input refunds.
    /// @param flash Optional DAI flash financing for the complete operation list.
    /// @param deadline Inclusive latest timestamp for the entire batch, in seconds.
    ///        Use type(uint48).max for the latest representable batch deadline.
    /// @param signedGrant Complete grant and signature data forwarded unchanged to Auth.
    /// @return results ABI-encoded public lending action return values in operation order, as in execute.
    function executeWithGrant(
        Funding[] calldata funding,
        Operation[] calldata operations,
        Output[] calldata outputs,
        FlashLoan calldata flash,
        uint48 deadline,
        SignedGrant calldata signedGrant
    ) external returns (bytes[] memory results);

    /// @notice Transfers the entire balance of an ERC-20 token to the current owner.
    /// @dev Available while execution is disabled. An empty balance leaves state unchanged.
    ///
    /// @param token ERC-20 token to recover.
    function rescue(address token) external;
}
