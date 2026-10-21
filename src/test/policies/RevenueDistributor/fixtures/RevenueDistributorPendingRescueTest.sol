// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorHarness} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorHarness.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

/// @dev A token callback records post-debit reads; comparing with final reads proves visibility.
// The observer and ledger assert the same action's callback/read state in one fixture.
// forge-lint: disable-next-line(multi-contract-file)
contract RevenueDistributorRescueObserver {
    uint256 public entitlement;
    uint256 public preview;
    bytes public failure;
    bytes32 public state;

    /// @dev Probe one unit, catching the expected insufficient-entitlement error after full drainage.
    function observe(
        RevenueDistributorHarness rd_,
        IERC20 asset_,
        address recipient_,
        address destination_
    ) external {
        entitlement = rd_.pendingPayout(address(asset_), recipient_);
        try rd_.previewRescuePendingPayout(address(asset_), recipient_, destination_, 1) returns (
            uint256 available
        ) {
            preview = available;
        } catch (bytes memory errorData) {
            failure = errorData;
        }
        state = observation(rd_, asset_, recipient_, destination_);
    }

    /// @dev Include raw accounting, indexes, config and custody; exclude the observer's own storage.
    function observation(
        RevenueDistributorHarness rd_,
        IERC20 asset_,
        address recipient_,
        address destination_
    ) public view returns (bytes32) {
        bytes32 accounting = keccak256(
            abi.encode(
                rd_.pendingAssetRouteForTest(address(asset_), recipient_),
                rd_.pendingRepurchaseForTest(address(asset_)),
                rd_.pendingTreasuryForTest(address(asset_)),
                rd_.totalPendingForTest(address(asset_)),
                rd_.getPendingPayoutAssets(),
                rd_.getPendingPayoutRecipients(address(asset_))
            )
        );
        bytes32 config = keccak256(
            abi.encode(
                rd_.assetState(address(asset_)),
                rd_.configOperator(),
                rd_.yieldRecipient(),
                rd_.treasury()
            )
        );
        return
            keccak256(
                abi.encode(
                    accounting,
                    config,
                    asset_.balanceOf(address(rd_)),
                    asset_.balanceOf(destination_)
                )
            );
    }
}

