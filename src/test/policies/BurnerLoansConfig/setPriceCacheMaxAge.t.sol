// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";
import {Vm} from "@forge-std-1.16.2/Vm.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";
import {BurnerLoansConfigTest} from "src/test/policies/BurnerLoansConfig/BurnerLoansConfigTest.sol";

contract BurnerLoansConfigSetPriceCacheMaxAgeTest is BurnerLoansConfigTest {
    error RiskLookupFailed();
    error AgeRejected(uint48 age);

    function _riskState() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _risk.backingOracle(),
                    _risk.priceCache(),
                    _risk.configOperator(),
                    _risk.gracePeriod(),
                    _risk.isEnabled(),
                    _risk.lastTransitionAt()
                )
            );
    }

    function _assertAgeChanged(address caller_, uint48 age_) private {
        bytes32 configBefore = _stateDigest();
        bytes32 riskBefore = _riskState();
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IBurnerLoansRisk.PriceCacheMaxAgeSet(age_);
        vm.recordLogs();
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (age_)),
            uint64(1)
        );
        vm.prank(caller_);
        _config.setPriceCacheMaxAge(age_);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one downstream event, no Config event");
        assertEq(logs[0].emitter, address(_risk), "Risk emits the cache-age event");
        assertEq(_risk.priceCacheMaxAge(), age_, "exact forwarded age stored on Risk");
        assertEq(_stateDigest(), configBefore, "Config and economic state unchanged");
        assertEq(_riskState(), riskBefore, "other Risk settings and lifecycle unchanged");
    }

    function _assertAgeUnchanged(address caller_, uint48 age_) private {
        bytes32 configBefore = _stateDigest();
        bytes32 riskBefore = _riskState();
        vm.recordLogs();
        vm.record();
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (age_)),
            uint64(1)
        );
        vm.prank(caller_);
        _config.setPriceCacheMaxAge(age_);
        assertEq(vm.getRecordedLogs().length, 0, "unchanged age emits no events");
        (, bytes32[] memory configWrites) = vm.accesses(address(_config));
        (, bytes32[] memory riskWrites) = vm.accesses(address(_risk));
        assertEq(configWrites.length, 0, "Config writes no storage");
        assertEq(riskWrites.length, 0, "Risk writes no storage for unchanged age");
        assertEq(_risk.priceCacheMaxAge(), age_, "unchanged authoritative age");
        assertEq(_stateDigest(), configBefore, "Config and economic state unchanged");
        assertEq(_riskState(), riskBefore, "other Risk state unchanged");
    }

    function _ageReverts(address caller_, uint48 age_, bytes memory error_) private {
        uint48 beforeAge = _risk.priceCacheMaxAge();
        bytes32 riskBefore = _riskState();
        _mutationReverts(caller_, abi.encodeCall(_config.setPriceCacheMaxAge, (age_)), error_);
        assertEq(_risk.priceCacheMaxAge(), beforeAge, "rejection preserves Risk age");
        assertEq(_riskState(), riskBefore, "rejection preserves other Risk state");
    }

    function _expectNoForward(uint48 age_) private {
        vm.expectCall(address(_core), abi.encodeCall(IBurnerLoansCore.risk, ()), uint64(0));
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (age_)),
            uint64(0)
        );
    }

    function _rejectRiskLookup() private {
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(IBurnerLoansCore.risk, ()),
            abi.encodeWithSelector(RiskLookupFailed.selector)
        );
    }

    function _changedAges(address caller_, uint48 previous_, uint48 age_) private {
        vm.assume(previous_ != age_);
        _risk.setPriceCacheMaxAge(previous_);
        _assertAgeChanged(caller_, age_);
    }

    function _boundaryAges(address caller_) private {
        _assertAgeChanged(caller_, 1);
        _assertAgeChanged(caller_, 0);
        _assertAgeChanged(caller_, type(uint48).max);
    }

    function _assertNoRiskAuthority() private {
        _ageReverts(address(this), 0, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        _ageReverts(
            _configurationCaller,
            1,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, _configurationCaller);
        _ageReverts(
            _configurationCaller,
            type(uint48).max,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    function _disabledConfigRejectsCallerSeeds() private {
        _expectNoForward(1);
        bytes memory failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);
        _ageReverts(address(this), 1, failure);
        _ageReverts(_configurationCaller, 1, failure);
        _ageReverts(_borrower, 1, failure);
        _ageReverts(address(0), 1, failure);
        _rolesAdmin.grantRole(ADMIN_ROLE, _configurationCaller);
        _ageReverts(_configurationCaller, 1, failure);
    }

    function _coreStateAcceptsChange(bool active_, bool enabled_, uint48 age_) private {
        uint256 checkpoint = vm.snapshotState();
        _setPolicyState(_core, active_, enabled_);
        _assertAgeChanged(_configurationCaller, age_);
        assertTrue(vm.revertToStateAndDelete(checkpoint), "restore Core lifecycle seed");
    }

    function _coreStateAcceptsNoOp(bool active_, bool enabled_, uint48 age_) private {
        uint256 checkpoint = vm.snapshotState();
        _setPolicyState(_core, active_, enabled_);
        _risk.setPriceCacheMaxAge(age_);
        _assertAgeUnchanged(_configurationCaller, age_);
        assertTrue(vm.revertToStateAndDelete(checkpoint), "restore Core lifecycle seed");
    }

    function _selectReplacementRisk() private returns (BurnerLoansRisk previous) {
        previous = _risk;
        _risk = new BurnerLoansRisk(
            _kernel,
            IERC20(address(_ohm)),
            previous.backingOracle(),
            address(0),
            0,
            address(_core)
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(_risk));
        _risk.setConfigOperator(address(_config));
        _risk.enable("");
        _core.setRisk(address(_risk));
    }

    // Scenarios: BLCFG-CACHE-AGE-A01.
    function test_whenUnauthorizedCallerConfiguresCacheAge_reverts() public {
        _expectNoForward(1);
        _ageReverts(_borrower, 1, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-A01.
    function test_whenUnauthorizedCallerConfiguresAnyAge_reverts(
        address caller_,
        uint48 age_
    ) public {
        _excludeConfigCallers(caller_);
        _expectNoForward(age_);
        _ageReverts(caller_, age_, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-A01.
    function test_whenUnauthorizedCallerSeedsConfigureAge_reverts() public {
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, _recipient);
        _expectNoForward(1);
        _ageReverts(address(0), 1, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
        _ageReverts(
            address(_price),
            1,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _ageReverts(_recipient, 1, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-A01.
    function test_givenRiskOnlyOperator_whenConfigCalled_reverts() public {
        _risk.setConfigOperator(_borrower);
        _expectNoForward(1);
        _ageReverts(_borrower, 1, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-A02, BLCFG-CACHE-AGE-L01, BLCFG-CACHE-AGE-N01.
    function test_givenAdminOnly_whenAgeChanged(
        address caller_,
        uint48 previous_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, true, false) {
        _changedAges(caller_, previous_, age_);
    }

    // Scenarios: BLCFG-CACHE-AGE-P01.
    function test_givenAdminOnly_whenAgeUnchanged(
        address caller_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, true, false) {
        _risk.setPriceCacheMaxAge(age_);
        _assertAgeUnchanged(caller_, age_);
    }

    // Scenarios: BLCFG-CACHE-AGE-L03.
    function test_givenInactiveConfig_whenAdminOnlyCalls_reverts(
        address caller_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, true, false) givenConfigInactive {
        _rejectRiskLookup();
        _expectNoForward(age_);
        _ageReverts(caller_, age_, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-CACHE-AGE-A02, BLCFG-CACHE-AGE-N02.
    function test_givenAdminOnly_whenAgeBoundaries() public {
        _boundaryAges(address(this));
    }

    // Scenarios: BLCFG-CACHE-AGE-A02, BLCFG-CACHE-AGE-L01, BLCFG-CACHE-AGE-N01.
    function test_givenOperatorOnly_whenAgeChanged(
        address caller_,
        uint48 previous_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, false, true) {
        _changedAges(caller_, previous_, age_);
    }

    // Scenarios: BLCFG-CACHE-AGE-P01.
    function test_givenOperatorOnly_whenAgeUnchanged(
        address caller_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, false, true) {
        _risk.setPriceCacheMaxAge(age_);
        _assertAgeUnchanged(caller_, age_);
    }

    // Scenarios: BLCFG-CACHE-AGE-L03.
    function test_givenInactiveConfig_whenOperatorOnlyCalls_reverts(
        address caller_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, false, true) givenConfigInactive {
        _rejectRiskLookup();
        _expectNoForward(age_);
        _ageReverts(caller_, age_, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-CACHE-AGE-A02, BLCFG-CACHE-AGE-N02.
    function test_givenOperatorOnly_whenAgeBoundaries() public {
        _boundaryAges(_configurationCaller);
    }

    // Scenarios: BLCFG-CACHE-AGE-A02, BLCFG-CACHE-AGE-L01, BLCFG-CACHE-AGE-N01.
    function test_givenAdminAndOperator_whenAgeChanged(
        address caller_,
        uint48 previous_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, true, true) {
        _changedAges(caller_, previous_, age_);
    }

    // Scenarios: BLCFG-CACHE-AGE-P01.
    function test_givenAdminAndOperator_whenAgeUnchanged(
        address caller_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, true, true) {
        _risk.setPriceCacheMaxAge(age_);
        _assertAgeUnchanged(caller_, age_);
    }

    // Scenarios: BLCFG-CACHE-AGE-L03.
    function test_givenInactiveConfig_whenAdminAndOperatorCalls_reverts(
        address caller_,
        uint48 age_
    ) public givenConfigurationCaller(caller_, true, true) givenConfigInactive {
        _rejectRiskLookup();
        _expectNoForward(age_);
        _ageReverts(caller_, age_, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-CACHE-AGE-A02, BLCFG-CACHE-AGE-N02.
    function test_givenAdminAndOperator_whenAgeBoundaries() public {
        _rolesAdmin.grantRole(ADMIN_ROLE, _configurationCaller);
        _boundaryAges(_configurationCaller);
    }

    // Scenarios: BLCFG-CACHE-AGE-A01, BLCFG-CACHE-AGE-A03.
    function test_givenOperatorReplaced_whenFormerOperatorCalls_reverts() public {
        address former = _configurationCaller;
        _config.setConfigOperator(_recipient);
        _expectNoForward(1);
        _ageReverts(former, 1, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-A06.
    function test_givenOperatorReplaced_whenNewOperatorCalls() public {
        _config.setConfigOperator(_recipient);
        _assertAgeChanged(_recipient, 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-A04.
    function test_givenConfigOperatorUnset_whenAdminCalls() public {
        _config.setConfigOperator(address(0));
        _assertAgeChanged(address(this), 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-A01.
    function test_givenConfigOperatorUnset_whenZeroCallerCalls_reverts() public {
        _config.setConfigOperator(address(0));
        _expectNoForward(1);
        _ageReverts(address(0), 1, abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-A05.
    function test_givenInactiveConfig_whenUnauthorizedCallerCalls_reverts(
        address caller_
    ) public givenConfigInactive {
        _excludeConfigCallers(caller_);
        _rejectRiskLookup();
        _expectNoForward(1);
        _ageReverts(caller_, 1, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-CACHE-AGE-L02.
    function test_givenDisabledConfig_whenAnyCallerCalls_reverts(
        address caller_,
        uint48 age_
    ) public givenConfigDisabled {
        _rejectRiskLookup();
        _expectNoForward(age_);
        _ageReverts(caller_, age_, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-L04.
    function test_givenInactiveDisabledConfig_whenAnyCallerCalls_reverts(
        address caller_,
        uint48 age_
    ) public givenConfigDisabled givenConfigInactive {
        _expectNoForward(age_);
        _ageReverts(caller_, age_, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-CACHE-AGE-L02.
    function test_givenDisabledConfig_whenCallerSeedsCall_reverts() public givenConfigDisabled {
        _rejectRiskLookup();
        _disabledConfigRejectsCallerSeeds();
    }

    // Scenarios: BLCFG-CACHE-AGE-L04.
    function test_givenInactiveDisabledConfig_whenCallerSeedsCall_reverts()
        public
        givenConfigDisabled
        givenConfigInactive
    {
        _expectNoForward(1);
        _ageReverts(address(this), 1, _inactiveError(address(_config)));
        _ageReverts(_configurationCaller, 1, _inactiveError(address(_config)));
        _ageReverts(_borrower, 1, _inactiveError(address(_config)));
        _ageReverts(address(0), 1, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-CACHE-AGE-L05.
    function test_givenReEnabledConfig_whenAgeChanged() public {
        _config.disable("");
        _config.reEnable();
        _assertAgeChanged(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-D01.
    function test_givenConfigNotRiskOperator_whenPermittedCallersCall_reverts() public {
        _risk.setConfigOperator(_recipient);
        _assertNoRiskAuthority();
    }

    // Scenarios: BLCFG-CACHE-AGE-D01.
    function test_givenRiskOperatorUnset_whenPermittedCallersCall_reverts() public {
        _risk.setConfigOperator(address(0));
        _assertNoRiskAuthority();
    }

    // Scenarios: BLCFG-CACHE-AGE-D02.
    function test_givenDisabledRisk_whenAgeSet_reverts(uint48 age_) public {
        _setPolicyState(_risk, true, false);
        _ageReverts(
            _configurationCaller,
            age_,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-CACHE-AGE-D02.
    function test_givenDisabledRisk_whenAgeUnchanged_reverts() public {
        _setPolicyState(_risk, true, false);
        _ageReverts(_configurationCaller, 0, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-D03.
    function test_givenInactiveRisk_whenAgeSet_reverts(uint48 age_) public {
        _setPolicyState(_risk, false, true);
        _ageReverts(_configurationCaller, age_, _inactiveError(address(_risk)));
    }

    // Scenarios: BLCFG-CACHE-AGE-D03.
    function test_givenInactiveRisk_whenAgeUnchanged_reverts() public {
        _setPolicyState(_risk, false, true);
        _ageReverts(_configurationCaller, 0, _inactiveError(address(_risk)));
    }

    // Scenarios: BLCFG-CACHE-AGE-D04.
    function test_givenInactiveDisabledRisk_whenAgeSet_reverts(uint48 age_) public {
        _setPolicyState(_risk, false, false);
        _ageReverts(_configurationCaller, age_, _inactiveError(address(_risk)));
    }

    // Scenarios: BLCFG-CACHE-AGE-D05.
    function test_givenConfigHoldsRiskAdmin_whenAnotherRiskOperatorSelected() public {
        _risk.setConfigOperator(_recipient);
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_config));
        _assertAgeChanged(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-D06.
    function test_givenReEnabledRisk_whenAgeChanged() public {
        _risk.disable("");
        _risk.reEnable();
        _assertAgeChanged(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-P01.
    function test_whenUnchangedAgeEndpoints() public {
        _assertAgeUnchanged(_configurationCaller, 0);
        _risk.setPriceCacheMaxAge(1);
        _assertAgeUnchanged(_configurationCaller, 1);
        _risk.setPriceCacheMaxAge(type(uint48).max);
        _assertAgeUnchanged(_configurationCaller, type(uint48).max);
    }

    // Scenarios: BLCFG-CACHE-AGE-P02.
    function test_givenIndependentCoreState_whenAgeChanged(bool active_, bool enabled_) public {
        _setPolicyState(_core, active_, enabled_);
        _assertAgeChanged(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-P02.
    function test_givenIndependentCoreState_whenAgeUnchanged(bool active_, bool enabled_) public {
        _setPolicyState(_core, active_, enabled_);
        _assertAgeUnchanged(_configurationCaller, 0);
    }

    // Scenarios: BLCFG-CACHE-AGE-P02.
    function test_whenCoreLifecycleChangeSeeds() public {
        _coreStateAcceptsChange(true, true, 1);
        _coreStateAcceptsChange(true, false, 2);
        _coreStateAcceptsChange(false, true, 3);
        _coreStateAcceptsChange(false, false, type(uint48).max);
    }

    // Scenarios: BLCFG-CACHE-AGE-P02.
    function test_whenCoreLifecycleNoOpSeeds() public {
        _coreStateAcceptsNoOp(true, true, 0);
        _coreStateAcceptsNoOp(true, false, 1);
        _coreStateAcceptsNoOp(false, true, 2);
        _coreStateAcceptsNoOp(false, false, type(uint48).max);
    }

    // Scenarios: BLCFG-CACHE-AGE-P03.
    function test_givenRiskReplacement_whenAgeChanged() public {
        _risk.setPriceCacheMaxAge(5);
        BurnerLoansRisk previous = _selectReplacementRisk();
        vm.expectCall(
            address(previous),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (uint48(7))),
            uint64(0)
        );
        _assertAgeChanged(_configurationCaller, 7);
        assertEq(previous.priceCacheMaxAge(), 5, "old Risk age untouched");
    }

    // Scenarios: BLCFG-CACHE-AGE-P04.
    function test_givenUnrelatedCoreGettersRevert_whenAgeChanged() public {
        bytes memory failure = abi.encodeWithSelector(RiskLookupFailed.selector);
        vm.mockCallRevert(address(_core), abi.encodeWithSignature("kernel()"), failure);
        vm.mockCallRevert(address(_core), abi.encodeCall(IEnabler.isEnabled, ()), failure);
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(IConfigOperator.configOperator, ()),
            failure
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(IBurnerLoansCore.requireNotReentrant, ()),
            failure
        );
        vm.expectCall(address(_core), abi.encodeCall(IBurnerLoansCore.risk, ()), uint64(1));
        _assertAgeChanged(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-CACHE-AGE-T01.
    function test_givenCoreRiskLookupReverts_whenAgeSet_reverts(uint48 age_) public {
        _rejectRiskLookup();
        vm.expectCall(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (age_)),
            uint64(0)
        );
        _ageReverts(_configurationCaller, age_, abi.encodeWithSelector(RiskLookupFailed.selector));
    }

    // Scenarios: BLCFG-CACHE-AGE-T02.
    function test_givenRiskSetterReverts_whenAgeSet_reverts(uint48 age_) public {
        bytes memory failure = abi.encodeWithSelector(AgeRejected.selector, age_);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(IBurnerLoansRisk.setPriceCacheMaxAge, (age_)),
            failure
        );
        _ageReverts(_configurationCaller, age_, failure);
    }

    // Scenarios: BLCFG-CACHE-AGE-T03.
    function test_givenReplacementRiskPaused_whenAgeSet_reverts() public {
        _risk.setPriceCacheMaxAge(5);
        BurnerLoansRisk previous = _selectReplacementRisk();
        _risk.disable("");
        _ageReverts(_configurationCaller, 1, abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        assertEq(previous.priceCacheMaxAge(), 5, "operational old Risk is not used as fallback");
    }
}
