// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Tests use explicit boundary values and bounded casts; action effects are asserted directly.
// Deterministic seed loops intentionally call contracts and Forge cheatcodes.
// forge-lint: disable-start(inline-assembly,missing-zero-check)

// Contracts
import {MockOhm} from "src/test/mocks/MockOhm.sol";

// Zero is an intentional invalid or cleared address in these test fixtures.

// The callback fixture bubbles the exact nested revert bytes to test mandatory rollback.

/// @dev Arms exactly one token boundary after setup. Keeps the real transfer/mint/burn so
/// tests can prove both committed deltas and rollback, rather than only mocked return data.
contract InventoryCallbackOhm is MockOhm {
    address internal _target;
    bytes internal _data;
    bytes4 internal _phase;
    bool internal _bubble;
    uint256 internal _extraReceipt;
    bytes public rejection;

    constructor() MockOhm("OHM", "OHM", 9) {}

    function arm(bytes4 phase_, address target_, bytes calldata data_, bool bubble_) external {
        _phase = phase_;
        _target = target_;
        _data = data_;
        _bubble = bubble_;
    }

    function setExtraReceipt(uint256 extra_) external {
        _extraReceipt = extra_;
    }

    function transfer(address to_, uint256 amount_) public override returns (bool) {
        bool result = super.transfer(to_, amount_);
        _callback(msg.sig);
        return result;
    }

    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public override returns (bool) {
        bool result = super.transferFrom(from_, to_, amount_);
        if (_extraReceipt != 0) _mint(to_, _extraReceipt);
        _callback(msg.sig);
        return result;
    }

    function mint(address to_, uint256 amount_) public override {
        super.mint(to_, amount_);
        _callback(msg.sig);
    }

    function burnFrom(address from_, uint256 amount_) public override {
        super.burnFrom(from_, amount_);
        _callback(msg.sig);
    }

    function _callback(bytes4 phase_) internal {
        if (_phase != phase_ || _target == address(0)) return;
        _phase = bytes4(0);
        // The callback deliberately targets the armed public action and records exact revert data.
        // forge-lint: disable-next-line(low-level-calls)
        (bool success, bytes memory result) = _target.call(_data);
        if (success) return;
        rejection = result;
        if (_bubble) {
            // Bubble the exact nested error for the outer mandatory/fail-soft boundary.
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }
}

// forge-lint: disable-end(inline-assembly,missing-zero-check)
