// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS

import "test-utils/convert.sol";

/// LOCAL

// types

import {Kernel, Module} from "src/Kernel.sol";

/// INLINED

struct ProposalConstraints {
    int96 yesThreshold; // use fixed point
    int96 endorsementThreshold; // use fixed point
    uint64 executionTimestamp;
}

contract GovernanceModule is Module {
    // wont autogen getter so need to declare as private...
    mapping(bytes4 => ProposalConstraints) _getConstraints; // 4 billion different sigs is enough? can check for collisions

    constructor(address kernel_) Module(Kernel(kernel_)) {}

    function KEYCODE() public pure virtual override returns (bytes5) {
        return "GVMOD";
    }

    function setConstraints(
        bytes4 functionSignature,
        int96 yesThreshold,
        int96 endorsementThreshold,
        uint64 executionTimestamp
    ) external onlyPermitted {
        _getConstraints[functionSignature] = ProposalConstraints(
            yesThreshold,
            endorsementThreshold,
            executionTimestamp
        );
    }

    function getConstraints(bytes4 functionSignature)
        public
        view
        returns (ProposalConstraints memory)
    {
        return _getConstraints[functionSignature];
    }
}
