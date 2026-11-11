// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {Actions} from "src/Kernel.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {stdError} from "@forge-std-1.16.2/StdError.sol";

// Scenario amounts are token base units. Bounded loops/casts build matrices; ignored returns must revert.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)

contract RevenueDistributorSetAssetRoutesTest is RevenueDistributorTest {
    // Scenarios: SAR-A03.
    function test_givenPolicyActiveEnabledAndInputState_whenUnauthorizedCallerSetsRoute_reverts(
        address caller_,
        bool invalidInput_
    ) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        IRevenueDistributor.AssetRoute[] memory initial = new IRevenueDistributor.AssetRoute[](1);
        initial[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, initial);
        distributor.seedPendingForTest(address(token), bob, 11, 22, 33);
        token.mint(address(distributor), 66);
        bytes32 hashBefore = distributor.assetDistributionHash(address(token));

        IRevenueDistributor.AssetRoute[] memory proposed = new IRevenueDistributor.AssetRoute[](1);
        proposed[0] = IRevenueDistributor.AssetRoute({
            recipient: bob,
            bps: invalidInput_ ? 0 : 5_000
        });
        address asset = invalidInput_ ? address(0) : address(token);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        distributor.setAssetRoutes(asset, type(uint16).max, proposed);

        assertEq(
            distributor.assetDistributionHash(address(token)),
            hashBefore,
            "unauthorized call preserves route"
        );
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "unauthorized call preserves custody");
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized call emits no event");
    }

    // Scenarios: SAR-L01.
    function test_givenPolicyActiveDisabledAndInputState_whenUnauthorizedCallerSetsRoute_reverts(
        address caller_,
        bool invalidInput_
    ) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        IRevenueDistributor.AssetRoute[] memory initial = new IRevenueDistributor.AssetRoute[](1);
        initial[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, initial);
        distributor.seedPendingForTest(address(token), bob, 11, 22, 33);
        token.mint(address(distributor), 66);
        bytes32 hashBefore = distributor.assetDistributionHash(address(token));

        _disableDistributor();

        IRevenueDistributor.AssetRoute[] memory proposed = new IRevenueDistributor.AssetRoute[](1);
        proposed[0] = IRevenueDistributor.AssetRoute({
            recipient: bob,
            bps: invalidInput_ ? 0 : 5_000
        });
        address asset = invalidInput_ ? address(0) : address(token);

        vm.recordLogs();
        _expectNotEnabled();
        vm.prank(caller_);
        distributor.setAssetRoutes(asset, type(uint16).max, proposed);

        assertEq(
            distributor.assetDistributionHash(address(token)),
            hashBefore,
            "unauthorized call preserves route"
        );
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "unauthorized call preserves custody");
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized call emits no event");
    }

    // Scenarios: SAR-L02, SAR-L03.
    function test_givenPolicyInactiveAndInputState_whenUnauthorizedCallerSetsRoute_reverts(
        address caller_,
        bool disable_,
        bool invalidInput_
    ) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        IRevenueDistributor.AssetRoute[] memory initial = new IRevenueDistributor.AssetRoute[](1);
        initial[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, initial);
        distributor.seedPendingForTest(address(token), bob, 11, 22, 33);
        token.mint(address(distributor), 66);
        bytes32 hashBefore = distributor.assetDistributionHash(address(token));
        if (disable_) {
            _disableDistributor();
        }

        _setPolicyActive(address(distributor), false);
        IRevenueDistributor.AssetRoute[] memory proposed = new IRevenueDistributor.AssetRoute[](1);
        proposed[0] = IRevenueDistributor.AssetRoute({
            recipient: bob,
            bps: invalidInput_ ? 0 : 5_000
        });
        address asset = invalidInput_ ? address(0) : address(token);

        vm.recordLogs();
        _expectPolicyInactive();
        vm.prank(caller_);
        distributor.setAssetRoutes(asset, type(uint16).max, proposed);

        assertEq(
            distributor.assetDistributionHash(address(token)),
            hashBefore,
            "unauthorized call preserves route"
        );
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "unauthorized call preserves custody");
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized call emits no event");
    }

    // Scenarios: SAR-A03.
    function test_givenSeededUnauthorizedIdentities_whenRouteSet_reverts() public {
        address[3] memory callers = [emergency, alice, bob];
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    callers[i]
                )
            );
            vm.prank(callers[i]);
            distributor.setAssetRoutes(address(token), 0, routes);
        }
        assertEq(
            distributor.getActiveAssetCount(),
            0,
            "seeded unauthorized callers activate no asset"
        );
    }

    // when unauthorized caller configures route
    //   [X] it reverts with the expected error
    //   [X] unauthorized caller leaves no active asset
    // Scenarios: SAR-A03.
    function test_whenUnauthorizedCallerConfiguresRoute_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        distributor.setAssetRoutes(address(token), 0, routes);
        assertEq(
            distributor.getActiveAssetCount(),
            0,
            "unauthorized caller leaves no active asset"
        );
    }

    // given admin
    //   [X] admin activates asset route
    // Scenarios: SAR-A01.
    function test_givenAdmin(address authority_, bool operatorOnly_, bool overlap_) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "admin activates asset route"
        );
    }

    // when zero asset configured
    //   [X] it reverts with the expected error
    //   [X] invalid asset is not activated
    // Scenarios: SAR-I01.
    function test_whenZeroAssetConfigured_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
                address(0)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(0), 0, routes);
        assertEq(distributor.getActiveAssetCount(), 0, "invalid asset is not activated");
    }

    // when eoaasset configured
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I01.
    function test_whenEOAAssetConfigured_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
                alice
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(alice, 0, routes);
    }

    // given disabled
    //   [X] it reverts with the expected error
    // Scenarios: SAR-L01.
    function test_givenDisabled_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        _disableDistributor();
        _expectNotEnabled();
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // Scenarios: SAR-L01.
    function test_givenDisabled_whenPermittedCallerSetsAnyRoute_reverts(
        bool adminCalls_,
        address asset_,
        uint16 repurchaseBps_
    ) public {
        IRevenueDistributor.AssetRoute[] memory initial = new IRevenueDistributor.AssetRoute[](1);
        initial[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, initial);
        bytes32 hashBefore = distributor.assetDistributionHash(address(token));
        _disableDistributor();
        IRevenueDistributor.AssetRoute[] memory proposed = new IRevenueDistributor.AssetRoute[](1);
        proposed[0] = IRevenueDistributor.AssetRoute({recipient: address(0), bps: 0});

        vm.recordLogs();
        _expectNotEnabled();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setAssetRoutes(asset_, repurchaseBps_, proposed);

        assertEq(
            distributor.assetDistributionHash(address(token)),
            hashBefore,
            "disabled call preserves route"
        );
        assertEq(distributor.getActiveAssetCount(), 1, "disabled call preserves membership");
        assertEq(vm.getRecordedLogs().length, 0, "disabled call emits no event");
    }

    // given re enabled
    //   [X] re-enabled distributor activates asset route
    function test_givenReEnabled() public {
        vm.startPrank(admin);
        distributor.disable("");
        distributor.reEnable();
        vm.stopPrank();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "re-enabled distributor activates asset route"
        );
    }

    // given policy inactive
    //   [X] it reverts with the expected error
    // Scenarios: SAR-L02.
    function test_givenPolicyInactive_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        _setPolicyActive(address(distributor), false);
        _expectPolicyInactive();
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // Scenarios: SAR-L02.
    function test_givenPolicyInactive_whenPermittedCallerSetsAnyRoute_reverts(
        bool adminCalls_,
        address asset_,
        uint16 repurchaseBps_
    ) public {
        IRevenueDistributor.AssetRoute[] memory initial = new IRevenueDistributor.AssetRoute[](1);
        initial[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, initial);
        bytes32 hashBefore = distributor.assetDistributionHash(address(token));
        _setPolicyActive(address(distributor), false);
        IRevenueDistributor.AssetRoute[] memory proposed = new IRevenueDistributor.AssetRoute[](1);
        proposed[0] = IRevenueDistributor.AssetRoute({recipient: address(0), bps: 0});

        vm.recordLogs();
        _expectPolicyInactive();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setAssetRoutes(asset_, repurchaseBps_, proposed);

        assertEq(
            distributor.assetDistributionHash(address(token)),
            hashBefore,
            "inactive call preserves route"
        );
        assertEq(distributor.getActiveAssetCount(), 1, "inactive call preserves membership");
        assertEq(vm.getRecordedLogs().length, 0, "inactive call emits no event");
    }

    // Scenarios: SAR-L03.
    function test_givenPolicyInactiveAndDisabled_whenRouteSet_revertsActivityFirst() public {
        vm.startPrank(admin);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();

        _expectPolicyInactive();
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(
            address(0),
            type(uint16).max,
            new IRevenueDistributor.AssetRoute[](0)
        );
    }

    // given policy reactivated
    //   [X] reactivated policy activates asset route
    function test_givenPolicyReactivated() public {
        vm.startPrank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        vm.stopPrank();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "reactivated policy activates asset route"
        );
    }

    // [X] route activates one asset
    // [X] indexed active asset matches
    // [X] active enumeration has one asset
    // [X] active enumeration contains token
    // [X] asset state is active
    // [X] route hash reflects stored route
    // Scenarios: SAR-A01, SAR-P02.
    function test_updatesActiveSetAndHash(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 10_000});
        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionSet(address(token), 0, routes);
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
        assertEq(distributor.getActiveAssetCount(), 1, "route activates one asset");
        assertEq(distributor.getActiveAssetAt(0), address(token), "indexed active asset matches");
        address[] memory active = distributor.getActiveAssets();
        assertEq(active.length, 1, "active enumeration has one asset");
        assertEq(active[0], address(token), "active enumeration contains token");
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "asset state is active"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            keccak256(
                abi.encode(IRevenueDistributor.AssetState.Active, uint16(0), routes, address(0))
            ),
            "route hash reflects stored route"
        );
    }

    // when asset route basis points exceed maximum
    //   [X] it reverts with the expected error
    //   [X] invalid BPS leaves no active asset
    // Scenarios: SAR-I04.
    function test_whenAssetRouteBasisPointsExceedMaximum_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 10_001});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                10_001
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
        assertEq(distributor.getActiveAssetCount(), 0, "invalid BPS leaves no active asset");
    }

    // when recipient basis points are zero
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I03.
    function test_whenRecipientBasisPointsAreZero_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 0});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_ZeroRecipientBasisPoints.selector,
                alice
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // when maximum uint16 basis points configured
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I13.
    function test_whenMaximumUint16BasisPointsConfigured_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: type(uint16).max});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                uint256(type(uint16).max)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // when zero recipient configured
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I02.
    function test_whenZeroRecipientConfigured_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(0), bps: 1});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(0)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // when treasury recipient configured
    //   [X] it reverts with the expected error
    function test_whenTreasuryRecipientConfigured_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(treasury), bps: 1});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(treasury)
            )
        );
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // given revenue distributor admin
    //   when calling distributor directly
    //     [X] it reverts with the expected error
    // Scenarios: SAR-A03.
    function test_givenRevenueDistributorAdmin_whenCallingDistributorDirectly_reverts() public {
        vm.prank(admin);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, alice);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                alice
            )
        );
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // given five recipients
    //   [X] recipient gets ten percent
    //   [X] Treasury gets the residual
    // Scenarios: SAR-P02.
    function test_givenFiveRecipients_distributesEachShare() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](5);
        for (uint256 i; i < routes.length; ++i) {
            routes[i] = IRevenueDistributor.AssetRoute({
                // i is below five, so i + 100 fits in uint160.
                // forge-lint: disable-next-line(unsafe-typecast)
                recipient: address(uint160(i + 100)),
                bps: 1_000
            });
        }
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
        token.mint(address(distributor), 100);
        distributor.distribute(address(token));
        for (uint256 i; i < routes.length; ++i) {
            assertEq(token.balanceOf(routes[i].recipient), 10, "recipient gets ten percent");
        }
        assertEq(token.balanceOf(address(treasury)), 50, "Treasury gets the residual");
    }

    // given duplicate configured recipients
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I06.
    function test_givenDuplicateConfiguredRecipients_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1_000});
        routes[1] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1_000});

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                alice
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // given yield recipient vault disabled
    //   when repurchase route set
    //     [X] it reverts with the expected error
    //     [X] disabled vault token is not listed
    // Scenarios: SAR-I17.
    function test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), false);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(token)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 1, routes);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "disabled vault token is not listed"
        );
    }

    // given yield recipient underlying supported
    //   when repurchase route set
    //     [X] enabled underlying route is active
    // Scenarios: SAR-P05.
    function test_givenYieldRecipientUnderlyingSupported_whenRepurchaseRouteSet() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(makeAddr("yield vault"), address(token), true);
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 1_000, routes);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "enabled underlying route is active"
        );
    }

    // given yield recipient underlying disabled
    //   when repurchase route set
    //     [X] it reverts with the expected error
    //     [X] disabled underlying remains unlisted
    // Scenarios: SAR-I17.
    function test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(makeAddr("yield vault"), address(token), false);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(token)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 1_000, routes);
        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "disabled underlying remains unlisted"
        );
    }

    // given self recipient
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I02.
    function test_givenSelfRecipient_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(distributor), bps: 1});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(distributor)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // given kernel recipient
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I02.
    function test_givenKernelRecipient_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(kernel), bps: 1});
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(kernel)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // given configured payout pending
    //   when route changes
    //     [X] old configured share awaits an explicit retry
    //     [X] new receipt follows new route
    //     [X] Treasury receives both residuals
    //     [X] old share remains owed
    //     [X] explicit retry pays original recipient
    //     [X] old share pays once
    // Scenarios: SAR-P03.
    function test_givenConfiguredPayoutPending_whenRouteChanges_thenOldRecipientKeepsAllocation()
        public
        givenAliceConfiguredAsRecipient
    {
        token.mint(address(distributor), 100);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, alice),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();

        IRevenueDistributor.AssetRoute[] memory next = new IRevenueDistributor.AssetRoute[](1);
        next[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 5_000});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, next);
        token.mint(address(distributor), 100);
        distributor.distribute(address(token));

        assertEq(token.balanceOf(alice), 0, "old configured share awaits an explicit retry");
        assertEq(token.balanceOf(bob), 50, "new receipt follows new route");
        assertEq(token.balanceOf(address(treasury)), 117, "Treasury receives both residuals");
        assertEq(distributor.pendingPayout(address(token), alice), 33, "old share remains owed");
        distributor.transferPendingPayout(address(token), alice);
        assertEq(token.balanceOf(alice), 33, "explicit retry pays original recipient");
        assertEq(distributor.pendingPayout(address(token), alice), 0, "old share pays once");
    }

    // when repurchase basis points exceed maximum
    //   [X] it reverts with the expected error
    //   [X] invalid sum does not list the asset
    // Scenarios: SAR-I14.
    function test_whenRepurchaseBasisPointsExceedMaximum_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(authority_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                10_001
            )
        );
        distributor.setAssetRoutes(address(token), 10_001, routes);
        assertEq(distributor.getActiveAssetCount(), 0, "invalid sum does not list the asset");
    }

    // when repurchase and route basis points exceed maximum
    //   [X] it reverts with the expected error
    //   [X] invalid sum does not list the asset
    // Scenarios: SAR-I15.
    function test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 5_001});
        vm.prank(authority_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                10_001
            )
        );
        distributor.setAssetRoutes(address(token), 5_000, routes);
        assertEq(distributor.getActiveAssetCount(), 0, "invalid sum does not list the asset");
    }

    // when named recipient is treasury
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsTreasury_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1_000});
        routes[1] = IRevenueDistributor.AssetRoute({recipient: address(treasury), bps: 1_000});
        vm.prank(authority_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(treasury)
            )
        );
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // when named recipient is yield recipient
    //   [X] it reverts with the expected error
    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsYieldRecipient_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1_000});
        routes[1] = IRevenueDistributor.AssetRoute({recipient: address(recipient), bps: 1_000});
        vm.prank(authority_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                address(recipient)
            )
        );
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // Scenarios: SAR-A01, SAR-P01.
    function test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionSet(address(token), 0, routes);
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);

        (uint16 repurchaseBps, IRevenueDistributor.AssetRoute[] memory stored) = distributor
            .getAssetDistribution(address(token));
        assertEq(repurchaseBps, 0, "Treasury-only route has zero repurchase BPS");
        assertEq(stored.length, 0, "Treasury-only route has no configured recipients");
        assertEq(distributor.getActiveAssetCount(), 1, "asset is listed once");
        assertEq(distributor.getActiveAssetAt(0), address(token), "listed asset is enumerable");
        assertEq(
            distributor.assetDistributionHash(address(token)),
            keccak256(
                abi.encode(IRevenueDistributor.AssetState.Active, uint16(0), routes, address(0))
            ),
            "route hash matches independent encoding"
        );
    }

    // Scenarios: SAR-P04.
    function test_givenRetiredAssetWithPendingDebt_whenRouteSet_reactivatesAndPreservesDebt()
        public
    {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.startPrank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 10, 20, 30);
        token.mint(address(distributor), 60);

        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "retired asset becomes active"
        );
        assertEq(distributor.getActiveAssetCount(), 1, "reactivated asset appears once");
        _assertPendingPayouts(address(token), alice, 10, 20, 30);
        assertEq(token.balanceOf(address(distributor)), 60, "reactivation preserves custody");
    }

    // Scenarios: SAR-I05.
    function test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(0),
                address(token)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 1, routes);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "failed repurchase route leaves asset unlisted"
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        recipient.setEnabled(false);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(recipient)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 1, routes);
    }

    // Scenarios: SAR-I16.
    function test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal(
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute(alice, type(uint16).max);
        routes[1] = IRevenueDistributor.AssetRoute(bob, type(uint16).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                uint256(type(uint16).max) * 2
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);
    }

    // Scenarios: SAR-V01.
    function test_givenActiveAssets_whenIndexOutsideSet_reverts() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(admin);
        distributor.setAssetRoutes(address(token), 0, routes);

        vm.expectRevert(stdError.indexOOBError);
        distributor.getActiveAssetAt(1);
        vm.expectRevert(stdError.indexOOBError);
        distributor.getActiveAssetAt(type(uint256).max);
    }

    // Scenarios: SAR-A01, SAR-P02.
    function test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute(
        uint8 length_,
        uint16 totalBps_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        totalBps_ = uint16(bound(totalBps_, 1, 10_000));
        uint256 maxLength = totalBps_ < 8 ? totalBps_ : 8;
        length_ = uint8(bound(length_, 1, maxLength));
        _assertRecipientSetStored(length_, totalBps_);
    }

    // Scenarios: SAR-P02.
    function test_givenNeverListedAsset_whenBoundaryRecipientSetsConfigured_storesExactRoutes()
        public
    {
        _assertRecipientSetStored(1, 1);
        _assertRecipientSetStored(2, 9_999);
        _assertRecipientSetStored(5, 10_000);
        _assertRecipientSetStored(8, 10_000);
    }

    // Scenarios: SAR-A01, SAR-P03.
    function test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt(
        uint8 pendingMask_,
        uint16 repurchaseBps_,
        bool emptyRoute_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        pendingMask_ = uint8(bound(pendingMask_, 0, 7));
        repurchaseBps_ = uint16(bound(repurchaseBps_, 0, 10_000));
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient(address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory initial = new IRevenueDistributor.AssetRoute[](1);
        initial[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, initial);
        uint256 routeAmount = pendingMask_ & 1 == 0 ? 0 : 11;
        uint256 yieldAmount = pendingMask_ & 2 == 0 ? 0 : 22;
        uint256 treasuryAmount = pendingMask_ & 4 == 0 ? 0 : 33;
        distributor.seedPendingForTest(
            address(token),
            alice,
            routeAmount,
            yieldAmount,
            treasuryAmount
        );
        token.mint(address(distributor), routeAmount + yieldAmount + treasuryAmount);
        IRevenueDistributor.AssetRoute[] memory next = new IRevenueDistributor.AssetRoute[](
            emptyRoute_ ? 0 : 1
        );
        if (!emptyRoute_) {
            uint16 configuredBps = uint16(10_000 - repurchaseBps_);
            if (configuredBps == 0) {
                next = new IRevenueDistributor.AssetRoute[](0);
            } else {
                next[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: configuredBps});
            }
        }

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionSet(address(token), repurchaseBps_, next);
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), repurchaseBps_, next);

        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "replacement does not duplicate active membership"
        );
        _assertStoredRoute(address(token), repurchaseBps_, next);
        _assertPendingPayouts(address(token), alice, routeAmount, yieldAmount, treasuryAmount);
        assertEq(
            token.balanceOf(address(distributor)),
            routeAmount + yieldAmount + treasuryAmount,
            "replacement preserves custody"
        );
    }

    // Scenarios: SAR-P03.
    function test_givenActiveAsset_whenSameRouteSet_rewritesWithoutDuplicateMembership() public {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.startPrank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.setAssetRoutes(address(token), 0, routes);
        vm.stopPrank();

        assertEq(distributor.getActiveAssetCount(), 1, "same route keeps one active membership");
        _assertStoredRoute(address(token), 0, routes);
    }

    // Scenarios: SAR-P04.
    function test_givenRetiredAssetWithAnyPendingBuckets_whenNonemptyRouteSet_reactivatesAndPreservesDebt(
        uint8 pendingMask_,
        uint16 repurchaseBps_
    ) public {
        pendingMask_ = uint8(bound(pendingMask_, 0, 7));
        repurchaseBps_ = uint16(bound(repurchaseBps_, 0, 9_999));
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient(address(token), true);
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory empty = new IRevenueDistributor.AssetRoute[](0);
        vm.startPrank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, empty);
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();
        uint256 routeAmount = pendingMask_ & 1 == 0 ? 0 : 11;
        uint256 yieldAmount = pendingMask_ & 2 == 0 ? 0 : 22;
        uint256 treasuryAmount = pendingMask_ & 4 == 0 ? 0 : 33;
        distributor.seedPendingForTest(
            address(token),
            alice,
            routeAmount,
            yieldAmount,
            treasuryAmount
        );
        token.mint(address(distributor), routeAmount + yieldAmount + treasuryAmount);
        IRevenueDistributor.AssetRoute[] memory next = new IRevenueDistributor.AssetRoute[](1);
        next[0] = IRevenueDistributor.AssetRoute({
            recipient: bob,
            bps: uint16(10_000 - repurchaseBps_)
        });

        vm.prank(admin);
        distributor.setAssetRoutes(address(token), repurchaseBps_, next);

        assertEq(distributor.getActiveAssetCount(), 1, "reactivation adds one active membership");
        _assertStoredRoute(address(token), repurchaseBps_, next);
        _assertPendingPayouts(address(token), alice, routeAmount, yieldAmount, treasuryAmount);
        assertEq(
            token.balanceOf(address(distributor)),
            routeAmount + yieldAmount + treasuryAmount,
            "reactivation preserves custody"
        );
    }

    // Scenarios: SAR-P05.
    function test_givenCompatibleYieldRecipient_whenPositiveRepurchaseRouteSet_succeeds(
        uint8 assetState_,
        bool directVault_,
        uint16 repurchaseBps_
    ) public {
        assetState_ = uint8(bound(assetState_, 0, 2));
        repurchaseBps_ = uint16(bound(repurchaseBps_, 1, 10_000));
        IRevenueDistributor.AssetRoute[] memory empty = new IRevenueDistributor.AssetRoute[](0);
        if (assetState_ != 0) {
            vm.prank(_configurationCaller());
            distributor.setAssetRoutes(address(token), 0, empty);
            if (assetState_ == 2) {
                vm.prank(_configurationCaller());
                distributor.disableAssetRoutes(address(token));
            }
        }
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient(address(token), directVault_);
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionSet(address(token), repurchaseBps_, empty);
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), repurchaseBps_, empty);

        _assertStoredRoute(address(token), repurchaseBps_, empty);
        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "positive repurchase route has one active membership"
        );
    }

    // Scenarios: SAR-V01.
    function test_givenEmptyOrMultipleAssets_whenGettersReadAcrossLifecycle_preservesState(
        address caller_,
        bool populate_,
        bool retireOne_,
        bool disable_,
        bool deactivate_
    ) public {
        MockERC20 second = new MockERC20("Second", "REV2", 18);
        MockERC20 third = new MockERC20("Third", "REV3", 18);
        IRevenueDistributor.AssetRoute[] memory empty = new IRevenueDistributor.AssetRoute[](0);
        if (populate_) {
            vm.startPrank(_configurationCaller());
            distributor.setAssetRoutes(address(token), 0, empty);
            distributor.setAssetRoutes(address(second), 0, empty);
            distributor.setAssetRoutes(address(third), 0, empty);
            if (retireOne_) distributor.disableAssetRoutes(address(second));
            vm.stopPrank();
        }
        if (disable_) {
            _disableDistributor();
        }
        if (deactivate_) {
            _setPolicyActive(address(distributor), false);
        }
        uint256 expectedCount = populate_ ? (retireOne_ ? 2 : 3) : 0;
        bytes32 tokenHash = distributor.assetDistributionHash(address(token));

        vm.startPrank(caller_);
        assertEq(
            distributor.getActiveAssetCount(),
            expectedCount,
            "getter returns expected active count"
        );
        address[] memory active = distributor.getActiveAssets();
        assertEq(active.length, expectedCount, "enumeration length matches count");
        for (uint256 i; i < active.length; ++i) {
            assertEq(
                distributor.getActiveAssetAt(i),
                active[i],
                "indexed getter matches enumeration"
            );
        }
        vm.expectRevert(stdError.indexOOBError);
        distributor.getActiveAssetAt(expectedCount);
        vm.expectRevert(stdError.indexOOBError);
        distributor.getActiveAssetAt(expectedCount + 1);
        vm.expectRevert(stdError.indexOOBError);
        distributor.getActiveAssetAt(type(uint256).max);
        vm.stopPrank();

        assertEq(distributor.getActiveAssetCount(), expectedCount, "reads preserve active count");
        assertEq(
            distributor.assetDistributionHash(address(token)),
            tokenHash,
            "reads preserve route hash"
        );
    }

    // Scenarios: SAR-I01.
    function test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState(
        bool zeroAsset_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        bytes32 hashBefore = _seedRouteAndDebt();
        address invalidAsset = zeroAsset_ ? address(0) : makeAddr("invalid asset EOA");
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 5_000});

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidAsset.selector,
                invalidAsset
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(invalidAsset, 0, routes);

        _assertSeededStateUnchanged(hashBefore);
        assertEq(
            uint8(distributor.assetState(invalidAsset)),
            uint8(IRevenueDistributor.AssetState.NeverListed),
            "invalid asset remains unlisted"
        );
    }

    // Scenarios: SAR-I02.
    function test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack(
        uint8 recipientKind_,
        bool invalidIsLater_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        recipientKind_ = uint8(bound(recipientKind_, 0, 4));
        MockYieldRepurchaseRecipient yieldRecipient = _newYieldRecipient(address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(yieldRecipient));
        bytes32 hashBefore = _seedRouteAndDebt();
        address[5] memory forbidden = [
            address(0),
            address(distributor),
            address(kernel),
            address(treasury),
            address(yieldRecipient)
        ];
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[invalidIsLater_ ? 0 : 1] = IRevenueDistributor.AssetRoute({
            recipient: bob,
            bps: 1_000
        });
        routes[invalidIsLater_ ? 1 : 0] = IRevenueDistributor.AssetRoute({
            recipient: forbidden[recipientKind_],
            bps: 1_000
        });

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidRecipient.selector,
                forbidden[recipientKind_]
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);

        _assertSeededStateUnchanged(hashBefore);
    }

    // Scenarios: SAR-I03.
    function test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack(
        bool zeroIsLater_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        bytes32 hashBefore = _seedRouteAndDebt();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[zeroIsLater_ ? 0 : 1] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 1_000});
        address zeroRecipient = zeroIsLater_ ? alice : bob;
        routes[zeroIsLater_ ? 1 : 0] = IRevenueDistributor.AssetRoute({
            recipient: zeroRecipient,
            bps: 0
        });

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_ZeroRecipientBasisPoints.selector,
                zeroRecipient
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);

        _assertSeededStateUnchanged(hashBefore);
    }

    // Scenarios: SAR-I06.
    function test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack(
        bool nonAdjacent_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        bytes32 hashBefore = _seedRouteAndDebt();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](3);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1_000});
        routes[1] = IRevenueDistributor.AssetRoute({
            recipient: nonAdjacent_ ? bob : alice,
            bps: 1_000
        });
        routes[2] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 1_000});

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                alice
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 0, routes);

        _assertSeededStateUnchanged(hashBefore);
    }

    // Scenarios: SAR-I04, SAR-I13, SAR-I14, SAR-I15.
    function test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack(
        uint8 invalidKind_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        invalidKind_ = uint8(bound(invalidKind_, 0, 3));
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient(address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        bytes32 hashBefore = _seedRouteAndDebt();
        uint16 repurchaseBps;
        uint256 expectedTotal;
        IRevenueDistributor.AssetRoute[] memory routes;
        if (invalidKind_ == 0) {
            routes = new IRevenueDistributor.AssetRoute[](1);
            routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 10_001});
            expectedTotal = 10_001;
        } else if (invalidKind_ == 1) {
            routes = new IRevenueDistributor.AssetRoute[](1);
            routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: type(uint16).max});
            expectedTotal = type(uint16).max;
        } else if (invalidKind_ == 2) {
            routes = new IRevenueDistributor.AssetRoute[](0);
            repurchaseBps = 10_001;
            expectedTotal = 10_001;
        } else {
            routes = new IRevenueDistributor.AssetRoute[](1);
            routes[0] = IRevenueDistributor.AssetRoute({recipient: bob, bps: 5_001});
            repurchaseBps = 5_000;
            expectedTotal = 10_001;
        }

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidBasisPoints.selector,
                expectedTotal
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), repurchaseBps, routes);

        _assertSeededStateUnchanged(hashBefore);
    }

    // Scenarios: SAR-I17.
    function test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack(
        uint8 failureKind_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        failureKind_ = uint8(bound(failureKind_, 0, 3));
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        if (failureKind_ == 1) recipient.setVaultConfig(address(token), address(token), false);
        if (failureKind_ == 2)
            recipient.setVaultConfig(makeAddr("disabled vault"), address(token), false);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        bytes32 hashBefore = _seedRouteAndDebt();
        if (failureKind_ == 3) recipient.setRevertGetVaultConfig(true);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(token)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 1, routes);

        _assertSeededStateUnchanged(hashBefore);
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs(
        bool kernelInactive_,
        address authority_,
        bool operatorOnly_,
        bool overlap_
    ) public {
        _grantConfigurationAuthority(authority_, operatorOnly_, overlap_);
        _configurationSeed = authority_;
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient(address(token), true);
        vm.prank(authority_);
        distributor.setYieldRecipient(address(recipient));
        bytes32 hashBefore = _seedRouteAndDebt();
        if (kernelInactive_) {
            _setPolicyActive(address(recipient), false);
        } else {
            recipient.setEnabled(false);
        }
        IRevenueDistributor.AssetRoute[]
            memory invalidRoutes = new IRevenueDistributor.AssetRoute[](1);
        invalidRoutes[0] = IRevenueDistributor.AssetRoute({recipient: address(0), bps: 0});

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(recipient)
            )
        );
        vm.prank(authority_);
        distributor.setAssetRoutes(address(token), 1, invalidRoutes);

        _assertSeededStateUnchanged(hashBefore);
    }

    function _assertRecipientSetStored(uint256 length_, uint16 totalBps_) internal {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
            length_
        );
        uint16 firstBps = uint16(uint256(totalBps_) - length_ + 1);
        for (uint256 i; i < length_; ++i) {
            routes[i] = IRevenueDistributor.AssetRoute({
                recipient: address(uint160(100 + i)),
                bps: i == 0 ? firstBps : 1
            });
        }

        vm.expectEmit(true, false, false, true, address(distributor));
        emit IRevenueDistributor.AssetDistributionSet(address(token), 0, routes);
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);

        _assertStoredRoute(address(token), 0, routes);
        assertEq(
            distributor.getActiveAssetCount(),
            1,
            "configured asset has one active membership"
        );
    }

    function _assertStoredRoute(
        address asset_,
        uint16 expectedRepurchaseBps_,
        IRevenueDistributor.AssetRoute[] memory expectedRoutes_
    ) internal view {
        (
            uint16 storedRepurchaseBps,
            IRevenueDistributor.AssetRoute[] memory storedRoutes
        ) = distributor.getAssetDistribution(asset_);
        assertEq(
            storedRepurchaseBps,
            expectedRepurchaseBps_,
            "stored repurchase BPS matches input"
        );
        assertEq(storedRoutes.length, expectedRoutes_.length, "stored route length matches input");
        for (uint256 i; i < storedRoutes.length; ++i) {
            assertEq(
                storedRoutes[i].recipient,
                expectedRoutes_[i].recipient,
                "stored recipient matches input order"
            );
            assertEq(
                storedRoutes[i].bps,
                expectedRoutes_[i].bps,
                "stored recipient BPS matches input"
            );
        }
        assertEq(
            distributor.assetDistributionHash(asset_),
            keccak256(
                abi.encode(
                    IRevenueDistributor.AssetState.Active,
                    expectedRepurchaseBps_,
                    expectedRoutes_,
                    distributor.yieldRecipient()
                )
            ),
            "route hash matches independent encoding"
        );
    }

    function _newYieldRecipient(
        address asset_,
        bool directVault_
    ) internal returns (MockYieldRepurchaseRecipient recipient) {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        address vault = directVault_ ? asset_ : makeAddr("yield vault");
        recipient.setVaultConfig(vault, asset_, true);
        _setPolicyActive(address(recipient), true);
    }

    function _seedRouteAndDebt() internal returns (bytes32 routeHash) {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 2_500});
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 0, routes);
        distributor.seedPendingForTest(address(token), bob, 11, 22, 33);
        token.mint(address(distributor), 66);
        routeHash = distributor.assetDistributionHash(address(token));
    }

    function _assertSeededStateUnchanged(bytes32 routeHash_) internal view {
        assertEq(
            distributor.assetDistributionHash(address(token)),
            routeHash_,
            "failed update preserves route hash"
        );
        assertEq(distributor.getActiveAssetCount(), 1, "failed update preserves active membership");
        _assertPendingPayouts(address(token), bob, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "failed update preserves custody");
        assertEq(vm.getRecordedLogs().length, 0, "failed update emits no event");
    }

    // Scenarios: SAR-A01.
    function test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_AdminOnlySeed()
        public
    {
        test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt(
            1,
            1,
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-A01.
    function test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_OperatorOnlySeed()
        public
    {
        test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt(
            1,
            1,
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-A01.
    function test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt_RolesOverlapSeed()
        public
    {
        test_givenActiveAssetWithAnyPendingBuckets_whenRouteChanges_preservesDebt(
            1,
            1,
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-A01.
    function test_givenAdmin_AdminOnlySeed() public {
        test_givenAdmin(address(0x1234), false, false);
    }

    // Scenarios: SAR-A01.
    function test_givenAdmin_OperatorOnlySeed() public {
        test_givenAdmin(address(0x1234), true, false);
    }

    // Scenarios: SAR-A01.
    function test_givenAdmin_RolesOverlapSeed() public {
        test_givenAdmin(address(0x1234), true, true);
    }

    // Scenarios: SAR-I06.
    function test_givenDuplicateConfiguredRecipients_reverts_AdminOnlySeed() public {
        test_givenDuplicateConfiguredRecipients_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I06.
    function test_givenDuplicateConfiguredRecipients_reverts_OperatorOnlySeed() public {
        test_givenDuplicateConfiguredRecipients_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I06.
    function test_givenDuplicateConfiguredRecipients_reverts_RolesOverlapSeed() public {
        test_givenDuplicateConfiguredRecipients_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I01.
    function test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_AdminOnlySeed()
        public
    {
        test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState(
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I01.
    function test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_OperatorOnlySeed()
        public
    {
        test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState(
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I01.
    function test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState_RolesOverlapSeed()
        public
    {
        test_givenExistingConfiguration_whenInvalidAssetSet_revertsAndPreservesState(
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I06.
    function test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_AdminOnlySeed()
        public
    {
        test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack(
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I06.
    function test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_OperatorOnlySeed()
        public
    {
        test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack(
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I06.
    function test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack_RolesOverlapSeed()
        public
    {
        test_givenExistingRoute_whenAdjacentOrNonAdjacentRecipientDuplicates_revertsAndRollsBack(
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I04, SAR-I13, SAR-I14, SAR-I15.
    function test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_AdminOnlySeed()
        public
    {
        test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack(
            1,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I04, SAR-I13, SAR-I14, SAR-I15.
    function test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_OperatorOnlySeed()
        public
    {
        test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack(
            1,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I04, SAR-I13, SAR-I14, SAR-I15.
    function test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack_RolesOverlapSeed()
        public
    {
        test_givenExistingRoute_whenAnyBasisPointTotalIsInvalid_revertsAndRollsBack(
            1,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I02.
    function test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_AdminOnlySeed()
        public
    {
        test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack(
            1,
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I02.
    function test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_OperatorOnlySeed()
        public
    {
        test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack(
            1,
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I02.
    function test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack_RolesOverlapSeed()
        public
    {
        test_givenExistingRoute_whenAnyForbiddenRecipientSet_revertsAndRollsBack(
            1,
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I03.
    function test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_AdminOnlySeed()
        public
    {
        test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack(
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I03.
    function test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_OperatorOnlySeed()
        public
    {
        test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack(
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I03.
    function test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack_RolesOverlapSeed()
        public
    {
        test_givenExistingRoute_whenAnyRecipientBpsIsZero_revertsAndRollsBack(
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I17.
    function test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_AdminOnlySeed()
        public
    {
        test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack(
            1,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I17.
    function test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_OperatorOnlySeed()
        public
    {
        test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack(
            1,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I17.
    function test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack_RolesOverlapSeed()
        public
    {
        test_givenExistingRoute_whenYieldRecipientCannotAcceptAsset_revertsAndRollsBack(
            1,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I02.
    function test_givenKernelRecipient_reverts_AdminOnlySeed() public {
        test_givenKernelRecipient_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I02.
    function test_givenKernelRecipient_reverts_OperatorOnlySeed() public {
        test_givenKernelRecipient_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I02.
    function test_givenKernelRecipient_reverts_RolesOverlapSeed() public {
        test_givenKernelRecipient_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-A01.
    function test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_AdminOnlySeed()
        public
    {
        test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute(
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-A01.
    function test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_OperatorOnlySeed()
        public
    {
        test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute(
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-A01.
    function test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute_RolesOverlapSeed()
        public
    {
        test_givenNeverListedAsset_whenTreasuryOnlyRouteSet_storesExactRoute(
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-A01.
    function test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_AdminOnlySeed()
        public
    {
        test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute(
            1,
            1,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-A01.
    function test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_OperatorOnlySeed()
        public
    {
        test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute(
            1,
            1,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-A01.
    function test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute_RolesOverlapSeed()
        public
    {
        test_givenNeverListedAsset_whenValidRecipientSetConfigured_storesExactRoute(
            1,
            1,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_AdminOnlySeed()
        public
    {
        test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs(
            false,
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_OperatorOnlySeed()
        public
    {
        test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs(
            false,
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs_RolesOverlapSeed()
        public
    {
        test_givenSelectedYieldRecipientBecomesUnavailable_whenPositiveRouteSet_revertsBeforeInputs(
            false,
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_AdminOnlySeed()
        public
    {
        test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts(
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_OperatorOnlySeed()
        public
    {
        test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts(
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I07.
    function test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts_RolesOverlapSeed()
        public
    {
        test_givenSelectedYieldRecipientDisabled_whenPositiveRouteSet_reverts(
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I02.
    function test_givenSelfRecipient_reverts_AdminOnlySeed() public {
        test_givenSelfRecipient_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I02.
    function test_givenSelfRecipient_reverts_OperatorOnlySeed() public {
        test_givenSelfRecipient_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I02.
    function test_givenSelfRecipient_reverts_RolesOverlapSeed() public {
        test_givenSelfRecipient_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I17.
    function test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_AdminOnlySeed()
        public
    {
        test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts(
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I17.
    function test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_OperatorOnlySeed()
        public
    {
        test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts(
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I17.
    function test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts_RolesOverlapSeed()
        public
    {
        test_givenYieldRecipientUnderlyingDisabled_whenRepurchaseRouteSet_reverts(
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I17.
    function test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_AdminOnlySeed()
        public
    {
        test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts(
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I17.
    function test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_OperatorOnlySeed()
        public
    {
        test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts(
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I17.
    function test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts_RolesOverlapSeed()
        public
    {
        test_givenYieldRecipientVaultDisabled_whenRepurchaseRouteSet_reverts(
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-I05.
    function test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_AdminOnlySeed()
        public
    {
        test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts(
            address(0x1234),
            false,
            false
        );
    }

    // Scenarios: SAR-I05.
    function test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_OperatorOnlySeed()
        public
    {
        test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts(
            address(0x1234),
            true,
            false
        );
    }

    // Scenarios: SAR-I05.
    function test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts_RolesOverlapSeed()
        public
    {
        test_givenZeroYieldRecipient_whenPositiveRepurchaseRouteSet_reverts(
            address(0x1234),
            true,
            true
        );
    }

    // Scenarios: SAR-A01.
    function test_updatesActiveSetAndHash_AdminOnlySeed() public {
        test_updatesActiveSetAndHash(address(0x1234), false, false);
    }

    // Scenarios: SAR-A01.
    function test_updatesActiveSetAndHash_OperatorOnlySeed() public {
        test_updatesActiveSetAndHash(address(0x1234), true, false);
    }

    // Scenarios: SAR-A01.
    function test_updatesActiveSetAndHash_RolesOverlapSeed() public {
        test_updatesActiveSetAndHash(address(0x1234), true, true);
    }

    // Scenarios: SAR-I04.
    function test_whenAssetRouteBasisPointsExceedMaximum_reverts_AdminOnlySeed() public {
        test_whenAssetRouteBasisPointsExceedMaximum_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I04.
    function test_whenAssetRouteBasisPointsExceedMaximum_reverts_OperatorOnlySeed() public {
        test_whenAssetRouteBasisPointsExceedMaximum_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I04.
    function test_whenAssetRouteBasisPointsExceedMaximum_reverts_RolesOverlapSeed() public {
        test_whenAssetRouteBasisPointsExceedMaximum_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I01.
    function test_whenEOAAssetConfigured_reverts_AdminOnlySeed() public {
        test_whenEOAAssetConfigured_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I01.
    function test_whenEOAAssetConfigured_reverts_OperatorOnlySeed() public {
        test_whenEOAAssetConfigured_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I01.
    function test_whenEOAAssetConfigured_reverts_RolesOverlapSeed() public {
        test_whenEOAAssetConfigured_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I13.
    function test_whenMaximumUint16BasisPointsConfigured_reverts_AdminOnlySeed() public {
        test_whenMaximumUint16BasisPointsConfigured_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I13.
    function test_whenMaximumUint16BasisPointsConfigured_reverts_OperatorOnlySeed() public {
        test_whenMaximumUint16BasisPointsConfigured_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I13.
    function test_whenMaximumUint16BasisPointsConfigured_reverts_RolesOverlapSeed() public {
        test_whenMaximumUint16BasisPointsConfigured_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsTreasury_reverts_AdminOnlySeed() public {
        test_whenNamedRecipientIsTreasury_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsTreasury_reverts_OperatorOnlySeed() public {
        test_whenNamedRecipientIsTreasury_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsTreasury_reverts_RolesOverlapSeed() public {
        test_whenNamedRecipientIsTreasury_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsYieldRecipient_reverts_AdminOnlySeed() public {
        test_whenNamedRecipientIsYieldRecipient_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsYieldRecipient_reverts_OperatorOnlySeed() public {
        test_whenNamedRecipientIsYieldRecipient_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I02.
    function test_whenNamedRecipientIsYieldRecipient_reverts_RolesOverlapSeed() public {
        test_whenNamedRecipientIsYieldRecipient_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I03.
    function test_whenRecipientBasisPointsAreZero_reverts_AdminOnlySeed() public {
        test_whenRecipientBasisPointsAreZero_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I03.
    function test_whenRecipientBasisPointsAreZero_reverts_OperatorOnlySeed() public {
        test_whenRecipientBasisPointsAreZero_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I03.
    function test_whenRecipientBasisPointsAreZero_reverts_RolesOverlapSeed() public {
        test_whenRecipientBasisPointsAreZero_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I15.
    function test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_AdminOnlySeed() public {
        test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I15.
    function test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_OperatorOnlySeed() public {
        test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I15.
    function test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts_RolesOverlapSeed() public {
        test_whenRepurchaseAndRouteBasisPointsExceedMaximum_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I14.
    function test_whenRepurchaseBasisPointsExceedMaximum_reverts_AdminOnlySeed() public {
        test_whenRepurchaseBasisPointsExceedMaximum_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I14.
    function test_whenRepurchaseBasisPointsExceedMaximum_reverts_OperatorOnlySeed() public {
        test_whenRepurchaseBasisPointsExceedMaximum_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I14.
    function test_whenRepurchaseBasisPointsExceedMaximum_reverts_RolesOverlapSeed() public {
        test_whenRepurchaseBasisPointsExceedMaximum_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I16.
    function test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_AdminOnlySeed() public {
        test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal(address(0x1234), false, false);
    }

    // Scenarios: SAR-I16.
    function test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_OperatorOnlySeed() public {
        test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal(address(0x1234), true, false);
    }

    // Scenarios: SAR-I16.
    function test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal_RolesOverlapSeed() public {
        test_whenTwoMaximumRouteSharesSet_revertsWithWideTotal(address(0x1234), true, true);
    }

    // Scenarios: SAR-I01.
    function test_whenZeroAssetConfigured_reverts_AdminOnlySeed() public {
        test_whenZeroAssetConfigured_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I01.
    function test_whenZeroAssetConfigured_reverts_OperatorOnlySeed() public {
        test_whenZeroAssetConfigured_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I01.
    function test_whenZeroAssetConfigured_reverts_RolesOverlapSeed() public {
        test_whenZeroAssetConfigured_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-I02.
    function test_whenZeroRecipientConfigured_reverts_AdminOnlySeed() public {
        test_whenZeroRecipientConfigured_reverts(address(0x1234), false, false);
    }

    // Scenarios: SAR-I02.
    function test_whenZeroRecipientConfigured_reverts_OperatorOnlySeed() public {
        test_whenZeroRecipientConfigured_reverts(address(0x1234), true, false);
    }

    // Scenarios: SAR-I02.
    function test_whenZeroRecipientConfigured_reverts_RolesOverlapSeed() public {
        test_whenZeroRecipientConfigured_reverts(address(0x1234), true, true);
    }

    // Scenarios: SAR-P06.
    function test_givenERC7575ShareToken_whenRepurchaseRouteSet() public {
        address vault = makeAddr("ERC7575 vault");
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(vault, makeAddr("underlying"), true);
        vm.mockCall(
            address(recipient),
            abi.encodeCall(MockYieldRepurchaseRecipient.getVaultConfig, (vault)),
            abi.encode(vault, address(token), makeAddr("underlying"), true)
        );
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);

        distributor.validateSetAssetRoutes(address(token), 1_000, routes);
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 1_000, routes);

        assertEq(
            uint8(distributor.assetState(address(token))),
            uint8(IRevenueDistributor.AssetState.Active),
            "separate share token route is active"
        );
        _assertStoredRoute(address(token), 1_000, routes);
    }

    // Scenarios: SAR-I18.
    function test_givenVaultIsNotShareToken_whenRepurchaseRouteSet_reverts() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), makeAddr("underlying"), true);
        vm.mockCall(
            address(recipient),
            abi.encodeCall(MockYieldRepurchaseRecipient.getVaultConfig, (address(token))),
            abi.encode(address(token), makeAddr("separate shares"), makeAddr("underlying"), true)
        );
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));
        _assertInvalidVaultConfig(recipient);
    }

    // Scenarios: SAR-I18.
    function test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts(
        uint256 malformed_,
        bool shareTokenWord_
    ) public {
        malformed_ = bound(malformed_, uint256(type(uint160).max) + 1, type(uint256).max);
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), true);
        vm.mockCall(
            address(recipient),
            abi.encodeCall(MockYieldRepurchaseRecipient.getVaultConfig, (address(token))),
            abi.encode(
                address(token),
                shareTokenWord_ ? malformed_ : uint256(uint160(address(token))),
                shareTokenWord_ ? uint256(uint160(address(token))) : malformed_,
                true
            )
        );
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));
        _assertInvalidVaultConfig(recipient);
    }

    // Scenarios: SAR-I18.
    function test_givenFourWordVaultConfig_whenAddressWordsAtMaximum_reverts() public {
        test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts(
            uint256(type(uint160).max) + 1,
            true
        );
        test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts(
            uint256(type(uint160).max) + 1,
            false
        );
        test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts(type(uint256).max, true);
        test_givenFourWordVaultConfig_whenAddressWordMalformed_reverts(type(uint256).max, false);
    }

    // Scenarios: SAR-I18.
    function test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(uint8 length_) public {
        vm.assume(length_ != 128);
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        _setPolicyActive(address(recipient), true);
        recipient.setVaultConfig(address(token), address(token), true);
        bytes memory data = new bytes(256);
        bytes memory canonical = abi.encode(address(token), address(token), address(token), true);
        for (uint256 i; i < canonical.length; ++i) data[i] = canonical[i];
        assembly ("memory-safe") {
            mstore(data, length_)
        }
        vm.mockCall(
            address(recipient),
            abi.encodeCall(MockYieldRepurchaseRecipient.getVaultConfig, (address(token))),
            data
        );
        vm.prank(_configurationCaller());
        distributor.setYieldRecipient(address(recipient));
        _assertInvalidVaultConfig(recipient);
    }

    // Scenarios: SAR-I18.
    function test_givenVaultConfig_whenReturnLengthBoundaries_reverts() public {
        test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(0);
        test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(1);
        test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(96);
        test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(127);
        test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(129);
        test_givenVaultConfig_whenReturnLengthIsNotFourWords_reverts(type(uint8).max);
    }

    function _assertInvalidVaultConfig(MockYieldRepurchaseRecipient recipient_) internal {
        bytes32 beforeHash = distributor.assetDistributionHash(address(token));
        bytes memory reason = abi.encodeWithSelector(
            IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
            address(recipient_),
            address(token)
        );
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.expectRevert(reason);
        distributor.validateSetAssetRoutes(address(token), 1_000, routes);
        vm.expectRevert(reason);
        vm.prank(_configurationCaller());
        distributor.setAssetRoutes(address(token), 1_000, routes);
        assertEq(distributor.assetDistributionHash(address(token)), beforeHash, "route unchanged");
        assertEq(distributor.getActiveAssetCount(), 0, "invalid metadata cannot list an asset");
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast,unused-return)
