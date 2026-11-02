// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskEnableTest is BurnerLoansRiskTest {
    function _transition(address caller_) private {
        bytes32 beforeConfig = _configurationHash();
        vm.expectEmit(false, false, false, true, address(_risk));
        emit IEnabler.Enabled();
        vm.expectEmit(true, true, false, true, address(_risk));
        emit IEnablerV2.Transition(caller_, true, "", uint48(block.timestamp));
        vm.recordLogs();
        vm.prank(caller_);
        _risk.enable("");
        assertEq(vm.getRecordedLogs().length, 2, "exact lifecycle event count");
        assertEq(_risk.isEnabled(), true, "transition flag");
        assertEq(_risk.lastTransitionAt(), block.timestamp, "transition time");
        assertEq(
            _configurationHash(),
            beforeConfig,
            "transition preserves configuration and token supply"
        );
    }

    // Scenarios: BLRISK-ENABLE-A01.
    function test_whenUnauthorizedCaller_reverts(address caller_) public givenDisabled {
        vm.assume(caller_ != address(this));
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.enable("");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed transition preserves time");
        assertEq(_risk.isEnabled(), false, "failed transition preserves flag");
    }

    // Scenarios: BLRISK-ENABLE-A02, BLRISK-ENABLE-L01.
    function test_givenAdmin_whenTransition(address caller_) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-L02.
    function test_givenAdminActive_whenAlreadyEnabled_reverts(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-L04.
    function test_givenAdminInactive_whenAlreadyEnabled_reverts(
        address caller_
    ) public givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.expectRevert(IEnabler.NotDisabled.selector);
        vm.prank(caller_);
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-L03.
    function test_givenAdminInactive_whenTransition_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _expectInactive();
        vm.prank(caller_);
        _risk.enable("");
    }

    // Scenarios: BLRISK-ENABLE-I01.
    function test_givenAdmin_whenDataIsNonempty_reverts(
        address caller_,
        bytes memory data_
    ) public givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.assume(data_.length > 0 && data_.length <= 256);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidEnablerData.selector);
        vm.prank(caller_);
        _risk.enable(data_);
    }

    // Scenarios: BLRISK-ENABLE-I01.
    function test_givenAdmin_whenPayloadBoundarySeeds_reverts(
        address caller_
    ) public givenDisabled {
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
            _risk.enable(seeds[i]);
        }
    }

    // Scenarios: BLRISK-ENABLE-D01.
    function test_givenAdminOracleInterface_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_oracle),
            abi.encodeCall(IERC165.supportsInterface, (type(IOlympusBackingOracle).interfaceId)),
            abi.encode(false)
        );
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBackingOracle.selector,
                address(_oracle)
            )
        );
        vm.prank(caller_);
        _risk.enable("");
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-ENABLE-D02.
    function test_givenAdminCacheInterface_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        bytes4[3] memory interfaces = [
            type(IPriceCache).interfaceId,
            type(IEnabler).interfaceId,
            type(IVersioned).interfaceId
        ];
        for (uint256 i; i < interfaces.length; ++i) {
            _cache.setInterfaceSupport(interfaces[i], false);
            uint48 beforeTime = _risk.lastTransitionAt();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                    address(_cache)
                )
            );
            vm.prank(caller_);
            _risk.enable("");
            assertFalse(_risk.isEnabled(), "failed activation remains disabled");
            assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
            _cache.setInterfaceSupport(interfaces[i], true);
        }
    }

    // Scenarios: BLRISK-ENABLE-D03.
    function test_givenAdminCacheKernel_whenTransition_reverts(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        uint48 beforeTime = _risk.lastTransitionAt();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_cache),
                address(_kernel),
                address(0xBAD)
            )
        );
        vm.prank(caller_);
        _risk.enable("");
        assertFalse(_risk.isEnabled(), "failed activation remains disabled");
        assertEq(_risk.lastTransitionAt(), beforeTime, "failed activation keeps time");
    }

    // Scenarios: BLRISK-ENABLE-D04.
    function test_givenAdminCache11_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-D04.
    function test_givenAdminCache10_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-D04.
    function test_givenAdminCache01_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-D04.
    function test_givenAdminCache00_whenTransition(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _transition(caller_);
    }

    // Scenarios: BLRISK-ENABLE-D05.
    function test_givenAdmin_whenDependencyRestored(
        address caller_
    ) public givenCache givenDisabled {
        vm.assume(caller_ != address(0) && caller_ != address(this));
        _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                address(_cache)
            )
        );
        vm.prank(caller_);
        _risk.enable("");
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, true);
        _transition(caller_);
    }
}
