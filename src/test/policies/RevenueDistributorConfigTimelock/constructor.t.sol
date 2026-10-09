// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// The target mock is test-local and is clearer beside the constructor cases that configure it.
// forge-lint: disable-start(multi-contract-file)

import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorConfigTimelock} from "src/policies/interfaces/IRevenueDistributorConfigTimelock.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";
import {RevenueDistributorConfigTimelock} from "src/policies/RevenueDistributorConfigTimelock.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

contract RevenueDistributorConfigTimelockConstructorTest is RevenueDistributorTest {
    // Scenarios: RDCT-CTOR-P01
    function test_whenConstructedWithValidTarget_setsTargetAndDefaults() public {
        RevenueDistributorConfigTimelock timelock = new RevenueDistributorConfigTimelock(
            kernel,
            distributor
        );

        assertEq(timelock.distributor(), address(distributor), "distributor target");
        assertFalse(timelock.isEnabled(), "initially disabled");
        assertEq(timelock.lastTransitionAt(), 0, "no transition recorded");
        assertEq(timelock.gracePeriod(), 7 days, "default grace period");
        assertEq(timelock.timelockDelay(), 1 days, "default timelock delay");
        assertEq(timelock.nextActionId(), 1, "first action ID");
        assertEq(timelock.EXECUTION_WINDOW(), 3 days, "execution window");
        assertEq(timelock.maxConfigKeysPerBatch(), 15, "maximum batch keys");
    }

    // Scenarios: RDCT-CTOR-I01
    function test_whenConstructedWithZeroTarget_reverts() public {
        _expectInvalidTarget(address(0));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(0)));
    }

    // Scenarios: RDCT-CTOR-I02
    function test_whenConstructedWithEoaTarget_reverts() public {
        address target = makeAddr("non-contract distributor");

        _expectInvalidTarget(target);
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(target));
    }

    // Scenarios: RDCT-CTOR-I03
    function test_whenTargetLacksRevenueDistributorInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            false,
            true,
            true,
            true
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I04
    function test_whenTargetLacksRescueInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            true,
            false,
            true,
            true
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I05
    function test_whenTargetLacksConfigOperatorInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            true,
            true,
            false,
            true
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I06
    function test_whenTargetLacksEnablerInterface_reverts() public {
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            kernel,
            true,
            true,
            true,
            false
        );

        _expectInvalidTarget(address(target));
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    // Scenarios: RDCT-CTOR-I07
    function test_whenTargetUsesDifferentKernel_reverts() public {
        Kernel targetKernel = new Kernel();
        MockRevenueDistributorTarget target = new MockRevenueDistributorTarget(
            targetKernel,
            true,
            true,
            true,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_KernelMismatch
                    .selector,
                address(targetKernel)
            )
        );
        new RevenueDistributorConfigTimelock(kernel, IRevenueDistributor(address(target)));
    }

    function _expectInvalidTarget(address target_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributorConfigTimelock
                    .RevenueDistributorConfigTimelock_InvalidDistributor
                    .selector,
                target_
            )
        );
    }
}

contract MockRevenueDistributorTarget is Policy, IERC165 {
    bool internal immutable _SUPPORTS_DISTRIBUTOR;
    bool internal immutable _SUPPORTS_RESCUE;
    bool internal immutable _SUPPORTS_CONFIG_OPERATOR;
    bool internal immutable _SUPPORTS_ENABLER;

    constructor(
        Kernel kernel_,
        bool supportsDistributor_,
        bool supportsRescue_,
        bool supportsConfigOperator_,
        bool supportsEnabler_
    ) Policy(kernel_) {
        _SUPPORTS_DISTRIBUTOR = supportsDistributor_;
        _SUPPORTS_RESCUE = supportsRescue_;
        _SUPPORTS_CONFIG_OPERATOR = supportsConfigOperator_;
        _SUPPORTS_ENABLER = supportsEnabler_;
    }

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

    function supportsInterface(bytes4 interfaceId_) external view returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            (_SUPPORTS_DISTRIBUTOR && interfaceId_ == type(IRevenueDistributor).interfaceId) ||
            (_SUPPORTS_RESCUE && interfaceId_ == type(IRevenueDistributorRescue).interfaceId) ||
            (_SUPPORTS_CONFIG_OPERATOR && interfaceId_ == type(IConfigOperator).interfaceId) ||
            (_SUPPORTS_ENABLER && interfaceId_ == type(IEnabler).interfaceId);
    }
}

// forge-lint: disable-end(multi-contract-file)
