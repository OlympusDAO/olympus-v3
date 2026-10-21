// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";

// Contracts
import {RevenueDistributorTest} from "../RevenueDistributorTest.sol";
import {Actions} from "src/Kernel.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {ReentrantPayoutToken} from "src/test/mocks/ReentrantPayoutToken.sol";

// Fixture amounts are 18-decimal base units; valid queue-revert calls ignore their return values.
// forge-lint: disable-start(literal-instead-of-constant,unused-return)
abstract contract RevenueDistributorRescueCallbackTest is RevenueDistributorTest {
    uint8 internal constant _TOKEN_DECIMALS = 18;
    uint256 internal constant _CALLBACK_TOTAL = 100;
    uint256 internal constant _CALLBACK_REPURCHASE = 20;
    uint256 internal constant _CALLBACK_RECIPIENT = 30;
    uint256 internal constant _CALLBACK_TREASURY = 50;
    uint16 internal constant _CALLBACK_REPURCHASE_BPS = 2_000;
    uint16 internal constant _CALLBACK_RECIPIENT_BPS = 3_000;

    /// @dev 0 = surplus, 1 = repurchase, 2 = Treasury, 3 = fixed recipient.
    function _callbackRescueOperation(bool useTreasury_) internal pure virtual returns (uint8);

    function _currentRepurchaseRecipient() internal view returns (address) {
        address selected = distributor.yieldRecipient();
        return selected == address(0) ? distributor.treasury() : selected;
    }

    function _createPreviewAsset(
        bool useTreasury_
    ) internal returns (MockRevertingTransferToken asset) {
        uint8 operation = _callbackRescueOperation(useTreasury_);
        asset = new MockRevertingTransferToken(_TOKEN_DECIMALS);
        if (operation != 0) {
            MockYieldRepurchaseRecipient recipient = new MockYieldRepurchaseRecipient(kernel);
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(recipient));
            recipient.setVaultConfig(address(asset), address(asset), true);
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute({
                recipient: alice,
                bps: _CALLBACK_RECIPIENT_BPS
            });
            vm.startPrank(admin);
            distributor.setYieldRecipient(address(recipient));
            distributor.setAssetRoutes(address(asset), _CALLBACK_REPURCHASE_BPS, routes);
            vm.stopPrank();
            asset.setTransferReverts(alice, true);
            asset.setTransferReverts(address(treasury), true);
            asset.setTransferReverts(address(recipient), true);
            asset.mint(address(distributor), _CALLBACK_TOTAL);
            distributor.distribute(address(asset));
        } else asset.mint(address(distributor), _CALLBACK_TOTAL);
    }

    function _createCallbackAsset(
        bool useTreasury_,
        uint8 nestedAction_,
        bool bubbleFailure_
    ) internal returns (ReentrantPayoutToken asset, MockYieldRepurchaseRecipient yieldRecipient) {
        uint8 operation = _callbackRescueOperation(useTreasury_);
        asset = new ReentrantPayoutToken();
        yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        if (operation != 0) {
            vm.prank(admin);
            kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
            yieldRecipient.setVaultConfig(address(asset), address(asset), true);
            IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](
                1
            );
            routes[0] = IRevenueDistributor.AssetRoute({
                recipient: alice,
                bps: _CALLBACK_RECIPIENT_BPS
            });
            vm.startPrank(admin);
            distributor.setYieldRecipient(address(yieldRecipient));
            distributor.setAssetRoutes(address(asset), _CALLBACK_REPURCHASE_BPS, routes);
            vm.stopPrank();
            asset.setTransferBlocked(alice, true);
            asset.setTransferBlocked(address(treasury), true);
            asset.setTransferBlocked(address(yieldRecipient), true);
            asset.mint(address(distributor), _CALLBACK_TOTAL);
            distributor.distribute(address(asset));
        } else asset.mint(address(distributor), _CALLBACK_TOTAL);
        vm.prank(admin);
        distributor.setConfigOperator(address(asset));
        bytes memory callback = _rescueCallback(asset, operation, nestedAction_);
        asset.setCallbackFrom(address(distributor), address(distributor), callback);
        asset.setBubbleCallbackFailure(bubbleFailure_);
    }

    function _rescueCallback(
        ReentrantPayoutToken asset,
        uint8 operation,
        uint8 nestedAction_
    ) internal view returns (bytes memory callback) {
        address repurchasePayoutRecipient = _currentRepurchaseRecipient();

        if (nestedAction_ == 0 && operation == 0)
            callback = abi.encodeCall(distributor.rescue, (address(asset), bob));
        else if (nestedAction_ == 0)
            callback = abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(asset), repurchasePayoutRecipient, bob, 1)
            );
        else if (nestedAction_ == 1)
            callback = abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(asset), address(treasury), bob, 1)
            );
        else if (nestedAction_ == 2)
            callback = abi.encodeCall(
                distributor.rescuePendingPayout,
                (address(asset), alice, bob, 1)
            );
        else if (nestedAction_ == 3)
            callback = abi.encodeCall(distributor.transferPendingPayout, (address(asset), alice));
        else callback = abi.encodeCall(distributor.distribute, (address(asset)));
    }

    function _assertCallbackAccounting(
        ReentrantPayoutToken asset,
        MockYieldRepurchaseRecipient yieldRecipient,
        uint256 expectedAssetRoute_,
        uint256 expectedRepurchase_,
        uint256 expectedTreasury_,
        uint256 expectedPaid_
    ) internal view {
        assertEq(asset.balanceOf(bob), expectedPaid_, "outer rescue transfers at most once");
        assertEq(
            asset.balanceOf(address(distributor)),
            _CALLBACK_TOTAL - expectedPaid_,
            "callback outcome preserves custody"
        );
        _assertPendingPayouts(
            address(asset),
            alice,
            expectedAssetRoute_,
            expectedRepurchase_,
            expectedTreasury_
        );
        assertEq(
            distributor.pendingPayout(address(asset), address(yieldRecipient)),
            expectedRepurchase_,
            "repurchase recipient retains the expected entitlement"
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant,unused-return)
