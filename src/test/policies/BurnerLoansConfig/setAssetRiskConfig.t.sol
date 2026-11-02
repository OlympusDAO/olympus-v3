// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {BurnerLoansConfigTimelock} from "src/policies/burnerloans/BurnerLoansConfigTimelock.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigSetAssetRiskConfigTest is BurnerLoansConfigTest {
    function _assertConfigurationRejected(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg_,
        bytes memory reason_
    ) internal {
        _bothRevert(
            _configurationCaller,
            abi.encodeCall(_config.setAssetRiskConfig, (asset_, cfg_)),
            _riskValidation(asset_, cfg_),
            reason_
        );
    }

    function _assertConfigSet(
        address caller_,
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg_
    ) internal {
        IBurnerLoansCore.AssetConfig memory expected = _config.getAssetConfig(address(_asset));
        bytes32 feeBefore = keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset))));
        expected.maxLtvBps = cfg_.maxLtvBps;
        expected.backingMultiplierBps = cfg_.backingMultiplierBps;
        expected.keeperRewardBps = cfg_.keeperRewardBps;
        expected.maxKeeperReward = cfg_.maxKeeperReward;
        expected.termLength = cfg_.termLength;
        expected.maxMaturityHorizon = cfg_.maxMaturityHorizon;
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetRiskConfigSet(address(_asset), cfg_);
        vm.prank(caller_);
        _config.setAssetRiskConfig(address(_asset), cfg_);
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_asset)))),
            keccak256(abi.encode(expected)),
            "Exact full risk fields; admin fields preserved"
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset)))),
            feeBefore,
            "Fee curve preserved"
        );
        _validationSucceeds(caller_, _riskValidation(address(_asset), cfg_));
    }

    // Scenarios: BLCFG-RISK-CONFIG-A01, BLCFG-RISK-CONFIG-P01.
    function test_givenAuthorizedCaller_whenCompleteConfigChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public {
        _grantConfigCaller(caller_, admin_, operator_);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigSet(caller_, cfg);
    }

    // Scenarios: BLCFG-RISK-CONFIG-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        _excludeConfigCallers(caller_);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setAssetRiskConfig, (address(_asset), cfg)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _validationSucceeds(caller_, _riskValidation(address(_asset), cfg));
    }

    // Scenarios: BLCFG-RISK-CONFIG-L01.
    function test_givenIndependentCoreState_whenChanged(
        bool active_,
        bool enabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, active_, enabled_);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-RISK-CONFIG-L04.
    function test_givenConfigActiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-L08.
    function test_givenConfigInactiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-RISK-CONFIG-L12.
    function test_givenConfigInactiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-VALIDATE-RISK-L05.
    function test_givenInvalidInputAndConfigActiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(0))
        );
    }

    // Scenarios: BLCFG-VALIDATE-RISK-L06.
    function test_givenInvalidInputAndConfigActiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-VALIDATE-RISK-L07.
    function test_givenInvalidInputAndConfigInactiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-VALIDATE-RISK-L08.
    function test_givenInvalidInputAndConfigInactiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-RISK-CONFIG-I01.
    function test_whenZeroLtv_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(0))
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I02.
    function test_whenLtvAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = uint16(bound(value_, 10001, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.maxLtvBps)
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I03.
    function test_whenBackingBelowMinimum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = uint16(bound(value_, 0, 9999));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I04.
    function test_whenBackingAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = uint16(bound(value_, 50001, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I05.
    function test_whenKeeperBpsAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.keeperRewardBps = uint16(bound(value_, 10001, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.keeperRewardBps)
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I06.
    function test_whenZeroTerm_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = 0;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I07.
    function test_whenTermAboveMaximum_reverts(
        uint48 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = uint48(bound(value_, 365 days + 1, type(uint48).max));
        cfg.maxMaturityHorizon = 366 days;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I08.
    function test_whenZeroHorizon_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxMaturityHorizon = 0;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I09.
    function test_whenHorizonBelowTerm_reverts(
        uint48 term_,
        uint48 horizon_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = uint48(bound(term_, 2, 365 days));
        cfg.maxMaturityHorizon = uint48(bound(horizon_, 1, cfg.termLength - 1));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I10.
    function test_whenHorizonEqualsTerm_reverts(
        uint48 term_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = uint48(bound(term_, 1, 365 days));
        cfg.maxMaturityHorizon = cfg.termLength;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I11.
    function test_whenHorizonAboveMaximum_reverts(
        uint48 horizon_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxMaturityHorizon = uint48(bound(horizon_, 366 days + 1, type(uint48).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I12.
    function test_givenInvalidStructAndUnregisteredAsset_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        address asset = address(0);
        _assertConfigurationRejected(
            asset,
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(0))
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I13.
    function test_givenValidStructAndUnregisteredAsset_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        address asset = address(0);
        _assertConfigurationRejected(
            asset,
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I14.
    function test_givenIncompatibleSchema_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        address asset = address(_asset);
        IFLOANv1.Market memory market = _floan.getMarket(_market);
        market.configId = bytes16("invalid");
        vm.mockCall(
            address(_floan),
            abi.encodeCall(_floan.getMarket, (_market)),
            abi.encode(market)
        );
        _assertConfigurationRejected(
            asset,
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_IncompatibleMarketConfig.selector,
                _market,
                bytes16("invalid")
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I15.
    function test_givenMalformedMarketData_whenSetAndValidated_reverts(
        uint256 length_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        address asset = address(_asset);
        length_ = bound(length_, 0, 256);
        vm.assume(length_ != 224);
        vm.mockCall(
            address(_floan),
            abi.encodeCall(_floan.getMarketConfigData, (_market)),
            abi.encode(new bytes(length_))
        );
        _assertConfigurationRejected(
            asset,
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_InvalidMarketConfigData.selector,
                _market,
                length_
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-P02.
    function test_whenConfigurationUnchanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigSet(_configurationCaller, cfg);
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.setAssetRiskConfig(address(_asset), cfg);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged struct emits nothing");
        assertEq(_stateDigest(), beforeState, "Unchanged struct writes nothing");
        _validationSucceeds(_configurationCaller, _riskValidation(address(_asset), cfg));
    }

    // Scenarios: BLCFG-RISK-CONFIG-P04.
    function test_givenLateFloanWriteFails_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        bytes memory failure = abi.encodeWithSignature("ConfigDataWriteFailed()");
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketConfigData.selector),
            failure
        );
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetRiskConfig, (address(_asset), cfg)),
            failure
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-D01.
    function test_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketPrincipalCap.selector),
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
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.registerMarket.selector),
            abi.encodeWithSignature("UnexpectedRegistryWrite()")
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-RISK-CONFIG-D02.
    function test_givenRiskHasIndependentController_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSignature("configOperator()"),
            hex"deadbeef"
        );
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-RISK-D01.
    function test_givenRiskUnset_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCall(address(_core), abi.encodeWithSignature("risk()"), abi.encode(address(0)));
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(2));
        _assertConfigurationRejected(address(_asset), cfg, bytes(""));
    }

    // Scenarios: BLCFG-VALIDATE-RISK-D02.
    function test_givenRiskRejectsStruct_whenSetAndValidated(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_InvalidParam.selector
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateRiskConfig.selector),
            failure
        );
        _assertConfigurationRejected(address(_asset), cfg, failure);
    }

    // Scenarios: BLCFG-VALIDATE-RISK-D03.
    function test_givenRiskReplaced_whenValidating(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        address replacement = makeAddr("replacementRisk");
        vm.etch(replacement, hex"00");
        vm.mockCall(address(_core), abi.encodeWithSignature("risk()"), abi.encode(replacement));
        vm.mockCall(
            replacement,
            abi.encodeWithSelector(IBurnerLoansRisk.validateRiskConfig.selector),
            bytes("")
        );
        vm.expectCall(
            replacement,
            abi.encodeWithSelector(IBurnerLoansRisk.validateRiskConfig.selector, cfg)
        );
        _validationSucceeds(_configurationCaller, _riskValidation(address(_asset), cfg));
    }

    // Scenarios: BLCFG-RISK-CONFIG-L16.
    function test_givenLocalRecovery_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _config.disable("");
        _config.enable("");
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-RISK-CONFIG-L17.
    function test_givenKernelRecovery_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _kernel.executeAction(Actions.ActivatePolicy, address(_config));
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-RISK-N13, BLCFG-RISK-CONFIG-P03.
    function test_whenMinimumRiskFields(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = IBurnerLoansRisk.AssetRiskConfigInput(
            1,
            10000,
            0,
            1,
            2,
            0
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-RISK-N14, BLCFG-RISK-CONFIG-P03.
    function test_whenMaximumRiskFields(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = IBurnerLoansRisk.AssetRiskConfigInput(
            10000,
            50000,
            10000,
            365 days,
            366 days,
            type(uint128).max
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-RISK-N15, BLCFG-RISK-CONFIG-P03.
    function test_whenMaximumKeeperReward(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = IBurnerLoansRisk.AssetRiskConfigInput(
            7500,
            12000,
            100,
            30 days,
            90 days,
            type(uint128).max
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-RISK-CONFIG-P01.
    function test_whenFullValidRiskDomainIsUsed(
        uint16 ltv_,
        uint16 backing_,
        uint16 keeper_,
        uint128 reward_,
        uint48 term_,
        uint48 horizon_
    ) public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg;
        cfg.maxLtvBps = uint16(bound(ltv_, 1, 10000));
        cfg.backingMultiplierBps = uint16(bound(backing_, 10000, 50000));
        cfg.keeperRewardBps = uint16(bound(keeper_, 0, 10000));
        cfg.maxKeeperReward = reward_;
        cfg.termLength = uint48(bound(term_, 1, 365 days));
        cfg.maxMaturityHorizon = uint48(bound(horizon_, cfg.termLength + 1, 366 days));
        vm.assume(cfg.maxLtvBps != 8500);
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-RISK-CONFIG-C01.
    function test_givenCollateralCallback_whenNestedConfigCaught_reverts(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetRiskConfig, (address(_asset), _riskConfig())),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackCaught(token);
    }

    // Scenarios: BLCFG-RISK-CONFIG-C01.
    function test_givenCollateralCallback_whenNestedConfigPropagated(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetRiskConfig, (address(_asset), _riskConfig())),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackPropagated(token);
    }

    // Scenarios: BLCFG-RISK-CONFIG-A01.
    function test_whenPermittedCallerClassesSeeded() public {
        address adminOnly = makeAddr("adminOnly");
        address overlap = makeAddr("adminAndOperator");
        _rolesAdmin.grantRole(ADMIN_ROLE, adminOnly);
        _assertConfigSet(
            adminOnly,
            IBurnerLoansRisk.AssetRiskConfigInput(7500, 12000, 100, 30 days, 90 days, 1e6)
        );
        _assertConfigSet(
            _configurationCaller,
            IBurnerLoansRisk.AssetRiskConfigInput(7501, 12000, 100, 30 days, 90 days, 1e6)
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, overlap);
        _config.setConfigOperator(overlap);
        _assertConfigSet(
            overlap,
            IBurnerLoansRisk.AssetRiskConfigInput(7502, 12000, 100, 30 days, 90 days, 1e6)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I02.
    function test_whenMaxLtvBpsAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.maxLtvBps)
            )
        );
        cfg.maxLtvBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.maxLtvBps)
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I03.
    function test_whenBackingMultiplierBpsBelowMinimumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = 0;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.backingMultiplierBps = 1;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.backingMultiplierBps = 9999;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I04.
    function test_whenBackingMultiplierBpsAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = 50001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.backingMultiplierBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I05.
    function test_whenKeeperRewardBpsAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.keeperRewardBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.keeperRewardBps)
            )
        );
        cfg.keeperRewardBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.keeperRewardBps)
            )
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I07.
    function test_whenTermLengthAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = 365 days + 1;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.termLength = type(uint48).max;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I11.
    function test_whenMaxMaturityHorizonAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxMaturityHorizon = 366 days + 1;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.maxMaturityHorizon = type(uint48).max;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-A01, BLCFG-RISK-CONFIG-P01.
    function test_givenTimelockOperator_whenQueuedAndExecuted() public {
        BurnerLoansConfigTimelock timelock = new BurnerLoansConfigTimelock(
            _kernel,
            IBurnerLoansConfig(address(_config))
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(timelock));
        _config.setConfigOperator(address(timelock));
        timelock.enable("");
        assertFalse(
            _roles.hasRole(address(timelock), ADMIN_ROLE),
            "Forwarding operator holds no ADMIN role"
        );
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        vm.expectCall(address(_config), _riskValidation(address(_asset), cfg));
        uint64 id = timelock.queueSetAssetRiskConfig(address(_asset), cfg);
        vm.warp(timelock.getQueuedAction(id).executableAt);
        timelock.executeQueuedAction(id);
        assertEq(
            _config.getAssetConfig(address(_asset)).maxLtvBps,
            cfg.maxLtvBps,
            "Queued risk fields applied"
        );
        assertEq(
            _config.getAssetConfig(address(_asset)).maxKeeperReward,
            cfg.maxKeeperReward,
            "Queued full-width reward applied"
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-P01.
    function test_givenExistingLoan_whenRiskTightened() public givenDebtBearingPosition {
        uint48 maturity = _lens.getPosition(address(_asset), _borrower).maturity;
        // $2000 collateral / max($100 / 0.85, $100 * 1.25) = 2000/125 = 16 WAD.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, 100e9),
            16e18,
            "Independent original health"
        );
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = 50000;
        cfg.termLength = 1 days;
        cfg.maxMaturityHorizon = 2 days;
        _assertConfigSet(_configurationCaller, cfg);
        // $2000 / max($100 / 0.75, $100 * 5) = 2000/500 = 4 WAD.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, 100e9),
            4e18,
            "New backing rule applies immediately"
        );
        cfg.maxLtvBps = 1;
        _assertConfigSet(_configurationCaller, cfg);
        // One basis point permits LTV 0.0001. $100 / 0.0001 = $1,000,000 required.
        // Health = $2000 / $1,000,000 * 1e18 = 2e15, below one WAD.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 2000e6, 100e9),
            2e15,
            "New LTV applies to the existing loan"
        );
        assertTrue(_lens.isSeizable(address(_asset), _borrower), "No grandfathered health rules");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).maturity,
            maturity,
            "Changing terms does not rewrite existing maturity"
        );
        assertEq(
            _floan.getMarketPrincipalDue(_market),
            100e9,
            "Risk update does not change principal"
        );
        assertEq(
            _floan.getMarketCollateral(_market),
            2000e6,
            "Risk update does not move collateral"
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-D01.
    function test_givenNondefaultShareMode_whenConfigurationChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _useShareCollateral();
        _assertConfigSet(_configurationCaller, _riskConfig());
        assertTrue(
            _config.getAssetConfig(address(_asset)).withdrawAsShares,
            "Unrelated nondefault share-output bit preserved"
        );
    }

    // Scenarios: BLCFG-RISK-CONFIG-I09, BLCFG-RISK-CONFIG-I10.
    function test_whenHorizonRelationBoundariesSeeded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = 365 days;
        cfg.maxMaturityHorizon = 1;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.maxMaturityHorizon = 365 days - 1;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.maxMaturityHorizon = 365 days;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.termLength = 1;
        cfg.maxMaturityHorizon = 1;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }
}
