// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Actions} from "src/Kernel.sol";

import {BurnerLoansTest} from "../BurnerLoansTest.sol";
import {MockYieldRecipient} from "./MockYieldRecipient.sol";

abstract contract BurnerLoansYieldRoutingTestBase is BurnerLoansTest {
    MockYieldRecipient internal yieldRecipient;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);
        yieldRecipient = new MockYieldRecipient(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(yieldRecipient));
        vm.stopPrank();
    }

    function _configureYieldRecipientAsset(address asset_, address vault_) internal {
        yieldRecipient.setVaultConfig(vault_, asset_, true);
    }

    function _setYieldRecipient(address recipient_) internal {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setYieldRecipient(recipient_);
    }

    function _setYieldRecipientAssetBps(address asset_, uint16 bps_) internal {
        vm.prank(address(burnerLoansConfig));
        burnerLoans.setYieldRecipientAssetBps(asset_, bps_);
    }

    function _configureDefaultUsdsYieldRecipient() internal {
        _addDefaultUsdsAsset();
        _configureYieldRecipientAsset(address(usds), address(0));
        _setYieldRecipient(address(yieldRecipient));
    }

    function _addYieldAsset() internal returns (MockERC20 asset, MockERC4626 vault) {
        (asset, vault) = _addVaultAssetForTest();
        _configureYieldRecipientAsset(address(asset), address(vault));
    }
}
