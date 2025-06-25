// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IPolicyEnabler} from "src/policies/interfaces/utils/IPolicyEnabler.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

contract DepositManagerAddAssetTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event AssetConfigured(address indexed asset, address indexed vault, uint256 depositCap);

    // ========== ASSERTIONS ========== //

    function _assertAssetConfiguration(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        bool isConfigured_
    ) internal view {
        // AssetConfiguration
        IAssetManager.AssetConfiguration memory configuration = depositManager
            .getAssetConfiguration(asset_);
        assertEq(
            configuration.isConfigured,
            isConfigured_,
            "AssetConfiguration: isConfigured mismatch"
        );
        assertEq(
            address(configuration.vault),
            address(vault_),
            "AssetConfiguration: vault mismatch"
        );
        assertEq(configuration.depositCap, depositCap_, "AssetConfiguration: depositCap mismatch");

        // getConfiguredAssets
        IERC20[] memory assets = depositManager.getConfiguredAssets();
        if (isConfigured_) {
            assertEq(assets.length, 1, "getConfiguredAssets: assets length mismatch");
            assertEq(
                address(assets[0]),
                address(asset_),
                "getConfiguredAssets: assets[0] mismatch"
            );
        } else {
            assertEq(assets.length, 0, "getConfiguredAssets: assets length mismatch");
        }
    }

    // ========== TESTS ========== //

    // when the caller is not the manager or admin
    //  [X] it reverts

    function test_givenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != MANAGER);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));

        vm.prank(caller_);
        depositManager.addAsset(iAsset, iVault, type(uint256).max);
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IPolicyEnabler.NotEnabled.selector));

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max);
    }

    // when the asset is the zero address
    //  when the vault is the zero address
    //   [X] it reverts
    //  [X] it reverts

    function test_whenAssetIsZeroAddress_whenVaultIsZeroAddress_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_InvalidAsset.selector));

        vm.prank(ADMIN);
        depositManager.addAsset(IERC20(address(0)), IERC4626(address(0)), type(uint256).max);
    }

    function test_whenAssetIsZeroAddress_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_InvalidAsset.selector));

        vm.prank(ADMIN);
        depositManager.addAsset(IERC20(address(0)), iVault, type(uint256).max);
    }

    // given the asset is already configured
    //  given the vault is the zero address
    //   [X] it reverts
    //  [X] it reverts

    function test_givenAssetIsAlreadyConfigured_whenVaultIsZeroAddress_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_AssetAlreadyConfigured.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max);
    }

    function test_givenAssetIsAlreadyConfigured_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
    {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_AssetAlreadyConfigured.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max);
    }

    // when the vault is the zero address
    //  [X] the asset configuration has the vault set to the zero address
    //  [X] the asset configuration is marked as configured
    //  [X] the configured assets array contains the asset
    //  [X] it emits an event

    function test_whenVaultIsZeroAddress() public givenIsEnabled {
        vm.expectEmit(true, true, true, true);
        emit AssetConfigured(address(asset), address(0), type(uint256).max);

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max);

        _assertAssetConfiguration(iAsset, IERC4626(address(0)), type(uint256).max, true);
    }

    // given the vault asset does not match the asset
    //  [X] it reverts

    function test_givenVaultAssetDoesNotMatchAsset_reverts() public givenIsEnabled {
        // Set the vault asset to a different asset
        MockERC20 newAsset = new MockERC20("New Asset", "NEW", 18);
        MockERC4626 newVault = new MockERC4626(ERC20(address(newAsset)), "New Vault", "NEW");

        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_VaultAssetMismatch.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(newVault)), type(uint256).max);
    }

    // [X] the asset configuration has the vault set to the vault address
    // [X] the asset configuration is marked as configured
    // [X] the configured assets array contains the asset
    // [X] it emits an event

    function test_setsAssetVault(uint256 depositCap_) public givenIsEnabled {
        vm.expectEmit(true, true, true, true);
        emit AssetConfigured(address(asset), address(vault), depositCap_);

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, depositCap_);

        _assertAssetConfiguration(iAsset, iVault, depositCap_, true);
    }
}
