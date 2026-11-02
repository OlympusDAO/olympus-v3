// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {Actions} from "src/Kernel.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigSetAssetWithdrawAsSharesTest is BurnerLoansConfigTest {
    MockERC20 internal _vaultAsset;
    MockERC4626 internal _vault;

    function setUp() public override {
        super.setUp();
        _vaultAsset = _listingToken(18);
        _vault = new MockERC4626(OZERC20(address(_vaultAsset)), "Vault", "V");
        _registerDepositAsset(_vaultAsset, address(_vault));
        _config.addAsset(address(_vaultAsset), 1, _riskConfig(), _feeConfig(), false);
    }

    function _assertModeSet(address caller_, bool shares_) internal {
        IBurnerLoansCore.AssetConfig memory expected = _config.getAssetConfig(address(_vaultAsset));
        bytes32 fee = keccak256(abi.encode(_config.getAssetFeeConfig(address(_vaultAsset))));
        expected.withdrawAsShares = shares_;
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetWithdrawAsSharesSet(address(_vaultAsset), shares_);
        vm.prank(caller_);
        _config.setAssetWithdrawAsShares(address(_vaultAsset), shares_);
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset)))),
            keccak256(abi.encode(expected)),
            "Only exit mode changes"
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(_vaultAsset)))),
            fee,
            "Fee fields preserved"
        );
        assertEq(
            _core.marketId(address(_vaultAsset)),
            _floan.getMarketCount() - 1,
            "Stable registered market"
        );
    }

    function _asyncVault() internal returns (MockERC20 token, MockERC7540ExternalShareVault vault) {
        token = _listingToken(18);
        vault = new MockERC7540ExternalShareVault(OZERC20(address(token)), false, true, true);
        _registerDepositAsset(token, address(vault));
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-A01, BLCFG-WITHDRAW-SHARES-P02.
    function test_givenAuthorizedCaller_whenSharesEnabled(
        address caller_,
        bool admin_,
        bool operator_
    ) public {
        _grantConfigCaller(caller_, admin_, operator_);
        _assertModeSet(caller_, true);
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        _excludeConfigCallers(caller_);
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-L01.
    function test_givenCoreDisabled_whenSharesChanged_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _core.disable("");
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-L02, BLCFG-WITHDRAW-SHARES-L03.
    function test_givenCoreInactive_whenSharesChanged_reverts(
        bool enabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        if (!enabled_) _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            _inactiveError(address(_core))
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-L04, BLCFG-WITHDRAW-SHARES-L05, BLCFG-WITHDRAW-SHARES-L06, BLCFG-WITHDRAW-SHARES-L07.
    function test_givenConfigActiveDisabled_whenSharesChanged_reverts(
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _config.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-L08, BLCFG-WITHDRAW-SHARES-L09, BLCFG-WITHDRAW-SHARES-L10, BLCFG-WITHDRAW-SHARES-L11.
    function test_givenConfigInactiveEnabled_whenSharesChanged_reverts(
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-L12, BLCFG-WITHDRAW-SHARES-L13, BLCFG-WITHDRAW-SHARES-L14, BLCFG-WITHDRAW-SHARES-L15.
    function test_givenConfigInactiveDisabled_whenSharesChanged_reverts(
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P01.
    function test_givenDirectCustody_whenSharesRequested_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_asset), true)),
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(_asset)
            )
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P03.
    function test_givenSynchronousVaultInShareMode_whenUnderlyingRequested(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _assertModeSet(_configurationCaller, true);
        _assertModeSet(_configurationCaller, false);
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P06.
    function test_givenExplicitShareRequirement_whenSharesEnabled(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _depositManager.setConfigOperator(_configurationCaller);
        vm.prank(_configurationCaller);
        _depositManager.setAssetShareWithdrawalRequired(IERC20(address(_vaultAsset)), true);
        _assertModeSet(_configurationCaller, true);
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P07.
    function test_givenExplicitShareRequirement_whenUnderlyingRequested_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _assertModeSet(_configurationCaller, true);
        _depositManager.setConfigOperator(_configurationCaller);
        vm.prank(_configurationCaller);
        _depositManager.setAssetShareWithdrawalRequired(IERC20(address(_vaultAsset)), true);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), false)),
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(_vaultAsset),
                address(_vault)
            )
        );
        assertTrue(
            _config.getAssetConfig(address(_vaultAsset)).withdrawAsShares,
            "Original shares mode preserved"
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P04.
    function test_givenVaultBecomesAsynchronous_whenSharesRequested(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        (MockERC20 token, MockERC7540ExternalShareVault vault) = _asyncVault();
        vault.setCapabilities(false, false, true, true);
        _config.addAsset(address(token), 1, _riskConfig(), _feeConfig(), false);
        vault.setCapabilities(false, true, true, true);
        vm.prank(_configurationCaller);
        _config.setAssetWithdrawAsShares(address(token), true);
        assertTrue(
            _config.getAssetConfig(address(token)).withdrawAsShares,
            "Async exits use shares"
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P05.
    function test_givenAsyncShareMode_whenUnderlyingRequested_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        (MockERC20 token, MockERC7540ExternalShareVault vault) = _asyncVault();
        _config.addAsset(address(token), 1, _riskConfig(), _feeConfig(), true);
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(token), false)),
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(token),
                address(vault)
            )
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P11.
    function test_givenAsyncVaultBecomesSynchronous_whenUnderlyingRequested(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        (MockERC20 token, MockERC7540ExternalShareVault vault) = _asyncVault();
        _config.addAsset(address(token), 1, _riskConfig(), _feeConfig(), true);
        vault.setCapabilities(false, false, true, true);
        vm.prank(_configurationCaller);
        _config.setAssetWithdrawAsShares(address(token), false);
        assertFalse(
            _config.getAssetConfig(address(token)).withdrawAsShares,
            "Current synchronous mode allows underlying"
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P08.
    function test_givenDepositManagerAssetRemoved_whenModeChanged_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSignature(
                "validateAssetWithdrawAsShares(address,bool)",
                address(_vaultAsset),
                true
            ),
            abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector)
        );
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector)
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P09.
    function test_givenBrokenDepositManagerAndSameUnderlying_whenModeSet(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("depositManager()"),
            hex"deadbeef"
        );
        bytes32 state = keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset))));
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.setAssetWithdrawAsShares(address(_vaultAsset), false);
        assertEq(vm.getRecordedLogs().length, 0, "No-op avoids downstream writes/events");
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset)))),
            state,
            "No-op preserves mode/config"
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-P10.
    function test_givenBrokenDepositManagerAndSameShares_whenModeSet(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _assertModeSet(_configurationCaller, true);
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("depositManager()"),
            hex"deadbeef"
        );
        bytes32 state = keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset))));
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.setAssetWithdrawAsShares(address(_vaultAsset), true);
        assertEq(vm.getRecordedLogs().length, 0, "No-op avoids downstream writes/events");
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset)))),
            state,
            "No-op preserves mode/config"
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-I01.
    function test_whenAssetUnregistered_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(0), true)),
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                address(0)
            )
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-I02.
    function test_givenRegistryWriteFails_whenModeChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        bytes32 beforeConfig = keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset))));
        bytes memory reason = abi.encodeWithSignature("RegistryRejected()");
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.registerMarket.selector),
            reason
        );
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetWithdrawAsShares, (address(_vaultAsset), true)),
            reason
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_vaultAsset)))),
            beforeConfig,
            "FLOAN mode write rolls back"
        );
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-D01.
    function test_whenModeChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketPrincipalCap.selector),
            abi.encodeWithSignature("UnexpectedWrite()")
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketRiskConfig.selector),
            abi.encodeWithSignature("UnexpectedWrite()")
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketBaseFee.selector),
            abi.encodeWithSignature("UnexpectedWrite()")
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketOriginationsEnabled.selector),
            abi.encodeWithSignature("UnexpectedWrite()")
        );
        _assertModeSet(_configurationCaller, true);
    }

    // Scenarios: BLCFG-WITHDRAW-SHARES-A01.
    function test_whenPermittedCallerClassesSeeded() public {
        address adminOnly = makeAddr("adminOnly");
        address overlap = makeAddr("adminAndOperator");
        _rolesAdmin.grantRole(ADMIN_ROLE, adminOnly);
        _assertModeSet(adminOnly, true);
        _assertModeSet(_configurationCaller, false);
        _rolesAdmin.grantRole(ADMIN_ROLE, overlap);
        _config.setConfigOperator(overlap);
        _assertModeSet(overlap, true);
    }
}
