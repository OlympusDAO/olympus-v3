pragma solidity >=0.8.24;

import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {RevenueDistributorSurplusRescueTestBase} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorSurplusRescueTest.sol";

// Quantities are base units; finite boundary/identity drivers avoid hidden state generators.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
contract RevenueDistributorRescueTest is RevenueDistributorSurplusRescueTestBase {
    uint256 internal constant _SURPLUS_PAYOUT = 19;
    uint256 internal constant _DESTINATION_BALANCE = 7;
    uint256 internal constant _ADDITIONAL_PAYOUT = 5;

    enum NestedAction {
        Surplus,
        PendingPayout,
        Retry,
        Distribute,
        Configuration
    }
    ReentrantPayoutToken internal _callbackAsset;

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenAdminRescues(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        token.mint(bob, _DESTINATION_BALANCE);

        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_PAYOUT,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, admin);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenAdminRescues(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        token.mint(bob, _DESTINATION_BALANCE);

        vm.startPrank(admin);
        distributor.disable("");

        vm.stopPrank();
        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_PAYOUT,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, admin);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenAdminRescues_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        token.mint(bob, _DESTINATION_BALANCE);

        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) distributor.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            );
            vm.expectRevert(failure);
            distributor.previewRescue(address(token), bob);
            vm.expectRevert(failure);
            distributor.previewRescue(address(0), address(0));
            _assertRDSurplusFailure(token, address(token), bob, admin, failure);
            _assertRDSurplusFailure(token, address(0), address(0), admin, failure);

            assertTrue(vm.revertToState(snapshot), "restore authorized RD lifecycle");
        }
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenOperatorRescues(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        token.mint(bob, _DESTINATION_BALANCE);

        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_PAYOUT,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, address(configTimelock));
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenOperatorRescues(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        token.mint(bob, _DESTINATION_BALANCE);

        vm.startPrank(admin);
        distributor.disable("");

        vm.stopPrank();
        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_PAYOUT,
            "surplus preview ignores local enablement"
        );
        _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, address(configTimelock));
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenOperatorRescues_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        token.mint(bob, _DESTINATION_BALANCE);

        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) distributor.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            );
            vm.expectRevert(failure);
            distributor.previewRescue(address(token), bob);
            vm.expectRevert(failure);
            distributor.previewRescue(address(0), address(0));
            _assertRDSurplusFailure(token, address(token), bob, address(configTimelock), failure);
            _assertRDSurplusFailure(
                token,
                address(0),
                address(0),
                address(configTimelock),
                failure
            );

            assertTrue(vm.revertToState(snapshot), "restore authorized RD lifecycle");
        }
    }

    // Scenarios: RD-RESCUE-L03, RD-RESCUE-L05.
    function test_givenActiveDistributor_whenCallerUnauthorized_reverts(address caller_) public {
        address operator = distributor.configOperator();
        vm.assume(
            !roles.hasRole(caller_, ADMIN_ROLE) && (operator == address(0) || caller_ != operator)
        );
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) distributor.disable("");

            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            );
            _assertRDSurplusFailure(token, address(token), bob, caller_, failure);
            _assertRDSurplusFailure(token, address(0), address(0), caller_, failure);
            assertTrue(vm.revertToState(snapshot), "restore unauthorized RD lifecycle");
        }
    }

    // Scenarios: RD-RESCUE-L04, RD-RESCUE-L06.
    function test_givenInactiveDistributor_whenCallerUnauthorized_reverts(address caller_) public {
        address operator = distributor.configOperator();
        vm.assume(
            !roles.hasRole(caller_, ADMIN_ROLE) && (operator == address(0) || caller_ != operator)
        );
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        for (uint256 disabled; disabled < 2; ++disabled) {
            uint256 snapshot = vm.snapshotState();
            vm.startPrank(admin);
            if (disabled != 0) distributor.disable("");
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
            vm.stopPrank();
            bytes memory failure = abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
                address(distributor)
            );
            _assertRDSurplusFailure(token, address(token), bob, caller_, failure);
            _assertRDSurplusFailure(token, address(0), address(0), caller_, failure);
            assertTrue(vm.revertToState(snapshot), "restore unauthorized RD lifecycle");
        }
    }

    // Preview ignores caller authorization and local enablement while RD is Kernel-active.
    // Scenarios: RD-RESCUE-L01, RD-RESCUE-L03, RD-RESCUE-L04, RD-RESCUE-L05, RD-RESCUE-L06, RD-RESCUE-L07.
    function test_givenActiveDistributor_whenAnyCallerPreviews(
        address caller_,
        bool disabled_
    ) public {
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        if (disabled_) {
            _disableDistributor();
        }
        vm.prank(caller_);
        assertEq(
            distributor.previewRescue(address(token), bob),
            _SURPLUS_PAYOUT,
            "preview is permissionless"
        );
    }

    // Activity is checked before invalid inputs, independently of caller identity.
    // Scenarios: RD-RESCUE-L03, RD-RESCUE-L04, RD-RESCUE-L05, RD-RESCUE-L06, RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenInactiveDistributor_whenAnyCallerPreviews_reverts(
        address caller_,
        bool disabled_
    ) public {
        vm.startPrank(admin);
        if (disabled_) distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();
        bytes memory failure = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_PolicyNotActive.selector,
            address(distributor)
        );
        vm.expectRevert(failure);
        vm.prank(caller_);
        distributor.previewRescue(address(token), bob);
        vm.expectRevert(failure);
        vm.prank(caller_);
        distributor.previewRescue(address(0), address(0));
    }

    // Scenarios: RD-RESCUE-L03, RD-RESCUE-L05.
    function test_givenUnauthorizedIdentities_whenSeeded_reverts() public {
        address[3] memory callers = [address(0), emergency, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            test_givenActiveDistributor_whenCallerUnauthorized_reverts(callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore seeded unauthorized identity");
        }
        vm.prank(admin);
        distributor.setConfigOperator(alice);
        test_givenActiveDistributor_whenCallerUnauthorized_reverts(address(configTimelock));
    }

    // Scenarios: RD-RESCUE-A01, RD-RESCUE-A02.
    function test_givenTimelockUnavailable_whenAdminRescuesDirectly() public {
        for (uint256 inactiveTimelock; inactiveTimelock < 2; ++inactiveTimelock)
            for (uint256 disabledRD; disabledRD < 2; ++disabledRD) {
                uint256 snapshot = vm.snapshotState();
                _createManagedRescueDebt();
                token.mint(address(distributor), _SURPLUS_PAYOUT);
                vm.startPrank(admin);
                if (inactiveTimelock == 0) configTimelock.disable("");
                else kernel.executeAction(Actions.DeactivatePolicy, address(configTimelock));
                if (disabledRD != 0) distributor.disable("");
                vm.stopPrank();
                uint64 counter = configTimelock.nextActionId();
                bytes32 timelockBefore = _timelockControlDigest();
                _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, admin);
                assertEq(
                    _timelockControlDigest(),
                    timelockBefore,
                    "Direct recovery preserves timelock lifecycle and queue control"
                );
                assertEq(
                    configTimelock.nextActionId(),
                    counter,
                    "direct recovery creates no queued action"
                );
                assertTrue(vm.revertToState(snapshot), "restore direct RD recovery");
            }
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenFullCustodyRescued(
        uint256 balance_,
        address destination_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        vm.assume(
            destination_ != address(0) &&
                destination_ != address(kernel) &&
                destination_ != address(distributor) &&
                destination_ != address(token)
        );
        _createManagedRescueDebt();
        _caseFullCustody(bound(balance_, 1, type(uint256).max), destination_);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        uint256[3] memory balances = [uint256(1), type(uint256).max - 1, type(uint256).max];
        address[3] memory destinations = [address(treasury), address(configTimelock), bob];
        for (uint256 b; b < balances.length; ++b)
            for (uint256 d; d < destinations.length; ++d) {
                uint256 snapshot = vm.snapshotState();
                _caseFullCustody(balances[b], destinations[d]);
                assertTrue(
                    vm.revertToState(snapshot),
                    "restore full-payout boundary and destination"
                );
            }
    }

    function _caseFullCustody(uint256 balance_, address destination_) internal {
        token.mint(address(distributor), balance_);
        uint256 supplyBudget = type(uint256).max - balance_;
        token.mint(
            destination_,
            supplyBudget < _DESTINATION_BALANCE ? supplyBudget : _DESTINATION_BALANCE
        );
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _assertRDSurplusPayment(token, destination_, balance_, callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore full custody between caller classes");
        }
    }

    // Scenarios: RD-RESCUE-P03.
    function test_givenZeroCustody_whenEachPermittedCallerRescues(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        _assertRDSurplusPayment(token, bob, 0, admin);
        _assertRDSurplusPayment(token, bob, 0, address(configTimelock));
    }

    // Scenarios: RD-RESCUE-P08.
    function test_givenOperatorRotated_whenFormerOperatorRescues_reverts() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        _assertRDSurplusFailure(
            token,
            address(token),
            bob,
            address(configTimelock),
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                address(configTimelock)
            )
        );
    }

    // Scenarios: RD-RESCUE-A03, RD-RESCUE-P07.
    function test_givenOperatorRotated_whenCurrentAuthorityRescues() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        address[2] memory callers = [admin, newOperator];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore independent authorized payment");
        }
    }

    // Scenarios: RD-RESCUE-P08.
    function test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        vm.prank(admin);
        distributor.setConfigOperator(address(0));
        address[2] memory callers = [newOperator, address(0)];
        for (uint256 c; c < callers.length; ++c)
            _assertRDSurplusFailure(
                token,
                address(token),
                bob,
                callers[c],
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    callers[c]
                )
            );
    }

    // Scenarios: RD-RESCUE-A03.
    function test_givenOperatorRevoked_whenAdminRescues() public {
        address newOperator = alice;
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        vm.prank(admin);
        distributor.setConfigOperator(newOperator);
        vm.prank(admin);
        distributor.setConfigOperator(address(0));
        _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, admin);
    }

    // Scenarios: RD-RESCUE-I01, RD-RESCUE-I02.
    function test_givenNeverListedAsset_whenAssetHasNoCode_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        address[2] memory callers = [admin, address(configTimelock)];
        uint256[3] memory balances = [uint256(0), 1, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 c; c < callers.length; ++c)
                for (uint256 b; b < balances.length; ++b) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabled != 0) {
                        _disableDistributor();
                    }
                    token.mint(address(distributor), balances[b]);
                    address[2] memory invalidAssets = [
                        address(0),
                        makeAddr("RD no-code rescue asset")
                    ];
                    for (uint256 a; a < invalidAssets.length; ++a) {
                        bytes memory failure = abi.encodeWithSelector(
                            IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
                            invalidAssets[a]
                        );
                        _assertRDMatchingError(token, invalidAssets[a], bob, callers[c], failure);
                        // Combining faults also proves asset validation precedes destination validation.
                        _assertRDMatchingError(
                            token,
                            invalidAssets[a],
                            address(0),
                            callers[c],
                            failure
                        );
                    }

                    assertTrue(vm.revertToState(snapshot), "restore invalid RD request");
                }
    }

    // Scenarios: RD-RESCUE-I05, RD-RESCUE-I06, RD-RESCUE-I07, RD-RESCUE-I08.
    function test_givenNeverListedAsset_whenDestinationIsForbidden_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        address[2] memory callers = [admin, address(configTimelock)];
        uint256[3] memory balances = [uint256(0), 1, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 c; c < callers.length; ++c)
                for (uint256 b; b < balances.length; ++b) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabled != 0) {
                        _disableDistributor();
                    }
                    token.mint(address(distributor), balances[b]);

                    address[4] memory forbidden = [
                        address(0),
                        address(kernel),
                        address(distributor),
                        address(token)
                    ];
                    for (uint256 d; d < forbidden.length; ++d)
                        _assertRDMatchingError(
                            token,
                            address(token),
                            forbidden[d],
                            callers[c],
                            abi.encodeWithSelector(
                                IRevenueDistributorRescue
                                    .RevenueDistributor_InvalidRescueDestination
                                    .selector,
                                forbidden[d]
                            )
                        );

                    assertTrue(vm.revertToState(snapshot), "restore invalid RD request");
                }
    }

    // Scenarios: RD-RESCUE-I17.
    function test_givenNeverListedAsset_whenBalanceQueryReverts_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        _createManagedRescueDebt();
        address[2] memory callers = [admin, address(configTimelock)];
        uint256[3] memory balances = [uint256(0), 1, type(uint256).max];
        for (uint256 disabled; disabled < 2; ++disabled)
            for (uint256 c; c < callers.length; ++c)
                for (uint256 b; b < balances.length; ++b) {
                    uint256 snapshot = vm.snapshotState();
                    if (disabled != 0) {
                        _disableDistributor();
                    }
                    token.mint(address(distributor), balances[b]);

                    _assertRDBalanceQueryFailure(token, callers[c]);
                    assertTrue(vm.revertToState(snapshot), "restore invalid RD request");
                }
    }

    /// @notice Managed assets are forbidden regardless of solvency, debt or local enablement.
    // Scenarios: RD-RESCUE-I13.
    function test_givenActiveAsset_whenSurplusRescueRequested_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 custodyState; custodyState < 4; ++custodyState)
            for (uint256 disabled; disabled < 2; ++disabled)
                for (uint256 c; c < callers.length; ++c) {
                    uint256 snapshot = vm.snapshotState();
                    ReentrantPayoutToken asset;
                    if (custodyState == 0) {
                        asset = new ReentrantPayoutToken();
                        IRevenueDistributor.AssetRoute[]
                            memory routes = new IRevenueDistributor.AssetRoute[](0);
                        vm.prank(admin);
                        distributor.setAssetRoutes(address(asset), 0, routes);
                    } else {
                        asset = _createManagedRescueDebt();
                        if (custodyState == 1) asset.burn(address(distributor), 1);
                        if (custodyState == 3) asset.mint(address(distributor), _ADDITIONAL_PAYOUT);
                    }

                    if (disabled != 0) {
                        _disableDistributor();
                    }
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        bob,
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue.RevenueDistributor_AssetManaged.selector,
                            address(asset)
                        )
                    );
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        address(kernel),
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue
                                .RevenueDistributor_InvalidRescueDestination
                                .selector,
                            address(kernel)
                        )
                    );
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore managed-asset payout and listing state"
                    );
                }
    }

    // Scenarios: RD-RESCUE-I15.
    function test_givenRetiredAsset_whenSurplusRescueRequested_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        address[2] memory callers = [admin, address(configTimelock)];
        for (uint256 custodyState; custodyState < 4; ++custodyState)
            for (uint256 disabled; disabled < 2; ++disabled)
                for (uint256 c; c < callers.length; ++c) {
                    uint256 snapshot = vm.snapshotState();
                    ReentrantPayoutToken asset;
                    if (custodyState == 0) {
                        asset = new ReentrantPayoutToken();
                        IRevenueDistributor.AssetRoute[]
                            memory routes = new IRevenueDistributor.AssetRoute[](0);
                        vm.prank(admin);
                        distributor.setAssetRoutes(address(asset), 0, routes);
                    } else {
                        asset = _createManagedRescueDebt();
                        if (custodyState == 1) asset.burn(address(distributor), 1);
                        if (custodyState == 3) asset.mint(address(distributor), _ADDITIONAL_PAYOUT);
                    }

                    vm.prank(admin);
                    distributor.disableAssetRoutes(address(asset));

                    if (disabled != 0) {
                        _disableDistributor();
                    }
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        bob,
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue.RevenueDistributor_AssetManaged.selector,
                            address(asset)
                        )
                    );
                    _assertRDMatchingError(
                        asset,
                        address(asset),
                        address(kernel),
                        callers[c],
                        abi.encodeWithSelector(
                            IRevenueDistributorRescue
                                .RevenueDistributor_InvalidRescueDestination
                                .selector,
                            address(kernel)
                        )
                    );
                    assertTrue(
                        vm.revertToState(snapshot),
                        "restore managed-asset payout and listing state"
                    );
                }
    }

    function _assertRDMatchingError(
        MockERC20 tracker_,
        address asset_,
        address destination_,
        address caller_,
        bytes memory failure_
    ) internal {
        vm.expectRevert(failure_);
        distributor.previewRescue(asset_, destination_);
        _assertRDSurplusFailure(tracker_, asset_, destination_, caller_, failure_);
    }

    // Scenarios: RD-RESCUE-T01.
    function test_givenNeverListedAsset_whenTransferReverts_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        ReentrantPayoutToken asset = _prepareRescueTransfer();
        asset.setTransferBlocked(bob, true);
        bytes memory failure = abi.encodeWithSelector(
            ReentrantPayoutToken.TransferBlocked.selector,
            bob
        );
        _assertRDSurplusFailure(asset, address(asset), bob, admin, failure);
        _assertRDSurplusFailure(asset, address(asset), bob, address(configTimelock), failure);
    }

    // Scenarios: RD-RESCUE-T03.
    function test_givenNeverListedAsset_whenTransferReturnsFalse_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        ReentrantPayoutToken asset = _prepareRescueTransfer();
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.transfer.selector, bob),
            abi.encode(false)
        );
        bytes memory failure = abi.encodeWithSelector(
            SafeERC20.SafeERC20FailedOperation.selector,
            address(asset)
        );
        _assertRDSurplusFailure(asset, address(asset), bob, admin, failure);
        _assertRDSurplusFailure(asset, address(asset), bob, address(configTimelock), failure);
        vm.clearMockedCalls();
    }

    function _prepareRescueTransfer() internal returns (ReentrantPayoutToken asset) {
        _createManagedRescueDebt();
        asset = new ReentrantPayoutToken();
        asset.mint(address(distributor), _SURPLUS_PAYOUT);
        asset.mint(bob, _DESTINATION_BALANCE);
        assertEq(
            distributor.previewRescue(address(asset), bob),
            _SURPLUS_PAYOUT,
            "preview omits transfer dependency"
        );
    }

    // Scenarios: RD-RESCUE-C01.
    function test_givenSurplusRescueCallback_whenFailureIsCaught(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 differentToken; differentToken < 2; ++differentToken)
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                (
                    MockERC20 nestedAsset,
                    bytes32 nestedBefore,
                    uint256 nestedCustody
                ) = _prepareSurplusCallback(NestedAction.Surplus, differentToken != 0);
                _callbackAsset.setBubbleCallbackFailure(false);
                address caller = operatorCaller == 0 ? admin : address(this);
                _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_PAYOUT, caller);
                assertEq(
                    _callbackAsset.callbackRevertData(),
                    abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                    "nested action reaches guard after callback reads"
                );
                _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: RD-RESCUE-C05.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 differentToken; differentToken < 2; ++differentToken)
            for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
                uint256 snapshot = vm.snapshotState();
                (
                    MockERC20 nestedAsset,
                    bytes32 nestedBefore,
                    uint256 nestedCustody
                ) = _prepareSurplusCallback(NestedAction.Surplus, differentToken != 0);
                _callbackAsset.setBubbleCallbackFailure(true);
                address caller = operatorCaller == 0 ? admin : address(this);
                _assertRDSurplusFailure(
                    _callbackAsset,
                    address(_callbackAsset),
                    bob,
                    caller,
                    abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
                );
                assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");
                _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
                assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
            }
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRescueCallback_whenFailureIsCaught(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.PendingPayout, false);
            _callbackAsset.setBubbleCallbackFailure(false);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_PAYOUT, caller);
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches guard after callback reads"
            );
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRescueCallback_whenFailureIsPropagated(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.PendingPayout, false);
            _callbackAsset.setBubbleCallbackFailure(true);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                bob,
                caller,
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRetryCallback_whenFailureIsCaught(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.Retry, false);
            _callbackAsset.setBubbleCallbackFailure(false);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_PAYOUT, caller);
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches guard after callback reads"
            );
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRetryCallback_whenFailureIsPropagated(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.Retry, false);
            _callbackAsset.setBubbleCallbackFailure(true);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                bob,
                caller,
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenDistributeCallback_whenFailureIsCaught(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.Distribute, false);
            _callbackAsset.setBubbleCallbackFailure(false);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_PAYOUT, caller);
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches guard after callback reads"
            );
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenDistributeCallback_whenFailureIsPropagated(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.Distribute, false);
            _callbackAsset.setBubbleCallbackFailure(true);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                bob,
                caller,
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenConfigurationCallback_whenFailureIsCaught(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.Configuration, false);
            _callbackAsset.setBubbleCallbackFailure(false);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusPayment(_callbackAsset, bob, _SURPLUS_PAYOUT, caller);
            assertEq(
                _callbackAsset.callbackRevertData(),
                abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
                "nested action reaches guard after callback reads"
            );
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenConfigurationCallback_whenFailureIsPropagated(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        for (uint256 operatorCaller; operatorCaller < 2; ++operatorCaller) {
            uint256 snapshot = vm.snapshotState();
            (
                MockERC20 nestedAsset,
                bytes32 nestedBefore,
                uint256 nestedCustody
            ) = _prepareSurplusCallback(NestedAction.Configuration, false);
            _callbackAsset.setBubbleCallbackFailure(true);
            address caller = operatorCaller == 0 ? admin : address(this);
            _assertRDSurplusFailure(
                _callbackAsset,
                address(_callbackAsset),
                bob,
                caller,
                abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector)
            );
            assertTrue(_callbackAsset.callbackEnabled(), "propagation restores callback state");
            _assertNestedCallbackState(nestedAsset, nestedBefore, nestedCustody);
            assertTrue(vm.revertToState(snapshot), "restore callback action/caller/outcome");
        }
    }

    function observeAndAttemptNestedAction(address nestedAsset_, NestedAction action_) external {
        assertEq(msg.sender, address(_callbackAsset), "observer called by outer token");
        assertEq(
            distributor.previewRescue(address(_callbackAsset), bob),
            0,
            "callback observes consumed surplus"
        );
        assertEq(
            distributor.totalPendingForTest(address(_managedAsset)),
            _MANAGED_RESERVE,
            "callback observes unrelated liabilities intact"
        );
        if (action_ == NestedAction.Surplus) distributor.rescue(nestedAsset_, bob);
        else if (action_ == NestedAction.PendingPayout)
            distributor.rescuePendingPayout(nestedAsset_, alice, bob, 1);
        else if (action_ == NestedAction.Retry)
            distributor.transferPendingPayout(nestedAsset_, alice);
        else if (action_ == NestedAction.Distribute) distributor.distribute(nestedAsset_);
        else distributor.setYieldRecipient(distributor.yieldRecipient());
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorRestored_whenSurplusRescued(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        token.mint(address(distributor), _SURPLUS_PAYOUT);
        vm.startPrank(admin);
        distributor.disable("");
        distributor.reEnable();
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        vm.stopPrank();
        _assertRDSurplusPayment(token, bob, _SURPLUS_PAYOUT, admin);
    }

    function _prepareSurplusCallback(
        NestedAction action_,
        bool differentToken_
    ) internal returns (MockERC20 nestedAsset, bytes32 nestedBefore, uint256 nestedCustody) {
        _createManagedRescueDebt();
        _callbackAsset = new ReentrantPayoutToken();
        _callbackAsset.mint(address(distributor), _SURPLUS_PAYOUT);
        nestedAsset = _managedAsset;
        if (action_ == NestedAction.Surplus) {
            nestedAsset = _callbackAsset;
            if (differentToken_) {
                nestedAsset = new MockERC20("Other surplus", "OSUR", 18);
                nestedAsset.mint(address(distributor), _ADDITIONAL_PAYOUT);
            }
        }
        vm.prank(admin);
        if (_configurationSeed == address(0)) distributor.setConfigOperator(address(this));
        else rolesAdmin.grantRole(ADMIN_ROLE, address(this));
        nestedBefore = _rdRawRescueHash(address(nestedAsset));
        nestedCustody = nestedAsset.balanceOf(address(distributor));
        _callbackAsset.setCallbackFrom(
            address(distributor),
            address(this),
            abi.encodeCall(this.observeAndAttemptNestedAction, (address(nestedAsset), action_))
        );
    }

    function _assertNestedCallbackState(
        MockERC20 nestedAsset_,
        bytes32 nestedBefore_,
        uint256 nestedCustody_
    ) internal view {
        assertEq(
            _rdRawRescueHash(address(nestedAsset_)),
            nestedBefore_,
            "nested accounting and indexes preserved"
        );
        if (address(nestedAsset_) != address(_callbackAsset))
            assertEq(
                nestedAsset_.balanceOf(address(distributor)),
                nestedCustody_,
                "other token payout unchanged"
            );
    }

    // Scenarios: RD-RESCUE-I13.
    function test_givenActiveAsset_whenSurplusRescueRequested_reverts_AdminOnlySeed() public {
        test_givenActiveAsset_whenSurplusRescueRequested_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-I13.
    function test_givenActiveAsset_whenSurplusRescueRequested_reverts_OperatorOnlySeed() public {
        test_givenActiveAsset_whenSurplusRescueRequested_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-I13.
    function test_givenActiveAsset_whenSurplusRescueRequested_reverts_RolesOverlapSeed() public {
        test_givenActiveAsset_whenSurplusRescueRequested_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenConfigurationCallback_whenFailureIsCaught_AdminOnlySeed() public {
        test_givenConfigurationCallback_whenFailureIsCaught(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenConfigurationCallback_whenFailureIsCaught_OperatorOnlySeed() public {
        test_givenConfigurationCallback_whenFailureIsCaught(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenConfigurationCallback_whenFailureIsCaught_RolesOverlapSeed() public {
        test_givenConfigurationCallback_whenFailureIsCaught(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenConfigurationCallback_whenFailureIsPropagated_AdminOnlySeed() public {
        test_givenConfigurationCallback_whenFailureIsPropagated(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenConfigurationCallback_whenFailureIsPropagated_OperatorOnlySeed() public {
        test_givenConfigurationCallback_whenFailureIsPropagated(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenConfigurationCallback_whenFailureIsPropagated_RolesOverlapSeed() public {
        test_givenConfigurationCallback_whenFailureIsPropagated(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenDistributeCallback_whenFailureIsCaught_AdminOnlySeed() public {
        test_givenDistributeCallback_whenFailureIsCaught(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenDistributeCallback_whenFailureIsCaught_OperatorOnlySeed() public {
        test_givenDistributeCallback_whenFailureIsCaught(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenDistributeCallback_whenFailureIsCaught_RolesOverlapSeed() public {
        test_givenDistributeCallback_whenFailureIsCaught(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenDistributeCallback_whenFailureIsPropagated_AdminOnlySeed() public {
        test_givenDistributeCallback_whenFailureIsPropagated(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenDistributeCallback_whenFailureIsPropagated_OperatorOnlySeed() public {
        test_givenDistributeCallback_whenFailureIsPropagated(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenDistributeCallback_whenFailureIsPropagated_RolesOverlapSeed() public {
        test_givenDistributeCallback_whenFailureIsPropagated(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenAdminRescues_AdminOnlySeed() public {
        test_givenDistributorDisabled_whenAdminRescues(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenAdminRescues_OperatorOnlySeed() public {
        test_givenDistributorDisabled_whenAdminRescues(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenAdminRescues_RolesOverlapSeed() public {
        test_givenDistributorDisabled_whenAdminRescues(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenOperatorRescues_AdminOnlySeed() public {
        test_givenDistributorDisabled_whenOperatorRescues(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenOperatorRescues_OperatorOnlySeed() public {
        test_givenDistributorDisabled_whenOperatorRescues(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L07.
    function test_givenDistributorDisabled_whenOperatorRescues_RolesOverlapSeed() public {
        test_givenDistributorDisabled_whenOperatorRescues(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenAdminRescues_AdminOnlySeed() public {
        test_givenDistributorEnabled_whenAdminRescues(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenAdminRescues_OperatorOnlySeed() public {
        test_givenDistributorEnabled_whenAdminRescues(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenAdminRescues_RolesOverlapSeed() public {
        test_givenDistributorEnabled_whenAdminRescues(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenOperatorRescues_AdminOnlySeed() public {
        test_givenDistributorEnabled_whenOperatorRescues(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenOperatorRescues_OperatorOnlySeed() public {
        test_givenDistributorEnabled_whenOperatorRescues(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorEnabled_whenOperatorRescues_RolesOverlapSeed() public {
        test_givenDistributorEnabled_whenOperatorRescues(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenAdminRescues_reverts_AdminOnlySeed() public {
        test_givenDistributorInactive_whenAdminRescues_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenAdminRescues_reverts_OperatorOnlySeed() public {
        test_givenDistributorInactive_whenAdminRescues_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenAdminRescues_reverts_RolesOverlapSeed() public {
        test_givenDistributorInactive_whenAdminRescues_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenOperatorRescues_reverts_AdminOnlySeed() public {
        test_givenDistributorInactive_whenOperatorRescues_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenOperatorRescues_reverts_OperatorOnlySeed() public {
        test_givenDistributorInactive_whenOperatorRescues_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L09, RD-RESCUE-L10.
    function test_givenDistributorInactive_whenOperatorRescues_reverts_RolesOverlapSeed() public {
        test_givenDistributorInactive_whenOperatorRescues_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorRestored_whenSurplusRescued_AdminOnlySeed() public {
        test_givenDistributorRestored_whenSurplusRescued(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorRestored_whenSurplusRescued_OperatorOnlySeed() public {
        test_givenDistributorRestored_whenSurplusRescued(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-L01.
    function test_givenDistributorRestored_whenSurplusRescued_RolesOverlapSeed() public {
        test_givenDistributorRestored_whenSurplusRescued(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-I01, RD-RESCUE-I02.
    function test_givenNeverListedAsset_whenAssetHasNoCode_reverts_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenAssetHasNoCode_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-I01, RD-RESCUE-I02.
    function test_givenNeverListedAsset_whenAssetHasNoCode_reverts_OperatorOnlySeed() public {
        test_givenNeverListedAsset_whenAssetHasNoCode_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-I01, RD-RESCUE-I02.
    function test_givenNeverListedAsset_whenAssetHasNoCode_reverts_RolesOverlapSeed() public {
        test_givenNeverListedAsset_whenAssetHasNoCode_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-I17.
    function test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenBalanceQueryReverts_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-I17.
    function test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_OperatorOnlySeed() public {
        test_givenNeverListedAsset_whenBalanceQueryReverts_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-I17.
    function test_givenNeverListedAsset_whenBalanceQueryReverts_reverts_RolesOverlapSeed() public {
        test_givenNeverListedAsset_whenBalanceQueryReverts_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_OperatorOnlySeed()
        public
    {
        test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded_RolesOverlapSeed()
        public
    {
        test_givenNeverListedAsset_whenBalancesAndDestinationsSeeded(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-I05, RD-RESCUE-I06, RD-RESCUE-I07, RD-RESCUE-I08.
    function test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenDestinationIsForbidden_reverts(
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: RD-RESCUE-I05, RD-RESCUE-I06, RD-RESCUE-I07, RD-RESCUE-I08.
    function test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_OperatorOnlySeed()
        public
    {
        test_givenNeverListedAsset_whenDestinationIsForbidden_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-I05, RD-RESCUE-I06, RD-RESCUE-I07, RD-RESCUE-I08.
    function test_givenNeverListedAsset_whenDestinationIsForbidden_reverts_RolesOverlapSeed()
        public
    {
        test_givenNeverListedAsset_whenDestinationIsForbidden_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenFullCustodyRescued_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenFullCustodyRescued(1, bob, address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenFullCustodyRescued_OperatorOnlySeed() public {
        test_givenNeverListedAsset_whenFullCustodyRescued(1, bob, address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-P01, RD-RESCUE-P05.
    function test_givenNeverListedAsset_whenFullCustodyRescued_RolesOverlapSeed() public {
        test_givenNeverListedAsset_whenFullCustodyRescued(1, bob, address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-T03.
    function test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenTransferReturnsFalse_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-T03.
    function test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_OperatorOnlySeed() public {
        test_givenNeverListedAsset_whenTransferReturnsFalse_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-T03.
    function test_givenNeverListedAsset_whenTransferReturnsFalse_reverts_RolesOverlapSeed() public {
        test_givenNeverListedAsset_whenTransferReturnsFalse_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-T01.
    function test_givenNeverListedAsset_whenTransferReverts_reverts_AdminOnlySeed() public {
        test_givenNeverListedAsset_whenTransferReverts_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-T01.
    function test_givenNeverListedAsset_whenTransferReverts_reverts_OperatorOnlySeed() public {
        test_givenNeverListedAsset_whenTransferReverts_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-T01.
    function test_givenNeverListedAsset_whenTransferReverts_reverts_RolesOverlapSeed() public {
        test_givenNeverListedAsset_whenTransferReverts_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRescueCallback_whenFailureIsCaught_AdminOnlySeed() public {
        test_givenPendingRescueCallback_whenFailureIsCaught(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRescueCallback_whenFailureIsCaught_OperatorOnlySeed() public {
        test_givenPendingRescueCallback_whenFailureIsCaught(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRescueCallback_whenFailureIsCaught_RolesOverlapSeed() public {
        test_givenPendingRescueCallback_whenFailureIsCaught(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRescueCallback_whenFailureIsPropagated_AdminOnlySeed() public {
        test_givenPendingRescueCallback_whenFailureIsPropagated(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRescueCallback_whenFailureIsPropagated_OperatorOnlySeed() public {
        test_givenPendingRescueCallback_whenFailureIsPropagated(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRescueCallback_whenFailureIsPropagated_RolesOverlapSeed() public {
        test_givenPendingRescueCallback_whenFailureIsPropagated(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRetryCallback_whenFailureIsCaught_AdminOnlySeed() public {
        test_givenPendingRetryCallback_whenFailureIsCaught(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRetryCallback_whenFailureIsCaught_OperatorOnlySeed() public {
        test_givenPendingRetryCallback_whenFailureIsCaught(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C03.
    function test_givenPendingRetryCallback_whenFailureIsCaught_RolesOverlapSeed() public {
        test_givenPendingRetryCallback_whenFailureIsCaught(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRetryCallback_whenFailureIsPropagated_AdminOnlySeed() public {
        test_givenPendingRetryCallback_whenFailureIsPropagated(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRetryCallback_whenFailureIsPropagated_OperatorOnlySeed() public {
        test_givenPendingRetryCallback_whenFailureIsPropagated(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C06.
    function test_givenPendingRetryCallback_whenFailureIsPropagated_RolesOverlapSeed() public {
        test_givenPendingRetryCallback_whenFailureIsPropagated(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-I15.
    function test_givenRetiredAsset_whenSurplusRescueRequested_reverts_AdminOnlySeed() public {
        test_givenRetiredAsset_whenSurplusRescueRequested_reverts(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-I15.
    function test_givenRetiredAsset_whenSurplusRescueRequested_reverts_OperatorOnlySeed() public {
        test_givenRetiredAsset_whenSurplusRescueRequested_reverts(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-I15.
    function test_givenRetiredAsset_whenSurplusRescueRequested_reverts_RolesOverlapSeed() public {
        test_givenRetiredAsset_whenSurplusRescueRequested_reverts(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C01.
    function test_givenSurplusRescueCallback_whenFailureIsCaught_AdminOnlySeed() public {
        test_givenSurplusRescueCallback_whenFailureIsCaught(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C01.
    function test_givenSurplusRescueCallback_whenFailureIsCaught_OperatorOnlySeed() public {
        test_givenSurplusRescueCallback_whenFailureIsCaught(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C01.
    function test_givenSurplusRescueCallback_whenFailureIsCaught_RolesOverlapSeed() public {
        test_givenSurplusRescueCallback_whenFailureIsCaught(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-C05.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated_AdminOnlySeed() public {
        test_givenSurplusRescueCallback_whenFailureIsPropagated(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-C05.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated_OperatorOnlySeed() public {
        test_givenSurplusRescueCallback_whenFailureIsPropagated(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-C05.
    function test_givenSurplusRescueCallback_whenFailureIsPropagated_RolesOverlapSeed() public {
        test_givenSurplusRescueCallback_whenFailureIsPropagated(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-P03.
    function test_givenZeroCustody_whenEachPermittedCallerRescues_AdminOnlySeed() public {
        test_givenZeroCustody_whenEachPermittedCallerRescues(address(0x1234), false, false);
    }

    // Scenarios: RD-RESCUE-P03.
    function test_givenZeroCustody_whenEachPermittedCallerRescues_OperatorOnlySeed() public {
        test_givenZeroCustody_whenEachPermittedCallerRescues(address(0x1234), true, false);
    }

    // Scenarios: RD-RESCUE-P03.
    function test_givenZeroCustody_whenEachPermittedCallerRescues_RolesOverlapSeed() public {
        test_givenZeroCustody_whenEachPermittedCallerRescues(address(0x1234), true, true);
    }

    // Scenarios: RD-RESCUE-L04, RD-RESCUE-L06.
    function test_givenInactiveUnauthorizedIdentities_whenSeeded_reverts() public {
        address[3] memory callers = [address(0), emergency, alice];
        for (uint256 c; c < callers.length; ++c) {
            uint256 snapshot = vm.snapshotState();
            test_givenInactiveDistributor_whenCallerUnauthorized_reverts(callers[c]);
            assertTrue(vm.revertToState(snapshot), "restore seeded unauthorized identity");
        }
        vm.prank(admin);
        distributor.setConfigOperator(alice);
        test_givenInactiveDistributor_whenCallerUnauthorized_reverts(address(configTimelock));
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return,unsafe-typecast)
