// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansPayoutConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansPayoutConfigTimelock.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansPayoutConfigTimelockTest} from "./BurnerLoansPayoutConfigTimelockTest.sol";
import {BurnerLoansPayoutConfigTimelock} from "src/policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol";

contract BurnerLoansPayoutConfigTimelockConstructorTest is BurnerLoansPayoutConfigTimelockTest {
    error ProbeFailed();

    // Scenarios: BLCUCT-CONSTRUCTOR-I01.
    function test_whenPayoutZero_reverts(address deployer_) public {
        _expectInvalid(address(0), deployer_);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-I02.
    function test_whenPayoutEOA_reverts(address candidate_, address deployer_) public {
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        _expectInvalid(candidate_, deployer_);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-D01.
    function test_givenMissingInterface_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_payout),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansPayout).interfaceId
            ),
            abi.encode(false)
        );
        _expectInvalid(address(_payout), deployer_);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-D02.
    function test_givenERC165Reverts_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            abi.encodeWithSelector(ProbeFailed.selector)
        );
        _expectInvalid(address(_payout), deployer_);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-D03.
    function test_givenERC165Malformed_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_payout),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"01"
        );
        _expectInvalid(address(_payout), deployer_);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-D04.
    function test_givenWrongKernel_whenDeployed_reverts(address deployer_, address other_) public {
        vm.assume(other_ != address(_kernel));
        _mockPayoutKernel(other_);
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                other_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansPayoutConfigTimelock(_kernel, _payout);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-D05.
    function test_givenKernelProbeReverts_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(ProbeFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_payout)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansPayoutConfigTimelock(_kernel, _payout);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-D06.
    function test_givenKernelProbeMalformed_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(address(_payout), abi.encodeWithSignature("kernel()"), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_payout)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansPayoutConfigTimelock(_kernel, _payout);
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-L01, BLCUCT-CONSTRUCTOR-L02.
    function test_givenIndependentLifecycle_whenDeployed_thenExactDefaults(
        address deployer_,
        bool payoutActive_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _setState(_core, coreActive_, coreEnabled_);
        _setState(_payout, payoutActive_, true);
        bytes32 beforeFunds = _payoutDigest();
        address controller = _payout.configOperator();
        vm.prank(deployer_);
        BurnerLoansPayoutConfigTimelock fresh = new BurnerLoansPayoutConfigTimelock(
            _kernel,
            _payout
        );
        assertEq(address(fresh.kernel()), address(_kernel), "Exact Kernel");
        assertEq(address(fresh.payout()), address(_payout), "Immutable target");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.lastTransitionAt(), 0, "No transition history");
        assertEq(fresh.nextActionId(), 1, "First action ID");
        assertEq(fresh.timelockDelay(), 1 days, "Default delay");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(_payout.configOperator(), controller, "Constructor does not select itself");
        assertEq(_payoutDigest(), beforeFunds, "No target mutations");
    }

    // Scenarios: BLCUCT-CONSTRUCTOR-L01, BLCUCT-CONSTRUCTOR-L02.
    function test_givenLifecycleSeeds_whenDeployed_thenExactDefaults() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 p; p < 2; ++p)
            for (uint256 a; a < 2; ++a)
                for (uint256 e; e < 2; ++e) {
                    test_givenIndependentLifecycle_whenDeployed_thenExactDefaults(
                        address(0),
                        p != 0,
                        a != 0,
                        e != 0
                    );
                    _restore(checkpoint);
                }
    }

    function _expectInvalid(address candidate_, address deployer_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansPayoutConfigTimelock.BurnerLoansPayoutTimelock_InvalidPayout.selector,
                candidate_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansPayoutConfigTimelock(_kernel, IBurnerLoansPayout(candidate_));
    }
}
