// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigSetGracePeriodTest is BurnerLoansConfigTest {
    // Scenarios: BLCFGGR-A01, BLCFGGR-A02.
    function test_whenCallerIsNotAdmin_reverts(address caller_, uint32 period_) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setGracePeriod, (period_)),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCFGGR-L01, BLCFGGR-L03.
    function test_givenDisabled_whenGraceChanged_reverts(
        address caller_,
        uint32 period_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigDisabled {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setGracePeriod, (period_)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFGGR-L02, BLCFGGR-L04.
    function test_givenInactiveDisabled_whenGraceChanged_reverts(
        address caller_,
        uint32 period_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigDisabled givenConfigInactive {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setGracePeriod, (period_)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFGGR-L06, BLCFGGR-L08, BLCFGGR-L10, BLCFGGR-L12.
    function test_givenInactiveEnabled_whenGraceChanged_reverts(
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigInactive {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.setGracePeriod, (uint32(1))),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFGGR-I01.
    function test_whenGraceIsZero_reverts() public {
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.setGracePeriod, (uint32(0))),
            abi.encodeWithSelector(IGracePeriod.GracePeriod_ZeroPeriod.selector)
        );
    }

    // Scenarios: BLCFGGR-N01, BLCFGGR-L05, BLCFGGR-L07, BLCFGGR-L09, BLCFGGR-L11.
    function test_givenActiveEnabled_whenValidGraceSet(
        uint32 period_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        period_ = uint32(bound(period_, 1, type(uint32).max));
        _setPolicyState(_core, coreActive_, coreEnabled_);
        uint48 last = _config.lastTransitionAt();
        bytes32 funds = _economicDigest();
        vm.expectEmit(address(_config));
        emit IGracePeriod.GracePeriodSet(period_);
        _config.setGracePeriod(period_);
        assertEq(_config.gracePeriod(), period_, "Exact grace duration");
        assertEq(
            _config.lastTransitionAt(),
            last,
            "Grace update does not restart transition clock"
        );
        assertTrue(_config.isEnabled(), "Remains enabled");
        assertEq(_economicDigest(), funds, "Grace update preserves funds");
    }

    // Scenarios: BLCFGGR-P01.
    function test_whenSameGraceSet(uint32 period_, address caller_) public {
        _grantAdmin(caller_);
        period_ = uint32(bound(period_, 1, type(uint32).max));
        vm.prank(caller_);
        _config.setGracePeriod(period_);
        uint48 last = _config.lastTransitionAt();
        vm.expectEmit(address(_config));
        emit IGracePeriod.GracePeriodSet(period_);
        vm.prank(caller_);
        _config.setGracePeriod(period_);
        assertEq(_config.gracePeriod(), period_, "Same grace stored");
        assertEq(_config.lastTransitionAt(), last, "Same duration does not restart clock");
    }

    // Scenarios: BLCFGGR-N01, BLCFGGR-P01.
    function test_whenGraceBoundariesAreSeeded() public {
        vm.expectEmit(address(_config));
        emit IGracePeriod.GracePeriodSet(1);
        _config.setGracePeriod(1);
        assertEq(_config.gracePeriod(), 1, "Minimum nonzero grace");
        vm.expectEmit(address(_config));
        emit IGracePeriod.GracePeriodSet(type(uint32).max);
        _config.setGracePeriod(type(uint32).max);
        assertEq(_config.gracePeriod(), type(uint32).max, "Maximum representable grace");
        vm.expectEmit(address(_config));
        emit IGracePeriod.GracePeriodSet(type(uint32).max);
        _config.setGracePeriod(type(uint32).max);
    }
}
