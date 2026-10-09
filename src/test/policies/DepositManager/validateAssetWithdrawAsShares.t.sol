// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Interfaces
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract DepositManagerValidateAssetWithdrawAsSharesTest is DepositManagerTest {
    MockERC7540ExternalShareVault internal _externalVault;

    function _validate(bool withdrawAsShares_) internal view {
        IAssetManagerV1_1(address(depositManager)).validateAssetWithdrawAsShares(
            iAsset,
            withdrawAsShares_
        );
    }

    function _addVault(IERC4626 vault_) internal {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, vault_, type(uint256).max, 0);
    }

    function _addAsyncRedeemVault() internal {
        _externalVault = new MockERC7540ExternalShareVault(asset, false, true, true);
        _addVault(IERC4626(address(_externalVault)));
    }

    function test_givenAssetIsUnconfigured_reverts(bool withdrawAsShares_) public {
        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        _validate(withdrawAsShares_);
    }

    function test_givenIdleAsset_whenUnderlyingOutput_whenCallerIsFuzzed(address caller_) public {
        vm.prank(ADMIN);
        depositManager.enable("");
        _addVault(IERC4626(address(0)));

        vm.prank(caller_);
        _validate(false);
    }

    function test_givenIdleAsset_whenWithdrawAsSharesIsTrue_reverts() public givenIsEnabled {
        _addVault(IERC4626(address(0)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(iAsset)
            )
        );
        _validate(true);
    }

    function test_givenSynchronousVault_whenUnderlyingOutput_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled {
        _addVault(iVault);

        vm.prank(caller_);
        _validate(false);
    }

    function test_givenSynchronousVault_whenShareOutput_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled {
        _addVault(iVault);

        vm.prank(caller_);
        _validate(true);
    }

    function test_givenAsyncRedeemVault_whenUnderlyingOutput_reverts() public givenIsEnabled {
        _addAsyncRedeemVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(_externalVault)
            )
        );
        _validate(false);
    }

    function test_givenAsyncRedeemVault_whenShareOutput_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled {
        _addAsyncRedeemVault();

        vm.prank(caller_);
        _validate(true);
    }

    function test_givenAsyncRedeemVault_givenContractIsDisabled_whenShareOutput_succeeds()
        public
        givenIsEnabled
    {
        _addAsyncRedeemVault();
        vm.prank(ADMIN);
        depositManager.disable("");

        _validate(true);
    }

    function test_givenAsyncRedeemVault_givenContractIsDisabled_whenUnderlyingOutput_reverts()
        public
        givenIsEnabled
    {
        _addAsyncRedeemVault();
        vm.prank(ADMIN);
        depositManager.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(_externalVault)
            )
        );
        _validate(false);
    }

    function test_givenAsyncRedeemBecomesSynchronous_whenUnderlyingOutput_succeeds()
        public
        givenIsEnabled
    {
        _addAsyncRedeemVault();
        _externalVault.setCapabilities(false, false, true, true);

        _validate(false);
    }

    function test_givenSynchronousRedeemBecomesAsync_whenUnderlyingOutput_reverts()
        public
        givenIsEnabled
    {
        _externalVault = new MockERC7540ExternalShareVault(asset, false, false, true);
        _addVault(IERC4626(address(_externalVault)));
        _externalVault.setCapabilities(false, true, true, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(_externalVault)
            )
        );
        _validate(false);
    }
}
