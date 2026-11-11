// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions, Module, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigSetAssetDebtCapTest is BurnerLoansConfigTest {
    // Scenarios: BLCFG-DEBT-CAP-P05.
    function test_givenCoreBusy_whenUnauthorizedSetsUnchangedCap_reverts(
        bool active_,
        bool enabled_
    ) public {
        address caller = makeAddr("busyConfigOutsider");
        _excludeConfigCallers(caller);
        uint128 cap = _config.getAssetConfig(address(_asset)).debtCap;
        _setPolicyState(_config, active_, enabled_);
        bytes memory reason = abi.encodeWithSelector(
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeCall(IBurnerLoansCore.requireNotReentrant, ()),
            reason
        );
        _mutationReverts(caller, _capCall(cap), reason);
    }

    function _assertCapSet(address caller_, uint128 cap_) internal {
        _validationSucceeds(_recipient, _capValidation(cap_));
        IBurnerLoansCore.AssetConfig memory expected = _config.getAssetConfig(address(_asset));
        bytes32 fee = keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset))));
        uint128 globalCap = _inventory.globalDebtCapOhm();
        expected.debtCap = cap_;
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetDebtCapSet(address(_asset), cap_);
        vm.prank(caller_);
        _config.setAssetDebtCap(address(_asset), cap_);
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_asset)))),
            keccak256(abi.encode(expected)),
            "Only asset cap changes"
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset)))),
            fee,
            "Fee curve preserved"
        );
        assertEq(_inventory.globalDebtCapOhm(), globalCap, "Global cap unchanged");
        assertEq(_core.marketId(address(_asset)), _market, "Stable Core registry");
    }

    // Scenarios: BLCFG-DEBT-CAP-A01, BLCFG-DEBT-CAP-N01.
    function test_givenAuthorizedCaller_whenCapChanged(
        address caller_,
        bool admin_,
        bool operator_,
        uint128 cap_
    ) public {
        _grantConfigCaller(caller_, admin_, operator_);
        vm.assume(cap_ != _config.getAssetConfig(address(_asset)).debtCap);
        _assertCapSet(caller_, cap_);
    }

    // Scenarios: BLCFG-DEBT-CAP-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        _excludeConfigCallers(caller_);
        _mutationReverts(
            caller_,
            _capCall(1),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _validationSucceeds(caller_, _capValidation(1));
    }

    // Scenarios: BLCFG-DEBT-CAP-L01.
    function test_givenIndependentCoreState_whenCapChanged(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        _setPolicyState(_core, active_, enabled_);
        _assertCapSet(_configurationCaller, 1);
        _validationSucceeds(caller_, _capValidation(1));
    }

    // Scenarios: BLCFG-DEBT-CAP-L04.
    function test_givenConfigActiveDisabled_whenCapSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-L08.
    function test_givenConfigInactiveEnabled_whenCapSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-L12.
    function test_givenConfigInactiveDisabled_whenCapSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-VALIDATE-CAP-L05.
    function test_givenInvalidCapAndConfigActiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _setPrincipal(1);
        _bothRevert(
            _configurationCaller,
            _capCall(0),
            _capValidation(0),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
    }

    // Scenarios: BLCFG-VALIDATE-CAP-L06.
    function test_givenInvalidCapAndConfigActiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _setPrincipal(1);
        _config.disable("");
        _bothRevert(
            _configurationCaller,
            _capCall(0),
            _capValidation(0),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-VALIDATE-CAP-L07.
    function test_givenInvalidCapAndConfigInactiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _setPrincipal(1);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _bothRevert(
            _configurationCaller,
            _capCall(0),
            _capValidation(0),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-VALIDATE-CAP-L08.
    function test_givenInvalidCapAndConfigInactiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _setPrincipal(1);
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _bothRevert(
            _configurationCaller,
            _capCall(0),
            _capValidation(0),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-I01.
    function test_whenAssetIsNotRegistered_reverts(
        address asset_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.assume(!_core.isAssetRegistered(asset_));
        _bothRevert(
            _configurationCaller,
            abi.encodeCall(_config.setAssetDebtCap, (asset_, uint128(1))),
            abi.encodeCall(_config.validateAssetDebtCap, (asset_, uint128(1))),
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-I02, BLCFG-VALIDATE-CAP-P02.
    function test_givenIncompatibleSchema_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IFLOANv1.Market memory market = _floan.getMarket(_market);
        market.configId = bytes16("invalid");
        vm.mockCall(
            address(_floan),
            abi.encodeCall(_floan.getMarket, (_market)),
            abi.encode(market)
        );
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_IncompatibleMarketConfig.selector,
                _market,
                market.configId
            )
        );
        vm.clearMockedCalls();
        _validationSucceeds(_configurationCaller, _capValidation(1));
        _assertCapSet(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-DEBT-CAP-I03.
    function test_givenPrincipal_whenCapIsBelowDebt_reverts(
        uint128 d_,
        uint128 cap_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        d_ = uint128(bound(d_, 1, type(uint128).max));
        cap_ = uint128(bound(cap_, 0, uint256(d_) - 1));
        _setPrincipal(d_);
        _bothRevert(
            _configurationCaller,
            _capCall(cap_),
            _capValidation(cap_),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-I04.
    function test_givenMalformedMarketData_whenSetAndValidated_reverts(
        uint256 length_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        length_ = bound(length_, 0, 256);
        vm.assume(length_ != 224);
        vm.mockCall(
            address(_floan),
            abi.encodeCall(_floan.getMarketConfigData, (_market)),
            abi.encode(new bytes(length_))
        );
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidMarketConfigData.selector,
                _market,
                length_
            )
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-N01.
    function test_givenValidFullWidthCap_whenValidated(
        address caller_,
        uint128 d_,
        uint128 cap_
    ) public {
        cap_ = uint128(bound(cap_, d_, type(uint128).max));
        vm.assume(cap_ != _config.getAssetConfig(address(_asset)).debtCap);
        _setPrincipal(d_);
        _validationSucceeds(caller_, _capValidation(cap_));
        _assertCapSet(_configurationCaller, cap_);
    }

    // Scenarios: BLCFG-DEBT-CAP-N01.
    function test_whenCapBoundaryValuesAreSeeded() public {
        _assertCapSet(_configurationCaller, 0);
        _assertCapSet(_configurationCaller, 1);
        _assertCapSet(_configurationCaller, type(uint128).max);
        _setPrincipal(type(uint128).max);
        _validationSucceeds(_configurationCaller, _capValidation(type(uint128).max));
        _setPrincipal(7);
        _assertCapSet(_configurationCaller, 7);
        _assertCapSet(_configurationCaller, 8);
    }

    // Scenarios: BLCFG-DEBT-CAP-N02.
    function test_whenCapUnchanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        uint128 cap = _config.getAssetConfig(address(_asset)).debtCap;
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.setAssetDebtCap(address(_asset), cap);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged cap has no event or write");
        assertEq(_stateDigest(), beforeState, "No-op preserves all tracked state");
        _validationSucceeds(_configurationCaller, _capValidation(cap));
    }

    // Scenarios: BLCFG-DEBT-CAP-N03.
    function test_whenAssetCapAboveGlobalCap(
        uint128 cap_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        cap_ = uint128(bound(cap_, uint256(_inventory.globalDebtCapOhm()) + 1, type(uint128).max));
        _assertCapSet(_configurationCaller, cap_);
        _validationSucceeds(_configurationCaller, _capValidation(cap_));
    }

    // Scenarios: BLCFG-VALIDATE-CAP-P01.
    function test_givenPrincipalChanges_whenOldCapRevalidated(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPrincipal(10e9);
        _validationSucceeds(_configurationCaller, _capValidation(10e9));
        uint256 snapshot = vm.snapshotState();
        _assertCapSet(_configurationCaller, 10e9);
        assertTrue(vm.revertToState(snapshot), "Restore existing cap before new borrowing");
        _setPrincipal(10e9 + 1);
        _bothRevert(
            _configurationCaller,
            _capCall(10e9),
            _capValidation(10e9),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-P01, BLCFG-DEBT-CAP-P02, BLCFG-DEBT-CAP-P03, BLCFG-DEBT-CAP-P04.
    function test_givenInventoryStateVaries_whenAssetCapChanged(
        bool active_,
        bool enabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _supplyInventory(_recipient, 50e9);
        _setPolicyState(_inventory, active_, enabled_);
        uint128 globalCap = _inventory.globalDebtCapOhm();
        uint128 debt = _inventory.activePrincipalOhm();
        uint256 mintApproval = MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR"))))
            .mintApproval(address(_inventory));
        uint256 balance = _ohm.balanceOf(address(_inventory));
        _assertCapSet(_configurationCaller, 1);
        _validationSucceeds(_recipient, _capValidation(1));
        assertEq(_inventory.globalDebtCapOhm(), globalCap, "Independent aggregate cap");
        assertEq(_inventory.activePrincipalOhm(), debt, "Funding ledger unchanged");
        assertEq(_inventory.suppliedIdleOhm(), 50e9, "Idle funding unchanged");
        assertEq(_inventory.suppliedOhm(), 50e9, "Provider funding unchanged");
        assertEq(_inventory.providerClaimOhm(_recipient), 50e9, "Provider claim unchanged");
        assertEq(_ohm.balanceOf(address(_inventory)), balance, "Inventory OHM unchanged");
        assertEq(
            MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR")))).mintApproval(
                address(_inventory)
            ),
            mintApproval,
            "Mint approval unchanged"
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-D01.
    function test_givenConfigNoLongerMarketManager_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.prank(address(_core));
        _floan.setMarketManager(_market, _recipient);
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            abi.encodeWithSelector(IFLOANv1.FLOAN_NotManager.selector, _market, address(_config))
        );
    }

    // Scenarios: BLCFG-DEBT-CAP-D02.
    function test_givenSetterPermissionRevoked_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCall(
            address(_kernel),
            abi.encodeCall(
                _kernel.modulePermissions,
                (
                    toKeycode("FLOAN"),
                    Policy(address(_config)),
                    IFLOANv1.setMarketPrincipalCap.selector
                )
            ),
            abi.encode(false)
        );
        _bothRevert(
            _configurationCaller,
            _capCall(1),
            _capValidation(1),
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, address(_config))
        );
    }

    // Scenarios: BLCFG-VALIDATE-CAP-D03.
    function test_givenPrincipalReadFails_whenSetAndValidated(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        bytes memory reason = abi.encodeWithSignature("PrincipalReadFailed()");
        vm.mockCallRevert(
            address(_floan),
            abi.encodeCall(_floan.getMarketPrincipalDue, (_market)),
            reason
        );
        _bothRevert(_configurationCaller, _capCall(1), _capValidation(1), reason);
    }

    // Scenarios: BLCFG-DEBT-CAP-D04.
    function test_whenCapChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _useShareCollateral();
        bytes memory unexpected = abi.encodeWithSignature("UnexpectedWrite()");
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketRiskConfig.selector),
            unexpected
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketBaseFee.selector),
            unexpected
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketOriginationsEnabled.selector),
            unexpected
        );
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketConfigData.selector),
            unexpected
        );
        // Only the market lookup and settlement-state view are legitimate Core calls here.
        vm.mockCallRevert(address(_core), bytes(""), unexpected);
        vm.mockCall(
            address(_core),
            abi.encodeCall(_core.marketId, (address(_asset))),
            abi.encode(_market)
        );
        vm.mockCall(address(_core), abi.encodeCall(_core.requireNotReentrant, ()), bytes(""));
        vm.expectCall(
            address(_floan),
            abi.encodeCall(_floan.setMarketPrincipalCap, (_market, uint128(1)))
        );
        _assertCapSet(_configurationCaller, 1);
    }

    // Scenarios: BLCFG-DEBT-CAP-L16.
    function test_givenLocalRecovery_whenCapSet(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _config.disable("");
        _config.enable("");
        _assertCapSet(_configurationCaller, 200e9);
        _validationSucceeds(_configurationCaller, _capValidation(200e9));
    }

    // Scenarios: BLCFG-DEBT-CAP-L17.
    function test_givenKernelRecovery_whenCapSet(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _kernel.executeAction(Actions.ActivatePolicy, address(_config));
        _assertCapSet(_configurationCaller, 200e9);
        _validationSucceeds(_configurationCaller, _capValidation(200e9));
    }

    // Scenarios: BLCFG-DEBT-CAP-C01.
    function test_givenCollateralCallback_whenNestedConfigCaught_reverts(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetDebtCap, (address(_asset), uint128(1))),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackCaught(token);
    }

    // Scenarios: BLCFG-DEBT-CAP-C01.
    function test_givenCollateralCallback_whenNestedConfigPropagated(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetDebtCap, (address(_asset), uint128(1))),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackPropagated(token);
    }

    // Scenarios: BLCFG-DEBT-CAP-A01.
    function test_whenPermittedCallerClassesSeeded() public {
        address adminOnly = makeAddr("adminOnly");
        address overlap = makeAddr("adminAndOperator");
        _rolesAdmin.grantRole(ADMIN_ROLE, adminOnly);
        _assertCapSet(adminOnly, 1);
        _assertCapSet(_configurationCaller, 2);
        _rolesAdmin.grantRole(ADMIN_ROLE, overlap);
        _config.setConfigOperator(overlap);
        _assertCapSet(overlap, 3);
    }

    // Scenarios: BLCFG-DEBT-CAP-N01.
    function test_givenExistingLoan_whenConfigurationChanged() public givenDebtBearingPosition {
        _assertCapSet(_configurationCaller, 100e9);
        _validationSucceeds(_configurationCaller, _capValidation(100e9));
        assertEq(_floan.getMarketPrincipalDue(_market), 100e9, "Existing debt unchanged");
        assertEq(_floan.getMarketCollateral(_market), 2000e6, "Existing collateral unchanged");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Funding accounting unchanged");
    }

    // Scenarios: BLCFG-DEBT-CAP-I03.
    function test_whenBelowDebtEndpointsSeeded_reverts() public {
        _setPrincipal(type(uint128).max);
        _bothRevert(
            _configurationCaller,
            _capCall(0),
            _capValidation(0),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
        uint128 cap = type(uint128).max - 1;
        _bothRevert(
            _configurationCaller,
            _capCall(cap),
            _capValidation(cap),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidCap.selector)
        );
    }
}
