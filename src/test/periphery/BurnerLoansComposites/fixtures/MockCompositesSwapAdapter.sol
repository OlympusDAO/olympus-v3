// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin-5.7.0/utils/introspection/ERC165.sol";
import {IBurnerLoansSwapAdapter} from "src/periphery/interfaces/IBurnerLoansSwapAdapter.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract MockCompositesSwapAdapter is IBurnerLoansSwapAdapter, ERC165 {
    error TransferFailed();
    error UnexpectedHookSuccess();

    mapping(address => uint256) internal _output;
    uint256 internal _unspent;
    uint256 internal _excessDebit;
    address internal _refundToken;
    uint256 internal _refundAmount;
    address internal _probe;
    bytes internal _probeData;

    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IBurnerLoansSwapAdapter).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    function setOutput(address token_, uint256 output_) external {
        _output[token_] = output_;
    }

    function setUnspent(uint256 unspent_) external {
        _unspent = unspent_;
    }

    function setRouteRefund(address token_, uint256 amount_) external {
        _refundToken = token_;
        _refundAmount = amount_;
    }

    function intermediateTokens(bytes calldata) external view returns (address[] memory tokens) {
        tokens = new address[](_refundToken == address(0) ? 0 : 1);
        if (tokens.length != 0) tokens[0] = _refundToken;
    }

    function setExpectedRejection(address probe_, bytes calldata probeData_) external {
        _probe = probe_;
        _probeData = probeData_;
    }

    function swapExactInput(ExactInputParams calldata params_) external returns (uint256) {
        if (_probe != address(0)) {
            (bool success, bytes memory reason) = _probe.call(_probeData);
            if (success) revert UnexpectedHookSuccess();
            assembly ("memory-safe") {
                revert(add(reason, 32), mload(reason))
            }
        }
        if (
            !IERC20(params_.tokenIn).transferFrom(
                msg.sender,
                address(this),
                params_.amountIn - _unspent
            )
        ) revert TransferFailed();
        if (_excessDebit != 0) MockERC20(params_.tokenIn).burn(msg.sender, _excessDebit);
        MockERC20(params_.tokenOut).mint(msg.sender, _output[params_.tokenOut]);
        _refundRouteToken();
        return type(uint256).max;
    }

    function setExcessDebit(uint256 amount_) external {
        _excessDebit = amount_;
    }

    function swapExactOutput(ExactOutputParams calldata params_) external returns (uint256) {
        if (
            !IERC20(params_.tokenIn).transferFrom(
                msg.sender,
                address(this),
                params_.maxAmountIn - _unspent
            )
        ) revert TransferFailed();
        if (_excessDebit != 0) MockERC20(params_.tokenIn).burn(msg.sender, _excessDebit);
        MockERC20(params_.tokenOut).mint(msg.sender, _output[params_.tokenOut]);
        _refundRouteToken();
        return type(uint256).max;
    }

    function _refundRouteToken() private {
        if (_refundAmount != 0) MockERC20(_refundToken).mint(msg.sender, _refundAmount);
    }
}
