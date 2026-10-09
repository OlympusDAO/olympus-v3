// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Test contracts
import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetAssetWithdrawAsSharesTest is BurnerLoansTest {
    function _useAsyncMockVault() internal {
        _useMockDepositManager();
        _configureUsdsVaultDependencies();
        mockDepositManager.setAssetAsyncRedeem(IERC20(address(usds)), true);
    }

    function _useExplicitShareRequiredMockVault() internal {
        _useMockDepositManager();
        _configureUsdsVaultDependencies();
        mockDepositManager.setAssetShareWithdrawalRequired(IERC20(address(usds)), true);
    }

    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        vm.prank(caller_);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
    }

    function test_givenConfigIsDisabled_reverts() public {
        _addDefaultUsdsVaultAsset();
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
    }

    function test_givenIdleAsset_whenEnabling_reverts() public {
        _addDefaultUsdsAsset();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(usds)
            )
        );
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "failed transition should preserve underlying output"
        );
    }

    function test_givenAssetOriginationsDisabled_whenEnablingAndDisabling() public {
        _addDefaultUsdsVaultAsset();
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
        IBurnerLoans.AssetConfig memory shareConfig = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        assertFalse(shareConfig.originationsEnabled, "originations remain disabled");
        assertTrue(shareConfig.withdrawAsShares, "share output enabled while disabled");

        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), false);
        IBurnerLoans.AssetConfig memory assetConfig = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        assertFalse(assetConfig.originationsEnabled, "originations still disabled");
        assertFalse(assetConfig.withdrawAsShares, "underlying output restored while disabled");
    }

    function test_givenVault_whenEnablingAndDisabling() public {
        _addDefaultUsdsVaultAsset();

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit IBurnerLoans.AssetWithdrawAsSharesSet(address(usds), true);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "false-to-true transition should be stored"
        );

        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit IBurnerLoans.AssetWithdrawAsSharesSet(address(usds), false);
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), false);
        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "true-to-false transition should be stored"
        );
    }

    function test_givenAsyncRedeem_whenCurrentModeIsUnderlying_reverts() public {
        _useAsyncMockVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(usds),
                depositManager.getAssetConfiguration(IERC20(address(usds))).vault
            )
        );
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), false);
    }

    function test_givenExplicitShareWithdrawalRequirement_whenCurrentModeIsUnderlying_reverts()
        public
    {
        _useExplicitShareRequiredMockVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(usds),
                depositManager.getAssetConfiguration(IERC20(address(usds))).vault
            )
        );
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), false);
    }

    function test_givenExplicitShareWithdrawalRequirement_whenEnablingShares_succeeds() public {
        _useExplicitShareRequiredMockVault();

        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "explicit requirement should permit share mode"
        );
    }

    function test_givenAsyncRedeem_whenEnablingShares_thenDisabling_reverts() public {
        _useAsyncMockVault();

        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "async vault should permit share output"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(usds),
                depositManager.getAssetConfiguration(IERC20(address(usds))).vault
            )
        );
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), false);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "failed transition should retain share output"
        );
    }

    function test_givenAsyncRedeemReturnsToSync_whenDisablingShares() public {
        _useAsyncMockVault();
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);
        mockDepositManager.setAssetAsyncRedeem(IERC20(address(usds)), false);

        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), false);

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "sync vault should permit underlying output"
        );
    }

    function test_givenConfigIsReEnabled_whenConfigOperatorEnablesShareOutput() public {
        _addDefaultUsdsVaultAsset();
        _setDefaultConfigOperator();
        vm.prank(admin);
        burnerLoansConfig.disable("");
        vm.prank(admin);
        burnerLoansConfig.enable("");

        vm.prank(address(configTimelock));
        burnerLoansConfig.setAssetWithdrawAsShares(address(usds), true);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).withdrawAsShares,
            "config operator transition after re-enable"
        );
    }
}
