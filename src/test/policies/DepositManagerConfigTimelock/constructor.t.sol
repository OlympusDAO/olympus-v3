// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// The V1-only interface stub is co-located with its sole constructor compatibility test.
// forge-lint: disable-start(literal-instead-of-constant, multi-contract-file)

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerConfigTimelock} from "src/policies/interfaces/deposits/IDepositManagerConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";
import {ReceiptTokenManager} from "src/policies/deposits/ReceiptTokenManager.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract V1DepositManagerInterfaceStub is IERC165 {
    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IDepositManager).interfaceId ||
            interfaceId_ == type(IConfigOperator).interfaceId ||
            interfaceId_ == type(IEnabler).interfaceId;
    }
}

contract DepositManagerConfigTimelockConstructorTest is DepositManagerConfigTimelockTest {
    function test_whenDepositManagerIsZero_reverts() public {
        vm.expectRevert(
            IDepositManagerConfigTimelock.DepositManagerConfigTimelock_ZeroAddress.selector
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(address(0)));
    }

    function test_whenDepositManagerDoesNotSupportRequiredInterfaces_reverts() public {
        address invalidTarget = makeAddr("invalidTarget");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                invalidTarget
            )
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(invalidTarget));
    }

    function test_whenDepositManagerOnlySupportsV1_reverts() public {
        address v1Target = address(new V1DepositManagerInterfaceStub());

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock
                    .DepositManagerConfigTimelock_InvalidDepositManager
                    .selector,
                v1Target
            )
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(v1Target));
    }

    function test_givenDepositManagerUsesDifferentKernel_reverts() public {
        Kernel foreignKernel = new Kernel();
        ReceiptTokenManager foreignTokenManager = new ReceiptTokenManager();
        DepositManager foreignDepositManager = new DepositManager(
            address(foreignKernel),
            address(foreignTokenManager)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerConfigTimelock.DepositManagerConfigTimelock_KernelMismatch.selector,
                address(foreignKernel)
            )
        );
        new DepositManagerConfigTimelock(kernel, IDepositManager(address(foreignDepositManager)));
    }

    function test_givenValidParameters_setsImmutableConfiguration() public view {
        assertEq(
            address(_configTimelock.depositManager()),
            address(depositManager),
            "DepositManager target mismatch"
        );
        assertEq(_configTimelock.MIN_TIMELOCK_DELAY(), 1 days, "minimum delay mismatch");
        assertEq(_configTimelock.MAX_TIMELOCK_DELAY(), 30 days, "maximum delay mismatch");
        assertEq(_configTimelock.EXECUTION_WINDOW(), 3 days, "execution window mismatch");
        assertEq(_configTimelock.timelockDelay(), 1 days, "initial delay mismatch");
        assertEq(_configTimelock.gracePeriod(), 7 days, "grace period mismatch");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, multi-contract-file)
