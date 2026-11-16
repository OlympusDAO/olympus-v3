// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE, DEPOSIT_MANAGER_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansForkTest} from "./fixtures/BurnerLoansForkTest.sol";
import {Timelock} from "src/external/governance/Timelock.sol";

contract BurnerLoansHeartOrderForkTest is BurnerLoansForkTest {
    // Keep the real mainnet graph prepared but unlaunched for execution-time drift tests.
    function _simulateProposal() internal override {}

    // Scenarios: BLAUNCH-P01, BLAUNCH-H08.
    function test_givenReviewedHeartBaseline_whenGovernanceExecutes() public {
        // The simulator returns snapshots which are unnecessary for these postconditions.
        // forge-lint: disable-next-item(unused-return)
        suite.testProposals();
        assertTrue(_activator.isActivated(), "Reviewed baseline launches through real governance");
        _assertHeartOrder();
        assertFalse(_roles.hasRole(address(_activator), ADMIN_ROLE), "Temporary ADMIN revoked");
    }

    // Scenarios: BLAUNCH-S04, BLPF-T01.
    function test_givenLateLaunchFailure_whenGovernanceExecutes_rollsBackBindingsAndRoles() public {
        vm.mockCallRevert(
            _graph.heart,
            abi.encodeCall(
                IPeriodicTaskManager.addPeriodicTaskAtIndex,
                (_graph.yieldClaimerTask, bytes4(0), uint256(4))
            ),
            abi.encodeWithSelector(Timelock.Timelock_InvalidTx_ExecReverted.selector)
        );
        vm.expectRevert(Timelock.Timelock_InvalidTx_ExecReverted.selector);
        // Failed simulation has no successful snapshot result.
        // forge-lint: disable-next-line(unused-return)
        suite.testProposals();
        assertFalse(_activator.isActivated(), "Late failure rolls back one-use flag");
        assertFalse(
            _roles.hasRole(address(_activator), ADMIN_ROLE),
            "Temporary ADMIN grant rolls back"
        );
        assertFalse(
            _roles.hasRole(_dao, DEPOSIT_MANAGER_ADMIN_ROLE),
            "Custody proposer grant rolls back"
        );
        assertFalse(
            _roles.hasRole(_graph.core, DEPOSIT_OPERATOR_ROLE),
            "Core custody grant rolls back"
        );
        assertEq(
            IConfigOperator(_graph.depositManager).configOperator(),
            address(0),
            "Custody controller selection rolls back"
        );
        assertFalse(
            IEnabler(_graph.depositManagerTimelock).isEnabled(),
            "Custody queue enablement rolls back"
        );
        assertFalse(IEnabler(_graph.depositManager).isEnabled(), "Manager enablement rolls back");
        assertEq(_core.getAssetCount(), 0, "Markets roll back");
        assertEq(
            IPeriodicTaskManager(_graph.heart).getPeriodicTaskCount(),
            6,
            "Earlier task insertion rolls back"
        );
        vm.clearMockedCalls();
        // Simulator returns snapshots unused by these postconditions.
        // forge-lint: disable-next-line(unused-return)
        suite.testProposals();
        assertTrue(_activator.isActivated(), "Restored prerequisite permits real governance retry");
    }

    // Scenarios: BLAUNCH-H05, BLAUNCH-H09.
    function test_givenHeartSelectorDrift_whenGovernanceExecutes_reverts() public {
        IPeriodicTaskManager heart = IPeriodicTaskManager(_graph.heart);
        vm.startPrank(_timelock);
        heart.removePeriodicTaskAtIndex(3);
        heart.addPeriodicTaskAtIndex(_existingHeartTasks[3], bytes4(0x12345678), 3);
        vm.stopPrank();
        vm.expectRevert(Timelock.Timelock_InvalidTx_ExecReverted.selector);
        // The failed simulation has no successful snapshot result.
        // forge-lint: disable-next-item(unused-return)
        suite.testProposals();
        assertFalse(_activator.isActivated(), "One-use flag rolls back");
        assertFalse(
            _roles.hasRole(address(_activator), ADMIN_ROLE),
            "Temporary ADMIN grant rolls back"
        );
        assertFalse(
            _roles.hasRole(_graph.core, DEPOSIT_OPERATOR_ROLE),
            "Custody role grant rolls back"
        );
        assertFalse(
            _roles.hasRole(_graph.seizerTask, BURNER_LOANS_SEIZER_ROLE),
            "Seizer role grant rolls back"
        );
        assertFalse(_roles.hasRole(_dao, BURNER_LOANS_ADMIN_ROLE), "DAO role grant rolls back");
        assertFalse(IEnabler(_graph.core).isEnabled(), "Core enablement rolls back");
        assertFalse(IEnabler(_graph.depositManager).isEnabled(), "Custody enablement rolls back");
        assertFalse(IEnabler(_graph.backingOracle).isEnabled(), "Oracle enablement rolls back");
        assertEq(
            IBackingOracle(_graph.backingOracle).backing(),
            0,
            "Backing initialization rolls back"
        );
        assertEq(
            IConfigOperator(_graph.core).configOperator(),
            address(0),
            "Controller selection rolls back"
        );
        assertEq(_core.getAssetCount(), 0, "No lending markets created");
        assertFalse(_price.isAssetApproved(_graph.usde), "USDe PRICE admission rolls back");
        assertEq(heart.getPeriodicTaskCount(), 6, "No automation tasks inserted");
        (address task, bytes4 selector) = heart.getPeriodicTaskAtIndex(3);
        assertEq(task, _existingHeartTasks[3], "Failed launch retains Operator identity");
        assertEq(selector, bytes4(0x12345678), "Failed launch preserves pre-existing drift");
    }
}
