pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {BurnerLoansConfigRescueTestBase} from "src/test/policies/BurnerLoansConfig/fixtures/BurnerLoansConfigRescueTest.sol";

// Only caller/lifecycle/forwarding vary here; BL owns quantity and bucket-range fuzzing.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return)
contract BurnerLoansConfigRescueTest is BurnerLoansConfigRescueTestBase {
    error ForwardingMustNotRun();

    /// @notice The four independent lifecycle dimensions remain visible instead of being encoded in a mask.
    // Scenarios: L-01.
    function test_givenConfigAndFacilityEnabled_whenAdminForwardsRescue() public {
        _setRescueLifecycle(false, false, false, false);
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            _FORWARDING_SURPLUS,
            "facility preview ignores forwarding lifecycle"
        );

        _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, admin);
        assertEq(
            _asset.balanceOf(address(burnerLoansConfig)),
            0,
            "Config never takes token custody"
        );
    }

    // Scenarios: L-09.
    function test_givenFacilityDisabled_whenAdminForwardsRescue() public {
        _setRescueLifecycle(false, false, true, false);
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            _FORWARDING_SURPLUS,
            "facility preview ignores forwarding lifecycle"
        );

        _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, admin);
        assertEq(
            _asset.balanceOf(address(burnerLoansConfig)),
            0,
            "Config never takes token custody"
        );
    }

    // Scenarios: L-06.
    function test_givenConfigDisabled_whenAdminForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
            for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                uint256 snapshot = vm.snapshotState();
                _setRescueLifecycle(true, false, facilityDisabled != 0, facilityInactive != 0);
                bytes memory failure;
                failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);

                vm.mockCallRevert(
                    address(burnerLoans),
                    abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
                    abi.encodeWithSelector(ForwardingMustNotRun.selector)
                );
                _assertSurplusFailure(_asset, address(_asset), _destination, admin, failure);
                _assertSurplusFailure(_asset, address(0), address(0), admin, failure);
                vm.clearMockedCalls();

                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "Config never takes token custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
            }
    }

    // Scenarios: L-07.
    function test_givenConfigInactive_whenAdminForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
            for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                uint256 snapshot = vm.snapshotState();
                _setRescueLifecycle(false, true, facilityDisabled != 0, facilityInactive != 0);
                bytes memory failure;
                failure = abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector
                );

                vm.mockCallRevert(
                    address(burnerLoans),
                    abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
                    abi.encodeWithSelector(ForwardingMustNotRun.selector)
                );
                _assertSurplusFailure(_asset, address(_asset), _destination, admin, failure);
                _assertSurplusFailure(_asset, address(0), address(0), admin, failure);
                vm.clearMockedCalls();

                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "Config never takes token custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
            }
    }

    // Scenarios: L-08.
    function test_givenConfigDisabledAndInactive_whenAdminForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
            for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                uint256 snapshot = vm.snapshotState();
                _setRescueLifecycle(true, true, facilityDisabled != 0, facilityInactive != 0);
                bytes memory failure;
                failure = abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector
                );

                vm.mockCallRevert(
                    address(burnerLoans),
                    abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
                    abi.encodeWithSelector(ForwardingMustNotRun.selector)
                );
                _assertSurplusFailure(_asset, address(_asset), _destination, admin, failure);
                _assertSurplusFailure(_asset, address(0), address(0), admin, failure);
                vm.clearMockedCalls();

                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "Config never takes token custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
            }
    }

    // Scenarios: L-04.
    function test_givenFacilityInactive_whenAdminForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
            uint256 snapshot = vm.snapshotState();
            _setRescueLifecycle(false, false, facilityDisabled != 0, true);
            vm.expectRevert(
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );
            burnerLoans.previewRescue(address(_asset), _destination);
            bytes memory failure;
            failure = abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector);

            _assertSurplusFailure(_asset, address(_asset), _destination, admin, failure);
            _assertSurplusFailure(_asset, address(0), address(0), admin, failure);
            vm.clearMockedCalls();

            assertEq(
                _asset.balanceOf(address(burnerLoansConfig)),
                0,
                "Config never takes token custody"
            );
            assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
        }
    }

    // Scenarios: L-02.
    function test_givenConfigAndFacilityEnabled_whenOperatorForwardsRescue() public {
        _setRescueLifecycle(false, false, false, false);
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            _FORWARDING_SURPLUS,
            "facility preview ignores forwarding lifecycle"
        );

        _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, address(configTimelock));
        assertEq(
            _asset.balanceOf(address(burnerLoansConfig)),
            0,
            "Config never takes token custody"
        );
    }

    // Scenarios: L-09.
    function test_givenFacilityDisabled_whenOperatorForwardsRescue() public {
        _setRescueLifecycle(false, false, true, false);
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            _FORWARDING_SURPLUS,
            "facility preview ignores forwarding lifecycle"
        );

        _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, address(configTimelock));
        assertEq(
            _asset.balanceOf(address(burnerLoansConfig)),
            0,
            "Config never takes token custody"
        );
    }

    // Scenarios: L-06.
    function test_givenConfigDisabled_whenOperatorForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
            for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                uint256 snapshot = vm.snapshotState();
                _setRescueLifecycle(true, false, facilityDisabled != 0, facilityInactive != 0);
                bytes memory failure;
                failure = abi.encodeWithSelector(IEnabler.NotEnabled.selector);

                vm.mockCallRevert(
                    address(burnerLoans),
                    abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
                    abi.encodeWithSelector(ForwardingMustNotRun.selector)
                );
                _assertSurplusFailure(
                    _asset,
                    address(_asset),
                    _destination,
                    address(configTimelock),
                    failure
                );
                _assertSurplusFailure(
                    _asset,
                    address(0),
                    address(0),
                    address(configTimelock),
                    failure
                );
                vm.clearMockedCalls();

                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "Config never takes token custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
            }
    }

    // Scenarios: L-07.
    function test_givenConfigInactive_whenOperatorForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
            for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                uint256 snapshot = vm.snapshotState();
                _setRescueLifecycle(false, true, facilityDisabled != 0, facilityInactive != 0);
                bytes memory failure;
                failure = abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector
                );

                vm.mockCallRevert(
                    address(burnerLoans),
                    abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
                    abi.encodeWithSelector(ForwardingMustNotRun.selector)
                );
                _assertSurplusFailure(
                    _asset,
                    address(_asset),
                    _destination,
                    address(configTimelock),
                    failure
                );
                _assertSurplusFailure(
                    _asset,
                    address(0),
                    address(0),
                    address(configTimelock),
                    failure
                );
                vm.clearMockedCalls();

                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "Config never takes token custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
            }
    }

    // Scenarios: L-08.
    function test_givenConfigDisabledAndInactive_whenOperatorForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
            for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                uint256 snapshot = vm.snapshotState();
                _setRescueLifecycle(true, true, facilityDisabled != 0, facilityInactive != 0);
                bytes memory failure;
                failure = abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector
                );

                vm.mockCallRevert(
                    address(burnerLoans),
                    abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
                    abi.encodeWithSelector(ForwardingMustNotRun.selector)
                );
                _assertSurplusFailure(
                    _asset,
                    address(_asset),
                    _destination,
                    address(configTimelock),
                    failure
                );
                _assertSurplusFailure(
                    _asset,
                    address(0),
                    address(0),
                    address(configTimelock),
                    failure
                );
                vm.clearMockedCalls();

                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "Config never takes token custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
            }
    }

    // Scenarios: L-05.
    function test_givenFacilityInactive_whenOperatorForwardsRescue_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
            uint256 snapshot = vm.snapshotState();
            _setRescueLifecycle(false, false, facilityDisabled != 0, true);
            vm.expectRevert(
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector)
            );
            burnerLoans.previewRescue(address(_asset), _destination);
            bytes memory failure;
            failure = abi.encodeWithSelector(IBurnerLoans.BurnerLoans_PolicyInactive.selector);

            _assertSurplusFailure(
                _asset,
                address(_asset),
                _destination,
                address(configTimelock),
                failure
            );
            _assertSurplusFailure(_asset, address(0), address(0), address(configTimelock), failure);
            vm.clearMockedCalls();

            assertEq(
                _asset.balanceOf(address(burnerLoansConfig)),
                0,
                "Config never takes token custody"
            );
            assertTrue(vm.revertToState(snapshot), "restore independent forwarding lifecycle");
        }
    }

    function _setRescueLifecycle(
        bool configDisabled_,
        bool configInactive_,
        bool facilityDisabled_,
        bool facilityInactive_
    ) internal {
        vm.startPrank(admin);
        if (configDisabled_) burnerLoansConfig.disable("");
        if (facilityDisabled_) burnerLoans.disable("");
        if (configInactive_)
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
        if (facilityInactive_) kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        vm.stopPrank();
    }

    // Scenarios: L-03.
    function test_givenLifecycleStates_whenCallerUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != burnerLoansConfig.configOperator());
        for (uint256 configDisabled; configDisabled < 2; ++configDisabled)
            for (uint256 configInactive; configInactive < 2; ++configInactive)
                for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled)
                    for (uint256 facilityInactive; facilityInactive < 2; ++facilityInactive) {
                        uint256 snapshot = vm.snapshotState();
                        _setRescueLifecycle(
                            configDisabled != 0,
                            configInactive != 0,
                            facilityDisabled != 0,
                            facilityInactive != 0
                        );
                        bytes memory failure = abi.encodeWithSelector(
                            IBurnerLoansConfig
                                .BurnerLoansConfig_UnauthorizedConfigOperator
                                .selector,
                            caller_
                        );
                        _assertSurplusFailure(
                            _asset,
                            address(_asset),
                            _destination,
                            caller_,
                            failure
                        );
                        _assertSurplusFailure(_asset, address(0), address(0), caller_, failure);
                        assertTrue(
                            vm.revertToState(snapshot),
                            "restore unauthorized forwarding state"
                        );
                    }
    }

    // Scenarios: L-03.
    function test_givenUnauthorizedIdentities_whenSeeded_reverts() public {
        address[3] memory callers = [address(0), emergency, burnerLoansAdmin];
        for (uint256 c; c < callers.length; ++c)
            test_givenLifecycleStates_whenCallerUnauthorized_reverts(callers[c]);
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(_destination);
        test_givenLifecycleStates_whenCallerUnauthorized_reverts(address(configTimelock));
    }

    // Scenarios: P-01.
    function test_givenOwedOrUnrelatedDestination_whenEachCallerForwards() public {
        address[2] memory callers = [admin, address(configTimelock)];
        address[2] memory destinations = [_keeper, _destination];
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(burnerLoans.rescue, (address(_asset), _keeper)),
            2
        );
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(burnerLoans.rescue, (address(_asset), _destination)),
            2
        );
        for (uint256 c; c < callers.length; ++c)
            for (uint256 d; d < destinations.length; ++d) {
                uint256 snapshot = vm.snapshotState();
                if (destinations[d] == _keeper) _asset.mint(_keeper, _DESTINATION_BALANCE);
                _assertSurplusPayment(_asset, destinations[d], _FORWARDING_SURPLUS, callers[c]);
                assertEq(
                    _asset.balanceOf(address(burnerLoansConfig)),
                    0,
                    "forwarder has no custody"
                );
                assertTrue(vm.revertToState(snapshot), "restore forwarded destination");
            }
    }

    // Scenarios: P-02, P-03.
    function test_givenCustodyAtOrBelowReserve_whenEachCallerForwards() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 below; below < 2; ++below)
            for (uint256 c; c < callers.length; ++c) {
                uint256 snapshot = vm.snapshotState();
                _asset.burn(address(burnerLoans), _FORWARDING_SURPLUS + below);
                _assertSurplusPayment(_asset, _destination, 0, callers[c]);
                assertTrue(vm.revertToState(snapshot), "restore forwarding no-op");
            }
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRotated_whenFormerOperatorRescues_reverts() public {
        address newOperator = makeAddr("new surplus operator");
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(newOperator);
        _assertSurplusFailure(
            _asset,
            address(_asset),
            _destination,
            address(configTimelock),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRotated_whenCurrentAuthorityRescues() public {
        address newOperator = makeAddr("new surplus operator");
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(newOperator);
        address[2] memory callers = [admin, newOperator];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore independent authorized payment");
        }
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts() public {
        address newOperator = makeAddr("new surplus operator");
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(newOperator);
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(0));
        address[2] memory callers = [newOperator, address(0)];
        for (uint256 c; c < callers.length; ++c)
            _assertSurplusFailure(
                _asset,
                address(_asset),
                _destination,
                callers[c],
                abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                    callers[c]
                )
            );
    }

    // Scenarios: AUTH-01.
    function test_givenOperatorRevoked_whenAdminRescues() public {
        address newOperator = makeAddr("new surplus operator");
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(newOperator);
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(0));
        _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, admin);
    }

    // Scenarios: BIND-01.
    function test_givenFacilityConfiguratorChanged_whenForwarded_reverts() public {
        address replacement = address(_activateReplacementConfigurator());
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.setConfigurator(replacement);
        vm.stopPrank();
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c)
            _assertSurplusFailure(
                _asset,
                address(_asset),
                _destination,
                callers[c],
                abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
            );
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            _FORWARDING_SURPLUS,
            "replacement does not change permissionless preview"
        );
    }

    // Scenarios: I-01.
    function test_givenValidForwarder_whenTokenHasNoCode_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c)
            for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
                uint256 snapshot = vm.snapshotState();
                if (disabledBL != 0) {
                    vm.prank(admin);
                    burnerLoans.disable("");
                }
                address[2] memory invalidAssets = [address(0), makeAddr("no-code surplus asset")];
                for (uint256 a; a < invalidAssets.length; ++a) {
                    bytes memory failure = abi.encodeWithSelector(
                        IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector,
                        invalidAssets[a]
                    );
                    vm.expectRevert(failure);
                    burnerLoans.previewRescue(invalidAssets[a], _destination);
                    _assertSurplusFailure(
                        _asset,
                        invalidAssets[a],
                        _destination,
                        callers[c],
                        failure
                    );
                }

                assertTrue(vm.revertToState(snapshot), "restore forwarded input failure");
            }
    }

    // Scenarios: I-02.
    function test_givenValidForwarder_whenDestinationIsForbidden_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c)
            for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
                uint256 snapshot = vm.snapshotState();
                if (disabledBL != 0) {
                    vm.prank(admin);
                    burnerLoans.disable("");
                }

                address[2] memory invalidDestinations = [address(0), address(burnerLoans)];
                for (uint256 d; d < invalidDestinations.length; ++d) {
                    bytes memory failure = abi.encodeWithSelector(
                        IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                        invalidDestinations[d]
                    );
                    vm.expectRevert(failure);
                    burnerLoans.previewRescue(address(_asset), invalidDestinations[d]);
                    _assertSurplusFailure(
                        _asset,
                        address(_asset),
                        invalidDestinations[d],
                        callers[c],
                        failure
                    );
                }

                assertTrue(vm.revertToState(snapshot), "restore forwarded input failure");
            }
    }

    // Scenarios: I-03.
    function test_givenValidForwarder_whenBalanceQueryReverts_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c)
            for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
                uint256 snapshot = vm.snapshotState();
                if (disabledBL != 0) {
                    vm.prank(admin);
                    burnerLoans.disable("");
                }

                _assertBalanceQueryFailure(_asset, callers[c]);
                assertTrue(vm.revertToState(snapshot), "restore forwarded input failure");
            }
    }

    // Scenarios: TX-01.
    function test_givenPositiveSurplus_whenTransferFails_reverts() public {
        _asset.setTransferBlocked(_destination, true);
        address[2] memory callers = [admin, address(configTimelock)];
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            _FORWARDING_SURPLUS,
            "preview omits transfer"
        );
        for (uint256 c; c < callers.length; ++c)
            _assertSurplusFailure(
                _asset,
                address(_asset),
                _destination,
                callers[c],
                abi.encodeWithSelector(ReentrantPayoutToken.TransferBlocked.selector, _destination)
            );
    }

    // Scenarios: CB-01.
    function test_givenAuthorizedCallback_whenNestedForwardingFailureIsCaught() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(this));
        address[2] memory callers = [admin, address(this)];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _asset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(this.observeAndReenterForwarder, ())
            );
            _asset.setBubbleCallbackFailure(false);

            _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, callers[c]);
            assertEq(
                _asset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "authorized nested forwarding reaches BL guard"
            );

            assertTrue(vm.revertToState(snapshot), "restore forwarding callback outcome");
        }
    }

    // Scenarios: CB-01.
    function test_givenAuthorizedCallback_whenNestedForwardingFailureIsPropagated_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.setConfigOperator(address(this));
        address[2] memory callers = [admin, address(this)];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _asset.setCallbackFrom(
                address(burnerLoans),
                address(this),
                abi.encodeCall(this.observeAndReenterForwarder, ())
            );
            _asset.setBubbleCallbackFailure(true);

            _assertSurplusFailure(
                _asset,
                address(_asset),
                _destination,
                callers[c],
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(
                _asset.callbackEnabled(),
                "callback state rolls back with propagated failure"
            );

            assertTrue(vm.revertToState(snapshot), "restore forwarding callback outcome");
        }
    }

    function observeAndReenterForwarder() external {
        assertEq(msg.sender, address(_asset), "observer called by outer token");
        assertEq(
            burnerLoans.previewRescue(address(_asset), _destination),
            0,
            "observer sees consumed surplus"
        );
        assertEq(
            burnerLoans.totalPendingForTest(address(_asset)),
            _PENDING_RESERVE,
            "observer sees reserve retained"
        );
        burnerLoansConfig.rescue(address(_asset), _destination);
    }

    // Current-state rows also retain a regression for explicit re-enable/reactivation histories.
    // Scenarios: L-01.
    function test_givenPoliciesRestored_whenRescueForwarded() public {
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.reEnable();
        burnerLoansConfig.disable("");
        burnerLoansConfig.reEnable();
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoans));
        kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
        kernel.executeAction(Actions.ActivatePolicy, address(burnerLoansConfig));
        vm.stopPrank();
        _assertSurplusPayment(_asset, _destination, _FORWARDING_SURPLUS, admin);
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return)
