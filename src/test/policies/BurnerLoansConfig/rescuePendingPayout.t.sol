// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansRescue} from "src/policies/interfaces/IBurnerLoansRescue.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {BurnerLoansConfigRescuePendingPayoutTestBase} from "src/test/policies/BurnerLoansConfig/fixtures/BurnerLoansConfigRescuePendingPayoutTest.sol";

// Small fixtures use base-unit literals. Expected reverts have no useful return value.
// forge-lint: disable-start(literal-instead-of-constant,unused-return,calls-loop)
/// @dev BLC owns authority and forwarding; BL's suite owns payout allocation and numeric fuzzing.
contract BurnerLoansConfigRescuePendingPayoutTest is BurnerLoansConfigRescuePendingPayoutTestBase {
    uint256 internal constant _AMOUNT = 4;
    address internal constant _NEW_OPERATOR = address(0xB0B);

    /// @notice Each success test proves exact forwarding for one caller and one facility local state.
    // Scenarios: BLC-L01, BLC-P01.
    function test_givenFacilityEnabled_whenAdminForwardsPendingPayout() public {
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_asset), _keeper, alice, _AMOUNT)
            ),
            1
        );
        vm.expectCall(address(_asset), abi.encodeCall(IERC20.transfer, (alice, _AMOUNT)), 1);
        _assertSuccessfulForwarding(admin);
    }

    // Scenarios: BLC-L01, BLC-P01.
    function test_givenFacilityDisabled_whenAdminForwardsPendingPayout() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_asset), _keeper, alice, _AMOUNT)
            ),
            1
        );
        vm.expectCall(address(_asset), abi.encodeCall(IERC20.transfer, (alice, _AMOUNT)), 1);
        _assertSuccessfulForwarding(admin);
    }

    // Scenarios: BLC-L01, BLC-P01.
    function test_givenFacilityEnabled_whenOperatorForwardsPendingPayout() public {
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_asset), _keeper, alice, _AMOUNT)
            ),
            1
        );
        vm.expectCall(address(_asset), abi.encodeCall(IERC20.transfer, (alice, _AMOUNT)), 1);
        _assertSuccessfulForwarding(address(configTimelock));
    }

    // Scenarios: BLC-L01, BLC-P01.
    function test_givenFacilityDisabled_whenOperatorForwardsPendingPayout() public {
        vm.prank(admin);
        burnerLoans.disable("");
        vm.expectCall(
            address(burnerLoans),
            abi.encodeCall(
                IBurnerLoansRescue.rescuePendingPayout,
                (address(_asset), _keeper, alice, _AMOUNT)
            ),
            1
        );
        vm.expectCall(address(_asset), abi.encodeCall(IERC20.transfer, (alice, _AMOUNT)), 1);
        _assertSuccessfulForwarding(address(configTimelock));
    }

    // Scenarios: BLC-L07.
    function test_givenConfigDisabled_whenAuthorizedCallerForwards_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            if (disabledBL != 0) {
                vm.prank(admin);
                burnerLoans.disable("");
            }
            for (uint256 c; c < callers.length; ++c) {
                _assertFailure(
                    callers[c],
                    address(_asset),
                    _keeper,
                    alice,
                    _AMOUNT,
                    abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                );
                _assertFailure(
                    callers[c],
                    address(_asset),
                    _keeper,
                    alice,
                    0,
                    abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                );
            }
            assertTrue(vm.revertToState(snapshot), "restore disabled facility");
        }
    }

    /// @notice Unauthorized callers fail before BL activity and input checks, with no forwarding.
    // Scenarios: BLC-L02.
    function test_givenConfigLifecycle_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        _assertUnauthorizedCaller(caller_);
    }

    /// @notice Guarantee unauthorized role-only, former-operator, payout-owner and zero identities.
    // Scenarios: BLC-L02.
    function test_whenUnauthorizedIdentitiesAreSeeded_reverts() public {
        vm.startPrank(admin);
        burnerLoansConfig.setConfigOperator(_NEW_OPERATOR);
        burnerLoansConfig.setConfigOperator(address(configTimelock));
        vm.stopPrank();
        address[5] memory callers = [
            burnerLoansAdmin,
            emergency,
            _NEW_OPERATOR,
            _keeper,
            address(0)
        ];
        for (uint256 i; i < callers.length; ++i) _assertUnauthorizedCaller(callers[i]);
    }

    /// @notice Inactive BLC rejects before any BL call, regardless of BL activity or either local state.
    // Scenarios: BLC-L06.
    function test_givenConfigInactive_whenAuthorizedCallerForwards_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoansConfig.BurnerLoansConfig_PolicyInactive.selector
        );
        // Prove no forwarding: an attempted BL call would instead return this sentinel error.
        vm.mockCallRevert(
            address(burnerLoans),
            abi.encodeWithSelector(burnerLoans.rescuePendingPayout.selector),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAmount.selector)
        );
        for (uint256 disabledConfig; disabledConfig < 2; ++disabledConfig) {
            for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
                for (uint256 inactiveBL; inactiveBL < 2; ++inactiveBL) {
                    uint256 snapshot = vm.snapshotState();
                    _setConfigState(2 + disabledConfig);
                    _setFacilityState(disabledBL != 0, inactiveBL != 0);
                    for (uint256 c; c < callers.length; ++c) {
                        _assertFailure(
                            callers[c],
                            address(_asset),
                            _keeper,
                            alice,
                            _AMOUNT,
                            expectedError
                        );
                        _assertFailure(
                            callers[c],
                            address(0),
                            address(0),
                            address(0),
                            0,
                            expectedError
                        );
                    }
                    assertTrue(vm.revertToState(snapshot), "restore inactive Config fixture");
                }
            }
        }
        vm.clearMockedCalls();
    }

    /// @notice BL inactivity wins over amount=0 for either permitted caller while BLC is active.
    // Scenarios: BLC-L03.
    function test_givenFacilityInactive_whenEnabledConfigForwards_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PolicyInactive.selector
        );

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            _setConfigState(0);
            _setFacilityState(disabledBL != 0, true);
            for (uint256 c; c < callers.length; ++c) {
                _assertFailure(callers[c], address(_asset), _keeper, alice, _AMOUNT, expectedError);
                _assertFailure(callers[c], address(_asset), _keeper, alice, 0, expectedError);
            }
            assertTrue(vm.revertToState(snapshot), "restore inactive facility fixture");
        }
    }

    // Scenarios: BLC-L07.
    function test_givenFacilityInactive_givenConfigDisabled_whenForwarded_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];

        for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
            uint256 snapshot = vm.snapshotState();
            _setConfigState(1);
            _setFacilityState(disabledBL != 0, true);
            for (uint256 c; c < callers.length; ++c) {
                _assertFailure(
                    callers[c],
                    address(_asset),
                    _keeper,
                    alice,
                    _AMOUNT,
                    abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                );
                _assertFailure(
                    callers[c],
                    address(_asset),
                    _keeper,
                    alice,
                    0,
                    abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                );
            }
            assertTrue(vm.revertToState(snapshot), "restore inactive facility fixture");
        }
    }

    /// @notice Representative BL validation and transfer failures bubble through either caller.
    // Scenarios: BLC-I01.
    function test_whenTokenIsZero_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(
                callers[c],
                address(0),
                _keeper,
                alice,
                _AMOUNT,
                abi.encodeWithSelector(
                    IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector,
                    address(0)
                )
            );
        }
    }

    // Scenarios: BLC-I01.
    function test_whenTokenHasNoCode_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            address noCodeToken = makeAddr("token without code");
            assertEq(noCodeToken.code.length, 0, "invalid token has no code");
            _assertFailure(
                callers[c],
                noCodeToken,
                _keeper,
                alice,
                _AMOUNT,
                abi.encodeWithSelector(
                    IBurnerLoansRescue.BurnerLoans_InvalidAsset.selector,
                    noCodeToken
                )
            );
        }
    }

    // Scenarios: BLC-I06.
    function test_whenRecipientIsZero_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        bytes memory zeroAddress = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_ZeroAddress.selector
        );
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(callers[c], address(_asset), address(0), alice, _AMOUNT, zeroAddress);
        }
    }

    // Scenarios: BLC-I03.
    function test_whenDestinationIsZero_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                address(0),
                _AMOUNT,
                abi.encodeWithSelector(
                    IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                    address(0)
                )
            );
        }
    }

    // Scenarios: BLC-I02.
    function test_whenDestinationIsForbidden_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            address[4] memory forbiddenDestinations = [
                address(burnerLoans),
                address(_asset),
                address(burnerLoansConfig),
                address(kernel)
            ];
            for (uint256 d; d < forbiddenDestinations.length; ++d) {
                _assertFailure(
                    callers[c],
                    address(_asset),
                    _keeper,
                    forbiddenDestinations[d],
                    _AMOUNT,
                    abi.encodeWithSelector(
                        IBurnerLoansRescue.BurnerLoans_InvalidRescueDestination.selector,
                        forbiddenDestinations[d]
                    )
                );
            }
        }
    }

    // Scenarios: BLC-I04, BLC-L01.
    function test_givenFacilityEnabled_whenAmountIsZero_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                alice,
                0,
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAmount.selector)
            );
        }
    }

    // Scenarios: BLC-I04, BLC-L01.
    function test_givenFacilityDisabled_whenAmountIsZero_reverts() public {
        vm.prank(admin);
        burnerLoans.disable("");
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                alice,
                0,
                abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAmount.selector)
            );
        }
    }

    // Scenarios: BLC-I05.
    function test_whenAmountExceedsEntitlement_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                alice,
                11,
                abi.encodeWithSelector(
                    IBurnerLoansRescue.BurnerLoans_InsufficientPendingPayout.selector,
                    address(_asset),
                    11,
                    _REWARD
                )
            );
        }
    }

    // Scenarios: BLC-X01.
    function test_whenTokenRejectsTransfer_reverts() public {
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            _asset.setTransferReverts(alice, true);
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                alice,
                _AMOUNT,
                abi.encodeWithSelector(MockRevertingTransferToken.TransferReverted.selector, alice)
            );
            _asset.setTransferReverts(alice, false);
        }
    }

    /// @notice Rotation and clearing change delegated authority while admin remains authorized.
    // Scenarios: BLC-L04.
    function test_givenOperatorRotated_whenFormerOperatorForwards_reverts() public {
        for (uint256 configDisabled; configDisabled < 2; ++configDisabled)
            for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
                uint256 snapshot = vm.snapshotState();
                vm.prank(admin);
                burnerLoansConfig.setConfigOperator(_NEW_OPERATOR);
                if (configDisabled != 0) {
                    vm.prank(admin);
                    burnerLoansConfig.disable("");
                }
                _setFacilityState(facilityDisabled != 0, false);
                _assertFailure(
                    address(configTimelock),
                    address(_asset),
                    _keeper,
                    alice,
                    _AMOUNT,
                    abi.encodeWithSelector(
                        IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                        address(configTimelock)
                    )
                );

                assertTrue(vm.revertToState(snapshot), "restore revoked delegation fixture");
            }
    }

    // Scenarios: BLC-L04.
    // Admin and the newly selected operator can forward while Config is enabled and BL is locally enabled or disabled.
    function test_givenOperatorRotated_givenConfigEnabled_whenCurrentAuthorityForwards() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(_NEW_OPERATOR);
            _setFacilityState(facilityDisabled != 0, false);
            address[2] memory callers = [admin, _NEW_OPERATOR];
            for (uint256 c; c < callers.length; ++c) {
                uint256 paymentSnapshot = vm.snapshotState();
                _assertSuccessfulForwarding(callers[c]);
                assertTrue(vm.revertToState(paymentSnapshot), "restore independent payment");
            }
            assertTrue(vm.revertToState(snapshot), "restore enabled Config fixture");
        }
    }

    // Scenarios: BLC-L04.
    function test_givenOperatorRotated_givenConfigDisabled_whenCurrentAuthorityForwards_reverts()
        public
    {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            burnerLoansConfig.setConfigOperator(_NEW_OPERATOR);
            burnerLoansConfig.disable("");
            vm.stopPrank();
            _setFacilityState(facilityDisabled != 0, false);
            address[2] memory callers = [admin, _NEW_OPERATOR];
            for (uint256 c; c < callers.length; ++c)
                _assertFailure(
                    callers[c],
                    address(_asset),
                    _keeper,
                    alice,
                    _AMOUNT,
                    abi.encodeWithSelector(IEnabler.NotEnabled.selector)
                );
            assertTrue(vm.revertToState(snapshot), "restore disabled Config fixture");
        }
    }

    // Scenarios: BLC-L04.
    function test_givenOperatorRevoked_whenFormerOperatorForwards_reverts() public {
        for (uint256 configDisabled; configDisabled < 2; ++configDisabled)
            for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
                uint256 snapshot = vm.snapshotState();
                vm.prank(admin);
                burnerLoansConfig.setConfigOperator(address(0));
                if (configDisabled != 0) {
                    vm.prank(admin);
                    burnerLoansConfig.disable("");
                }
                _setFacilityState(facilityDisabled != 0, false);
                _assertFailure(
                    address(configTimelock),
                    address(_asset),
                    _keeper,
                    alice,
                    _AMOUNT,
                    abi.encodeWithSelector(
                        IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                        address(configTimelock)
                    )
                );
                _assertFailure(
                    _NEW_OPERATOR,
                    address(_asset),
                    _keeper,
                    alice,
                    _AMOUNT,
                    abi.encodeWithSelector(
                        IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                        _NEW_OPERATOR
                    )
                );
                assertTrue(vm.revertToState(snapshot), "restore revoked delegation fixture");
            }
    }

    // Scenarios: BLC-L04.
    // Admin can forward while Config is enabled and BL is locally enabled or disabled.
    function test_givenOperatorRevoked_givenConfigEnabled_whenAdminForwards() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(admin);
            burnerLoansConfig.setConfigOperator(address(0));
            _setFacilityState(facilityDisabled != 0, false);
            _assertSuccessfulForwarding(admin);
            assertTrue(vm.revertToState(snapshot), "restore enabled Config fixture");
        }
    }

    // Scenarios: BLC-L04.
    function test_givenOperatorRevoked_givenConfigDisabled_whenAdminForwards_reverts() public {
        for (uint256 facilityDisabled; facilityDisabled < 2; ++facilityDisabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            burnerLoansConfig.setConfigOperator(address(0));
            burnerLoansConfig.disable("");
            vm.stopPrank();
            _setFacilityState(facilityDisabled != 0, false);
            _assertFailure(
                admin,
                address(_asset),
                _keeper,
                alice,
                _AMOUNT,
                abi.encodeWithSelector(IEnabler.NotEnabled.selector)
            );
            assertTrue(vm.revertToState(snapshot), "restore disabled Config fixture");
        }
    }

    /// @notice A replaced Configurator loses facility authority even if its own admin/operator remain authorized.
    // Scenarios: BLC-B01.
    function test_givenFacilityConfiguratorChanged_whenEnabledConfigForwards_reverts() public {
        BurnerLoansConfig replacement = _activateReplacementConfigurator();
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.setConfigurator(address(replacement));
        vm.stopPrank();
        address[2] memory callers = [admin, address(configTimelock)];
        bytes memory errorData = abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector);

        uint256 snapshot = vm.snapshotState();
        _setConfigState(0);
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(callers[c], address(_asset), _keeper, alice, _AMOUNT, errorData);
            _assertFailure(callers[c], address(_asset), _keeper, alice, 0, errorData);
        }
        assertTrue(vm.revertToState(snapshot), "restore replaced Configurator fixture");

        assertEq(
            burnerLoans.configurator(),
            address(replacement),
            "replacement retains facility authority"
        );
    }

    // Scenarios: BLC-B01, BLC-L07.
    function test_givenFacilityConfiguratorChanged_whenDisabledConfigForwards_reverts() public {
        BurnerLoansConfig replacement = _activateReplacementConfigurator();
        vm.startPrank(admin);
        burnerLoans.disable("");
        burnerLoans.setConfigurator(address(replacement));
        vm.stopPrank();
        address[2] memory callers = [admin, address(configTimelock)];

        uint256 snapshot = vm.snapshotState();
        _setConfigState(1);
        for (uint256 c; c < callers.length; ++c) {
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                alice,
                _AMOUNT,
                abi.encodeWithSelector(IEnabler.NotEnabled.selector)
            );
            _assertFailure(
                callers[c],
                address(_asset),
                _keeper,
                alice,
                0,
                abi.encodeWithSelector(IEnabler.NotEnabled.selector)
            );
        }
        assertTrue(vm.revertToState(snapshot), "restore replaced Configurator fixture");

        assertEq(
            burnerLoans.configurator(),
            address(replacement),
            "replacement retains facility authority"
        );
    }

    /// @notice An unbound, disabled BLC rejects recovery before attempting a facility call.
    // Scenarios: BLC-L05.
    function test_givenFacilityUnset_whenAdminForwards_reverts() public {
        BurnerLoansConfig unbound = new BurnerLoansConfig(kernel, IERC20(address(ohm)));
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(unbound));
        assertFalse(unbound.isEnabled(), "unbound Config remains locally disabled");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        unbound.rescuePendingPayout(address(_asset), _keeper, alice, _AMOUNT);
        assertEq(unbound.facility(), address(0), "failed forwarding leaves facility unset");
        _assertPendingRescueBalances(0);
    }

    /// @dev Enumerate enabled/disabled independently of Kernel-active/inactive; no history cases.
    /// @param state_ 0 active/enabled, 1 active/disabled, 2 inactive/enabled, 3 inactive/disabled.
    function _setConfigState(uint256 state_) internal {
        if (state_ % 2 != 0) {
            vm.prank(admin);
            burnerLoansConfig.disable("");
        }
        if (state_ >= 2) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoansConfig));
        }
    }

    /// @dev Set BL's local state before deactivation, keeping the two lifecycle axes independent.
    function _setFacilityState(bool disabled_, bool inactive_) internal {
        vm.startPrank(admin);
        if (disabled_) burnerLoans.disable("");
        if (inactive_) kernel.executeAction(Actions.DeactivatePolicy, address(burnerLoans));
        vm.stopPrank();
    }

    /// @dev Exercise one unauthorized caller across BLC state, BL activity, and valid/invalid amount.
    function _assertUnauthorizedCaller(address caller_) internal {
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
            caller_
        );
        // Any attempted BL forwarding would produce this different sentinel error.
        vm.mockCallRevert(
            address(burnerLoans),
            abi.encodeWithSelector(burnerLoans.rescuePendingPayout.selector),
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_ZeroAmount.selector)
        );
        for (uint256 state; state < 4; ++state) {
            for (uint256 disabledBL; disabledBL < 2; ++disabledBL) {
                for (uint256 inactiveBL; inactiveBL < 2; ++inactiveBL) {
                    uint256 snapshot = vm.snapshotState();
                    _setConfigState(state);
                    _setFacilityState(disabledBL != 0, inactiveBL != 0);
                    _assertFailure(
                        caller_,
                        address(_asset),
                        _keeper,
                        alice,
                        _AMOUNT,
                        expectedError
                    );
                    _assertFailure(caller_, address(_asset), _keeper, alice, 0, expectedError);
                    assertTrue(vm.revertToState(snapshot), "restore unauthorized fixture");
                }
            }
        }
        vm.clearMockedCalls();
    }

    /// @dev Expect one keeper-debit event and one transfer, then verify remaining debt and config.
    function _assertSuccessfulForwarding(address caller_) internal {
        bytes32 configBefore = _configHash();
        assertEq(
            burnerLoans.previewRescuePendingPayout(address(_asset), _keeper, alice, _AMOUNT),
            _REWARD,
            "preview reports original entitlement"
        );
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoansRescue.PendingSeizureRewardRescued(
            address(_asset),
            _keeper,
            alice,
            _AMOUNT
        );
        vm.recordLogs();
        vm.prank(caller_);
        burnerLoansConfig.rescuePendingPayout(address(_asset), _keeper, alice, _AMOUNT);
        assertEq(vm.getRecordedLogs().length, 2, "one reward event and one token transfer event");
        _assertPendingRescueBalances(_AMOUNT);
        assertEq(_configHash(), configBefore, "forwarding preserves configuration");
    }

    /// @dev Match a single representative downstream error and verify custody, debts and config rollback.
    /// @param error_ Exact BLC authorization or BL/dependency revert data, including arguments.
    function _assertFailure(
        address caller_,
        address token_,
        address recipient_,
        address destination_,
        uint256 amount_,
        bytes memory error_
    ) internal {
        bytes32 beforeState = _configHash();
        vm.expectRevert(error_);
        vm.prank(caller_);
        burnerLoansConfig.rescuePendingPayout(token_, recipient_, destination_, amount_);
        assertEq(_configHash(), beforeState, "failed forwarding preserves configuration");
        _assertPendingRescueBalances(0);
    }

    /// @dev Fingerprint the forwarding binding, authority, local state and Kernel membership.
    function _configHash() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    burnerLoansConfig.facility(),
                    burnerLoansConfig.configOperator(),
                    burnerLoans.configurator(),
                    burnerLoansConfig.isEnabled(),
                    burnerLoans.isEnabled(),
                    kernel.isPolicyActive(burnerLoansConfig),
                    kernel.isPolicyActive(burnerLoans)
                )
            );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return,calls-loop)
