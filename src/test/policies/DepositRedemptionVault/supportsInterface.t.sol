// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {DepositRedemptionVaultTest} from "./DepositRedemptionVaultTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract DepositRedemptionVaultSupportsInterfaceTest is DepositRedemptionVaultTest {
    function test_supportsInterface() public view {
        // Validate ERC165 compliance
        ERC165Helper.validateSupportsInterface(address(redemptionVault));

        // Test IERC165
        assertEq(
            redemptionVault.supportsInterface(type(IERC165).interfaceId),
            true,
            "IERC165 mismatch"
        );

        // Test IDepositRedemptionVault
        assertEq(
            redemptionVault.supportsInterface(type(IDepositRedemptionVault).interfaceId),
            true,
            "IDepositRedemptionVault mismatch"
        );

        // Test IEnabler
        assertEq(
            redemptionVault.supportsInterface(type(IEnabler).interfaceId),
            true,
            "IEnabler mismatch"
        );

        // Test non-implemented interfaces (should be false)
        assertEq(
            redemptionVault.supportsInterface(type(IERC20).interfaceId),
            false,
            "Should not support IERC20"
        );
        assertEq(
            redemptionVault.supportsInterface(type(IERC4626).interfaceId),
            false,
            "Should not support IERC4626"
        );
    }
}