// Scenario fixtures intentionally use fixed base units, calls in finite loops and raw-state seeding.
// forge-lint: disable-start(literal-instead-of-constant,unused-return,calls-loop)
/// @dev Each ledger contains only identities and raw obligations, never an operation or outcome.
// forge-lint: disable-next-line(multi-contract-file)
abstract contract RevenueDistributorPendingRescueTest is RevenueDistributorTest {
    enum Layout {
        Distinct,
        RouteYield,
        RouteTreasury,
        YieldTreasury,
        All
    }
    uint8 internal constant _ROUTE = 1;
    uint8 internal constant _REPURCHASE = 2;
    uint8 internal constant _TREASURY = 4;

    struct Ledger {
        MockERC20 asset;
        MockRevertingTransferToken otherAsset;
        address routeOwner;
        address yieldOwner;
        address treasuryOwner;
        address otherOwner;
        uint256 route;
        uint256 repurchase;
        uint256 treasuryDebt;
        uint256 otherRoute;
        uint256 otherAssetDebt;
        uint256 surplus;
    }

    /// @dev Establish aliases through real role changes and Treasury upgrades, not overwritten owners.
    ///      A route owner may become a role owner only after the route has been validated.
    function _configureLayout(Layout layout_, MockERC20 asset_) internal returns (Ledger memory l) {
        l.asset = asset_;
        l.otherOwner = makeAddr("unrelated debt owner");
        l.otherAsset = new MockRevertingTransferToken(18);
        MockYieldRepurchaseRecipient oldYield = _newYieldRecipient(address(asset_));
        l.routeOwner = alice;
        OlympusTreasury futureTreasury;
        if (layout_ == Layout.RouteYield)
            l.routeOwner = address(_newYieldRecipient(address(asset_)));
        if (layout_ == Layout.RouteTreasury || layout_ == Layout.All) {
            futureTreasury = new OlympusTreasury(kernel);
            l.routeOwner = address(futureTreasury);
        }
        _setSingleRoute(address(asset_), l.routeOwner);
        _setSingleRoute(address(l.otherAsset), l.otherOwner);
        vm.startPrank(admin);
        distributor.setYieldRecipient(address(oldYield));
        if (layout_ == Layout.RouteYield) {
            // Historical fixed debt can overlap a later role only after the live route is removed.
            distributor.setAssetRoutes(address(asset_), 0, new IRevenueDistributor.AssetRoute[](0));
            distributor.setYieldRecipient(l.routeOwner);
        }
        if (layout_ == Layout.YieldTreasury || layout_ == Layout.All)
            distributor.setYieldRecipient(address(0));
        if (address(futureTreasury) != address(0))
            kernel.executeAction(Actions.UpgradeModule, address(futureTreasury));
        vm.stopPrank();
        l.treasuryOwner = distributor.treasury();
        l.yieldOwner = distributor.yieldRecipient() == address(0)
            ? l.treasuryOwner
            : distributor.yieldRecipient();
    }

    /// @dev Build an enabled, same-Kernel recipient accepted by the actual role setter.
    function _newYieldRecipient(
        address asset_
    ) internal returns (MockYieldRepurchaseRecipient recipient) {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(recipient));
        recipient.setVaultConfig(asset_, asset_, true);
    }

    /// @dev Validate a fixed route before any owner becomes a role recipient.
    function _setSingleRoute(address asset_, address owner_) internal {
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute(owner_, 10_000);
        vm.prank(admin);
        distributor.setAssetRoutes(asset_, 0, routes);
    }

    /// @dev Each mask bit denotes a globally recorded bucket, independently of selected eligibility.
    function _ordinaryQuantities(
        Ledger memory l,
        uint8 mask_
    ) internal pure returns (Ledger memory) {
        l.route = mask_ & _ROUTE == 0 ? 0 : 10;
        l.repurchase = mask_ & _REPURCHASE == 0 ? 0 : 20;
        l.treasuryDebt = mask_ & _TREASURY == 0 ? 0 : 30;
        return l;
    }

    /// @dev Seed independent raw debt and fund exactly reserve plus surplus; retirement precedes disablement.
    ///      This action suite does not reproduce distribution arithmetic; MAX must remain reachable.
    function _fundLedger(Ledger memory l, bool retired_, bool disabled_) internal {
        distributor.seedPendingForTest(
            address(l.asset),
            l.routeOwner,
            l.route,
            l.repurchase,
            l.treasuryDebt
        );
        if (l.otherRoute != 0)
            distributor.addPendingRouteForTest(address(l.asset), l.otherOwner, l.otherRoute);
        if (l.otherAssetDebt != 0) {
            distributor.seedPendingForTest(
                address(l.otherAsset),
                l.otherOwner,
                l.otherAssetDebt,
                0,
                0
            );
            l.otherAsset.mint(address(distributor), l.otherAssetDebt);
        }
        l.asset.mint(
            address(distributor),
            l.route + l.repurchase + l.treasuryDebt + l.otherRoute + l.surplus
        );
        if (retired_) {
            vm.prank(admin);
            distributor.disableAssetRoutes(address(l.asset));
        }
        if (disabled_) {
            vm.prank(admin);
            distributor.disable("");
        }
        assertEq(
            uint256(distributor.assetState(address(l.asset))),
            uint256(
                retired_
                    ? IRevenueDistributor.AssetState.Retired
                    : IRevenueDistributor.AssetState.Active
            ),
            "listing state constructed"
        );
        assertEq(distributor.isEnabled(), !disabled_, "local state constructed");
        _assertLedger(l, l.route, l.repurchase, l.treasuryDebt);
    }

    /// @dev Choose an original recipient from the constructed identities without changing any ownership.
    function _recipient(Ledger memory l, uint8 owner_) internal pure returns (address) {
        if (owner_ == 0) return l.routeOwner;
        if (owner_ == 1) return l.yieldOwner;
        if (owner_ == 2) return l.treasuryOwner;
        return l.otherOwner;
    }

    /// @dev Eligibility depends on the selected identity; ineligible global debt stays in custody.
    function _eligible(
        Ledger memory l,
        address recipient_
    ) internal pure returns (uint256[3] memory e) {
        if (recipient_ == l.routeOwner) e[0] = l.route;
        if (recipient_ == l.yieldOwner) e[1] = l.repurchase;
        if (recipient_ == l.treasuryOwner) e[2] = l.treasuryDebt;
        if (recipient_ == l.otherOwner) e[0] = l.otherRoute;
    }

    /// @dev Verify previews as the action caller, not a privileged reader; match exact error and no writes.
    function _assertPreview(
        Ledger memory l,
        address caller_,
        address recipient_,
        address destination_,
        uint256 amount_,
        uint256 expected_,
        bytes memory error_
    ) internal {
        bytes32 beforeState = _stateHash(l, destination_);
        vm.recordLogs();
        if (error_.length != 0) vm.expectRevert(error_);
        vm.prank(caller_);
        uint256 available = distributor.previewRescuePendingPayout(
            address(l.asset),
            recipient_,
            destination_,
            amount_
        );
        if (error_.length == 0)
            assertEq(available, expected_, "preview equals independent entitlement");
        assertEq(vm.getRecordedLogs().length, 0, "preview emits no events");
        assertEq(_stateHash(l, destination_), beforeState, "preview preserves all observed state");
    }

    /// @dev Expected paid components are supplied by each partition, not chosen by this assertion helper.
    /// @param paid_ Route, repurchase and Treasury debits in token base units, in that order.
    function _assertSuccess(
        Ledger memory l,
        address caller_,
        address recipient_,
        address destination_,
        uint256 amount_,
        uint256[3] memory paid_
    ) internal {
        uint256 entitlement;
        {
            uint256[3] memory eligible = _eligible(l, recipient_);
            entitlement = eligible[0] + eligible[1] + eligible[2];
        }
        _assertPreview(l, caller_, recipient_, destination_, amount_, entitlement, "");
        assertEq(
            distributor.pendingPayout(address(l.asset), recipient_),
            entitlement,
            "getter equals independent entitlement"
        );
        bytes32 configBefore = _configHash(l);
        uint256 destinationBefore = l.asset.balanceOf(destination_);
        uint256 custodyBefore = l.asset.balanceOf(address(distributor));
        uint256 eventCount = _expectRescueEvents(l.asset, recipient_, destination_, amount_, paid_);
        vm.recordLogs();
        vm.prank(caller_);
        distributor.rescuePendingPayout(address(l.asset), recipient_, destination_, amount_);
        assertEq(
            vm.getRecordedLogs().length,
            eventCount,
            "exact per-kind and single-transfer event count"
        );
        assertEq(
            l.asset.balanceOf(destination_),
            destinationBefore + amount_,
            "destination paid exact amount once"
        );
        assertEq(
            l.asset.balanceOf(address(distributor)),
            custodyBefore - amount_,
            "custody debited exact amount"
        );
        assertEq(_configHash(l), configBefore, "rescue preserves configuration");
        _assertLedger(l, l.route - paid_[0], l.repurchase - paid_[1], l.treasuryDebt - paid_[2]);
        assertEq(
            distributor.pendingPayout(address(l.asset), recipient_),
            entitlement - amount_,
            "selected entitlement reduced exactly"
        );
    }

    /// @dev Expect only nonzero debits, in production order, followed by one exact token payment.
    function _expectRescueEvents(
        MockERC20 asset_,
        address recipient_,
        address destination_,
        uint256 amount_,
        uint256[3] memory paid_
    ) internal returns (uint256 count) {
        count = 1;
        if (paid_[0] != 0) {
            vm.expectEmit(true, true, true, true, address(distributor));
            emit IRevenueDistributorRescue.PendingAssetRouteRescued(
                address(asset_),
                recipient_,
                destination_,
                paid_[0]
            );
            ++count;
        }
        if (paid_[1] != 0) {
            vm.expectEmit(true, true, false, true, address(distributor));
            emit IRevenueDistributorRescue.PendingRepurchaseRescued(
                address(asset_),
                destination_,
                paid_[1]
            );
            ++count;
        }
        if (paid_[2] != 0) {
            vm.expectEmit(true, true, false, true, address(distributor));
            emit IRevenueDistributorRescue.PendingTreasuryRescued(
                address(asset_),
                destination_,
                paid_[2]
            );
            ++count;
        }
        vm.expectEmit(true, true, false, true, address(asset_));
        emit IERC20.Transfer(address(distributor), destination_, amount_);
    }

    /// @dev Preview and execution may fail at different gates; both must preserve authoritative state.
    function _assertFailure(
        Ledger memory l,
        address caller_,
        address recipient_,
        address destination_,
        uint256 amount_,
        bytes memory previewError_,
        bytes memory executionError_
    ) internal {
        uint256[3] memory e = _eligible(l, recipient_);
        _assertPreview(
            l,
            caller_,
            recipient_,
            destination_,
            amount_,
            e[0] + e[1] + e[2],
            previewError_
        );
        bytes32 beforeState = _stateHash(l, destination_);
        vm.expectRevert(executionError_);
        vm.prank(caller_);
        distributor.rescuePendingPayout(address(l.asset), recipient_, destination_, amount_);
        assertEq(_stateHash(l, destination_), beforeState, "failed rescue fully rolls back");
    }

    /// @dev Check raw debts, aggregate, internal indexes, public unions and untouched unrelated custody.
    // Explicit owner aliases and presence states are part of the independent assertion oracle.
    // forge-lint: disable-next-line(cyclomatic-complexity)
    function _assertLedger(
        Ledger memory l,
        uint256 route_,
        uint256 repurchase_,
        uint256 treasury_
    ) internal view {
        assertEq(
            distributor.pendingAssetRouteForTest(address(l.asset), l.routeOwner),
            route_,
            "raw route debt"
        );
        assertEq(
            distributor.pendingRepurchaseForTest(address(l.asset)),
            repurchase_,
            "raw repurchase debt"
        );
        assertEq(
            distributor.pendingTreasuryForTest(address(l.asset)),
            treasury_,
            "raw Treasury debt"
        );
        uint256 total = route_ + repurchase_ + treasury_ + l.otherRoute;
        assertEq(
            distributor.totalPendingForTest(address(l.asset)),
            total,
            "aggregate equals independent raw sum"
        );
        assertEq(
            distributor.pendingRouteMemberForTest(address(l.asset), l.routeOwner),
            route_ != 0,
            "raw route index follows its debt, not combined entitlement"
        );
        assertEq(
            distributor.pendingAssetMemberForTest(address(l.asset)),
            total != 0,
            "asset index follows all debt"
        );
        assertEq(
            l.asset.balanceOf(address(distributor)),
            total + l.surplus,
            "custody equals reserve plus unchanged surplus"
        );
        assertEq(
            distributor.pendingAssetRouteForTest(address(l.asset), l.otherOwner),
            l.otherRoute,
            "unrelated fixed debt unchanged"
        );
        assertEq(
            distributor.pendingRouteMemberForTest(address(l.asset), l.otherOwner),
            l.otherRoute != 0,
            "unrelated route index unchanged"
        );
        assertEq(
            distributor.totalPendingForTest(address(l.otherAsset)),
            l.otherAssetDebt,
            "unrelated asset debt unchanged"
        );
        assertEq(
            l.otherAsset.balanceOf(address(distributor)),
            l.otherAssetDebt,
            "unrelated asset custody unchanged"
        );
        address[] memory recipients = distributor.getPendingPayoutRecipients(address(l.asset));
        address[4] memory owners = [l.routeOwner, l.yieldOwner, l.treasuryOwner, l.otherOwner];
        uint256 expectedCount;
        for (uint256 i; i < owners.length; ++i) {
            bool duplicate;
            for (uint256 j; j < i; ++j) if (owners[i] == owners[j]) duplicate = true;
            if (duplicate) continue;
            uint256 owed;
            if (owners[i] == l.routeOwner) owed += route_;
            if (owners[i] == l.yieldOwner) owed += repurchase_;
            if (owners[i] == l.treasuryOwner) owed += treasury_;
            if (owners[i] == l.otherOwner) owed += l.otherRoute;
            _assertMembership(recipients, owners[i], owed != 0);
            assertEq(
                distributor.pendingPayout(address(l.asset), owners[i]),
                owed,
                "combined entitlement equals eligible raw sum"
            );
            if (owed != 0) ++expectedCount;
        }
        assertEq(
            recipients.length,
            expectedCount,
            "public recipient union has no extras or duplicates"
        );
        address[] memory assets = distributor.getPendingPayoutAssets();
        _assertMembership(assets, address(l.asset), total != 0);
        _assertMembership(assets, address(l.otherAsset), l.otherAssetDebt != 0);
        assertEq(
            assets.length,
            (total == 0 ? 0 : 1) + (l.otherAssetDebt == 0 ? 0 : 1),
            "public asset index reflects all debts"
        );
    }

    /// @dev Counting occurrences proves both presence and absence and catches duplicate public entries.
    function _assertMembership(
        address[] memory values_,
        address target_,
        bool present_
    ) internal pure {
        uint256 count;
        for (uint256 i; i < values_.length; ++i) if (values_[i] == target_) ++count;
        assertEq(count, present_ ? 1 : 0, "membership appears exactly once iff owed");
    }

    /// @dev Hash only protocol configuration; debt changes must never change this fingerprint.
    function _configHash(Ledger memory l) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    distributor.configOperator(),
                    distributor.yieldRecipient(),
                    distributor.treasury(),
                    distributor.assetDistributionHash(address(l.asset)),
                    distributor.assetState(address(l.asset)),
                    distributor.isEnabled(),
                    kernel.isPolicyActive(distributor)
                )
            );
    }

    /// @dev Fingerprint raw/index/config state and authoritative balances, including an invalid destination.
    function _stateHash(Ledger memory l, address destination_) internal view returns (bytes32) {
        bytes32 debt = keccak256(
            abi.encode(
                distributor.pendingAssetRouteForTest(address(l.asset), l.routeOwner),
                distributor.pendingRepurchaseForTest(address(l.asset)),
                distributor.pendingTreasuryForTest(address(l.asset)),
                distributor.totalPendingForTest(address(l.asset)),
                distributor.pendingAssetRouteForTest(address(l.asset), l.otherOwner),
                distributor.totalPendingForTest(address(l.otherAsset))
            )
        );
        bytes32 indexes = keccak256(
            abi.encode(
                distributor.getPendingPayoutAssets(),
                distributor.getPendingPayoutRecipients(address(l.asset)),
                distributor.pendingRouteMemberForTest(address(l.asset), l.routeOwner),
                distributor.pendingRouteMemberForTest(address(l.asset), l.otherOwner),
                distributor.pendingAssetMemberForTest(address(l.asset))
            )
        );
        return
            keccak256(
                abi.encode(
                    debt,
                    indexes,
                    _configHash(l),
                    l.asset.balanceOf(address(distributor)),
                    l.asset.balanceOf(destination_),
                    l.otherAsset.balanceOf(address(distributor))
                )
            );
    }

    /// @dev Use the exact requested/available values; no broad revert matching masks the branch.
    function _insufficient(
        address asset_,
        uint256 amount_,
        uint256 available_
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IRevenueDistributorRescue
                    .RevenueDistributor_InsufficientPendingDistribution
                    .selector,
                asset_,
                amount_,
                available_
            );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return,calls-loop)
