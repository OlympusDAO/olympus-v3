// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansActivator} from "src/proposals/interfaces/IBurnerLoansActivator.sol";

// Libraries
import {BL_COLLATERAL_POLICY_ROLE, BL_DEBT_POLICY_ROLE, BL_LIQUIDATION_POLICY_ROLE, BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {ADMIN_ROLE, BURNER_LOANS_SEIZER_ROLE, DEPOSIT_OPERATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansActivatorTest} from "./fixtures/BurnerLoansActivatorTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansActivator} from "src/proposals/BurnerLoansActivator.sol";

contract BurnerLoansActivatorActivateTest is BurnerLoansActivatorTest {
    error LateFailure();

    // Scenarios: BLAUNCH-A01.
    function test_whenCallerIsNotTimelock_reverts(address caller_) public {
        vm.assume(caller_ != _timelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_NotTimelock.selector,
                caller_
            )
        );
        vm.prank(caller_);
        _activator.activate();
        assertFalse(_activator.isActivated(), "Unauthorized launch preserves one-use state");
    }

    // Scenarios: BLAUNCH-P01.
    function test_givenPreparedStack_whenTimelockActivates() public {
        assertLe(address(_activator).code.length, 24_576, "Activator fits EIP-170");
        _activate();
        assertEq(
            IBurnerLoansRisk(_graph.risk).priceCache(),
            _graph.priceCache,
            "Risk uses deployed cache"
        );
        assertEq(
            IBurnerLoansRisk(_graph.risk).priceCacheMaxAge(),
            300,
            "Cache freshness is five minutes"
        );
        assertTrue(IEnabler(_graph.priceCache).isEnabled(), "Cache enabled by governance");
        assertTrue(
            IEnabler(_graph.revenueDistributor).isEnabled(),
            "Distributor enabled by governance"
        );
        assertEq(
            IConfigOperator(_graph.revenueDistributor).configOperator(),
            _graph.revenueDistributorTimelock,
            "Distributor uses its configuration queue"
        );
        assertTrue(
            IEnabler(_graph.revenueDistributorTimelock).isEnabled(),
            "Distributor queue enabled"
        );
        assertTrue(_activator.isActivated(), "Launch completes");
        (address selectedAuth, uint256 authEpoch) = IBurnerLoansCore(_graph.core).authConfig();
        assertEq(
            selectedAuth,
            _deployer.resolve("olympus.periphery.BurnerLoansAuth"),
            "Launch selects the deployed Core-bound Auth"
        );
        assertEq(authEpoch, 1, "Launch installs Auth exactly once");
        IBurnerLoansCore.AssetConfig memory usds = IBurnerLoansConfig(_graph.config).getAssetConfig(
            _graph.usds
        );
        IBurnerLoansCore.AssetConfig memory usde = IBurnerLoansConfig(_graph.config).getAssetConfig(
            _graph.usde
        );
        // OHM caps use 9 decimals; collateral keeper caps use 18 decimals.
        assertEq(usds.debtCap, 50_000e9, "USDS market debt cap");
        assertEq(usde.debtCap, 50_000e9, "USDe market debt cap");
        assertEq(usds.maxKeeperReward, 100e18, "USDS keeper reward cap");
        assertEq(usde.maxKeeperReward, 100e18, "USDe keeper reward cap");
        assertEq(usds.termLength, 30 days, "Initial loan term");
        assertEq(usde.maxMaturityHorizon, 90 days, "Extension horizon");
        assertEq(usds.maxLtvBps, 8500, "Maximum LTV");
        assertEq(usde.backingMultiplierBps, 12500, "Backing multiplier");
        assertFalse(usds.withdrawAsShares, "USDS exits use underlying");
        assertTrue(usde.withdrawAsShares, "USDe exits use vault shares");
        assertEq(
            IBurnerLoansInventory(_graph.inventory).globalDebtCapOhm(),
            100_000e9,
            "Global OHM debt cap"
        );
        (address retained, bytes4 selector) = _heart.getPeriodicTaskAtIndex(3);
        assertEq(retained, address(_existingTask), "Existing task order is retained");
        assertEq(selector, bytes4(0), "Existing task selector is retained");
    }

    // Scenarios: BLAUNCH-S01.
    function test_givenAlreadyActivated_whenTimelockActivates_reverts() public {
        _activate();
        vm.expectRevert(IBurnerLoansActivator.BurnerLoansActivator_AlreadyActivated.selector);
        _activate();
        assertEq(IBurnerLoansCore(_graph.core).getAssetCount(), 2, "Replay creates no market");
    }

    // Scenarios: BLAUNCH-S02.
    function test_givenInactivePolicy_whenTimelockActivates_reverts(uint8 index_) public {
        address[] memory targets = _deployer.policies();
        address target = targets[bound(index_, 0, targets.length - 1)];
        _kernel.executeAction(Actions.DeactivatePolicy, target);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                target
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-A02.
    function test_givenMissingRole_whenTimelockActivates_reverts(uint8 index_) public {
        address[7] memory holders = [
            address(_activator),
            _graph.core,
            _graph.collateral,
            _graph.debt,
            _graph.seize,
            _graph.yieldClaimerTask,
            _graph.seizerTask
        ];
        bytes32[7] memory roles = [
            ADMIN_ROLE,
            DEPOSIT_OPERATOR_ROLE,
            BL_COLLATERAL_POLICY_ROLE,
            BL_DEBT_POLICY_ROLE,
            BL_LIQUIDATION_POLICY_ROLE,
            BL_YIELD_CLAIMER_ROLE,
            BURNER_LOANS_SEIZER_ROLE
        ];
        uint256 index = bound(index_, 0, holders.length - 1);
        _rolesAdmin.revokeRole(roles[index], holders[index]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                holders[index]
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-C05.
    function test_givenWrongTimelockTarget_whenTimelockActivates_reverts(uint8 index_) public {
        address[5] memory queues = [
            _graph.configTimelock,
            _graph.riskTimelock,
            _graph.payoutTimelock,
            _graph.inventoryTimelock,
            _graph.revenueDistributorTimelock
        ];
        bytes[5] memory getters = [
            abi.encodeWithSignature("burnerLoans()"),
            abi.encodeWithSignature("risk()"),
            abi.encodeWithSignature("payout()"),
            abi.encodeWithSignature("inventory()"),
            abi.encodeWithSignature("distributor()")
        ];
        uint256 index = bound(index_, 0, queues.length - 1);
        vm.mockCall(queues[index], getters[index], abi.encode(address(0)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                queues[index]
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-C06.
    function test_whenAuthHasNoCode_reverts() public {
        _graph.auth = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                address(0)
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C07.
    function test_whenAuthBoundToDifferentCore_reverts() public {
        vm.mockCall(_graph.auth, abi.encodeWithSignature("core()"), abi.encode(_graph.config));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                _graph.auth
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C04.
    function test_whenRevenueTaskBoundToDifferentDistributor_reverts() public {
        vm.mockCall(
            _graph.revenueDistributorTask,
            abi.encodeWithSignature("distributor()"),
            abi.encode(_graph.core)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                _graph.revenueDistributorTask
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-O01.
    function test_givenBackingOracleDisabled_whenPreparationValidated_reverts() public {
        _oracle.disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.backingOracle
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-O02.
    function test_givenBackingOracleInactive_whenPreparationValidated_reverts() public {
        _kernel.executeAction(Actions.DeactivatePolicy, _graph.backingOracle);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.backingOracle
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-S03.
    function test_givenRiskPreviouslyEnabled_givenReferrerAllowed_whenTimelockActivates_reverts()
        public
    {
        IEnabler(_graph.risk).enable("");
        IBurnerLoansRisk(_graph.risk).setReferrerAllowed(address(0xFEE), true);
        IEnabler(_graph.risk).disable("");
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.risk
            )
        );
        _activate();
        _assertUnlaunched();
        assertTrue(
            IBurnerLoansRisk(_graph.risk).isReferrerAllowed(address(0xFEE)),
            "Failed launch preserves existing whitelist"
        );
    }

    // Scenarios: BLAUNCH-S04.
    function test_givenLateTaskFailure_whenTimelockActivates_reverts() public {
        vm.mockCallRevert(
            _graph.heart,
            abi.encodeCall(
                IPeriodicTaskManager.addPeriodicTaskAtIndex,
                (_graph.yieldClaimerTask, bytes4(0), 1)
            ),
            abi.encodeWithSelector(LateFailure.selector)
        );
        vm.expectRevert(LateFailure.selector);
        _activate();
        _assertUnlaunched();
        assertEq(_heart.getPeriodicTaskCount(), 1, "Earlier task insertion rolls back");
        assertFalse(_heart.hasPeriodicTask(_graph.seizerTask), "Seizer insertion rolls back");
    }

    // Scenarios: BLAUNCH-S05.
    function test_givenPriceSupportMissing_whenTimelockActivates_reverts(uint8 index_) public {
        address[2] memory assets = [_graph.ohm, _graph.usds];
        address asset = assets[bound(index_, 0, assets.length - 1)];
        vm.mockCall(
            address(_price),
            abi.encodeCall(IPRICEv2.isAssetApproved, (asset)),
            abi.encode(false)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                address(_price)
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-S06.
    function test_givenZeroBacking_whenTimelockActivates_reverts() public {
        _oracle.setBacking(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidPrerequisite.selector,
                _graph.backingOracle
            )
        );
        _activate();
        _assertUnlaunched();
    }

    // Scenarios: BLAUNCH-C01.
    function test_whenTimelockIsZero_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                address(0)
            )
        );
        new BurnerLoansActivator(address(0), _graph);
    }

    // Scenarios: BLAUNCH-C02.
    function test_whenComponentHasNoCode_reverts(address candidate_) public {
        vm.assume(candidate_.code.length == 0);
        _graph.core = candidate_;
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansActivator.BurnerLoansActivator_InvalidDeployment.selector,
                candidate_
            )
        );
        new BurnerLoansActivator(_timelock, _graph);
    }

    // Scenarios: BLAUNCH-C03.
    function test_whenCreatedByAnyCaller(address caller_) public {
        vm.prank(caller_);
        BurnerLoansActivator subject = new BurnerLoansActivator(_timelock, _graph);
        assertEq(subject.timelock(), _timelock, "Constructor caller gains no authority");
    }

    function _assertUnlaunched() internal view {
        assertFalse(_activator.isActivated(), "Failed launch restores one-use state");
        assertFalse(IEnabler(_graph.priceCache).isEnabled(), "Cache enablement rolls back");
        assertFalse(
            IEnabler(_graph.revenueDistributor).isEnabled(),
            "Distributor enablement rolls back"
        );
        assertEq(
            IBurnerLoansRisk(_graph.risk).priceCache(),
            address(0),
            "Risk cache binding rolls back"
        );
        assertFalse(IEnabler(_graph.depositManager).isEnabled(), "Custody enablement rolls back");
        assertFalse(IEnabler(_graph.core).isEnabled(), "Core enablement rolls back");
        assertEq(IBurnerLoansCore(_graph.core).getAssetCount(), 0, "Market creation rolls back");
        assertEq(
            IBurnerLoansInventory(_graph.inventory).globalDebtCapOhm(),
            0,
            "Global cap rolls back"
        );
    }
}
