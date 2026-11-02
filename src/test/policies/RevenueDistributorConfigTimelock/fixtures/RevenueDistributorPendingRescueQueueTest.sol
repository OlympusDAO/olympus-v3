// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {IRevenueDistributorRescue} from "src/policies/interfaces/IRevenueDistributorRescue.sol";

// Libraries
import {REVENUE_DISTRIBUTOR_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorRescueOverlapTest} from "src/test/policies/RevenueDistributor/fixtures/RevenueDistributorRescueOverlapTest.sol";

// Base-unit fixtures explicitly exercise the numeric and independent lifecycle matrix.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)
abstract contract RevenueDistributorPendingRescueQueueTest is RevenueDistributorRescueOverlapTest {
    uint256 internal constant _QUEUED_RECEIPTS = 100;
    uint256 internal constant _QUEUED_ASSET_ROUTE = 33;
    uint256 internal constant _QUEUED_REPURCHASE = 20;
    uint256 internal constant _QUEUED_TREASURY = 47;

    MockRevertingTransferToken internal _rescueAsset;
    MockYieldRepurchaseRecipient internal _repurchaseRecipient;

    function setUp() public virtual override {
        super.setUp();
        _rescueAsset = new MockRevertingTransferToken(18);
        _repurchaseRecipient = new MockYieldRepurchaseRecipient(kernel);
        vm.prank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(_repurchaseRecipient));
        _repurchaseRecipient.setVaultConfig(address(_rescueAsset), address(_rescueAsset), true);
        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](1);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        vm.startPrank(admin);
        distributor.setYieldRecipient(address(_repurchaseRecipient));
        distributor.setAssetRoutes(address(_rescueAsset), 2_000, routes);
        rolesAdmin.grantRole(REVENUE_DISTRIBUTOR_ADMIN_ROLE, alice);
        vm.stopPrank();
        _rescueAsset.setTransferReverts(alice, true);
        _rescueAsset.setTransferReverts(address(treasury), true);
        _rescueAsset.setTransferReverts(address(_repurchaseRecipient), true);
        _rescueAsset.mint(address(distributor), 100);
        distributor.distribute(address(_rescueAsset));
    }

    /// @dev The overlap scenario replaces the role recipient. Support the existing deferred
    ///      repurchase asset and disable its future repurchases before clearing that role.
    function _createOverlappingRepurchaseRecipient()
        internal
        override
        returns (MockYieldRepurchaseRecipient recipient)
    {
        recipient = super._createOverlappingRepurchaseRecipient();
        recipient.setVaultConfig(address(_rescueAsset), address(_rescueAsset), true);
        distributor.disableAssetRoutes(address(_rescueAsset));
    }

    function _selector() internal pure returns (bytes4) {
        return IRevenueDistributorRescue.rescuePendingPayout.selector;
    }

    function _payload(address recipient_, uint256 amount_) internal view returns (bytes memory) {
        return abi.encode(address(_rescueAsset), recipient_, bob, amount_);
    }

    function _key() internal view returns (bytes32) {
        bytes32 localKey = keccak256(
            abi.encode(keccak256("REVENUE_DISTRIBUTOR_ASSET"), address(_rescueAsset))
        );
        return keccak256(abi.encode(address(distributor), localKey));
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return)
