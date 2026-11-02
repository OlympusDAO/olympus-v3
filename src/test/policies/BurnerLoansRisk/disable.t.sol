// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskDisableTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-DISABLE-A02, BLRISK-DISABLE-L02.
    function test_givenBrokenPricingDependencies_whenDisabled() public givenCache {
        vm.mockCallRevert(
            address(_oracle),
            bytes(""),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.mockCallRevert(
            address(_cache),
            bytes(""),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _transition(address(this));
    }

    function _transition(address caller_) private {
        bytes32 beforeConfig = _configurationHash();
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IEnabler.Disabled();
        vm.expectEmit(true, true, false, true, address(_risk));
        emit IEnablerV2.Transition(caller_, false, "", uint48(block.timestamp));
        vm.recordLogs();
        vm.prank(caller_);
        _risk.disable("");
        assertEq(vm.getRecordedLogs().length, 2, "exact lifecycle event count");
        assertEq(_risk.isEnabled(), false, "transition flag");
        assertEq(_risk.lastTransitionAt(), block.timestamp, "transition time");
        assertEq(
            _configurationHash(),
            beforeConfig,
            "transition preserves configuration and token supply"
        );
    }

    // Scenarios: BLRISK-DISABLE-A01.
    function test_whenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != address(this));
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.disable("");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed transition preserves time");
        assertEq(_risk.isEnabled(), true, "failed transition preserves flag");
    }

    // Scenarios: BLRISK-DISABLE-A02, BLRISK-DISABLE-L02.
    function test_givenAdmin_whenTransition(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-DISABLE-L01.
    function test_givenAdminActive_whenAlreadyDisabled_reverts(
        address caller_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.disable("");
    }

    // Scenarios: BLRISK-DISABLE-L03.
    function test_givenAdminInactive_whenAlreadyDisabled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.disable("");
    }

    // Scenarios: BLRISK-DISABLE-L04.
    function test_givenAdminInactive_whenTransition(address caller_) public givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-DISABLE-I01.
    function test_givenAdmin_whenDataIsNonempty_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.assume(data_.length > 0 && data_.length <= 256);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _risk.disable(data_);
    }

    // Scenarios: BLRISK-DISABLE-I01.
    function test_givenAdmin_whenPayloadBoundarySeeds_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        bytes[4] memory seeds = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < seeds.length; ++i) {
            vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
            vm.prank(caller_);
            _risk.disable(seeds[i]);
        }
    }

    // Scenarios: BLRISK-DISABLE-A02, BLRISK-DISABLE-L02.
    function test_givenEmergency_whenTransition(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-DISABLE-L01.
    function test_givenEmergencyActive_whenAlreadyDisabled_reverts(
        address caller_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.disable("");
    }

    // Scenarios: BLRISK-DISABLE-L03.
    function test_givenEmergencyInactive_whenAlreadyDisabled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.disable("");
    }

    // Scenarios: BLRISK-DISABLE-L04.
    function test_givenEmergencyInactive_whenTransition(address caller_) public givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-DISABLE-I01.
    function test_givenEmergency_whenDataIsNonempty_reverts(
        address caller_,
        bytes memory data_
    ) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        vm.assume(data_.length > 0 && data_.length <= 256);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _risk.disable(data_);
    }

    // Scenarios: BLRISK-DISABLE-I01.
    function test_givenEmergency_whenPayloadBoundarySeeds_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, caller_);
        bytes[4] memory seeds = [
            bytes(hex"00"),
            bytes(hex"01"),
            abi.encode(uint256(0)),
            new bytes(256)
        ];
        for (uint256 i; i < seeds.length; ++i) {
            vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
            vm.prank(caller_);
            _risk.disable(seeds[i]);
        }
    }
}
