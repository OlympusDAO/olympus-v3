// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

/// @dev Retains the fixture's OZ token storage when installed with vm.etch.
contract RecoveryCallbackOhm is MockERC20 {
    address internal _target;
    bytes internal _data;

    constructor() MockERC20("OHM", "OHM", 9) {}

    // A zero target explicitly disarms the callback.
    // forge-lint: disable-next-line(missing-zero-check)
    function arm(address target_, bytes calldata data_) external {
        _target = target_;
        _data = data_;
    }

    function transfer(address to_, uint256 amount_) public override returns (bool) {
        bool transferred = super.transfer(to_, amount_);
        if (_target != address(0)) {
            address target = _target;
            _target = address(0);
            // Invoke the authorized nested recovery and preserve its exact revert bytes.
            // forge-lint: disable-next-line(low-level-calls)
            (bool success, bytes memory reason) = target.call(_data);
            if (!success) {
                // No ABI wrapper: the scenario requires the original guard error.
                // forge-lint: disable-next-line(inline-assembly)
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        return transferred;
    }
}
