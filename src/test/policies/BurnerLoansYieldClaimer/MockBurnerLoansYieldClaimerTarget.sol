// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/IBurnerLoansYieldClaim.sol";

contract MockBurnerLoansYieldClaimerTarget is Policy, IERC165 {
    error ClaimReverted();

    bool public claimReverts;
    bool public claimRevertsWithShortData;
    bool public claimRevertsWithLargeData;
    bool public claimConsumesAllGas;
    uint256 public claimCalls;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies()
        external
        pure
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](0);
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        permissions = new Permissions[](0);
    }

    function setClaimReverts(bool reverts_) external {
        claimReverts = reverts_;
    }

    function setClaimRevertsWithShortData(bool reverts_) external {
        claimRevertsWithShortData = reverts_;
    }

    function setClaimRevertsWithLargeData(bool reverts_) external {
        claimRevertsWithLargeData = reverts_;
    }

    function setClaimConsumesAllGas(bool consumesAllGas_) external {
        claimConsumesAllGas = consumesAllGas_;
    }

    function claimYield() external {
        if (claimConsumesAllGas) {
            assembly ("memory-safe") {
                invalid()
            }
        }
        if (claimRevertsWithShortData) {
            assembly ("memory-safe") {
                mstore(0, 0xab)
                revert(0x1f, 1)
            }
        }
        if (claimRevertsWithLargeData) {
            assembly ("memory-safe") {
                revert(0, 100000)
            }
        }
        if (claimReverts) revert ClaimReverted();
        ++claimCalls;
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansYieldClaim).interfaceId;
    }
}
