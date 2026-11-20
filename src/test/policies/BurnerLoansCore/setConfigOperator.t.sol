// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansCoreTest} from "./BurnerLoansCoreTest.sol";
import {CoreService} from "./fixtures/CoreService.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansCore} from "src/policies/burnerloans/BurnerLoansCore.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract BurnerLoansCoreSetConfigOperatorTest is BurnerLoansCoreTest {
    // Scenarios: BLCORE-CONFIGURATOR-A01.
    function test_givenUnauthorized_whenConfigOperatorSet_reverts(
        address caller_,
        address next_,
        bool enabled_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _setCoreLifecycle(true, enabled_);
        bytes32 before = _state();
        vm.expectCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketManager.selector),
            uint64(0)
        );
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _core.setConfigOperator(next_);
        assertEq(_state(), before, "Unauthorized selection preserves state");
    }

    // Scenarios: BLCORE-CONFIGURATOR-L03, BLCORE-CONFIGURATOR-L04.
    function test_givenCoreInactive_whenConfigOperatorSet_reverts(
        address caller_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        _setCoreLifecycle(false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        _core.setConfigOperator(address(0));
    }

    // Scenarios: BLCORE-CONFIGURATOR-D01.
    function test_whenZeroConfigOperatorSet_reverts() public {
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector);
        _core.setConfigOperator(address(0));
    }

    // Scenarios: BLCORE-CONFIGURATOR-D02.
    function test_givenSameConfigOperator_whenSelected_reverts() public {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectCall(
            address(_floan),
            abi.encodeCall(
                IFLOANv1.setMarketManager,
                (_core.marketId(address(_asset)), address(_config))
            ),
            uint64(0)
        );
        vm.recordLogs();
        vm.expectRevert(IConfigOperator.ConfigOperator_Unchanged.selector);
        _core.setConfigOperator(address(_config));
        assertEq(_core.configOperator(), address(_config), "Config authority unchanged");
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged authority emits no event");
    }

    // Scenarios: BLCORE-CONFIGURATOR-L01, BLCORE-CONFIGURATOR-L02, BLCORE-CONFIGURATOR-P01.
    function test_givenCompatibleAuthority_whenConfigOperatorSet(
        address caller_,
        address next_,
        bool enabled_
    ) public {
        _grantAdmin(caller_);
        vm.assume(next_ != address(0) && next_ != address(_config));
        _deposit(2000e6);
        _borrow(100e9);
        _setCoreLifecycle(true, enabled_);
        bytes32 ledger = _ledger();
        address riskOperator = _risk.configOperator();
        address inventoryOperator = _inventory.configOperator();
        address payoutOperator = _payout.configOperator();
        uint32 id = _core.marketId(address(_asset));
        vm.expectEmit(true, false, false, true, address(_core));
        emit IConfigOperator.ConfigOperatorSet(next_);
        vm.prank(caller_);
        _core.setConfigOperator(next_);
        assertEq(_core.configOperator(), next_, "Trusted Config authority selected");
        assertEq(_floan.getMarket(id).manager, next_, "FLOAN manager follows Config authority");
        assertEq(_core.marketId(address(_asset)), id, "Market id stable");
        assertEq(_risk.configOperator(), riskOperator, "Risk controller independent");
        assertEq(
            _inventory.configOperator(),
            inventoryOperator,
            "Inventory controller independent"
        );
        assertEq(_payout.configOperator(), payoutOperator, "Payout controller independent");
        assertEq(_ledger(), ledger, "Handoff preserves debt and custody");
    }

    // Scenarios: BLCORE-CONFIGURATOR-D03.
    function test_givenCandidateLifecycleIndependent_whenConfigOperatorSet(
        bool active_,
        bool enabled_
    ) public {
        CoreService next = _service();
        _setPolicyLifecycle(next, active_, enabled_);
        _core.setConfigOperator(address(next));
        assertEq(
            _core.configOperator(),
            address(next),
            "Config lifecycle is upstream responsibility"
        );
    }

    // Scenarios: BLCORE-CONFIGURATOR-D04.
    function test_givenCandidateGettersRevert_whenConfigOperatorSet() public {
        CoreService next = _service();
        vm.mockCallRevert(
            address(next),
            bytes(""),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        _core.setConfigOperator(address(next));
        assertEq(_core.configOperator(), address(next), "Core queries no candidate metadata");
    }

    // Scenarios: BLCORE-CONFIGURATOR-P04.
    function test_givenIndependentRiskAuthority_whenConfigOperatorSet(
        address riskOperator_
    ) public {
        vm.assume(riskOperator_ != address(0xCAFE));
        vm.assume(riskOperator_ != address(_config));
        _risk.setConfigOperator(riskOperator_);
        address oracle = _risk.backingOracle();
        address cache = _risk.priceCache();
        uint48 cacheAge = _risk.priceCacheMaxAge();
        address inventoryOperator = _inventory.configOperator();
        address payoutOperator = _payout.configOperator();
        _core.setConfigOperator(address(0xCAFE));
        assertEq(_risk.configOperator(), riskOperator_, "Risk authority untouched");
        assertEq(_risk.backingOracle(), oracle, "Risk oracle untouched");
        assertEq(_risk.priceCache(), cache, "Risk cache untouched");
        assertEq(_risk.priceCacheMaxAge(), cacheAge, "Risk cache age untouched");
        assertEq(_inventory.configOperator(), inventoryOperator, "Inventory authority untouched");
        assertEq(_payout.configOperator(), payoutOperator, "Payout authority untouched");
        assertEq(
            _floan.getMarket(_core.marketId(address(_asset))).manager,
            address(0xCAFE),
            "Registered market manager follows Core authority"
        );
        assertEq(
            _core.configOperator(),
            address(0xCAFE),
            "Config handoff requires no Risk preparation"
        );
    }

    // Scenarios: BLCORE-CONFIGURATOR-D05.
    function test_givenRiskMetadataUnavailable_whenConfigOperatorSet(
        bool active_,
        bool enabled_
    ) public {
        _setPolicyLifecycle(_risk, active_, enabled_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSignature("configurator()"),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        _core.setConfigOperator(address(0xCAFE));
        assertEq(
            _core.configOperator(),
            address(0xCAFE),
            "Core does not inspect independent Risk authority"
        );
    }

    // Scenarios: BLCORE-CONFIGURATOR-P04.
    function test_whenIndependentRiskAuthoritySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenIndependentRiskAuthority_whenConfigOperatorSet(address(0));
        vm.revertToState(snapshot);
        test_givenIndependentRiskAuthority_whenConfigOperatorSet(_recipient);
    }

    // Scenarios: BLCORE-CONFIGURATOR-P02.
    function test_givenLateManagerFailure_whenConfigOperatorSet_reverts() public {
        MockERC20 second = new MockERC20("Other", "OTH", 6);
        _price.setPrice(address(second), 1e18);
        _admit(address(second));
        uint32 firstId = _core.marketId(address(_asset));
        uint32 secondId = _core.marketId(address(second));
        address firstManager = _floan.getMarket(firstId).manager;
        // Isolate the manager rollback boundary; Risk preparation is a separate red acceptance case.
        vm.mockCall(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            abi.encode(address(0xCAFE))
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketManager.selector, secondId, address(0xCAFE)),
            abi.encodeWithSelector(DependencyFailed.selector)
        );
        vm.expectRevert(DependencyFailed.selector);
        _core.setConfigOperator(address(0xCAFE));
        assertEq(
            _floan.getMarket(firstId).manager,
            firstManager,
            "Earlier manager write rolled back"
        );
        assertEq(_core.configOperator(), address(_config), "Selected Config rolled back");
    }

    // Scenarios: BLCORE-CONFIGURATOR-P01.
    function test_givenNoMarkets_whenConfigOperatorSelected(address next_) public {
        vm.assume(next_ != address(0));
        BurnerLoansCore fresh = new BurnerLoansCore(
            _kernel,
            IERC20(address(_ohm)),
            _depositManager
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(fresh));
        vm.expectEmit(true, false, false, true, address(fresh));
        emit IConfigOperator.ConfigOperatorSet(next_);
        fresh.setConfigOperator(next_);
        assertEq(fresh.getAssetCount(), 0, "Empty market collection remains empty");
        assertEq(
            fresh.configOperator(),
            next_,
            "First trusted authority selected without a Risk prerequisite"
        );
    }

    // Scenarios: BLCORE-CONFIGURATOR-P01.
    function test_givenMultipleMarkets_whenConfigOperatorSelected() public {
        MockERC20 other = new MockERC20("Second", "SEC", 6);
        _price.setPrice(address(other), 1e18);
        _admit(address(other));
        uint32 first = _core.marketId(address(_asset));
        uint32 second = _core.marketId(address(other));
        bytes32 ledger = _ledger();
        _core.setConfigOperator(_recipient);
        assertEq(_floan.getMarket(first).manager, _recipient, "First manager transferred");
        assertEq(_floan.getMarket(second).manager, _recipient, "Second manager transferred");
        assertEq(_core.getAssetCount(), 2, "No asset duplicated or removed");
        assertEq(_ledger(), ledger, "Manager rotation moves no custody or debt");
    }

    // Scenarios: BLCORE-CONFIGURATOR-L03, BLCORE-CONFIGURATOR-L04.
    function test_givenInactive_whenUnauthorizedAndInvalid_reverts(
        address caller_,
        bool enabled_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _setCoreLifecycle(false, enabled_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_core)
            )
        );
        vm.prank(caller_);
        _core.setConfigOperator(address(0));
    }
}
