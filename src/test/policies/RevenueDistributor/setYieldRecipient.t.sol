// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Contracts
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";
import {ERC20} from "@openzeppelin-5.7.0/token/ERC20/ERC20.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";

// Scenario amounts are token base units. Bounded loops/casts intentionally exercise state matrices.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unsafe-typecast)

contract RevenueDistributorSetYieldRecipientTest is RevenueDistributorTest {
    // given admin
    //   when yield recipient set
    //     [X] admin selects yield recipient
    // Scenarios: SYR-A01, SYR-P09
    function test_givenAdmin_whenYieldRecipientSet() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        vm.prank(admin);
        distributor.setYieldRecipient(address(recipient));
        assertEq(distributor.yieldRecipient(), address(recipient), "admin selects yield recipient");
    }

    // Scenarios: SYR-P04
    function test_givenZeroYieldRecipient_whenSetToZeroAgain_noOps() public {
        bytes32 beforeHash = distributor.assetDistributionHash(address(token));

        vm.recordLogs();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));

        assertEq(distributor.yieldRecipient(), address(0), "yield recipient remains zero");
        assertEq(
            distributor.assetDistributionHash(address(token)),
            beforeHash,
            "same zero recipient preserves route hash"
        );
        assertEq(vm.getRecordedLogs().length, 0, "same zero recipient emits no event");
    }

    // Scenarios: SYR-P03
    function test_givenSelectedCompatibleRecipient_whenSetAgain_noOps() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();
        bytes32 beforeHash = distributor.assetDistributionHash(address(token));

        vm.recordLogs();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));

        assertEq(
            distributor.yieldRecipient(),
            address(recipient),
            "same compatible recipient remains selected"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            beforeHash,
            "same compatible recipient preserves route hash"
        );
        assertEq(vm.getRecordedLogs().length, 0, "same compatible recipient emits no event");
    }

    // Scenarios: SYR-I07
    function test_givenSelectedRecipientBecomesDisabled_whenSetAgain_reverts() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        recipient.setEnabled(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
    }

    // Scenarios: SYR-I05
    function test_whenEOASelectedAsYieldRecipient_reverts(address recipient_) public {
        vm.assume(recipient_.code.length == 0);
        vm.assume(recipient_ != address(0));
        vm.assume(recipient_ != address(treasury));

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                recipient_
            )
        );
        vm.prank(admin);
        distributor.setYieldRecipient(recipient_);
        assertEq(distributor.yieldRecipient(), address(0), "invalid EOA is not selected");
    }

    // given treasury address
    //   when yield recipient set
    //     [X] it reverts with the expected error
    // Scenarios: SYR-I01
    function test_givenTreasuryAddress_whenYieldRecipientSet_reverts() public {
        vm.prank(address(configTimelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(treasury)
            )
        );
        distributor.setYieldRecipient(address(treasury));
    }

    // when unauthorized caller sets yield recipient
    //   [X] it reverts with the expected error
    // Scenarios: SYR-A03
    function test_whenUnauthorizedCallerSetsYieldRecipient_reverts(address caller_) public {
        vm.assume(caller_ != address(configTimelock));
        vm.assume(caller_ != admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        distributor.setYieldRecipient(address(0));
    }

    // given disabled
    //   when operator sets yield recipient
    //     [X] it reverts with the expected error
    // Scenarios: SYR-L01
    function test_givenDisabled_whenOperatorSetsYieldRecipient_reverts() public {
        vm.prank(admin);
        distributor.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));
    }

    // given re enabled
    //   when operator sets yield recipient
    //     [X] re-enabled distributor selects yield recipient
    function test_givenReEnabled_whenOperatorSetsYieldRecipient() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        distributor.disable("");
        distributor.reEnable();
        vm.stopPrank();

        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));

        assertEq(
            distributor.yieldRecipient(),
            address(recipient),
            "re-enabled distributor selects yield recipient"
        );
    }

    // given policy inactive
    //   when operator sets yield recipient
    //     [X] it reverts with the expected error
    // Scenarios: SYR-L02
    function test_givenPolicyInactive_whenOperatorSetsYieldRecipient_reverts() public {
        vm.prank(admin);
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.expectRevert(IRevenueDistributor.RevenueDistributor_PolicyInactive.selector);
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));
    }

    // Scenarios: SYR-L03
    function test_givenPolicyInactiveAndDisabled_whenYieldRecipientSet_revertsNotEnabledFirst()
        public
    {
        vm.startPrank(admin);
        distributor.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        vm.stopPrank();

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));
    }

    // given policy reactivated
    //   when operator sets yield recipient
    //     [X] reactivated policy selects yield recipient
    function test_givenPolicyReactivated_whenOperatorSetsYieldRecipient() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));
        vm.stopPrank();

        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));

        assertEq(
            distributor.yieldRecipient(),
            address(recipient),
            "reactivated policy selects yield recipient"
        );
    }

    // given active repurchase route
    //   when yield recipient cleared
    //     [X] it reverts with the expected error
    //     [X] active repurchase route keeps valid recipient
    // Scenarios: SYR-I02
    function test_givenActiveRepurchaseRoute_whenYieldRecipientCleared_reverts() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        distributor.setAssetRoutes(address(token), 2_000, routes);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(0),
                address(token)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(0));
        assertEq(
            distributor.yieldRecipient(),
            address(recipient),
            "active repurchase route keeps valid recipient"
        );
    }

    // Scenarios: SYR-P07
    function test_givenActiveVaultShareRoute_whenCompatibleYieldRecipientChanges_succeeds() public {
        MockYieldRepurchaseRecipient former = new MockYieldRepurchaseRecipient(kernel);
        MockYieldRepurchaseRecipient current = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(former));
        kernel.executeAction(Actions.ActivatePolicy, address(current));
        vm.stopPrank();
        former.setVaultConfig(address(token), address(token), true);
        current.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(current));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(current));

        assertEq(distributor.yieldRecipient(), address(current), "compatible recipient changes");
    }

    // Scenarios: SYR-I09
    function test_givenActiveVaultShareRoute_whenUnsupportedYieldRecipientSelected_reverts()
        public
    {
        MockYieldRepurchaseRecipient former = new MockYieldRepurchaseRecipient(kernel);
        MockYieldRepurchaseRecipient unsupported = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(former));
        kernel.executeAction(Actions.ActivatePolicy, address(unsupported));
        vm.stopPrank();
        former.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(unsupported),
                address(token)
            )
        );
        vm.prank(admin);
        distributor.setYieldRecipient(address(unsupported));

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "unsupported candidate is rejected"
        );
    }

    // Scenarios: SYR-I06
    function test_whenCandidateLacksRequiredInterface_reverts(
        uint8 missingInterface_,
        bool adminCalls_
    ) public {
        missingInterface_ = uint8(bound(missingInterface_, 0, 2));
        address candidate;
        if (missingInterface_ == 0) {
            candidate = address(token);
        } else {
            MockYieldRepurchaseRecipient recipient = _newYieldRecipient();
            if (missingInterface_ == 1) recipient.setSupportsEnablerInterface(false);
            if (missingInterface_ == 2) recipient.setSupportsYieldRepurchaseInterface(false);
            candidate = address(recipient);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                candidate
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(candidate);

        assertEq(distributor.yieldRecipient(), address(0), "invalid interface is not selected");
    }

    // Scenarios: SYR-I07
    function test_whenCandidatePolicyIsInactiveOrDisabled_reverts(bool inactive_) public {
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        if (inactive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(candidate));
        } else {
            candidate.setEnabled(false);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(candidate)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(candidate));
    }

    // Scenarios: SYR-I10
    function test_givenActiveUnderlyingRoute_whenUnsupportedRecipientSelected_reverts() public {
        address vault = makeAddr("vault");
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient unsupported = _newYieldRecipient();
        former.setVaultConfig(vault, address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(unsupported),
                address(token)
            )
        );
        vm.prank(admin);
        distributor.setYieldRecipient(address(unsupported));
    }

    // Scenarios: SYR-I12
    function test_givenSameRecipientRegistrationDisabled_whenSetAgain_reverts() public {
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient();
        recipient.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();
        recipient.setVaultConfig(address(token), address(token), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(recipient),
                address(token)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
    }

    // Scenarios: SYR-P10
    function test_givenNoPositiveRoutes_whenNonzeroRecipientChanges_succeeds() public {
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient current = _newYieldRecipient();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(former));

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(current));
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(current));

        assertEq(distributor.yieldRecipient(), address(current), "nonzero recipient changes");
    }

    // Scenarios: SYR-P08
    function test_givenActiveUnderlyingRoute_whenCompatibleRecipientChanges_succeeds() public {
        address vault = makeAddr("vault");
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient current = _newYieldRecipient();
        former.setVaultConfig(vault, address(token), true);
        current.setVaultConfig(vault, address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        distributor.setYieldRecipient(address(current));
        vm.stopPrank();

        assertEq(distributor.yieldRecipient(), address(current), "underlying recipient changes");
    }

    // given ordinary recipient
    //   when selected as yield recipient
    //     [X] it reverts with the expected error
    //     [X] duplicate role destination is not selected
    // Scenarios: SYR-I04
    function test_givenOrdinaryRecipient_whenSelectedAsYieldRecipient_reverts() public {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: address(recipient), bps: 1});
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, routes);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                address(recipient)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        assertEq(
            distributor.yieldRecipient(),
            address(0),
            "duplicate role destination is not selected"
        );
    }

    // given yield payout pending
    //   when yield recipient changes
    //     [X] yield share remains pending
    //     [X] former recipient is not owed
    //     [X] current recipient is owed
    //     [X] one current recipient
    //     [X] recipient follows YRF change
    //     [X] former YRF receives nothing
    //     [X] current YRF receives yield share
    //     [X] Treasury received its residual
    // Scenarios: SYR-A02, SYR-P02
    function test_givenYieldPayoutPending_whenYieldRecipientChanges_thenRetryPaysCurrentRecipient()
        public
    {
        MockYieldRepurchaseRecipient former = new MockYieldRepurchaseRecipient(kernel);
        MockYieldRepurchaseRecipient current = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(former));
        kernel.executeAction(Actions.ActivatePolicy, address(current));
        former.setVaultConfig(address(token), address(token), true);
        current.setVaultConfig(address(token), address(token), true);
        vm.stopPrank();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 2_000, routes);
        token.mint(address(distributor), 10);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(former)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();
        assertEq(
            distributor.pendingPayout(address(token), address(former)),
            2,
            "yield share remains pending"
        );

        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(current));
        assertEq(
            distributor.pendingPayout(address(token), address(former)),
            0,
            "former recipient is not owed"
        );
        assertEq(
            distributor.pendingPayout(address(token), address(current)),
            2,
            "current recipient is owed"
        );
        address[] memory currentRecipients = distributor.getPendingPayoutRecipients(address(token));
        assertEq(currentRecipients.length, 1, "one current recipient");
        assertEq(currentRecipients[0], address(current), "recipient follows YRF change");
        distributor.transferPendingPayout(address(token), address(current));

        assertEq(token.balanceOf(address(former)), 0, "former YRF receives nothing");
        assertEq(token.balanceOf(address(current)), 2, "current YRF receives yield share");
        assertEq(token.balanceOf(address(treasury)), 8, "Treasury received its residual");
    }

    // given retired asset with pending yield
    //   when yield recipient cleared
    //     [X] fallback destination remains discoverable
    //     [X] pending yield falls back to Treasury
    //     [X] Treasury is owed yield
    //     [X] Treasury receives the full balance
    //     [X] no payout remains stranded
    // Scenarios: SYR-P01
    function test_givenRetiredAssetWithPendingYield_whenYieldRecipientCleared_thenTreasuryCanRetry()
        public
    {
        MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        distributor.setAssetRoutes(address(token), 2_000, routes);
        vm.stopPrank();
        token.mint(address(distributor), 10);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(recipient)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();
        vm.startPrank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));
        distributor.setYieldRecipient(address(0));
        vm.stopPrank();

        address[] memory pendingRecipients = distributor.getPendingPayoutRecipients(address(token));
        assertEq(pendingRecipients.length, 1, "fallback destination remains discoverable");
        assertEq(pendingRecipients[0], address(treasury), "pending yield falls back to Treasury");
        assertEq(
            distributor.pendingPayout(address(token), address(treasury)),
            2,
            "Treasury is owed yield"
        );
        distributor.transferPendingPayout(address(token), address(treasury));
        assertEq(token.balanceOf(address(treasury)), 10, "Treasury receives the full balance");
        assertEq(distributor.getPendingPayoutAssets().length, 0, "no payout remains stranded");
    }

    // given retired asset with pending yield
    //   when incompatible recipient selected
    //     [X] it reverts with the expected error
    //     [X] old recipient remains selected
    // Scenarios: SYR-I03
    function test_givenRetiredAssetWithPendingYield_whenIncompatibleRecipientSelected_reverts()
        public
    {
        MockYieldRepurchaseRecipient former = new MockYieldRepurchaseRecipient(kernel);
        MockYieldRepurchaseRecipient incompatible = new MockYieldRepurchaseRecipient(kernel);
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(former));
        kernel.executeAction(Actions.ActivatePolicy, address(incompatible));
        vm.stopPrank();
        former.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](0);
        distributor.setAssetRoutes(address(token), 2_000, routes);
        vm.stopPrank();
        token.mint(address(distributor), 10);
        vm.mockCallRevert(
            address(token),
            abi.encodeWithSelector(ERC20.transfer.selector, address(former)),
            abi.encodeWithSignature("Error(string)", "blacklisted")
        );
        distributor.distribute(address(token));
        vm.clearMockedCalls();
        vm.prank(address(configTimelock));
        distributor.disableAssetRoutes(address(token));

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(incompatible),
                address(token)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(incompatible));
        assertEq(distributor.yieldRecipient(), address(former), "old recipient remains selected");
    }

    // Scenarios: SYR-I13
    function test_givenRetiredUnderlyingWithPendingYield_whenUnsupportedRecipientSelected_reverts()
        public
    {
        address vault = makeAddr("vault");
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient unsupported = _newYieldRecipient();
        former.setVaultConfig(vault, address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 2_000, new IRevenueDistributor.AssetRoute[](0));
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 0, 1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(unsupported),
                address(token)
            )
        );
        vm.prank(admin);
        distributor.setYieldRecipient(address(unsupported));
    }

    // Scenarios: SYR-I14
    function test_givenMultipleRetiredPendingAssets_whenLaterAssetUnsupported_reverts() public {
        MockERC20 otherToken = new MockERC20("Other Revenue", "OREV", 18);
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        former.setVaultConfig(address(token), address(token), true);
        former.setVaultConfig(address(otherToken), address(otherToken), true);
        candidate.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.setAssetRoutes(address(otherToken), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.disableAssetRoutes(address(token));
        distributor.disableAssetRoutes(address(otherToken));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 0, 1, 0);
        distributor.seedPendingForTest(address(otherToken), alice, 0, 1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(candidate),
                address(otherToken)
            )
        );
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "later failure keeps old recipient"
        );
    }

    // Scenarios: SYR-I11
    function test_givenUnsupportedActiveAndPendingAssets_whenRecipientChanges_revertsForActiveFirst()
        public
    {
        MockERC20 retiredToken = new MockERC20("Retired Revenue", "RREV", 18);
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        former.setVaultConfig(address(token), address(token), true);
        former.setVaultConfig(address(retiredToken), address(retiredToken), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.setAssetRoutes(
            address(retiredToken),
            1,
            new IRevenueDistributor.AssetRoute[](0)
        );
        distributor.disableAssetRoutes(address(retiredToken));
        vm.stopPrank();
        distributor.seedPendingForTest(address(retiredToken), alice, 0, 1, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(candidate),
                address(token)
            )
        );
        vm.prank(admin);
        distributor.setYieldRecipient(address(candidate));
    }

    // Scenarios: SYR-A03
    function test_givenAnyLifecycleAndCandidate_whenUnauthorizedCallerSetsYieldRecipient_reverts(
        address caller_,
        address candidate_,
        bool disable_,
        bool deactivate_
    ) public {
        vm.assume(caller_ != admin && caller_ != address(configTimelock));
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.seedPendingForTest(address(token), alice, 11, 22, 33);
        token.mint(address(distributor), 66);
        if (disable_) {
            vm.prank(admin);
            distributor.disable("");
        }
        if (deactivate_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        }

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        distributor.setYieldRecipient(candidate_);

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "unauthorized call preserves recipient"
        );
        _assertPendingPayouts(address(token), alice, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "unauthorized call preserves custody");
        assertEq(vm.getRecordedLogs().length, 0, "unauthorized call emits no event");
    }

    // Scenarios: SYR-A03
    function test_givenSeededUnauthorizedIdentities_whenYieldRecipientSet_reverts() public {
        address[3] memory callers = [emergency, alice, bob];
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRevenueDistributor.RevenueDistributor_UnauthorizedConfigOperator.selector,
                    callers[i]
                )
            );
            vm.prank(callers[i]);
            distributor.setYieldRecipient(address(0));
        }
        assertEq(
            distributor.yieldRecipient(),
            address(0),
            "seeded unauthorized callers preserve recipient"
        );
    }

    // Scenarios: SYR-L01, SYR-L02
    function test_givenUnavailableDistributor_whenPermittedCallerSetsAnyYieldRecipient_reverts(
        bool disabled_,
        bool adminCalls_,
        address candidate_
    ) public {
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.seedPendingForTest(address(token), alice, 11, 22, 33);
        token.mint(address(distributor), 66);
        if (disabled_) {
            vm.prank(admin);
            distributor.disable("");
        } else {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(distributor));
        }

        vm.recordLogs();
        vm.expectRevert(
            disabled_
                ? IEnabler.NotEnabled.selector
                : IRevenueDistributor.RevenueDistributor_PolicyInactive.selector
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(candidate_);

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "lifecycle rejection preserves recipient"
        );
        _assertPendingPayouts(address(token), alice, 11, 22, 33);
        assertEq(
            token.balanceOf(address(distributor)),
            66,
            "lifecycle rejection preserves custody"
        );
        assertEq(vm.getRecordedLogs().length, 0, "lifecycle rejection emits no event");
    }

    // Scenarios: SYR-I01, SYR-I05
    function test_givenAnyPointerAndAssetState_whenExcludedAddressSelected_revertsAndRollsBack(
        address eoa_,
        bool treasuryCandidate_,
        bool currentNonzero_,
        bool populated_,
        bool adminCalls_
    ) public {
        vm.assume(eoa_.code.length == 0 && eoa_ != address(0) && eoa_ != address(treasury));
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        if (currentNonzero_) {
            vm.prank(address(configTimelock));
            distributor.setYieldRecipient(address(former));
        }
        if (populated_) {
            vm.prank(address(configTimelock));
            distributor.setAssetRoutes(address(token), 0, new IRevenueDistributor.AssetRoute[](0));
            distributor.seedPendingForTest(address(token), alice, 11, 22, 33);
            token.mint(address(distributor), 66);
        }
        address candidate = treasuryCandidate_ ? address(treasury) : eoa_;
        address beforeRecipient = distributor.yieldRecipient();

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                candidate
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(candidate);

        assertEq(
            distributor.yieldRecipient(),
            beforeRecipient,
            "invalid candidate preserves recipient"
        );
        if (populated_) _assertPendingPayouts(address(token), alice, 11, 22, 33);
        assertEq(vm.getRecordedLogs().length, 0, "invalid candidate emits no event");
    }

    // Scenarios: SYR-I07
    function test_givenInactiveOrDisabledCandidate_whenSetAsSameOrDifferentPointer_revertsAndRollsBack(
        bool samePointer_,
        bool inactive_,
        bool adminCalls_
    ) public {
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = samePointer_ ? former : _newYieldRecipient();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.seedPendingForTest(address(token), alice, 11, 22, 33);
        if (inactive_) {
            vm.prank(admin);
            kernel.executeAction(Actions.DeactivatePolicy, address(candidate));
        } else {
            candidate.setEnabled(false);
        }

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_InvalidYieldRecipient.selector,
                address(candidate)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "invalid policy state preserves recipient"
        );
        _assertPendingPayouts(address(token), alice, 11, 22, 33);
        assertEq(vm.getRecordedLogs().length, 0, "invalid policy state emits no event");
    }

    // Scenarios: SYR-I02
    function test_givenLaterActiveRepurchaseRoute_whenYieldRecipientCleared_revertsAndRollsBack(
        bool adminCalls_
    ) public {
        MockERC20 earlier = new MockERC20("Earlier Revenue", "EREV", 18);
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        former.setVaultConfig(address(earlier), address(earlier), true);
        former.setVaultConfig(address(token), address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(earlier), 0, new IRevenueDistributor.AssetRoute[](0));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();
        distributor.seedPendingForTest(address(earlier), alice, 1, 2, 3);
        bytes32 earlierHash = distributor.assetDistributionHash(address(earlier));
        bytes32 tokenHash = distributor.assetDistributionHash(address(token));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(0),
                address(token)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(0));

        assertEq(distributor.yieldRecipient(), address(former), "failed clear preserves recipient");
        assertEq(
            distributor.assetDistributionHash(address(earlier)),
            earlierHash,
            "failed clear preserves first hash"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            tokenHash,
            "failed clear preserves later hash"
        );
        _assertPendingPayouts(address(earlier), alice, 1, 2, 3);
        assertEq(vm.getRecordedLogs().length, 0, "failed clear emits no event");
    }

    // Scenarios: SYR-I09, SYR-I10, SYR-I12
    function test_givenActiveRepurchaseRoute_whenCandidateRegistrationInvalid_revertsAndRollsBack(
        bool directVault_,
        bool samePointer_,
        uint8 failureKind_,
        bool adminCalls_
    ) public {
        failureKind_ = uint8(bound(failureKind_, 0, 3));
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = samePointer_ ? former : _newYieldRecipient();
        address vault = directVault_ ? address(token) : makeAddr("active underlying vault");
        former.setVaultConfig(vault, address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 11, 22, 33);
        if (samePointer_) {
            _invalidateExistingRegistration(former, vault, address(token), failureKind_);
        } else {
            _setRegistrationFailure(candidate, address(token), directVault_, failureKind_);
        }
        bytes32 hashBefore = distributor.assetDistributionHash(address(token));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(candidate),
                address(token)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "unsupported active asset preserves recipient"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            hashBefore,
            "unsupported asset preserves hash"
        );
        _assertPendingPayouts(address(token), alice, 11, 22, 33);
        assertEq(vm.getRecordedLogs().length, 0, "unsupported active asset emits no event");
    }

    // Scenarios: SYR-I03, SYR-I13
    function test_givenRetiredPendingYield_whenCandidateRegistrationInvalid_revertsAndRollsBack(
        bool directVault_,
        uint8 failureKind_,
        bool adminCalls_
    ) public {
        failureKind_ = uint8(bound(failureKind_, 0, 3));
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        address vault = directVault_ ? address(token) : makeAddr("retired underlying vault");
        former.setVaultConfig(vault, address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 11, 22, 33);
        token.mint(address(distributor), 66);
        _setRegistrationFailure(candidate, address(token), directVault_, failureKind_);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(candidate),
                address(token)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "unsupported pending asset preserves recipient"
        );
        _assertPendingPayouts(address(token), alice, 11, 22, 33);
        assertEq(token.balanceOf(address(distributor)), 66, "failed update preserves custody");
        assertEq(vm.getRecordedLogs().length, 0, "unsupported pending asset emits no event");
    }

    // Scenarios: SYR-I14
    function test_givenMultipleRetiredUnderlyingAssets_whenLaterAssetUnsupported_revertsAndRollsBack(
        bool adminCalls_
    ) public {
        MockERC20 later = new MockERC20("Later Revenue", "LREV", 18);
        address firstVault = makeAddr("first vault");
        address laterVault = makeAddr("later vault");
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        former.setVaultConfig(firstVault, address(token), true);
        former.setVaultConfig(laterVault, address(later), true);
        candidate.setVaultConfig(firstVault, address(token), true);
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.setAssetRoutes(address(later), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.disableAssetRoutes(address(token));
        distributor.disableAssetRoutes(address(later));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 0, 1, 0);
        distributor.seedPendingForTest(address(later), alice, 0, 2, 0);

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_YieldRecipientUnavailable.selector,
                address(candidate),
                address(later)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(former),
            "later failure preserves recipient"
        );
        assertEq(
            distributor.pendingPayout(address(token), address(former)),
            1,
            "first pending yield stays assigned"
        );
        assertEq(
            distributor.pendingPayout(address(later), address(former)),
            2,
            "later pending yield stays assigned"
        );
        assertEq(vm.getRecordedLogs().length, 0, "later failure emits no event");
    }

    // Scenarios: SYR-I04
    function test_givenCandidateIsConfiguredOnLaterActiveAsset_whenSelected_revertsAndRollsBack(
        bool adminCalls_
    ) public {
        MockERC20 later = new MockERC20("Later Revenue", "LREV", 18);
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        IRevenueDistributor.AssetRoute[] memory empty = new IRevenueDistributor.AssetRoute[](0);
        IRevenueDistributor.AssetRoute[] memory collision = new IRevenueDistributor.AssetRoute[](1);
        collision[0] = IRevenueDistributor.AssetRoute({recipient: address(candidate), bps: 1});
        vm.startPrank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, empty);
        distributor.setAssetRoutes(address(later), 0, collision);
        vm.stopPrank();
        bytes32 firstHash = distributor.assetDistributionHash(address(token));
        bytes32 laterHash = distributor.assetDistributionHash(address(later));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IRevenueDistributor.RevenueDistributor_DuplicateRecipient.selector,
                address(candidate)
            )
        );
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(distributor.yieldRecipient(), address(0), "collision preserves zero recipient");
        assertEq(
            distributor.assetDistributionHash(address(token)),
            firstHash,
            "collision preserves first hash"
        );
        assertEq(
            distributor.assetDistributionHash(address(later)),
            laterHash,
            "collision preserves later hash"
        );
        assertEq(vm.getRecordedLogs().length, 0, "collision emits no event");
    }

    // Scenarios: SYR-I04
    function test_givenCandidateConfiguredOnlyOnRetiredAsset_whenSelected_succeeds(
        bool adminCalls_
    ) public {
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        IRevenueDistributor.AssetRoute[] memory collision = new IRevenueDistributor.AssetRoute[](1);
        collision[0] = IRevenueDistributor.AssetRoute({recipient: address(candidate), bps: 1});
        vm.startPrank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, collision);
        distributor.disableAssetRoutes(address(token));
        vm.stopPrank();

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(candidate));
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(candidate),
            "retired-only collision is allowed"
        );
    }

    // Scenarios: SYR-A01, SYR-A02, SYR-P09
    function test_givenZeroPointer_whenPermittedCallerSelectsRecipient_emitsAndPreservesState(
        bool adminCalls_
    ) public {
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        vm.prank(address(configTimelock));
        distributor.setAssetRoutes(address(token), 0, new IRevenueDistributor.AssetRoute[](0));
        distributor.seedPendingForTest(address(token), alice, 11, 0, 33);
        token.mint(address(distributor), 44);
        bytes32 expectedHash = keccak256(
            abi.encode(
                IRevenueDistributor.AssetState.Active,
                uint16(0),
                new IRevenueDistributor.AssetRoute[](0),
                address(candidate)
            )
        );

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(candidate));
        vm.recordLogs();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(
            distributor.yieldRecipient(),
            address(candidate),
            "permitted caller selects recipient"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            expectedHash,
            "global pointer updates route hash"
        );
        _assertPendingPayouts(address(token), alice, 11, 0, 33);
        assertEq(token.balanceOf(address(distributor)), 44, "pointer update preserves custody");
        assertEq(vm.getRecordedLogs().length, 1, "pointer update emits exactly one event");
    }

    // Scenarios: SYR-A02, SYR-P02
    function test_givenMultipleActiveAndRetiredYieldDebts_whenRecipientChanges_redirectsOnlyRoleDebt(
        bool directVault_,
        bool adminCalls_
    ) public {
        MockERC20 retired = new MockERC20("Retired Revenue", "RREV", 18);
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        MockYieldRepurchaseRecipient candidate = _newYieldRecipient();
        _setCompatibleRegistration(former, address(token), directVault_, "former active vault");
        _setCompatibleRegistration(former, address(retired), directVault_, "former retired vault");
        _setCompatibleRegistration(
            candidate,
            address(token),
            directVault_,
            "candidate active vault"
        );
        _setCompatibleRegistration(
            candidate,
            address(retired),
            directVault_,
            "candidate retired vault"
        );
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.setAssetRoutes(address(retired), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.disableAssetRoutes(address(retired));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 5, 7, 11);
        distributor.seedPendingForTest(address(retired), address(candidate), 13, 17, 19);
        token.mint(address(distributor), 23);
        retired.mint(address(distributor), 49);

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(candidate));
        vm.recordLogs();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(candidate));

        assertEq(distributor.yieldRecipient(), address(candidate), "new recipient is selected");
        assertEq(
            distributor.pendingPayout(address(token), address(former)),
            0,
            "former loses active role debt"
        );
        assertEq(
            distributor.pendingPayout(address(token), address(candidate)),
            7,
            "candidate gains active role debt"
        );
        assertEq(
            distributor.pendingPayout(address(retired), address(candidate)),
            30,
            "overlapping fixed and role debt combine"
        );
        address[] memory recipients = distributor.getPendingPayoutRecipients(address(retired));
        assertEq(recipients.length, 2, "overlap is deduplicated beside Treasury");
        assertEq(recipients[0], address(candidate), "candidate appears once");
        _assertPendingPayouts(address(token), alice, 5, 7, 11);
        _assertPendingPayouts(address(retired), address(candidate), 13, 17, 19);
        assertEq(token.balanceOf(address(distributor)), 23, "active custody is unchanged");
        assertEq(retired.balanceOf(address(distributor)), 49, "retired custody is unchanged");
        assertEq(vm.getRecordedLogs().length, 1, "recipient change emits exactly one event");
    }

    // Scenarios: SYR-P01
    function test_givenAnySupportedPendingYieldSet_whenRecipientCleared_redirectsToTreasury(
        uint8 assetCount_,
        uint8 retiredMask_,
        bool adminCalls_
    ) public {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        MockERC20 second = new MockERC20("Second Revenue", "REV2", 18);
        MockERC20 third = new MockERC20("Third Revenue", "REV3", 18);
        address[3] memory assets = [address(token), address(second), address(third)];
        MockYieldRepurchaseRecipient former = _newYieldRecipient();
        vm.prank(address(configTimelock));
        distributor.setYieldRecipient(address(former));
        for (uint256 i; i < assetCount_; ++i) {
            vm.prank(address(configTimelock));
            distributor.setAssetRoutes(assets[i], 0, new IRevenueDistributor.AssetRoute[](0));
            if (retiredMask_ & (1 << i) != 0) {
                vm.prank(address(configTimelock));
                distributor.disableAssetRoutes(assets[i]);
            }
            distributor.seedPendingForTest(assets[i], alice, i + 1, i + 2, i + 3);
        }

        vm.expectEmit(true, false, false, false, address(distributor));
        emit IRevenueDistributor.YieldRecipientSet(address(0));
        vm.recordLogs();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(0));

        assertEq(distributor.yieldRecipient(), address(0), "recipient clears to Treasury fallback");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(former)),
                0,
                "former recipient loses role debt"
            );
            assertEq(
                distributor.pendingPayout(assets[i], address(treasury)),
                (i + 2) + (i + 3),
                "Treasury combines yield and Treasury debt"
            );
            assertEq(
                distributor.pendingPayout(assets[i], alice),
                i + 1,
                "fixed recipient debt is unchanged"
            );
        }
        assertEq(vm.getRecordedLogs().length, 1, "clear emits exactly one event");
    }

    // Scenarios: SYR-P03
    function test_givenSameCompatibleRecipientWithAnyAssetStates_whenSetAgain_noOps(
        bool underlying_,
        bool retireSecond_,
        bool adminCalls_
    ) public {
        MockERC20 second = new MockERC20("Second Revenue", "REV2", 18);
        MockYieldRepurchaseRecipient recipient = _newYieldRecipient();
        _setCompatibleRegistration(recipient, address(token), !underlying_, "same first vault");
        _setCompatibleRegistration(recipient, address(second), !underlying_, "same second vault");
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(recipient));
        distributor.setAssetRoutes(address(token), 1, new IRevenueDistributor.AssetRoute[](0));
        distributor.setAssetRoutes(address(second), 1, new IRevenueDistributor.AssetRoute[](0));
        if (retireSecond_) distributor.disableAssetRoutes(address(second));
        vm.stopPrank();
        distributor.seedPendingForTest(address(token), alice, 1, 2, 3);
        distributor.seedPendingForTest(address(second), bob, 4, 5, 6);
        bytes32 firstHash = distributor.assetDistributionHash(address(token));
        bytes32 secondHash = distributor.assetDistributionHash(address(second));

        vm.recordLogs();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(recipient));

        assertEq(
            distributor.yieldRecipient(),
            address(recipient),
            "same recipient remains selected"
        );
        assertEq(
            distributor.assetDistributionHash(address(token)),
            firstHash,
            "same pointer preserves first hash"
        );
        assertEq(
            distributor.assetDistributionHash(address(second)),
            secondHash,
            "same pointer preserves second hash"
        );
        _assertPendingPayouts(address(token), alice, 1, 2, 3);
        _assertPendingPayouts(address(second), bob, 4, 5, 6);
        assertEq(vm.getRecordedLogs().length, 0, "same pointer emits no event");
    }

    // Scenarios: SYR-P04
    function test_givenZeroPointerAndAnyPendingYieldSet_whenSetToZeroAgain_noOps(
        uint8 assetCount_,
        uint8 retiredMask_,
        bool adminCalls_
    ) public {
        assetCount_ = uint8(bound(assetCount_, 0, 3));
        MockERC20 second = new MockERC20("Second Revenue", "REV2", 18);
        MockERC20 third = new MockERC20("Third Revenue", "REV3", 18);
        address[3] memory assets = [address(token), address(second), address(third)];
        for (uint256 i; i < assetCount_; ++i) {
            vm.prank(address(configTimelock));
            distributor.setAssetRoutes(assets[i], 0, new IRevenueDistributor.AssetRoute[](0));
            if (retiredMask_ & (1 << i) != 0) {
                vm.prank(address(configTimelock));
                distributor.disableAssetRoutes(assets[i]);
            }
            distributor.seedPendingForTest(assets[i], alice, i + 1, i + 2, i + 3);
        }

        vm.recordLogs();
        vm.prank(adminCalls_ ? admin : address(configTimelock));
        distributor.setYieldRecipient(address(0));

        assertEq(distributor.yieldRecipient(), address(0), "zero pointer remains selected");
        for (uint256 i; i < assetCount_; ++i) {
            assertEq(
                distributor.pendingPayout(assets[i], address(treasury)),
                (i + 2) + (i + 3),
                "Treasury fallback remains entitled"
            );
            assertEq(
                distributor.pendingPayout(assets[i], alice),
                i + 1,
                "fixed debt remains unchanged"
            );
        }
        assertEq(vm.getRecordedLogs().length, 0, "same zero pointer emits no event");
    }

    function _setRegistrationFailure(
        MockYieldRepurchaseRecipient recipient_,
        address asset_,
        bool directVault_,
        uint8 failureKind_
    ) internal {
        if (failureKind_ == 0) return;
        address vault = directVault_ ? asset_ : makeAddr("invalid underlying vault");
        recipient_.setVaultConfig(vault, asset_, failureKind_ != 1);
        if (failureKind_ == 2)
            recipient_.setReturnedVault(vault, makeAddr("malformed returned vault"));
        if (failureKind_ == 3) recipient_.setRevertGetVaultConfig(true);
    }

    function _invalidateExistingRegistration(
        MockYieldRepurchaseRecipient recipient_,
        address vault_,
        address asset_,
        uint8 failureKind_
    ) internal {
        if (failureKind_ == 0) {
            recipient_.removeVaultConfig(vault_);
        } else if (failureKind_ == 1) {
            recipient_.setVaultConfig(vault_, asset_, false);
        } else if (failureKind_ == 2) {
            recipient_.setReturnedVault(vault_, makeAddr("malformed existing vault"));
        } else {
            recipient_.setRevertGetVaultConfig(true);
        }
    }

    function _setCompatibleRegistration(
        MockYieldRepurchaseRecipient recipient_,
        address asset_,
        bool directVault_,
        string memory vaultLabel_
    ) internal {
        address vault = directVault_ ? asset_ : makeAddr(vaultLabel_);
        recipient_.setVaultConfig(vault, asset_, true);
    }

    function _newYieldRecipient() internal returns (MockYieldRepurchaseRecipient recipient) {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
    }
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unsafe-typecast)
