// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(calls-loop)

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Actions} from "src/Kernel.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "../BurnerLoansTest.sol";
import {MockYieldRepurchaseRecipient} from "./MockYieldRepurchaseRecipient.sol";

abstract contract BurnerLoansYieldRoutingTestBase is BurnerLoansTest {
    MockYieldRepurchaseRecipient internal yieldRecipient;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);
        yieldRecipient = new MockYieldRepurchaseRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
        vm.stopPrank();
    }

    function _configureYieldRepurchaseRecipientAsset(address asset_, address vault_) internal {
        yieldRecipient.setVaultConfig(vault_, asset_, true);
    }

    function _setYieldRepurchaseRecipient(address recipient_) internal {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setYieldRepurchaseRecipient(recipient_);
    }

    function _setYieldAssetRouting(
        address asset_,
        IBurnerLoans.AssetYieldRouting memory routing_
    ) internal {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setYieldAssetRouting(asset_, routing_);
    }

    function _addYieldAsset() internal returns (MockERC20 asset, MockERC4626 vault) {
        (asset, vault) = _addVaultAssetForTest();
        _configureYieldRepurchaseRecipientAsset(address(asset), address(vault));
    }

    function _treasuryOnlyRouting()
        internal
        pure
        returns (IBurnerLoans.AssetYieldRouting memory routing)
    {
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](0);
    }

    function _repurchaseRouting(
        uint16 repurchaseBps_
    ) internal pure returns (IBurnerLoans.AssetYieldRouting memory routing) {
        routing.repurchaseRecipientBps = repurchaseBps_;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](0);
    }

    function _directRouting(
        address[] memory recipients_,
        uint16[] memory bps_
    ) internal pure returns (IBurnerLoans.AssetYieldRouting memory routing) {
        uint256 directCount = recipients_.length;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](directCount);
        for (uint256 i; i < directCount; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: recipients_[i],
                bps: bps_[i]
            });
        }
    }
}

// forge-lint: disable-end(calls-loop)
