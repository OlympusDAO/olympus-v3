// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(unused-return)

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {Policy, Keycode, Actions, toKeycode} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {BurnerLoansPayout} from "src/policies/burnerloans/BurnerLoansPayout.sol";

contract BurnerLoansPayoutConfigureDependenciesTest is BurnerLoansPayoutTest {
    // Scenarios: BLCU-DEPENDENCIES-P01, BLCU-DEPENDENCIES-P02.
    function test_whenConfigured_thenOrderedDependenciesAndCache(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        bytes32 state = _ledgerDigest();
        vm.prank(caller_);
        Keycode[] memory keys = _payout.configureDependencies();
        assertEq(keys.length, 2, "Two dependencies");
        assertEq(Keycode.unwrap(keys[0]), "ROLES", "ROLES first");
        assertEq(Keycode.unwrap(keys[1]), "TRSRY", "Treasury second");
        assertEq(address(_payout.ROLES()), address(_roles), "Live ROLES cache");
        vm.prank(caller_);
        _payout.configureDependencies();
        assertEq(_ledgerDigest(), state, "Repeat preserves custody");
    }

    // Scenarios: BLCU-DEPENDENCIES-P01, BLCU-DEPENDENCIES-P02.
    function test_givenNewRoles_whenConfigured_thenCacheReplaced(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        OlympusRoles next = new OlympusRoles(_kernel);
        _kernel.executeAction(Actions.UpgradeModule, address(next));
        vm.prank(caller_);
        _payout.configureDependencies();
        assertEq(
            address(_payout.ROLES()),
            address(next),
            "Permissionless cache follows upgraded module even while inactive"
        );
    }

    // Scenarios: BLCU-DEPENDENCIES-P03, BLCU-DEPENDENCIES-P04.
    function test_givenRolesMissing_whenConfigured_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.getModuleForKeycode, (toKeycode("ROLES"))),
            abi.encode(address(0))
        );
        _expectConfigureRejected(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("ROLES")),
            caller_
        );
    }

    // Scenarios: BLCU-DEPENDENCIES-I01, BLCU-DEPENDENCIES-I02.
    function test_givenTreasuryMissing_whenConfigured_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public givenPendingBuckets {
        _setState(_payout, active_, enabled_);
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(_kernel.getModuleForKeycode, (toKeycode("TRSRY"))),
            abi.encode(address(0))
        );
        _expectConfigureRejected(
            abi.encodeWithSelector(Policy.Policy_ModuleDoesNotExist.selector, toKeycode("TRSRY")),
            caller_
        );
    }

    // Scenarios: BLCU-DEPENDENCIES-D02.
    function test_givenUnsupportedRolesVersion_whenConfigured_reverts(
        address caller_,
        bool active_,
        uint8 major_
    ) public givenPendingBuckets {
        vm.assume(major_ != 1);
        _setState(_payout, active_, true);
        vm.mockCall(
            address(_roles),
            abi.encodeWithSignature("VERSION()"),
            abi.encode(major_, uint8(0))
        );
        _expectConfigureRejected(
            abi.encodeWithSelector(
                Policy.Policy_WrongModuleVersion.selector,
                abi.encode([uint8(1)])
            ),
            caller_
        );
    }

    // Scenarios: BLCU-DEPENDENCIES-D01.
    function test_givenCachedRoles_whenAdminConfigures_thenNoKernelRolesLookup()
        public
        givenPendingBuckets
    {
        vm.mockCallRevert(
            address(_kernel),
            abi.encodeCall(_kernel.getModuleForKeycode, (toKeycode("ROLES"))),
            hex"deadbeef"
        );
        bytes32 state = _ledgerDigest();
        _payout.setSendFeesToDistributor(false);
        assertEq(_ledgerDigest(), state, "Cached authority does not alter custody");
    }

    function _expectConfigureRejected(bytes memory reason_, address caller_) internal {
        address roles = address(_payout.ROLES());
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _payout.configureDependencies();
        assertEq(address(_payout.ROLES()), roles, "Partial cache update rolls back");
    }

    // Scenarios: BLCU-DEPENDENCIES-P02.
    function test_givenNeverActivated_whenFirstConfigured_thenCacheInitialized(
        address caller_
    ) public {
        BurnerLoansPayout fresh = new BurnerLoansPayout(_kernel, address(_core));
        assertEq(address(fresh.ROLES()), address(0), "Unconfigured cache starts empty");
        vm.prank(caller_);
        Keycode[] memory dependencies = fresh.configureDependencies();
        assertEq(dependencies.length, 2, "Both dependencies resolved before activation");
        assertEq(address(fresh.ROLES()), address(_roles), "First configuration stores ROLES");
    }
}

// forge-lint: disable-end(unused-return)
