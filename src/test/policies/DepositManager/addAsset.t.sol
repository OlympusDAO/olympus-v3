// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Vault variants exercise the same onboarding action and are intentionally co-located.
// Scenario-specific literals and ignored revert-path return values remain explicit.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IERC7540Deposit, IERC7540Operator, IERC7540Redeem} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7540.sol";
import {IERC7575} from "@openzeppelin-community-contracts-0.0.1/interfaces/IERC7575.sol";
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ERC7540SyncDepositAsyncRedeemVault} from "src/test/policies/DepositManager/fixtures/ERC7540SyncDepositAsyncRedeemVault.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault, MockIncompatibleShareToken, MockRevertingShareToken, MockSharedERC7575ShareToken, MockSharedERC7575Vault} from "src/test/policies/DepositManager/fixtures/MockERC7575Vault.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerAddAssetTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event AssetConfigured(address indexed asset, address indexed vault);

    // ========== ASSERTIONS ========== //

    function _assertAssetConfiguration(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_,
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
        assertEq(
            configuration.minimumDeposit,
            minimumDeposit_,
            "AssetConfiguration: minimumDeposit mismatch"
        );

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

        if (isConfigured_) _assertShareWithdrawalRequired(false);
    }

    function _assertShareWithdrawalRequired(bool expected_) internal view {
        assertEq(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            expected_,
            "share withdrawal requirement mismatch"
        );
    }

    // ========== TESTS ========== //

    // when the caller is not admin
    //  [X] it reverts

    function test_whenCallerIsNotAdmin_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN);

        _expectRevertNotAdmin();

        vm.prank(caller_);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
    }

    function test_givenConfigOperator_whenAddingAsset_reverts() public givenIsEnabled {
        _setConfigOperator(CONFIG_OPERATOR);

        _expectRevertNotAdmin();
        vm.prank(CONFIG_OPERATOR);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
    }

    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
    }

    // when the asset is the zero address
    //  when the vault is the zero address
    //   [X] it reverts
    //  [X] it reverts

    function test_whenAssetIsZeroAddress_whenVaultIsZeroAddress_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_InvalidAsset.selector));

        vm.prank(ADMIN);
        depositManager.addAsset(IERC20(address(0)), IERC4626(address(0)), type(uint256).max, 0);
    }

    function test_whenAssetIsZeroAddress_reverts() public givenIsEnabled {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_InvalidAsset.selector));

        vm.prank(ADMIN);
        depositManager.addAsset(IERC20(address(0)), iVault, type(uint256).max, 0);
    }

    // given the asset is already configured
    //  given the vault is the zero address
    //   [X] it reverts
    //  [X] it reverts

    function test_givenAssetIsAlreadyConfigured_whenVaultIsZeroAddress_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_AssetAlreadyConfigured.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);
    }

    function test_givenAssetIsAlreadyConfigured_reverts() public givenIsEnabled givenAssetIsAdded {
        vm.expectRevert(
            abi.encodeWithSelector(IAssetManager.AssetManager_AssetAlreadyConfigured.selector)
        );

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, 0);
    }

    // when the vault is the zero address
    //  [X] the asset configuration has the vault set to the zero address
    //  [X] the asset configuration is marked as configured
    //  [X] the configured assets array contains the asset
    //  [X] it emits an event

    function test_whenVaultIsZeroAddress() public givenIsEnabled {
        vm.expectEmit(true, true, true, true);
        emit AssetConfigured(address(asset), address(0));

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);

        _assertAssetConfiguration(iAsset, IERC4626(address(0)), type(uint256).max, 0, true);
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
        depositManager.addAsset(iAsset, IERC4626(address(newVault)), type(uint256).max, 0);
    }

    // [X] the asset configuration has the vault set to the vault address
    // [X] the asset configuration is marked as configured
    // [X] the configured assets array contains the asset
    // [X] it emits an event

    function test_setsAssetVault(
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) public givenIsEnabled {
        // Bound values to ensure minimumDeposit_ <= depositCap_
        depositCap_ = bound(depositCap_, 0, type(uint128).max);
        minimumDeposit_ = bound(minimumDeposit_, 0, depositCap_);

        vm.expectEmit(true, true, true, true);
        emit AssetConfigured(address(asset), address(vault));

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, depositCap_, minimumDeposit_);

        _assertAssetConfiguration(iAsset, iVault, depositCap_, minimumDeposit_, true);
    }

    // when minimum deposit exceeds deposit cap
    //  [X] it reverts

    function test_whenMinimumDepositExceedsDepositCap_reverts(
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) public givenIsEnabled {
        depositCap_ = bound(depositCap_, 0, type(uint128).max - 1);
        minimumDeposit_ = bound(minimumDeposit_, depositCap_ + 1, type(uint128).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositExceedsDepositCap.selector,
                address(iAsset),
                minimumDeposit_,
                depositCap_
            )
        );

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, depositCap_, minimumDeposit_);
    }

    // when deposit cap equals minimum deposit
    //  [X] it succeeds

    function test_whenDepositCapEqualsMinimumDeposit_succeeds(
        uint256 amount_
    ) public givenIsEnabled {
        amount_ = bound(amount_, 1, type(uint128).max);

        vm.expectEmit(true, true, true, true);
        emit AssetConfigured(address(asset), address(vault));

        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, amount_, amount_);

        _assertAssetConfiguration(iAsset, iVault, amount_, amount_, true);
    }

    // ========== ERC-7540 AND ERC-7575 TESTS ========== //

    uint256 internal constant _PREVIEW_AMOUNT = 1e18;

    event AssetDepositCapSet(address indexed asset, uint256 depositCap);
    event AssetMinimumDepositSet(address indexed asset, uint256 minimumDeposit);

    function _addVault(IERC4626 vault_) internal {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, vault_, type(uint256).max, 0);
    }

    function _assertAssetIsUnconfigured() internal view {
        IAssetManager.AssetConfiguration memory configuration = depositManager
            .getAssetConfiguration(iAsset);
        assertFalse(configuration.isConfigured, "asset should remain unconfigured");
        assertEq(configuration.vault, address(0), "vault should remain unset");
        assertEq(
            depositManager.getConfiguredAssets().length,
            0,
            "configured assets should remain empty"
        );
    }

    function test_givenStandardsInterfaces_interfaceIdsMatchPublishedValues() public pure {
        bytes4 erc7575VaultInterfaceId = type(IERC4626).interfaceId ^ type(IERC7575).interfaceId;

        assertEq(erc7575VaultInterfaceId, bytes4(0x2f0a18c5), "ERC-7575 vault interface ID");
        assertEq(
            type(IERC7540Redeem).interfaceId,
            bytes4(0x620ee8e4),
            "ERC-7540 redeem interface ID"
        );
        assertEq(
            type(IERC7540Deposit).interfaceId,
            bytes4(0xce3bbe50),
            "ERC-7540 deposit interface ID"
        );
        assertEq(
            type(IERC7540Operator).interfaceId,
            bytes4(0xe3bc4e65),
            "ERC-7540 operator interface ID"
        );
    }

    function test_whenAssetIsUnconfigured_whenCallerIsFuzzed(
        address caller_,
        bool withdrawAsShares_
    ) public {
        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        vm.prank(caller_);
        depositManager.getAssetWithdrawalToken(iAsset, withdrawAsShares_);
    }

    function test_whenAssetIsZeroAddress_reverts(bool withdrawAsShares_) public {
        vm.expectRevert(IAssetManager.AssetManager_NotConfigured.selector);
        depositManager.getAssetWithdrawalToken(IERC20(address(0)), withdrawAsShares_);
    }

    function test_givenIdleCustody_whenWithdrawAsSharesIsFalse() public givenIsEnabled {
        _addVault(IERC4626(address(0)));
        _assertShareWithdrawalRequired(false);

        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, false)),
            address(iAsset),
            "idle custody should withdraw the underlying token"
        );
    }

    function test_givenIdleCustody_whenWithdrawAsSharesIsTrue_reverts() public givenIsEnabled {
        _addVault(IERC4626(address(0)));
        _assertShareWithdrawalRequired(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(iAsset)
            )
        );
        depositManager.getAssetWithdrawalToken(iAsset, true);
    }

    function test_givenNonERC165ERC4626Vault_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled {
        vm.expectEmit(true, true, true, true);
        emit AssetConfigured(address(iAsset), address(iVault));
        vm.expectEmit(true, true, true, true);
        emit AssetDepositCapSet(address(iAsset), type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit AssetMinimumDepositSet(address(iAsset), 0);
        vm.expectEmit(true, true, true, true);
        emit IAssetManagerV1_1.AssetShareTokenConfigured(address(iAsset), address(iVault));

        _addVault(iVault);
        _assertShareWithdrawalRequired(false);

        vm.startPrank(caller_);
        IERC20 underlyingToken = depositManager.getAssetWithdrawalToken(iAsset, false);
        IERC20 shareToken = depositManager.getAssetWithdrawalToken(iAsset, true);
        bool shareWithdrawalRequired = depositManager.isAssetShareWithdrawalRequired(iAsset);
        vm.stopPrank();
        assertEq(address(underlyingToken), address(iAsset), "underlying withdrawal token");
        assertEq(address(shareToken), address(iVault), "share withdrawal token");
        assertFalse(shareWithdrawalRequired, "synchronous vault requirement");
    }

    function test_givenConfiguredVault_givenContractIsDisabled_whenCallerIsFuzzed(
        address caller_
    ) public givenIsEnabled {
        _addVault(iVault);
        _assertShareWithdrawalRequired(false);
        vm.prank(ADMIN);
        depositManager.disable("");

        vm.prank(caller_);
        IERC20 shareToken = depositManager.getAssetWithdrawalToken(iAsset, true);

        assertEq(
            address(shareToken),
            address(iVault),
            "disabled contract should expose its stored share token"
        );
    }

    function test_givenERC7575SelfShareVault() public givenIsEnabled {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, false);

        _addVault(IERC4626(address(erc7575Vault)));
        _assertShareWithdrawalRequired(false);

        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            address(erc7575Vault),
            "ERC-7575 self-share vault should custody the vault token"
        );
        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, false)),
            address(iAsset),
            "synchronous self-share vault should support underlying output"
        );
    }

    function test_givenSynchronousERC7575ExternalShareVault() public givenIsEnabled {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);

        _addVault(IERC4626(address(erc7575Vault)));
        _assertShareWithdrawalRequired(false);

        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            erc7575Vault.share(),
            "ERC-7575 vault should custody its external share token"
        );
        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, false)),
            address(iAsset),
            "synchronous external-share vault should support underlying output"
        );
    }

    function test_givenCommunitySyncDepositAsyncRedeemVault() public givenIsEnabled {
        ERC7540SyncDepositAsyncRedeemVault erc7540Vault = new ERC7540SyncDepositAsyncRedeemVault(
            OZIERC20(address(asset))
        );

        _addVault(IERC4626(address(erc7540Vault)));
        _assertShareWithdrawalRequired(true);

        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            address(erc7540Vault),
            "community ERC-7540 fixture should custody self-shares"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(erc7540Vault)
            )
        );
        depositManager.validateAssetWithdrawAsShares(iAsset, false);
    }

    function test_givenSynchronousVault_whenExplicitShareWithdrawalIsRequired()
        public
        givenIsEnabled
    {
        vm.prank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            true
        );

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "explicit requirement should be stored"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(iVault)
            )
        );
        depositManager.validateAssetWithdrawAsShares(iAsset, false);
    }

    function test_givenSynchronousVault_whenExplicitShareWithdrawalIsNotRequired()
        public
        givenIsEnabled
    {
        vm.prank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            false
        );

        _assertShareWithdrawalRequired(false);
        depositManager.validateAssetWithdrawAsShares(iAsset, false);
    }

    function test_whenCallerIsNotAdmin_whenShareWithdrawalRequirementIsSpecified_reverts(
        address caller_,
        bool requiresShareWithdrawal_
    ) public givenIsEnabled {
        vm.assume(caller_ != ADMIN);

        _expectRevertNotAdmin();
        vm.prank(caller_);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            requiresShareWithdrawal_
        );
    }

    function test_givenContractIsDisabled_whenShareWithdrawalRequirementIsSpecified_reverts(
        bool requiresShareWithdrawal_
    ) public {
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            requiresShareWithdrawal_
        );
    }

    function test_givenContractIsReEnabled_whenShareWithdrawalRequirementIsSpecified(
        bool requiresShareWithdrawal_
    ) public givenIsEnabled {
        vm.startPrank(ADMIN);
        depositManager.disable("");
        depositManager.reEnable();
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            iVault,
            type(uint256).max,
            0,
            requiresShareWithdrawal_
        );
        vm.stopPrank();

        assertTrue(
            depositManager.getAssetConfiguration(iAsset).isConfigured,
            "re-enabled contract should configure asset"
        );
        _assertShareWithdrawalRequired(requiresShareWithdrawal_);
    }

    function test_givenIdleAsset_whenExplicitShareWithdrawalIsRequired_reverts()
        public
        givenIsEnabled
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(iAsset)
            )
        );
        vm.prank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            IERC4626(address(0)),
            type(uint256).max,
            0,
            true
        );

        _assertAssetIsUnconfigured();
    }

    function test_givenAsyncRedeemVault_whenExplicitShareWithdrawalIsFalse_reverts()
        public
        givenIsEnabled
    {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(erc7540Vault)
            )
        );
        vm.prank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            IERC4626(address(erc7540Vault)),
            type(uint256).max,
            0,
            false
        );

        _assertAssetIsUnconfigured();
    }

    function test_givenAsyncRedeemVault_whenExplicitShareWithdrawalIsTrue_succeeds()
        public
        givenIsEnabled
    {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );

        vm.prank(ADMIN);
        IDepositManagerV1_1(address(depositManager)).addAsset(
            iAsset,
            IERC4626(address(erc7540Vault)),
            type(uint256).max,
            0,
            true
        );

        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "async redemption should require share withdrawal"
        );
        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            erc7540Vault.share(),
            "async vault withdrawal token"
        );
    }

    function test_givenAsyncRedeemExternalShareVault() public givenIsEnabled {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );

        _addVault(IERC4626(address(erc7540Vault)));
        _assertShareWithdrawalRequired(true);

        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            erc7540Vault.share(),
            "async-redeem vault should custody its external share token"
        );
    }

    function test_givenAsyncDepositOnlyVault_reverts() public givenIsEnabled {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            true,
            false,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidVaultCapabilities.selector,
                address(iAsset),
                address(erc7540Vault)
            )
        );
        _addVault(IERC4626(address(erc7540Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenFullyAsyncVault_reverts() public givenIsEnabled {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            true,
            true,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidVaultCapabilities.selector,
                address(iAsset),
                address(erc7540Vault)
            )
        );
        _addVault(IERC4626(address(erc7540Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenAsyncRedeemVault_givenOperatorInterfaceMissing_reverts()
        public
        givenIsEnabled
    {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        erc7540Vault.setCapabilities(false, true, false, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidVaultCapabilities.selector,
                address(iAsset),
                address(erc7540Vault)
            )
        );
        _addVault(IERC4626(address(erc7540Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenAsyncRedeemVault_givenERC7575InterfaceMissing_reverts()
        public
        givenIsEnabled
    {
        MockERC7540ExternalShareVault erc7540Vault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        erc7540Vault.setCapabilities(false, true, true, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidVaultCapabilities.selector,
                address(iAsset),
                address(erc7540Vault)
            )
        );
        _addVault(IERC4626(address(erc7540Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenERC7575Vault_whenShareTokenIsZero_reverts() public givenIsEnabled {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);
        erc7575Vault.setReportedShare(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidShareToken.selector,
                address(iAsset),
                address(0)
            )
        );
        _addVault(IERC4626(address(erc7575Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenERC7575Vault_whenShareTokenIsEOA_reverts() public givenIsEnabled {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);
        address eoaShareToken = makeAddr("eoaShareToken");
        erc7575Vault.setReportedShare(eoaShareToken);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidShareToken.selector,
                address(iAsset),
                eoaShareToken
            )
        );
        _addVault(IERC4626(address(erc7575Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenERC7575Vault_whenShareQueryReverts_reverts() public givenIsEnabled {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);
        erc7575Vault.setShareQueryReverts(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidShareToken.selector,
                address(iAsset),
                address(0)
            )
        );
        _addVault(IERC4626(address(erc7575Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenERC7575Vault_whenShareTokenBalanceQueryReverts_reverts()
        public
        givenIsEnabled
    {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);
        MockRevertingShareToken revertingShareToken = new MockRevertingShareToken();
        erc7575Vault.setReportedShare(address(revertingShareToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidShareToken.selector,
                address(iAsset),
                address(revertingShareToken)
            )
        );
        _addVault(IERC4626(address(erc7575Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenERC7575Vault_whenShareTokenIsIncompatible_reverts() public givenIsEnabled {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);
        MockIncompatibleShareToken incompatibleShareToken = new MockIncompatibleShareToken();
        erc7575Vault.setReportedShare(address(incompatibleShareToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InvalidShareToken.selector,
                address(iAsset),
                address(incompatibleShareToken)
            )
        );
        _addVault(IERC4626(address(erc7575Vault)));

        _assertAssetIsUnconfigured();
    }

    function test_givenConfiguredERC7575Vault_whenReportedShareChanges_usesStoredShareToken()
        public
        givenIsEnabled
    {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, true);
        address configuredShareToken = erc7575Vault.share();
        _addVault(IERC4626(address(erc7575Vault)));
        _assertShareWithdrawalRequired(false);

        erc7575Vault.setReportedShare(makeAddr("replacementShareToken"));
        (IERC20 tokenOut, uint256 amountOut) = depositManager.previewWithdraw(
            iAsset,
            _PREVIEW_AMOUNT,
            true
        );
        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            configuredShareToken,
            "stored share token should remain immutable"
        );
        assertEq(address(tokenOut), configuredShareToken, "preview should use stored share token");
        assertEq(amountOut, _PREVIEW_AMOUNT, "preview should return converted shares");
    }

    function test_givenExternalShareTokenIsAlreadyManaged_whenAddingSecondVault_reverts()
        public
        givenIsEnabled
    {
        MockERC20 secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        MockSharedERC7575ShareToken shareToken = new MockSharedERC7575ShareToken();
        MockSharedERC7575Vault firstVault = new MockSharedERC7575Vault(asset, shareToken);
        MockSharedERC7575Vault secondVault = new MockSharedERC7575Vault(
            ERC20(address(secondAsset)),
            shareToken
        );

        _addVault(IERC4626(address(firstVault)));
        _assertShareWithdrawalRequired(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_TokenAlreadyManaged.selector,
                address(shareToken)
            )
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );
    }

    function test_givenVaultIsUnderlyingAsset_givenSelfShareToken_reverts() public givenIsEnabled {
        MockERC7575Vault selfUnderlyingVault = new MockERC7575Vault(asset, false);
        vm.mockCall(
            address(selfUnderlyingVault),
            abi.encodeCall(IERC4626.asset, ()),
            abi.encode(address(selfUnderlyingVault))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_TokenAlreadyManaged.selector,
                address(selfUnderlyingVault)
            )
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(selfUnderlyingVault)),
            IERC4626(address(selfUnderlyingVault)),
            type(uint256).max,
            0
        );

        _assertAssetIsUnconfigured();
    }

    function test_givenVaultIsUnderlyingAsset_givenExternalShareToken_reverts()
        public
        givenIsEnabled
    {
        MockERC7575Vault selfUnderlyingVault = new MockERC7575Vault(asset, true);
        vm.mockCall(
            address(selfUnderlyingVault),
            abi.encodeCall(IERC4626.asset, ()),
            abi.encode(address(selfUnderlyingVault))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_TokenAlreadyManaged.selector,
                address(selfUnderlyingVault)
            )
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(selfUnderlyingVault)),
            IERC4626(address(selfUnderlyingVault)),
            type(uint256).max,
            0
        );

        _assertAssetIsUnconfigured();
    }

    function test_givenExternalShareTokenIsManaged_whenAddingItAsAnIdleAsset_reverts()
        public
        givenIsEnabled
    {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            false,
            true
        );
        _addVault(IERC4626(address(externalVault)));
        _assertShareWithdrawalRequired(false);
        address shareToken = externalVault.share();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_TokenAlreadyManaged.selector,
                shareToken
            )
        );
        vm.prank(ADMIN);
        depositManager.addAsset(IERC20(shareToken), IERC4626(address(0)), type(uint256).max, 0);
    }

    function test_givenConfiguredAsset_whenAddingItAsAnExternalShareToken_reverts()
        public
        givenIsEnabled
    {
        _addVault(IERC4626(address(0)));
        _assertShareWithdrawalRequired(false);
        MockERC20 secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        MockERC7575Vault secondVault = new MockERC7575Vault(ERC20(address(secondAsset)), true);
        secondVault.setReportedShare(address(iAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_TokenAlreadyManaged.selector,
                address(iAsset)
            )
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );
    }

    function test_givenConfiguredVault_whenAddingItAsAnExternalShareToken_reverts()
        public
        givenIsEnabled
    {
        _addVault(iVault);
        _assertShareWithdrawalRequired(false);
        MockERC20 secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        MockERC7575Vault secondVault = new MockERC7575Vault(ERC20(address(secondAsset)), true);
        secondVault.setReportedShare(address(iVault));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_TokenAlreadyManaged.selector,
                address(iVault)
            )
        );
        vm.prank(ADMIN);
        depositManager.addAsset(
            IERC20(address(secondAsset)),
            IERC4626(address(secondVault)),
            type(uint256).max,
            0
        );
    }
}
// forge-lint: disable-end(literal-instead-of-constant, unused-return)
