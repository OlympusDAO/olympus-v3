// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetPriceCacheMaxAgeTest is BurnerLoansRiskTest {
    function _setAge(address caller_, uint48 age_) private {
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IBurnerLoansRisk.PriceCacheMaxAgeSet(age_);
        vm.recordLogs();
        vm.prank(caller_);
        _risk.setPriceCacheMaxAge(age_);
        assertEq(_risk.priceCacheMaxAge(), age_, "requested cache age");
        assertEq(vm.getRecordedLogs().length, 1, "changed age emits once");
    }

    // Scenarios: BLRISK-CACHE-AGE-A01, BLRISK-CACHE-AGE-N01, BLRISK-CACHE-AGE-P01, BLRISK-CACHE-AGE-L05.
    function test_givenAdmin_whenAgeChanges(uint48 age_, address caller_) public givenOperator {
        vm.assume(age_ != 60);
        vm.assume(caller_ != _operator);
        _grantAdmin(caller_);
        _setAge(caller_, age_);
    }

    // Scenarios: BLRISK-CACHE-AGE-A01, BLRISK-CACHE-AGE-N01, BLRISK-CACHE-AGE-P01, BLRISK-CACHE-AGE-L05.
    function test_givenAdmin_whenAgeBoundaries() public givenOperator {
        _setAge(address(this), 0);
        _setAge(address(this), 1);
        _setAge(address(this), type(uint48).max);
    }

    // Scenarios: BLRISK-CACHE-AGE-A02, BLRISK-CACHE-AGE-N02, BLRISK-CACHE-AGE-L05.
    function test_givenOperator_whenAgeChanges(uint48 age_) public givenOperator {
        vm.assume(age_ != 60);
        vm.mockCallRevert(
            address(_roles),
            abi.encodeWithSignature("hasRole(address,bytes32)", _operator, ADMIN_ROLE),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _setAge(_operator, age_);
    }

    // Scenarios: BLRISK-CACHE-AGE-A02, BLRISK-CACHE-AGE-N02, BLRISK-CACHE-AGE-L05.
    function test_givenOperator_whenAgeBoundaries() public givenOperator {
        vm.mockCallRevert(
            address(_roles),
            abi.encodeWithSignature("hasRole(address,bytes32)", _operator, ADMIN_ROLE),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _setAge(_operator, 0);
        _setAge(_operator, 1);
        _setAge(_operator, type(uint48).max);
    }

    // Scenarios: BLRISK-CACHE-AGE-L06.
    function test_givenDisabled_whenAdminChangesAge_reverts() public givenOperator givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(this));
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-L06.
    function test_givenDisabled_whenOperatorChangesAge_reverts()
        public
        givenOperator
        givenDisabled
    {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-L07.
    function test_givenInactive_whenAdminChangesAge_reverts() public givenOperator givenInactive {
        _expectInactive();
        vm.prank(address(this));
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-L07.
    function test_givenInactive_whenOperatorChangesAge_reverts()
        public
        givenOperator
        givenInactive
    {
        _expectInactive();
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-L08.
    function test_givenInactiveAndDisabled_whenAdminChangesAge_reverts()
        public
        givenOperator
        givenDisabled
        givenInactive
    {
        _expectInactive();
        vm.prank(address(this));
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-L08.
    function test_givenInactiveAndDisabled_whenOperatorChangesAge_reverts()
        public
        givenOperator
        givenDisabled
        givenInactive
    {
        _expectInactive();
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-A07.
    function test_whenUnauthorizedCallerChangesAge_reverts(
        address caller_,
        uint48 age_
    ) public givenOperator {
        vm.assume(caller_ != address(this) && caller_ != _operator);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.setPriceCacheMaxAge(age_);
        assertEq(_risk.priceCacheMaxAge(), 60, "age unchanged");
    }

    // Scenarios: BLRISK-CACHE-AGE-A03, BLRISK-CACHE-AGE-A08.
    function test_givenOperator_whenReplaced_reverts() public givenOperator {
        _risk.setConfigOperator(address(0xABCD));
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(_operator);
        _risk.setPriceCacheMaxAge(1);
        assertEq(_risk.priceCacheMaxAge(), 60, "former operator cannot write");
    }

    // Scenarios: BLRISK-CACHE-AGE-P02.
    function test_whenAgeIsUnchanged() public {
        vm.recordLogs();
        _risk.setPriceCacheMaxAge(60);
        assertEq(vm.getRecordedLogs().length, 0, "same age is event-free");
        assertEq(_risk.priceCacheMaxAge(), 60, "age preserved");
    }

    // Scenarios: BLRISK-CACHE-AGE-L01, BLRISK-CACHE-AGE-D01.
    function test_givenControllerActiveAndEnabled_whenAgeChanges() public {
        _risk.setConfigOperator(address(_cache));
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _setAge(address(_cache), 1);
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _setAge(address(_cache), 2);
    }

    // Scenarios: BLRISK-CACHE-AGE-L02, BLRISK-CACHE-AGE-D01.
    function test_givenControllerActiveAndDisabled_whenAgeChanges() public {
        _risk.setConfigOperator(address(_cache));
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _setAge(address(_cache), 1);
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _setAge(address(_cache), 2);
    }

    // Scenarios: BLRISK-CACHE-AGE-L03, BLRISK-CACHE-AGE-D01.
    function test_givenControllerInactiveAndEnabled_whenAgeChanges() public {
        _risk.setConfigOperator(address(_cache));
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _setAge(address(_cache), 1);
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _setAge(address(_cache), 2);
    }

    // Scenarios: BLRISK-CACHE-AGE-L04, BLRISK-CACHE-AGE-D01.
    function test_givenControllerInactiveAndDisabled_whenAgeChanges() public {
        _risk.setConfigOperator(address(_cache));
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _setAge(address(_cache), 1);
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("isEnabled()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _setAge(address(_cache), 2);
    }
}
