// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

contract BurnerLoansInventoryPrincipal is Policy, IERC165 {
    address internal immutable _FACILITY;

    // Zero intentionally models an unset facility in constructor validation tests.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(Kernel kernel_, address facility_) Policy(kernel_) {
        _FACILITY = facility_;
    }

    // Only the Core guard boundary is exercised by this double. Modular tests use real Core.
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansCore).interfaceId;
    }

    function facility() external view returns (address) {
        return _FACILITY;
    }

    // Inventory asks Core whether a settlement is in progress. This unit fixture is idle;
    // callback tests mock this boundary, while modular tests exercise Core's real guard.
    function requireNotReentrant() external pure {
        return;
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }
}
