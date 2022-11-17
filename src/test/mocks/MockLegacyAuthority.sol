// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IOlympusAuthority} from "src/external/OlympusERC20.sol";

contract MockLegacyAuthority is IOlympusAuthority {
    address internal kernel;

    constructor(address kernel_) {
        kernel = kernel_;
    }

    function governor() external view returns (address) {
        return kernel;
    }

    function guardian() external view returns (address) {
        return kernel;
    }

    function policy() external view returns (address) {
        return kernel;
    }

    function vault() external view returns (address) {
        return kernel;
    }
}
