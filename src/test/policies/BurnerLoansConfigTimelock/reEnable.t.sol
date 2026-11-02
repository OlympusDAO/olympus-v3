// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";
import {Actions, Kernel} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";

contract BurnerLoansConfigTimelockReEnableTest is BurnerLoansConfigTimelockTest {
    // Scenarios: BLCT-REENABLE-D01.
    function test_givenConfigActiveFalse_givenConfigEnabledTrue_whenReenable_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _timelock.disable("");
        _setState(_config, false, true);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-REENABLE-D02.
    function test_givenConfigActiveTrue_givenConfigEnabledFalse_whenReenable_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _timelock.disable("");
        _setState(_config, true, false);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-REENABLE-D03.
    function test_givenConfigActiveFalse_givenConfigEnabledFalse_whenReenable_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _timelock.disable("");
        _setState(_config, false, false);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCT-REENABLE-D04.
    function test_givenForeignConfigKernel_whenReenable_reverts(
        address caller_,
        uint8 role_
    ) public {
        _proposer(caller_, role_);
        _timelock.disable("");
        Kernel other = new Kernel();
        vm.mockCall(
            address(_config),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(other))
        );
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_config),
                address(_kernel),
                address(other)
            )
        );
    }

    // Scenarios: BLCT-REENABLE-L03.
    function test_givenOwnPolicyInactive_whenReenable_reverts(address caller_, uint8 role_) public {
        _proposer(caller_, role_);
        _setState(_timelock, false, false);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_timelock)
            )
        );
    }

    // Scenarios: BLCT-REENABLE-D06.
    function test_givenRiskOperatorIndependent_whenReenable_thenEnabled(
        address caller_,
        uint8 role_,
        bool zero_
    ) public {
        _proposer(caller_, role_);
        _timelock.disable("");
        _risk.setConfigOperator(zero_ ? address(0) : _recipient);
        _expectTransition(caller_, true, "");
        vm.prank(caller_);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "Risk controller does not constrain activation");
    }

    // Scenarios: BLCT-REENABLE-A01.
    function test_givenUnauthorizedWithinGrace_whenReEnabled_thenAuthorizationFirst(
        address caller_
    ) public {
        _outsider(caller_);
        _timelock.disable("");
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCT-REENABLE-A02.
    function test_givenUnauthorizedExpiredGraceWithUnavailableConfig_whenReEnabled_thenAuthorizationFirst(
        address caller_
    ) public {
        _outsider(caller_);
        _timelock.disable("");
        vm.warp(uint256(_timelock.lastTransitionAt()) + _timelock.gracePeriod() + 1);
        _setState(_config, false, false);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCT-REENABLE-L01.
    function test_givenAlreadyEnabled_whenReEnabled_thenStateError(
        address caller_,
        bool active_
    ) public {
        _setState(_timelock, active_, true);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(IEnabler.NotDisabled.selector)
        );
    }

    // Scenarios: BLCT-REENABLE-L02.
    function test_givenNeverEnabledActivated_whenReEnabled_thenNeverEnabledFirst(
        address caller_
    ) public {
        _timelock = new BurnerLoansConfigTimelock(_kernel, _config);
        _kernel.executeAction(Actions.ActivatePolicy, address(_timelock));
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: BLCT-REENABLE-L04.
    function test_givenNeverEnabledUninitialized_whenReEnabled_thenNeverEnabledFirst(
        address caller_
    ) public {
        _timelock = new BurnerLoansConfigTimelock(_kernel, _config);
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(IReEnabler.NeverEnabled.selector)
        );
    }

    // Scenarios: BLCT-REENABLE-P01.
    function test_givenBeforeDeadline_whenReEnabled_thenExactTransition(
        address caller_,
        uint8 role_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _proposer(caller_, role_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_));
        _timelock.setGracePeriod(grace_);
        vm.warp(last_);
        _timelock.disable("");
        uint256 deadline = uint256(last_) + grace_;
        vm.warp(bound(now_, last_, deadline - 1));
        _expectTransition(caller_, true, "");
        vm.prank(caller_);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "Inclusive grace transition");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "Exact new history");
    }

    // Scenarios: BLCT-REENABLE-P02.
    function test_givenAtDeadline_whenReEnabled_thenExactTransition(
        address caller_,
        uint8 role_,
        uint48 last_,
        uint32 grace_
    ) public {
        _proposer(caller_, role_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_));
        _timelock.setGracePeriod(grace_);
        vm.warp(last_);
        _timelock.disable("");
        uint256 deadline = uint256(last_) + grace_;
        vm.warp(deadline);
        _expectTransition(caller_, true, "");
        vm.prank(caller_);
        _timelock.reEnable();
        assertTrue(_timelock.isEnabled(), "Inclusive grace transition");
        assertEq(_timelock.lastTransitionAt(), vm.getBlockTimestamp(), "Exact new history");
    }

    // Scenarios: BLCT-REENABLE-P03.
    function test_givenAfterDeadline_whenReEnabled_reverts(
        address caller_,
        uint8 role_,
        uint48 last_,
        uint32 grace_,
        uint48 now_
    ) public {
        _proposer(caller_, role_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, 1, uint256(type(uint48).max) - grace_ - 1));
        _timelock.setGracePeriod(grace_);
        vm.warp(last_);
        _timelock.disable("");
        uint256 deadline = uint256(last_) + grace_;
        vm.warp(bound(now_, deadline + 1, type(uint48).max));
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(IGracePeriod.GracePeriod_Expired.selector, uint48(deadline))
        );
    }

    // Scenarios: BLCT-REENABLE-N01.
    function test_givenOverflowDeadline_whenReEnabled_reverts(
        address caller_,
        uint8 role_,
        uint48 last_,
        uint32 grace_
    ) public {
        _proposer(caller_, role_);
        grace_ = uint32(bound(grace_, 1, type(uint32).max));
        last_ = uint48(bound(last_, uint256(type(uint48).max) - grace_ + 1, type(uint48).max));
        _timelock.setGracePeriod(grace_);
        vm.warp(last_);
        _timelock.disable("");
        uint256 deadline = uint256(last_) + grace_;
        _transitionReverts(
            abi.encodeCall(_timelock.reEnable, ()),
            caller_,
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector,
                uint8(48),
                deadline
            )
        );
    }

    // Scenarios: BLCT-REENABLE-P01.
    function test_givenGraceP01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role) {
            for (uint256 period; period < 2; ++period) {
                uint32 grace = period == 0 ? 1 : type(uint32).max;
                for (uint256 endpoint; endpoint < 2; ++endpoint) {
                    uint48 last = endpoint == 0 ? uint48(1) : type(uint48).max - grace;
                    test_givenBeforeDeadline_whenReEnabled_thenExactTransition(
                        address(0xabc1),
                        role,
                        last,
                        grace,
                        last
                    );
                    _restore(checkpoint);
                    test_givenBeforeDeadline_whenReEnabled_thenExactTransition(
                        address(0xabc1),
                        role,
                        last,
                        grace,
                        last + grace - 1
                    );
                    _restore(checkpoint);
                }
            }
        }
    }

    // Scenarios: BLCT-REENABLE-P02.
    function test_givenGraceP02RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role) {
            for (uint256 period; period < 2; ++period) {
                uint32 grace = period == 0 ? 1 : type(uint32).max;
                for (uint256 endpoint; endpoint < 2; ++endpoint) {
                    uint48 last = endpoint == 0 ? uint48(1) : type(uint48).max - grace;
                    test_givenAtDeadline_whenReEnabled_thenExactTransition(
                        address(0xabc1),
                        role,
                        last,
                        grace
                    );
                    _restore(checkpoint);
                }
            }
        }
    }

    // Scenarios: BLCT-REENABLE-P03.
    function test_givenGraceP03RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role) {
            for (uint256 period; period < 2; ++period) {
                uint32 grace = period == 0 ? 1 : type(uint32).max;
                for (uint256 endpoint; endpoint < 2; ++endpoint) {
                    uint48 last = endpoint == 0 ? uint48(1) : type(uint48).max - grace - 1;
                    test_givenAfterDeadline_whenReEnabled_reverts(
                        address(0xabc1),
                        role,
                        last,
                        grace,
                        last + grace + 1
                    );
                    _restore(checkpoint);
                    test_givenAfterDeadline_whenReEnabled_reverts(
                        address(0xabc1),
                        role,
                        last,
                        grace,
                        type(uint48).max
                    );
                    _restore(checkpoint);
                }
            }
        }
    }

    // Scenarios: BLCT-REENABLE-N01.
    function test_givenGraceN01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds()
        public
    {
        uint256 checkpoint = vm.snapshotState();
        for (uint8 role; role < 3; ++role) {
            for (uint256 period; period < 2; ++period) {
                uint32 grace = period == 0 ? 1 : type(uint32).max;
                for (uint256 endpoint; endpoint < 2; ++endpoint) {
                    uint48 last = endpoint == 0 ? type(uint48).max - grace + 1 : type(uint48).max;
                    test_givenOverflowDeadline_whenReEnabled_reverts(
                        address(0xabc1),
                        role,
                        last,
                        grace
                    );
                    _restore(checkpoint);
                }
            }
        }
    }
}
