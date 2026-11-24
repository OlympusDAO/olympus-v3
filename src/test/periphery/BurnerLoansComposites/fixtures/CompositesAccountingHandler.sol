// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

// Interfaces
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {CoreCallbackToken} from "src/test/policies/BurnerLoansCore/fixtures/CoreCallbackToken.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {CompositesAccount} from "./CompositesAccount.sol";
import {signCompositesGrant} from "./SignCompositesGrant.sol";

/// @dev Independent raw-unit model. Each actor keeps a collateral reserve of 2,000 units
///      and has a distinct callback token. The campaign configures a zero fee for borrowing.
contract CompositesAccountingHandler is CompositesAccount {
    error UnexpectedSuccess();
    error UnexpectedFailure(bytes reason);

    IExecutor internal immutable _EXECUTOR;
    MockERC20 internal immutable _ASSET;
    MockERC20 internal immutable _OHM;
    BurnerLoansAuth internal immutable _AUTH;
    bool internal immutable _INLINE_GRANT;
    uint256 internal immutable _KEY;
    Vm internal constant _VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint128 internal constant _COLLATERAL_RESERVE = 2000e6;
    IOperatorAuth.Grant internal _grant;
    CoreCallbackToken public immutable callbackToken;
    uint256 public mintedTotal;
    uint256 public depositedTotal;
    uint128 public principal;
    uint256 public withdrawals;
    uint256 public refundCallbacks;

    constructor(
        IExecutor executor_,
        MockERC20 asset_,
        MockERC20 ohm_,
        BurnerLoansAuth auth_,
        bool inlineGrant_,
        uint256 key_
    ) CompositesAccount(address(this), _VM.addr(key_)) {
        _EXECUTOR = executor_;
        _ASSET = asset_;
        _OHM = ohm_;
        _AUTH = auth_;
        _INLINE_GRANT = inlineGrant_;
        _KEY = key_;
        asset_.approve(address(executor_), type(uint256).max);
        ohm_.approve(address(executor_), type(uint256).max);
        callbackToken = new CoreCallbackToken();
        callbackToken.mint(address(this), 1);
        callbackToken.mint(address(executor_), 23);
    }

    function initialize(IOperatorAuth.Grant calldata grant_) external {
        if (grant_.multiple && !_INLINE_GRANT) _AUTH.approveGrant(grant_);
        else _grant = grant_;
        _ASSET.mint(address(this), _COLLATERAL_RESERVE);
        mintedTotal = _COLLATERAL_RESERVE;
        _execute(
            _funding(_COLLATERAL_RESERVE),
            _operations(_COLLATERAL_RESERVE),
            new IExecutor.Output[](0)
        );
        depositedTotal = _COLLATERAL_RESERVE;
    }

    function deposit(uint128 amount_, uint128 surplus_) external {
        // Campaign domain: deposits 1..1e6, unused inputs 0..1e6 raw units, within uint128.
        uint128 amount = uint128(1 + (uint256(amount_) % 1e6));
        uint256 surplus = uint256(surplus_) % (1e6 + 1);
        uint256 funding = uint256(amount) + surplus;
        _ASSET.mint(address(this), funding);
        mintedTotal += funding;
        IExecutor.Output[] memory outputs = new IExecutor.Output[](1);
        outputs[0] = IExecutor.Output(address(_ASSET), surplus);
        _execute(_funding(funding), _operations(amount), outputs);
        depositedTotal += amount;
    }

    function borrow(uint128 amount_) external {
        uint256 room = 800e9 - principal;
        if (room == 0) return;
        uint128 amount = uint128(1 + (uint256(amount_) % room));
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](1);
        operations[0] = IExecutor.Operation(
            IExecutor.OperationKind.Borrow,
            abi.encode(IExecutor.Borrow(address(_ASSET), amount, address(_EXECUTOR), 0, address(0)))
        );
        _execute(new IExecutor.Funding[](0), operations, new IExecutor.Output[](0));
        principal += amount;
    }

    function repay(uint128 amount_) external {
        if (principal == 0) return;
        uint128 amount = uint128(1 + (uint256(amount_) % principal));
        _VM.roll(_VM.getBlockNumber() + 1);
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](1);
        operations[0] = IExecutor.Operation(
            IExecutor.OperationKind.Repay,
            abi.encode(IExecutor.Repay(address(_ASSET), amount))
        );
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](1);
        funding[0] = IExecutor.Funding(address(_OHM), amount);
        _EXECUTOR.execute(
            funding,
            operations,
            new IExecutor.Output[](0),
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
        principal -= amount;
    }

    function withdraw(uint128 amount_) external {
        uint256 excess = depositedTotal - _COLLATERAL_RESERVE;
        if (excess == 0) return;
        uint128 amount = uint128(1 + (uint256(amount_) % excess));
        IExecutor.Operation[] memory operations = new IExecutor.Operation[](1);
        operations[0] = IExecutor.Operation(
            IExecutor.OperationKind.Withdraw,
            abi.encode(
                IExecutor.Withdraw(
                    address(_ASSET),
                    amount,
                    address(_EXECUTOR),
                    address(_ASSET),
                    amount
                )
            )
        );
        IExecutor.Funding[] memory funding = new IExecutor.Funding[](1);
        funding[0] = IExecutor.Funding(address(callbackToken), 1);
        callbackToken.approve(address(_EXECUTOR), 1);
        callbackToken.setCallbackFrom(
            address(_EXECUTOR),
            address(this),
            abi.encodeCall(this.observeRefund, ())
        );
        callbackToken.setCallbackPhases(true, false);
        callbackToken.setBubbleCallbackFailure(true);
        _execute(funding, operations, new IExecutor.Output[](0));
        depositedTotal -= amount;
        ++withdrawals;
    }

    function observeRefund() external {
        if (msg.sender != address(callbackToken)) revert UnexpectedSuccess();
        ++refundCallbacks;
    }

    function failDeposit() external {
        _ASSET.mint(address(this), 1);
        ++mintedTotal;
        try this.attemptDeposit() {
            revert UnexpectedSuccess();
        } catch (bytes memory reason) {
            if (
                keccak256(reason) !=
                keccak256(
                    abi.encodeWithSelector(
                        IExecutor.BurnerLoansComposites_InsufficientFunds.selector,
                        address(_ASSET),
                        2,
                        1
                    )
                )
            ) revert UnexpectedFailure(reason);
        }
    }

    function attemptDeposit() external {
        if (msg.sender != address(this)) revert UnexpectedSuccess();
        _execute(_funding(1), _operations(2), new IExecutor.Output[](0));
    }

    function _execute(
        IExecutor.Funding[] memory funding_,
        IExecutor.Operation[] memory operations_,
        IExecutor.Output[] memory outputs_
    ) private {
        if (_grant.account != address(0)) {
            IOperatorAuth.Grant memory grant = _grant;
            grant.pairEpoch = _AUTH.pairEpochs(address(this), address(_EXECUTOR));
            if (_INLINE_GRANT) {
                IExecutor.SignedGrant memory signed = signCompositesGrant(_VM, _AUTH, grant, _KEY);
                _EXECUTOR.executeWithGrant(
                    funding_,
                    operations_,
                    outputs_,
                    IExecutor.FlashLoan(0, 0),
                    type(uint48).max,
                    signed
                );
                return;
            }
            // Each invariant handler call is driven directly by Forge. Keep approval and use
            // inside a single external call so transaction isolation preserves temporary authority.
            this.approveGrantAndRun(_AUTH, grant, _EXECUTOR, funding_, operations_, outputs_);
            return;
        }
        _EXECUTOR.execute(
            funding_,
            operations_,
            outputs_,
            IExecutor.FlashLoan(0, 0),
            type(uint48).max
        );
    }

    function _funding(uint256 amount_) private view returns (IExecutor.Funding[] memory inputs) {
        inputs = new IExecutor.Funding[](1);
        inputs[0] = IExecutor.Funding(address(_ASSET), amount_);
    }

    function _operations(
        uint128 amount_
    ) private view returns (IExecutor.Operation[] memory operations) {
        operations = new IExecutor.Operation[](1);
        operations[0] = IExecutor.Operation(
            IExecutor.OperationKind.Deposit,
            abi.encode(IExecutor.Deposit(address(_ASSET), amount_))
        );
    }
}
