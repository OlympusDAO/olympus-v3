// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Contracts
import {RevenueDistributorTest} from "../RevenueDistributorTest.sol";
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";

abstract contract RevenueDistributorRescueOverlapTest is RevenueDistributorTest {
    uint8 internal constant _DECIMALS = 18;
    uint256 internal constant _RECEIPTS = 100;
    uint256 internal constant _ASSET_ROUTE = 30;
    uint256 internal constant _REPURCHASE = 20;
    uint256 internal constant _TREASURY = 50;
    uint16 internal constant _ASSET_ROUTE_BPS = 3_000;
    uint16 internal constant _REPURCHASE_BPS = 2_000;
    MockRevertingTransferToken internal _overlapAsset;
    OlympusTreasury internal _newTreasury;
    MockYieldRepurchaseRecipient internal _overlapRepurchaseRecipient;

    event PendingAssetRouteRescued(
        address indexed asset,
        address indexed originalRecipient,
        address indexed destination,
        uint256 amount
    );
    event PendingRepurchaseRescued(
        address indexed asset,
        address indexed destination,
        uint256 amount
    );
    event PendingTreasuryRescued(
        address indexed asset,
        address indexed destination,
        uint256 amount
    );

    modifier givenOverlappingLiabilities() {
        _overlapAsset = new MockRevertingTransferToken(_DECIMALS);
        vm.startPrank(admin);
        _newTreasury = new OlympusTreasury(kernel);
        _overlapRepurchaseRecipient = _createOverlappingRepurchaseRecipient();
        kernel.executeAction(Actions.ActivatePolicy, address(_overlapRepurchaseRecipient));
        vm.stopPrank();
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({
            recipient: address(_newTreasury),
            bps: _ASSET_ROUTE_BPS
        });
        vm.startPrank(admin);
        distributor.setYieldRecipient(address(_overlapRepurchaseRecipient));
        distributor.setAssetRoutes(address(_overlapAsset), _REPURCHASE_BPS, routes);
        vm.stopPrank();
        _overlapAsset.setTransferReverts(address(_newTreasury), true);
        _overlapAsset.setTransferReverts(address(_overlapRepurchaseRecipient), true);
        _overlapAsset.setTransferReverts(address(treasury), true);
        _overlapAsset.mint(address(distributor), _RECEIPTS);
        distributor.distribute(address(_overlapAsset));
        vm.startPrank(admin);
        distributor.setAssetRoutes(address(_overlapAsset), 0, routes);
        distributor.setYieldRecipient(address(0));
        kernel.executeAction(Actions.UpgradeModule, address(_newTreasury));
        vm.stopPrank();
        _;
    }

    function _createOverlappingRepurchaseRecipient()
        internal
        virtual
        returns (MockYieldRepurchaseRecipient recipient)
    {
        recipient = new MockYieldRepurchaseRecipient(kernel);
        recipient.setVaultConfig(address(_overlapAsset), address(_overlapAsset), true);
    }

    function _assertOverlappingRescue(
        uint256 expectedAssetRoute_,
        uint256 expectedRepurchase_,
        uint256 expectedTreasury_
    ) internal view {
        _assertPendingPayouts(
            address(_overlapAsset),
            address(_newTreasury),
            expectedAssetRoute_,
            expectedRepurchase_,
            expectedTreasury_
        );
        assertEq(
            distributor.pendingPayout(address(_overlapAsset), address(_newTreasury)),
            expectedAssetRoute_ + expectedRepurchase_ + expectedTreasury_,
            "combined recipient entitlement matches expected liabilities"
        );
    }
}
