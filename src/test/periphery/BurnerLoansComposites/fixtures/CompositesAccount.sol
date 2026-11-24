// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.34;

// Interfaces
import {IERC1271} from "@openzeppelin-5.7.0/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IBurnerLoansComposites as IExecutor} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {ECDSA} from "@openzeppelin-5.7.0/utils/cryptography/ECDSA.sol";

/// @dev Optional contract-account fixture; ordinary users do not deploy this or another wallet.
contract CompositesAccount is IERC1271 {
    error NotOwner();
    address internal immutable _OWNER;
    address internal immutable _SIGNER;

    constructor(address owner_, address signer_) {
        _OWNER = owner_;
        _SIGNER = signer_;
    }

    function isValidSignature(
        bytes32 digest_,
        bytes memory signature_
    ) external view returns (bytes4) {
        return
            ECDSA.recover(digest_, signature_) == _SIGNER
                ? IERC1271.isValidSignature.selector
                : bytes4(0xffffffff);
    }

    function run(
        IExecutor executor_,
        IExecutor.Funding[] calldata funding_,
        IExecutor.Operation[] calldata operations_,
        IExecutor.Output[] calldata outputs_,
        IExecutor.SignedGrant calldata signedGrant_
    ) external returns (bytes[] memory results) {
        if (msg.sender != _OWNER) revert NotOwner();
        _approveInputs(executor_, funding_);
        return
            executor_.executeWithGrant(
                funding_,
                operations_,
                outputs_,
                IExecutor.FlashLoan(0, 0),
                type(uint48).max,
                signedGrant_
            );
    }

    function approveGrantAndRun(
        IOperatorAuth auth_,
        IOperatorAuth.Grant calldata grant_,
        IExecutor executor_,
        IExecutor.Funding[] calldata funding_,
        IExecutor.Operation[] calldata operations_,
        IExecutor.Output[] calldata outputs_
    ) external returns (bytes[] memory results) {
        if (msg.sender != _OWNER) revert NotOwner();
        _approveInputs(executor_, funding_);
        auth_.approveGrant(grant_);
        return
            executor_.execute(
                funding_,
                operations_,
                outputs_,
                IExecutor.FlashLoan(0, 0),
                type(uint48).max
            );
    }

    function approveGrant(IOperatorAuth auth_, IOperatorAuth.Grant calldata grant_) external {
        if (msg.sender != _OWNER) revert NotOwner();
        auth_.approveGrant(grant_);
    }

    function cancelGrant(IOperatorAuth auth_, address operator_) external {
        if (msg.sender != _OWNER) revert NotOwner();
        auth_.cancelGrant(operator_);
    }

    function runWithExistingGrant(
        IExecutor executor_,
        IExecutor.Funding[] calldata funding_,
        IExecutor.Operation[] calldata operations_,
        IExecutor.Output[] calldata outputs_
    ) external returns (bytes[] memory results) {
        if (msg.sender != _OWNER) revert NotOwner();
        _approveInputs(executor_, funding_);
        return
            executor_.execute(
                funding_,
                operations_,
                outputs_,
                IExecutor.FlashLoan(0, 0),
                type(uint48).max
            );
    }

    function _approveInputs(IExecutor executor_, IExecutor.Funding[] calldata funding_) private {
        for (uint256 i; i < funding_.length; ++i)
            IERC20(funding_[i].token).approve(address(executor_), funding_[i].amount);
    }
}
