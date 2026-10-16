// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";
import {RevenueDistributorTest} from "src/test/policies/RevenueDistributor/RevenueDistributorTest.sol";

/// @dev Only surplus-rescue assertions live here; NeverListed assets never receive fabricated debt.
// Finite fixtures and base-unit quantities; reverting view calls do not return.
// forge-lint: disable-start(calls-loop,literal-instead-of-constant,unused-return)
abstract contract RevenueDistributorSurplusRescueTestBase is RevenueDistributorTest {
    uint256 internal constant _ROUTE_DEBT = 10;
    uint256 internal constant _SECOND_ROUTE_DEBT = 2;
    uint256 internal constant _THIRD_ROUTE_DEBT = 3;
    uint256 internal constant _REPURCHASE_DEBT = 20;
    uint256 internal constant _TREASURY_DEBT = 30;
    uint256 internal constant _MANAGED_RESERVE =
        _ROUTE_DEBT + _SECOND_ROUTE_DEBT + _THIRD_ROUTE_DEBT + _REPURCHASE_DEBT + _TREASURY_DEBT;
    uint16 internal constant _ROUTE_BPS = 1000;
    uint16 internal constant _REPURCHASE_BPS = 2000;

    error BalanceQueryFailed();
    error TransferMustNotRun();
    ReentrantPayoutToken internal _managedAsset;
    address internal _thirdRecipient;

    function setUp() public virtual override {
        super.setUp();
        _thirdRecipient = makeAddr("third surplus isolation recipient");
    }

    /// @dev Three distinct route owners plus yield/Treasury debt expose cross-asset corruption.
    ///      Raw amounts are 10/2/3 routes, 20 repurchase, 30 Treasury, totaling 65 base units.
    function _createManagedRescueDebt() internal returns (ReentrantPayoutToken asset) {
        asset = new ReentrantPayoutToken();
        _managedAsset = asset;
        MockYieldRepurchaseRecipient yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
        yieldRecipient.setVaultConfig(address(asset), address(asset), true);
        vm.prank(admin);
        distributor.setYieldRecipient(address(yieldRecipient));
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](3);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: _ROUTE_BPS});
        routes[1] = IRevenueDistributor.AssetRoute({recipient: emergency, bps: _ROUTE_BPS});
        routes[2] = IRevenueDistributor.AssetRoute({recipient: _thirdRecipient, bps: _ROUTE_BPS});
        vm.prank(admin);
        distributor.setAssetRoutes(address(asset), _REPURCHASE_BPS, routes);
        distributor.seedPendingForTest(
            address(asset),
            alice,
            _ROUTE_DEBT,
            _REPURCHASE_DEBT,
            _TREASURY_DEBT
        );
        distributor.addPendingRouteForTest(address(asset), emergency, _SECOND_ROUTE_DEBT);
        distributor.addPendingRouteForTest(address(asset), _thirdRecipient, _THIRD_ROUTE_DEBT);
        asset.mint(address(distributor), _MANAGED_RESERVE);
    }

    /// @dev Include authoritative route membership; public getters alone may hide stale indexes.
    function _rdRawRescueHash(address asset_) internal view returns (bytes32) {
        bytes32 debts = keccak256(
            abi.encode(
                distributor.pendingAssetRouteForTest(asset_, alice),
                distributor.pendingAssetRouteForTest(asset_, emergency),
                distributor.pendingAssetRouteForTest(asset_, _thirdRecipient),
                distributor.pendingRepurchaseForTest(asset_),
                distributor.pendingTreasuryForTest(asset_),
                distributor.totalPendingForTest(asset_)
            )
        );
        return
            keccak256(
                abi.encode(
                    debts,
                    distributor.pendingAssetMemberForTest(asset_),
                    distributor.pendingRouteMemberForTest(asset_, alice),
                    distributor.pendingRouteMemberForTest(asset_, emergency),
                    distributor.pendingRouteMemberForTest(asset_, _thirdRecipient),
                    distributor.getPendingPayoutAssets(),
                    distributor.getPendingPayoutRecipients(asset_),
                    distributor.assetState(asset_),
                    distributor.assetDistributionHash(asset_)
                )
            );
    }

    /// @dev Configuration plus selected and unrelated authoritative ledgers; custody of the
    ///      managed isolation token is included because a surplus rescue must never touch it.
    function _rdSurplusStateHash(address selected_) internal view returns (bytes32) {
        bytes32 state = keccak256(
            abi.encode(
                _rdRawRescueHash(selected_),
                distributor.configOperator(),
                distributor.yieldRecipient(),
                distributor.treasury(),
                distributor.isEnabled()
            )
        );
        if (address(_managedAsset) != address(0))
            state = keccak256(
                abi.encode(
                    state,
                    _rdRawRescueHash(address(_managedAsset)),
                    _managedAsset.balanceOf(address(distributor)),
                    _managedAsset.balanceOf(alice),
                    _managedAsset.balanceOf(emergency),
                    _managedAsset.balanceOf(_thirdRecipient)
                )
            );
        return state;
    }

    /// @dev The caller supplies independently expected custody, never a preview-derived oracle.
    function _assertRDSurplusPayment(
        MockERC20 asset_,
        address destination_,
        uint256 amount_,
        address caller_
    ) internal {
        uint256 custody = asset_.balanceOf(address(distributor));
        uint256 destinationBalance = asset_.balanceOf(destination_);
        bytes32 beforeState = _rdSurplusStateHash(address(asset_));
        assertEq(
            distributor.previewRescue(address(asset_), destination_),
            amount_,
            "preview equals independent NeverListed custody"
        );
        if (amount_ != 0) {
            vm.expectEmit(true, true, false, true, address(asset_));
            emit IERC20.Transfer(address(distributor), destination_, amount_);
            vm.expectEmit(true, true, false, true, address(distributor));
            emit IRevenueDistributorRescue.AssetRescued(address(asset_), destination_, amount_);
        } else
            vm.mockCallRevert(
                address(asset_),
                abi.encodeWithSelector(IERC20.transfer.selector, destination_),
                abi.encodeWithSelector(TransferMustNotRun.selector)
            );
        _expectSurplusCompletionEvents(caller_);
        vm.recordLogs();
        _executeRDSurplusRescue(address(asset_), destination_, caller_);
        assertEq(
            vm.getRecordedLogs().length,
            _rdSurplusExecutionLogCount(amount_),
            "exact Transfer and AssetRescued log count"
        );
        vm.clearMockedCalls();
        assertEq(
            asset_.balanceOf(address(distributor)),
            custody - amount_,
            "only selected NeverListed custody moves"
        );
        assertEq(
            asset_.balanceOf(destination_),
            destinationBalance + amount_,
            "destination receives full exact balance"
        );
        assertEq(
            _rdSurplusStateHash(address(asset_)),
            beforeState,
            "selected/unrelated debts, membership, routes and configuration preserved"
        );
        assertEq(
            distributor.previewRescue(address(asset_), destination_),
            0,
            "selected custody is fully cleared"
        );
    }

    function _executeRDSurplusRescue(
        address asset_,
        address destination_,
        address caller_
    ) internal virtual {
        vm.prank(caller_);
        distributor.rescue(asset_, destination_);
    }

    function _assertRDSurplusFailure(
        MockERC20 tracker_,
        address requested_,
        address destination_,
        address caller_,
        bytes memory failure_
    ) internal {
        uint256 custody = tracker_.balanceOf(address(distributor));
        uint256 destinationBalance = tracker_.balanceOf(destination_);
        bytes32 beforeState = _rdSurplusStateHash(address(tracker_));
        vm.expectRevert(failure_);
        _executeRDSurplusRescue(requested_, destination_, caller_);
        assertEq(tracker_.balanceOf(address(distributor)), custody, "failure preserves custody");
        assertEq(
            tracker_.balanceOf(destination_),
            destinationBalance,
            "failure preserves destination balance"
        );
        assertEq(
            _rdSurplusStateHash(address(tracker_)),
            beforeState,
            "failure preserves every raw liability, index and configuration"
        );
    }

    function _assertRDBalanceQueryFailure(MockERC20 asset_, address caller_) internal {
        uint256 custody = asset_.balanceOf(address(distributor));
        bytes32 beforeState = _rdSurplusStateHash(address(asset_));
        bytes memory failure = abi.encodeWithSelector(BalanceQueryFailed.selector);
        vm.mockCallRevert(
            address(asset_),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(distributor)),
            failure
        );
        vm.expectRevert(failure);
        distributor.previewRescue(address(asset_), bob);
        vm.expectRevert(failure);
        _executeRDSurplusRescue(address(asset_), bob, caller_);
        vm.clearMockedCalls();
        assertEq(
            asset_.balanceOf(address(distributor)),
            custody,
            "balanceOf failure preserves actual custody"
        );
        assertEq(
            _rdSurplusStateHash(address(asset_)),
            beforeState,
            "balanceOf failure preserves raw ledgers and configuration"
        );
    }

    /// @dev Timelock wrappers append their own two completion events.
    function _rdSurplusExecutionLogCount(uint256 amount_) internal pure virtual returns (uint256) {
        return amount_ == 0 ? 0 : 2;
    }

    function _expectSurplusCompletionEvents(address) internal virtual {}
}
// forge-lint: disable-end(calls-loop,literal-instead-of-constant,unused-return)
