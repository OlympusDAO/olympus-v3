// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC6909} from "@openzeppelin-5.3.0/interfaces/draft-IERC6909.sol";

// Contracts
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

/// @dev Preserves ReceiptTokenManager storage and real approvals while adding a one-shot hook.
contract BurnerLoansCollateralCallbackReceipts is ReceiptTokenManager {
    error CallbackFailed();

    address internal _target;
    bytes internal _data;
    bool internal _armed;
    bool internal _propagate;
    bytes public rejection;

    // Callback targets are explicit valid fixture contracts.
    // forge-lint: disable-next-line(missing-zero-check)
    function arm(address target_, bytes calldata data_, bool propagate_) external {
        _target = target_;
        _data = data_;
        _armed = true;
        _propagate = propagate_;
    }

    function approve(
        address spender_,
        uint256 id_,
        uint256 amount_
    ) public override(ERC6909, IERC6909) returns (bool) {
        bool result = super.approve(spender_, id_, amount_);
        if (_armed) {
            _armed = false;
            // The configured hook models an untrusted approval dependency.
            // forge-lint: disable-next-line(low-level-calls)
            (bool ok, bytes memory reason) = _target.call(_data);
            rejection = reason;
            if (!ok && _propagate) revert CallbackFailed();
        }
        return result;
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
