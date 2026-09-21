// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.27;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract DepositManagerSetAssetShareWithdrawalRequiredTest is DepositManagerTest {
    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(ADMIN);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
    }

    function test_whenCallerIsNeitherAdminNorConfigOperator_reverts(
        address caller_
    ) public givenIsEnabled {
        vm.assume(caller_ != CONFIG_OPERATOR);
        vm.assume(caller_ != ADMIN);
        _setConfigOperator(CONFIG_OPERATOR);

        _expectRevertNotConfigOperator(caller_);
        vm.prank(caller_);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
    }

    function test_givenAssetIsNotConfigured_reverts(bool required_) public givenIsEnabled {
        _setConfigOperator(CONFIG_OPERATOR);
        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, required_);
    }

    function test_givenIdleAsset_whenRequiredIsTrue_reverts() public givenIsEnabled {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);
        _setConfigOperator(CONFIG_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(iAsset)
            )
        );
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
    }

    function test_givenAsyncRedeemVault_whenRequiredIsFalse_reverts() public givenIsEnabled {
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(vault)), type(uint256).max, 0);
        _setConfigOperator(CONFIG_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(vault)
            )
        );
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, false);
    }

    function test_givenSynchronousVault_whenValidatingRequirement_whenCallerIsFuzzed(
        address caller_,
        bool required_
    ) public givenIsEnabled {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);

        vm.prank(caller_);
        depositManager.validateAssetShareWithdrawalRequired(iAsset, required_);
    }

    function test_givenSynchronousVault_whenCallerIsAdmin_whenRequirementChanges()
        public
        givenIsEnabled
    {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
        _setConfigOperator(CONFIG_OPERATOR);

        vm.expectEmit(address(depositManager));
        emit IAssetManagerV1_1.AssetShareWithdrawalRequirementSet(address(iAsset), true);
        vm.prank(ADMIN);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "admin should enable the explicit requirement"
        );
    }

    function test_givenSynchronousVault_whenCallerIsConfigOperator_whenRequirementChanges()
        public
        givenIsEnabled
    {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
        _setConfigOperator(CONFIG_OPERATOR);

        vm.expectEmit(address(depositManager));
        emit IAssetManagerV1_1.AssetShareWithdrawalRequirementSet(address(iAsset), true);
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "explicit requirement should be enabled"
        );

        vm.expectEmit(address(depositManager));
        emit IAssetManagerV1_1.AssetShareWithdrawalRequirementSet(address(iAsset), false);
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, false);

        assertFalse(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "explicit requirement should be disabled"
        );
    }

    function test_givenVaultChangesFromAsyncToSynchronous_whenRequiredIsFalse()
        public
        givenIsEnabled
    {
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(vault)), type(uint256).max, 0);
        _setConfigOperator(CONFIG_OPERATOR);
        vault.setCapabilities(false, false, true, true);
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, false);

        assertFalse(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "synchronous vault should permit underlying withdrawals"
        );
    }
}
