// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {DepositManagerConfigTimelock} from "src/policies/deposits/DepositManagerConfigTimelock.sol";

import {DepositManagerConfigTimelockTest} from "./DepositManagerConfigTimelockTest.sol";

contract DepositManagerConfigTimelockReEnableTest is DepositManagerConfigTimelockTest {
    function test_givenContractWasNeverEnabled_reverts() public {
        DepositManagerConfigTimelock freshTimelock = new DepositManagerConfigTimelock(
            kernel,
            IDepositManager(address(depositManager))
        );

        vm.expectRevert(IReEnabler.NeverEnabled.selector);
        vm.prank(ADMIN);
        freshTimelock.reEnable();
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _configTimelock.reEnable();
    }

    function test_givenAdminWithinGracePeriod_reenables(uint32 elapsed_) public {
        uint256 elapsed = bound(elapsed_, 0, _configTimelock.gracePeriod());
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        uint48 disabledAt = _configTimelock.lastTransitionAt();

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(ADMIN);
        _configTimelock.reEnable();

        assertTrue(_configTimelock.isEnabled(), "admin should re-enable timelock");
    }

    function test_givenDepositManagerAdminWithinGracePeriod_reenables(uint32 elapsed_) public {
        uint256 elapsed = bound(elapsed_, 0, _configTimelock.gracePeriod());
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        uint48 disabledAt = _configTimelock.lastTransitionAt();

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();

        assertTrue(_configTimelock.isEnabled(), "Deposit Manager admin should re-enable timelock");
    }

    function test_givenDepositManagerAdminAtGraceDeadline_reenables() public {
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        uint48 deadline = _configTimelock.lastTransitionAt() + _configTimelock.gracePeriod();

        vm.warp(deadline);
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();

        assertTrue(_configTimelock.isEnabled(), "grace deadline should be inclusive");
    }

    function test_givenGracePeriodExpired_reverts(uint48 elapsedAfterDeadline_) public {
        uint256 elapsedAfterDeadline = bound(elapsedAfterDeadline_, 1, 365 days);
        vm.prank(EMERGENCY);
        _configTimelock.disable("");
        uint48 deadline = _configTimelock.lastTransitionAt() + _configTimelock.gracePeriod();
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.expectRevert(
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, deadline)
        );
        vm.prank(DEPOSIT_MANAGER_ADMIN);
        _configTimelock.reEnable();
    }

    function test_givenTimelockIsDisabled_setGracePeriodReverts() public {
        vm.prank(EMERGENCY);
        _configTimelock.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(ADMIN);
        _configTimelock.setGracePeriod(1 days);
    }

    function test_whenGracePeriodIsZero_reverts() public {
        vm.expectRevert(IGracePeriod.GracePeriod_ZeroPeriod.selector);
        vm.prank(ADMIN);
        _configTimelock.setGracePeriod(0);
    }

    function test_givenCallerIsNotAdmin_setGracePeriodReverts(address caller_) public {
        vm.assume(caller_ != ADMIN);

        _expectRevertNotAdmin();
        vm.prank(caller_);
        _configTimelock.setGracePeriod(1 days);
    }

    function test_givenAdmin_setsGracePeriod(uint32 gracePeriod_) public {
        // bound() caps the result at uint32 max, so this cast cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 gracePeriod = uint32(bound(gracePeriod_, 1, type(uint32).max));

        vm.prank(ADMIN);
        _configTimelock.setGracePeriod(gracePeriod);

        assertEq(_configTimelock.gracePeriod(), gracePeriod, "grace period mismatch");
    }

    function test_givenAdmin_setsMaximumGracePeriod() public {
        vm.prank(ADMIN);
        _configTimelock.setGracePeriod(type(uint32).max);

        assertEq(_configTimelock.gracePeriod(), type(uint32).max, "maximum grace period mismatch");
    }
}

// forge-lint: disable-end(literal-instead-of-constant)
