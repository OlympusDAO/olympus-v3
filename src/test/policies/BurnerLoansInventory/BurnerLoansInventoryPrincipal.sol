// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

contract BurnerLoansInventoryPrincipal is Policy {
    address internal immutable _FACILITY;

    // Zero intentionally models an unset facility in constructor validation tests.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(Kernel kernel_, address facility_) Policy(kernel_) {
        _FACILITY = facility_;
    }

    function facility() external view returns (address) {
        return _FACILITY;
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }
}
