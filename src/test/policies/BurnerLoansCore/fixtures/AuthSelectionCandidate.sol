// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

contract AuthSelectionCandidate {
    address public immutable core;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(address core_) {
        core = core_;
    }

    // forge-lint: disable-end(missing-zero-check)

    function supportsInterface(bytes4 id_) external pure returns (bool) {
        return id_ != 0xffffffff;
    }

    function VERSION() external pure returns (uint8, uint8) {
        return (1, 0);
    }
}
