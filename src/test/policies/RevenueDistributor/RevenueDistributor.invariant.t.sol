// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {StdInvariant} from "@forge-std-1.16.2/StdInvariant.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";
import {MockYieldRepurchaseRecipient} from "src/test/mocks/MockYieldRepurchaseRecipient.sol";
import {RevenueDistributorInvariantHandler} from "./handlers/RevenueDistributorInvariantHandler.sol";
import {RevenueDistributorTest} from "./RevenueDistributorTest.sol";

/// forge-config: default.invariant.fail-on-revert = true
contract RevenueDistributorInvariantTest is StdInvariant, RevenueDistributorTest {
    RevenueDistributorInvariantHandler internal _handler;

    function setUp() public override {
        super.setUp();
        MockRevertingTransferToken asset = new MockRevertingTransferToken(18);
        OlympusTreasury replacementTreasury = new OlympusTreasury(kernel);
        MockYieldRepurchaseRecipient firstYieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        MockYieldRepurchaseRecipient secondYieldRecipient = new MockYieldRepurchaseRecipient(
            kernel
        );
        vm.label(address(asset), "Invariant revenue token");
        vm.label(address(replacementTreasury), "Replacement TRSRY");
        vm.label(address(firstYieldRecipient), "First yield recipient");
        vm.label(address(secondYieldRecipient), "Second yield recipient");
        vm.startPrank(admin);
        kernel.executeAction(Actions.ActivatePolicy, address(firstYieldRecipient));
        kernel.executeAction(Actions.ActivatePolicy, address(secondYieldRecipient));
        vm.stopPrank();
        firstYieldRecipient.setVaultConfig(address(asset), address(asset), true);
        secondYieldRecipient.setVaultConfig(address(asset), address(asset), true);

        IRevenueDistributor.AssetRoute[] memory routes = new IRevenueDistributor.AssetRoute[](2);
        routes[0] = IRevenueDistributor.AssetRoute({recipient: alice, bps: 3_333});
        routes[1] = IRevenueDistributor.AssetRoute({
            recipient: address(replacementTreasury),
            bps: 1_667
        });
        vm.startPrank(address(configTimelock));
        distributor.setYieldRecipient(address(firstYieldRecipient));
        distributor.setAssetRoutes(address(asset), 2_000, routes);
        vm.stopPrank();

        // Fail every initial destination so all three liability classes begin unpaid.
        asset.setTransferReverts(alice, true);
        asset.setTransferReverts(bob, true);
        asset.setTransferReverts(address(treasury), true);
        asset.setTransferReverts(address(replacementTreasury), true);
        asset.setTransferReverts(address(firstYieldRecipient), true);
        asset.setTransferReverts(address(secondYieldRecipient), true);
        asset.mint(address(distributor), 100);
        distributor.distribute(address(asset));

        _handler = new RevenueDistributorInvariantHandler(
            RevenueDistributorInvariantHandler.Dependencies({
                kernel: kernel,
                distributor: distributor,
                configTimelock: configTimelock,
                asset: asset,
                originalTreasury: treasury,
                replacementTreasury: replacementTreasury,
                firstYieldRecipient: firstYieldRecipient,
                secondYieldRecipient: secondYieldRecipient,
                admin: admin,
                alice: alice,
                bob: bob
            })
        );
        vm.label(address(_handler), "Revenue distributor invariant handler");
        targetContract(address(_handler));
    }

    function invariant_pendingSharesStaySolventAndConserved() public view {
        _handler.assertAccounting();
    }
}
