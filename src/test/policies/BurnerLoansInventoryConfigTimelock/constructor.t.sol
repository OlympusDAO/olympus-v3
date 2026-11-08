// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Bounded seed loops intentionally repeat isolated contract calls.
// Literal amounts, delays and timestamps are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansInventoryConfigTimelock} from "src/policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansInventoryConfigTimelockTest} from "./BurnerLoansInventoryConfigTimelockTest.sol";
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansInventoryConfigTimelock} from "src/policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol";

contract BurnerLoansInventoryConfigTimelockConstructorTest is
    BurnerLoansInventoryConfigTimelockTest
{
    error TargetViewFailed();

    // Scenarios: BLINCT-CONSTRUCTOR-I01.
    function test_whenInventoryZero_reverts(address deployer_) public {
        _expectInvalidInventory(address(0), deployer_);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I02.
    function test_whenInventoryEOA_reverts(address candidate_, address deployer_) public {
        vm.assume(candidate_ != address(0) && candidate_.code.length == 0);
        _expectInvalidInventory(candidate_, deployer_);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I03, BLINCT-CONSTRUCTOR-I04, BLINCT-CONSTRUCTOR-I10.
    function test_givenRequiredInterfaceMissing_whenDeployed_reverts(
        uint8 index_,
        address deployer_
    ) public {
        bytes4[3] memory ids = [
            type(IBurnerLoansInventory).interfaceId,
            type(IEnabler).interfaceId,
            type(IConfigOperator).interfaceId
        ];
        bytes4 id = ids[bound(index_, 0, 2)];
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature("supportsInterface(bytes4)", id),
            abi.encode(false)
        );
        _expectInvalidInventory(address(_inventory), deployer_);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I05.
    function test_givenInventoryOnOtherKernel_whenDeployed_reverts(address deployer_) public {
        Kernel other = new Kernel();
        _mockInventoryKernel(address(other));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_inventory),
                address(_kernel),
                address(other)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansInventoryConfigTimelock(_kernel, _inventory);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I06.
    function test_givenERC165Reverts_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansInventory).interfaceId
            ),
            abi.encodeWithSelector(TargetViewFailed.selector)
        );
        _expectInvalidInventory(address(_inventory), deployer_);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I07.
    function test_givenERC165Malformed_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_inventory),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IBurnerLoansInventory).interfaceId
            ),
            hex"01"
        );
        _expectInvalidInventory(address(_inventory), deployer_);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I08.
    function test_givenKernelViewReverts_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(TargetViewFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_inventory)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansInventoryConfigTimelock(_kernel, _inventory);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I09.
    function test_givenKernelViewEmpty_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(address(_inventory), abi.encodeWithSignature("kernel()"), bytes(""));
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_inventory)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansInventoryConfigTimelock(_kernel, _inventory);
    }

    // Scenarios: BLINCT-CONSTRUCTOR-P01, BLINCT-CONSTRUCTOR-P02, BLINCT-CONSTRUCTOR-P03, BLINCT-CONSTRUCTOR-P04.
    function test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults(
        bool active_,
        bool enabled_,
        address deployer_
    ) public {
        _setState(_inventory, active_, enabled_);
        bytes32 funds = _inventoryDigest();
        vm.expectEmit();
        emit IGracePeriod.GracePeriodSet(7 days);
        vm.expectEmit();
        emit ITimelockBatchQueue.TimelockDelaySet(1 days);
        vm.prank(deployer_);
        BurnerLoansInventoryConfigTimelock fresh = new BurnerLoansInventoryConfigTimelock(
            _kernel,
            _inventory
        );
        assertEq(address(fresh.inventory()), address(_inventory), "Immutable target");
        assertEq(address(fresh.kernel()), address(_kernel), "Initial Kernel");
        assertFalse(fresh.isEnabled(), "New timelock disabled");
        assertFalse(fresh.isActive(), "New timelock inactive");
        assertEq(fresh.lastTransitionAt(), 0, "No prior transition");
        assertEq(fresh.gracePeriod(), 7 days, "Default recovery grace");
        assertEq(fresh.timelockDelay(), 1 days, "Default notice");
        assertEq(fresh.MIN_TIMELOCK_DELAY(), 1 days, "Minimum notice");
        assertEq(fresh.MAX_TIMELOCK_DELAY(), 30 days, "Maximum notice");
        assertEq(fresh.EXECUTION_WINDOW(), 3 days, "Inclusive execution window");
        assertEq(fresh.nextActionId(), 1, "Counter starts at one");
        assertEq(fresh.maxConfigKeysPerBatch(), 15, "Inherited key bound");
        assertEq(address(fresh.ROLES()), address(0), "Construction does not resolve ROLES");
        assertFalse(_roles.hasRole(address(fresh), ADMIN_ROLE), "No implicit ADMIN grant");
        assertEq(_ohm.balanceOf(address(fresh)), 0, "No funds delivered");
        assertEq(_inventoryDigest(), funds, "Construction preserves live Inventory accounting");
    }

    // Scenarios: BLINCT-CONSTRUCTOR-I03, BLINCT-CONSTRUCTOR-I04, BLINCT-CONSTRUCTOR-I10.
    function test_givenEachRequiredInterfaceMissing_whenDeployed_reverts() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 i; i < 3; ++i) {
            test_givenRequiredInterfaceMissing_whenDeployed_reverts(i, address(this));
            _restore(checkpoint);
        }
    }

    // Scenarios: BLINCT-CONSTRUCTOR-P05.
    function test_givenRuntimeReadinessGettersRevert_whenConstructed(address deployer_) public {
        vm.mockCallRevert(address(_inventory), abi.encodeWithSignature("isEnabled()"), hex"ff");
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSignature("configOperator()"),
            hex"ff"
        );
        vm.mockCallRevert(
            address(_kernel),
            abi.encodeWithSignature("isPolicyActive(address)", address(_inventory)),
            hex"ff"
        );
        vm.prank(deployer_);
        BurnerLoansInventoryConfigTimelock fresh = new BurnerLoansInventoryConfigTimelock(
            _kernel,
            _inventory
        );
        assertEq(
            address(fresh.inventory()),
            address(_inventory),
            "Compatible target bound without readiness reads"
        );
        assertFalse(fresh.isEnabled(), "Construction leaves queue disabled");
    }

    function _expectInvalidInventory(address inventory_, address deployer_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventoryConfigTimelock
                    .BurnerLoansInventoryTimelock_InvalidInventory
                    .selector,
                inventory_
            )
        );
        vm.prank(deployer_);
        new BurnerLoansInventoryConfigTimelock(_kernel, IBurnerLoansInventory(inventory_));
    }

    // Scenarios: BLINCT-CONSTRUCTOR-P01, BLINCT-CONSTRUCTOR-P02, BLINCT-CONSTRUCTOR-P03, BLINCT-CONSTRUCTOR-P04.
    function test_givenEachInventoryLifecyclePair_whenDeployed_thenExactDefaults() public {
        uint256 checkpoint = vm.snapshotState();
        for (uint256 active; active < 2; ++active) {
            for (uint256 enabled; enabled < 2; ++enabled) {
                test_givenAnyInventoryLifecycle_whenDeployed_thenExactDefaults(
                    active != 0,
                    enabled != 0,
                    address(0)
                );
                _restore(checkpoint);
            }
        }
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
