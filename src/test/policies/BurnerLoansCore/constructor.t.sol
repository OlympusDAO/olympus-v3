// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";

contract BurnerLoansCoreConstructorTest is BurnerLoansCoreTest {
    // Pending production-interface error; use the declared selector in acceptance tests.
    error BurnerLoansCore_InvalidOhm(address ohm);

    // Scenarios: BLCORE-CONSTRUCTOR-P03, BLCORE-CONSTRUCTOR-P04, BLCORE-CONSTRUCTOR-P05, BLCORE-CONSTRUCTOR-P06, BLCORE-CONSTRUCTOR-P07.
    function test_whenDeployed(
        address deployer_,
        uint8 decimals_,
        bool active_,
        bool enabled_
    ) public {
        decimals_ = uint8(bound(decimals_, 0, 36));
        vm.mockCall(address(_ohm), abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
        if (!enabled_) IEnabler(address(_depositManager)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(_depositManager));
        vm.recordLogs();
        vm.prank(deployer_);
        BurnerLoansCore fresh = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        assertEq(fresh.ohm(), address(_ohm), "Immutable OHM");
        assertEq(fresh.depositManager(), address(_depositManager), "Immutable DepositManager");
        assertFalse(fresh.isEnabled(), "Starts disabled");
        assertEq(fresh.payout(), address(0), "No child Payout");
        assertEq(vm.getNonce(address(fresh)), 1, "Constructor creates no child contract");
        assertEq(fresh.inventory(), address(0), "Inventory unset");
        assertEq(fresh.risk(), address(0), "Risk unset");
        assertEq(fresh.configOperator(), address(0), "Config unset");
        assertEq(fresh.gracePeriod(), 7 days, "Default grace");
        assertEq(fresh.lastTransitionAt(), 0, "No lifecycle transition");
        assertEq(fresh.authorizationNonces(deployer_), 0, "No initial nonce");
        assertEq(fresh.authorizationDeadlines(deployer_, _recipient), 0, "No grants");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Only grace initialization event, no child deployment event");
        assertEq(logs[0].emitter, address(fresh), "Constructor event emitter");
        assertEq(logs[0].topics[0], keccak256("GracePeriodSet(uint32)"), "Exact constructor event");
        assertEq(abi.decode(logs[0].data, (uint32)), 7 days, "Exact initial period");
    }

    // Scenarios: BLCORE-CONSTRUCTOR-P03.
    function test_whenDecimalsBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_whenDeployed(address(0), 0, true, true);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_whenDeployed(address(1), 1, true, true);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_whenDeployed(_recipient, 9, true, true);
        vm.revertToState(snapshot);
        snapshot = vm.snapshotState();
        test_whenDeployed(_recipient, 18, true, true);
        vm.revertToState(snapshot);
        test_whenDeployed(_recipient, 36, true, true);
    }

    // Scenarios: BLCORE-CONSTRUCTOR-I01.
    function test_givenZeroOhm_whenDeployed_reverts(address deployer_) public {
        vm.expectRevert(abi.encodeWithSelector(BurnerLoansCore_InvalidOhm.selector, address(0)));
        vm.prank(deployer_);
        new BurnerLoansCore(_kernel, IERC20(address(0)), IDepositManager(address(_depositManager)));
    }

    // Scenarios: BLCORE-CONSTRUCTOR-I02.
    function test_givenZeroDepositManager_whenDeployed_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(_kernel, IERC20(address(_ohm)), IDepositManager(address(0)));
    }

    // Scenarios: BLCORE-CONSTRUCTOR-I03.
    function test_givenEOADepositManager_whenDeployed_reverts(address deployer_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(0xBEEF)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(_kernel, IERC20(address(_ohm)), IDepositManager(address(0xBEEF)));
    }

    // Scenarios: BLCORE-CONSTRUCTOR-I04.
    function test_givenMissingInterface_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "supportsInterface(bytes4)",
                type(IDepositManagerV1_1).interfaceId
            ),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            IDepositManager(address(_depositManager))
        );
    }

    // Scenarios: BLCORE-CONSTRUCTOR-D01.
    function test_givenRevertingERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            IDepositManager(address(_depositManager))
        );
    }

    // Scenarios: BLCORE-CONSTRUCTOR-D02.
    function test_givenMalformedERC165_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            hex"01"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            IDepositManager(address(_depositManager))
        );
    }

    // Scenarios: BLCORE-CONSTRUCTOR-D03.
    function test_givenWrongKernel_whenDeployed_reverts(address deployer_) public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_depositManager),
                address(_kernel),
                address(0)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            IDepositManager(address(_depositManager))
        );
    }

    // Scenarios: BLCORE-CONSTRUCTOR-P01.
    function test_givenKernelGetterReverts_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_depositManager)
            )
        );
        vm.prank(deployer_);
        new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            IDepositManager(address(_depositManager))
        );
    }

    // Scenarios: BLCORE-CONSTRUCTOR-P02.
    function test_givenDecimalsGetterReverts_whenDeployed_reverts(address deployer_) public {
        vm.mockCallRevert(
            address(_ohm),
            abi.encodeWithSignature("decimals()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(abi.encodeWithSelector(BurnerLoansCore_InvalidOhm.selector, address(_ohm)));
        vm.prank(deployer_);
        new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            IDepositManager(address(_depositManager))
        );
    }

    // Scenarios: BLCORE-CONSTRUCTOR-N01.
    function test_givenUnsupportedDecimals_whenDeployed_reverts(
        address deployer_,
        uint8 decimals_
    ) public {
        decimals_ = uint8(bound(decimals_, 37, type(uint8).max));
        vm.mockCall(address(_ohm), abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
        vm.expectRevert(abi.encodeWithSelector(BurnerLoansCore_InvalidOhm.selector, address(_ohm)));
        vm.prank(deployer_);
        new BurnerLoansCore(_kernel, IERC20(address(_ohm)), _depositManager);
    }

    // Scenarios: BLCORE-CONSTRUCTOR-N01.
    function test_whenUnsupportedDecimalSeeds_reverts() public {
        test_givenUnsupportedDecimals_whenDeployed_reverts(_recipient, 37);
        test_givenUnsupportedDecimals_whenDeployed_reverts(address(0), type(uint8).max);
    }
}
