// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IPolicyEnabler} from "src/policies/interfaces/utils/IPolicyEnabler.sol";
import {uint2str} from "src/libraries/Uint2str.sol";
import {String} from "src/libraries/String.sol";

contract DepositManagerConfigureDepositTest is DepositManagerTest {
    // ========== ASSERTIONS ========== //

    function assertReceiptTokenConfigured(
        uint256 tokenId_,
        IERC20 asset_,
        uint8 depositPeriod_
    ) internal {
        // Check name
        string memory expectedName = String.truncate32(
            string.concat(asset_.name(), " Receipt - ", uint2str(depositPeriod_), " months")
        );
        assertEq(
            depositManager.getReceiptTokenName(tokenId_),
            expectedName,
            "Receipt token name does not match expected format"
        );

        // Check symbol
        string memory expectedSymbol = String.truncate32(
            string.concat("r", asset_.symbol(), "-", uint2str(depositPeriod_), "m")
        );
        assertEq(
            depositManager.getReceiptTokenSymbol(tokenId_),
            expectedSymbol,
            "Receipt token symbol does not match expected format"
        );

        // Check decimals
        assertEq(
            depositManager.getReceiptTokenDecimals(tokenId_),
            asset_.decimals(),
            "Receipt token decimals do not match asset decimals"
        );

        // Check owner
        assertEq(
            depositManager.getReceiptTokenOwner(tokenId_),
            address(depositManager),
            "Receipt token owner is not the deposit manager"
        );

        // Check asset
        IERC20 asset = depositManager.getReceiptTokenAsset(tokenId_);
        assertEq(
            address(asset),
            address(asset_),
            "Receipt token asset does not match expected asset"
        );

        // Check deposit period
        uint8 depositPeriod = depositManager.getReceiptTokenDepositPeriod(tokenId_);
        assertEq(
            depositPeriod,
            depositPeriod_,
            "Receipt token deposit period does not match expected period"
        );

        // Check asset and deposit period
        (IERC20 receiptTokenIdAsset, uint8 receiptTokenIdDepositPeriod) = depositManager
            .getAssetFromReceiptTokenId(tokenId_);
        assertEq(
            address(receiptTokenIdAsset),
            address(asset_),
            "Asset for token id does not match expected asset"
        );
        assertEq(
            receiptTokenIdDepositPeriod,
            depositPeriod_,
            "Deposit period for token id does not match expected period"
        );
    }

    function assertAssetConfigured(
        address asset_,
        address vault_,
        uint8 depositPeriod_,
        uint256 reclaimRate_
    ) internal {
        // Check if asset is configured
        assertTrue(
            depositManager.isDepositAsset(IERC20(asset_), depositPeriod_),
            "Asset is not configured as a deposit asset"
        );

        // Check asset configuration
        IAssetManager.AssetConfiguration memory configuration = depositManager
            .getAssetConfiguration(IERC20(asset_));
        assertTrue(configuration.isConfigured, "Asset configuration is not marked as configured");
        assertEq(address(configuration.vault), vault_, "Asset vault does not match expected vault");

        // Check deposit configuration
        (IERC20 asset, uint8 depositPeriod) = depositManager.getAssetFromReceiptTokenId(
            depositManager.getReceiptTokenId(IERC20(asset_), depositPeriod_)
        );
        assertEq(address(asset), asset_, "Asset does not match expected asset");
        assertEq(depositPeriod, depositPeriod_, "Deposit period does not match expected period");

        // Check all deposit assets
        IDepositManager.DepositConfiguration[] memory depositAssets = depositManager
            .getDepositAssets();
        bool found = false;
        for (uint256 i; i < depositAssets.length; ++i) {
            if (
                address(depositAssets[i].asset) == asset_ &&
                depositAssets[i].depositPeriod == depositPeriod_
            ) {
                found = true;
                assertEq(
                    depositAssets[i].reclaimRate,
                    reclaimRate_,
                    "Deposit reclaim rate does not match expected rate"
                );
                break;
            }
        }
        assertTrue(found, "Asset not found in deposit assets");
    }

    // ========== TESTS ========== //

    // when the caller is not the manager or admin
    //  [X] it reverts
    function test_whenCallerIsNotManagerOrAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_OPERATOR);

        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));

        vm.prank(caller_);
        depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );
    }

    // given the policy is disabled
    //  [X] it reverts
    function test_givenPolicyIsDisabled_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IPolicyEnabler.NotEnabled.selector));

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );
    }

    // given the asset is already configured with the same deposit period
    //  [X] it reverts
    function test_givenAssetIsAlreadyConfiguredWithSameDepositPeriod_reverts()
        public
        givenIsEnabled
        givenAssetIsConfigured(address(vault))
    {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_VaultAlreadySet.selector)
        );

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );
    }

    // when the asset address is the zero address
    //  when the vault address is the zero address
    //   [X] it reverts
    function test_whenAssetAddressIsZero_whenVaultAddressIsZero_reverts() public givenIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_VaultAssetMismatch.selector)
        );

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(0)),
            IERC4626(address(0)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );
    }

    //  [X] it reverts
    function test_whenAssetAddressIsZero_reverts() public givenIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_VaultAssetMismatch.selector)
        );

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(0)),
            IERC4626(address(vault)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );
    }

    // when the deposit period is 0
    //  [X] it reverts
    function test_whenDepositPeriodIsZero_reverts() public givenIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            0,
            RECLAIM_RATE
        );
    }

    // when the vault and asset do not match
    //  [X] it reverts
    function test_whenVaultAndAssetDoNotMatch_reverts() public givenIsEnabled {
        MockERC20 differentAsset = new MockERC20("Different Asset", "DIFF", 18);
        MockERC4626 differentVault = new MockERC4626(
            ERC20(address(differentAsset)),
            "Different Vault",
            "DIFF"
        );

        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_VaultAssetMismatch.selector)
        );

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(differentVault)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );
    }

    // when the reclaim rate is greater than 100%
    //  [X] it reverts
    function test_whenReclaimRateIsGreaterThan100Percent_reverts() public givenIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_OutOfBounds.selector)
        );

        vm.prank(ADMIN);
        depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            DEPOSIT_PERIOD,
            100e2 + 1
        );
    }

    // given the asset is already configured with a different deposit period
    //  [X] the asset configuration has the vault set to the vault address
    //  [X] the asset is recorded as configured
    //  [X] the deposit configuration is recorded with the derived receipt token ID
    //  [X] the deposit configuration has the reclaim rate set
    //  [X] the deposit reclaim rate is set
    //  [X] the receipt token has the name set
    //  [X] the receipt token has the symbol set
    //  [X] the receipt token has the decimals set
    //  [X] the receipt token has the owner set
    //  [X] the receipt token has the asset set
    //  [X] the receipt token has the deposit period set
    //  [X] the returned receipt token ID matches
    //  [X] the deposit configuration is returned for the receipt token ID
    //  [X] the asset and deposit period is recognised as a deposit asset
    function test_givenAssetIsAlreadyConfiguredWithDifferentDepositPeriod()
        public
        givenIsEnabled
        givenAssetIsConfigured(address(vault))
    {
        uint8 newDepositPeriod = DEPOSIT_PERIOD + 1;

        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            newDepositPeriod,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), address(vault), newDepositPeriod, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(receiptTokenId, IERC20(address(asset)), newDepositPeriod);
    }

    // when the vault is the zero address
    //  [X] the asset configuration has the vault set to the zero address
    function test_whenVaultIsZeroAddress_configuresAsset() public givenIsEnabled {
        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(0)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), address(0), DEPOSIT_PERIOD, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(receiptTokenId, IERC20(address(asset)), DEPOSIT_PERIOD);
    }

    // [X] the asset configuration has the vault set to the vault address
    // [X] the asset is recorded as configured
    // [X] the deposit configuration is recorded with the derived receipt token ID
    // [X] the deposit configuration has the reclaim rate set
    // [X] the deposit reclaim rate is set
    // [X] the receipt token has the name set
    // [X] the receipt token has the symbol set
    // [X] the receipt token has the decimals set
    // [X] the receipt token has the owner set
    // [X] the receipt token has the asset set
    // [X] the receipt token has the deposit period set
    // [X] the returned receipt token ID matches
    // [X] the deposit configuration is returned for the receipt token ID
    // [X] the asset and deposit period is recognised as a deposit asset
    function test_configuresAsset() public givenIsEnabled {
        vm.prank(ADMIN);
        uint256 receiptTokenId = depositManager.configureDeposit(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            DEPOSIT_PERIOD,
            RECLAIM_RATE
        );

        // Check asset configuration
        assertAssetConfigured(address(asset), address(vault), DEPOSIT_PERIOD, RECLAIM_RATE);

        // Check receipt token configuration
        assertReceiptTokenConfigured(receiptTokenId, IERC20(address(asset)), DEPOSIT_PERIOD);
    }
}
