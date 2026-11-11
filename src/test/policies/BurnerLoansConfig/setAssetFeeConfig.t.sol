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

contract BurnerLoansConfigSetAssetFeeConfigTest is BurnerLoansConfigTest {
    function _assertConfigurationRejected(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig memory cfg_,
        bytes memory reason_
    ) internal {
        _bothRevert(
            _configurationCaller,
            abi.encodeCall(_config.setAssetFeeConfig, (asset_, cfg_)),
            _feeValidation(asset_, cfg_),
            reason_
        );
    }

    function _assertConfigSet(
        address caller_,
        IBurnerLoansRisk.AssetFeeConfig memory cfg_
    ) internal {
        bytes32 riskBefore = keccak256(abi.encode(_config.getAssetConfig(address(_asset))));
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetFeeConfigSet(address(_asset), cfg_);
        vm.prank(caller_);
        _config.setAssetFeeConfig(address(_asset), cfg_);
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset)))),
            keccak256(abi.encode(cfg_)),
            "Exact complete fee curve"
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_asset)))),
            riskBefore,
            "Risk, cap, decimals and output mode preserved"
        );
        _validationSucceeds(caller_, _feeValidation(address(_asset), cfg_));
    }

    // Scenarios: BLCFG-FEE-CONFIG-A01, BLCFG-FEE-CONFIG-P01.
    function test_givenAuthorizedCaller_whenCompleteConfigChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public {
        _grantConfigCaller(caller_, admin_, operator_);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigSet(caller_, cfg);
    }

    // Scenarios: BLCFG-FEE-CONFIG-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        _excludeConfigCallers(caller_);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setAssetFeeConfig, (address(_asset), cfg)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
        _validationSucceeds(caller_, _feeValidation(address(_asset), cfg));
    }

    // Scenarios: BLCFG-FEE-CONFIG-L01.
    function test_givenIndependentCoreState_whenChanged(
        bool active_,
        bool enabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, active_, enabled_);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-FEE-CONFIG-L04.
    function test_givenConfigActiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-L08.
    function test_givenConfigInactiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-FEE-CONFIG-L12.
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
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-VALIDATE-FEE-L05.
    function test_givenInvalidInputAndConfigActiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(10001))
        );
    }

    // Scenarios: BLCFG-VALIDATE-FEE-L06.
    function test_givenInvalidInputAndConfigActiveDisabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-VALIDATE-FEE-L07.
    function test_givenInvalidInputAndConfigInactiveEnabled_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = 10001;
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-VALIDATE-FEE-L08.
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
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = 10001;
        _assertConfigurationRejected(address(_asset), cfg, _inactiveError(address(_config)));
    }

    // Scenarios: BLCFG-FEE-CONFIG-I01.
    function test_whenBaseFeeAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = uint16(bound(value_, 10001, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.baseFeeBps)
            )
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I02.
    function test_whenPreKinkSlopeAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.preKinkSlopeBps = uint16(bound(value_, 10001, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.preKinkSlopeBps)
            )
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I03.
    function test_whenPostKinkSlopeAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.postKinkSlopeBps = uint16(bound(value_, 10001, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.postKinkSlopeBps)
            )
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I04.
    function test_whenKinkAtOrAboveMaximum_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.kinkBps = uint16(bound(value_, 10000, type(uint16).max));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I05.
    function test_whenZeroKinkAndPositivePreSlope_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg = IBurnerLoansRisk.AssetFeeConfig(0, 0, uint16(bound(value_, 1, 10000)), 0);
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I06.
    function test_whenZeroKinkAndPositivePostSlope_reverts(
        uint16 value_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg = IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, uint16(bound(value_, 1, 10000)));
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I07.
    function test_whenTotalAboveMaximum_reverts(
        uint16 base_,
        uint16 pre_,
        uint16 post_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = uint16(bound(base_, 0, 10000));
        cfg.preKinkSlopeBps = uint16(bound(pre_, 0, 10000));
        cfg.postKinkSlopeBps = uint16(bound(post_, 0, 10000));
        vm.assume(uint256(cfg.baseFeeBps) + cfg.preKinkSlopeBps + cfg.postKinkSlopeBps > 10000);
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I08.
    function test_givenInvalidStructAndUnregisteredAsset_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = 10001;
        address asset = address(0);
        _assertConfigurationRejected(
            asset,
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(10001))
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I09.
    function test_givenValidStructAndUnregisteredAsset_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
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

    // Scenarios: BLCFG-FEE-CONFIG-I10.
    function test_givenIncompatibleSchema_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
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

    // Scenarios: BLCFG-FEE-CONFIG-I11.
    function test_givenMalformedMarketData_whenSetAndValidated_reverts(
        uint256 length_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
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

    // Scenarios: BLCFG-FEE-CONFIG-P02.
    function test_whenConfigurationUnchanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigSet(_configurationCaller, cfg);
        bytes32 beforeState = _stateDigest();
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.setAssetFeeConfig(address(_asset), cfg);
        assertEq(vm.getRecordedLogs().length, 0, "Unchanged struct emits nothing");
        assertEq(_stateDigest(), beforeState, "Unchanged struct writes nothing");
        _validationSucceeds(_configurationCaller, _feeValidation(address(_asset), cfg));
    }

    // Scenarios: BLCFG-FEE-CONFIG-P04.
    function test_givenLateFloanWriteFails_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        bytes memory failure = abi.encodeWithSignature("ConfigDataWriteFailed()");
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketConfigData.selector),
            failure
        );
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetFeeConfig, (address(_asset), cfg)),
            failure
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-D01.
    function test_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
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

    // Scenarios: BLCFG-FEE-CONFIG-D02.
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
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-D01.
    function test_givenRiskUnset_whenSetAndValidated_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCall(address(_core), abi.encodeWithSignature("risk()"), abi.encode(address(0)));
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        vm.expectCall(address(_core), abi.encodeWithSignature("risk()"), uint64(2));
        _assertConfigurationRejected(address(_asset), cfg, bytes(""));
    }

    // Scenarios: BLCFG-VALIDATE-FEE-D02.
    function test_givenRiskRejectsStruct_whenSetAndValidated(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_InvalidParam.selector
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validateFeeConfig.selector),
            failure
        );
        _assertConfigurationRejected(address(_asset), cfg, failure);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-D03.
    function test_givenRiskReplaced_whenValidating(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        address replacement = makeAddr("replacementRisk");
        vm.etch(replacement, hex"00");
        vm.mockCall(address(_core), abi.encodeWithSignature("risk()"), abi.encode(replacement));
        vm.mockCall(
            replacement,
            abi.encodeWithSelector(IBurnerLoansRisk.validateFeeConfig.selector),
            bytes("")
        );
        vm.expectCall(
            replacement,
            abi.encodeWithSelector(IBurnerLoansRisk.validateFeeConfig.selector, cfg)
        );
        _validationSucceeds(_configurationCaller, _feeValidation(address(_asset), cfg));
    }

    // Scenarios: BLCFG-FEE-CONFIG-L16.
    function test_givenLocalRecovery_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _config.disable("");
        _config.enable("");
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-FEE-CONFIG-L17.
    function test_givenKernelRecovery_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _kernel.executeAction(Actions.ActivatePolicy, address(_config));
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-N09, BLCFG-FEE-CONFIG-P03.
    function test_whenZeroFee(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0);
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-N10, BLCFG-FEE-CONFIG-P03.
    function test_whenMaximumFlatFee(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = IBurnerLoansRisk.AssetFeeConfig(
            10000,
            0,
            0,
            0
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-N11, BLCFG-FEE-CONFIG-P03.
    function test_whenMaximumPreSlope(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = IBurnerLoansRisk.AssetFeeConfig(
            0,
            1,
            10000,
            0
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-N12, BLCFG-FEE-CONFIG-P03.
    function test_whenMaximumKink(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = IBurnerLoansRisk.AssetFeeConfig(
            100,
            9999,
            200,
            300
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-VALIDATE-FEE-N13, BLCFG-FEE-CONFIG-P03.
    function test_whenDecreasingSlopes(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = IBurnerLoansRisk.AssetFeeConfig(
            0,
            5000,
            6000,
            4000
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-FEE-CONFIG-P01.
    function test_whenFullValidFeeDomainIsUsed(
        uint16 base_,
        uint16 kink_,
        uint16 pre_,
        uint16 post_
    ) public {
        IBurnerLoansRisk.AssetFeeConfig memory cfg;
        cfg.baseFeeBps = uint16(bound(base_, 0, 10000));
        cfg.preKinkSlopeBps = uint16(bound(pre_, 0, 10000 - cfg.baseFeeBps));
        cfg.postKinkSlopeBps = uint16(
            bound(post_, 0, 10000 - cfg.baseFeeBps - cfg.preKinkSlopeBps)
        );
        cfg.kinkBps = uint16(
            bound(kink_, (cfg.preKinkSlopeBps == 0 && cfg.postKinkSlopeBps == 0) ? 0 : 1, 9999)
        );
        vm.assume(
            keccak256(abi.encode(cfg)) !=
                keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset))))
        );
        _assertConfigSet(_configurationCaller, cfg);
    }

    // Scenarios: BLCFG-FEE-CONFIG-C01.
    function test_givenCollateralCallback_whenNestedConfigCaught_reverts(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetFeeConfig, (address(_asset), _feeConfig())),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackCaught(token);
    }

    // Scenarios: BLCFG-FEE-CONFIG-C01.
    function test_givenCollateralCallback_whenNestedConfigPropagated(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetFeeConfig, (address(_asset), _feeConfig())),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackPropagated(token);
    }

    // Scenarios: BLCFG-FEE-CONFIG-A01.
    function test_whenPermittedCallerClassesSeeded() public {
        address adminOnly = makeAddr("adminOnly");
        address overlap = makeAddr("adminAndOperator");
        _rolesAdmin.grantRole(ADMIN_ROLE, adminOnly);
        _assertConfigSet(adminOnly, IBurnerLoansRisk.AssetFeeConfig(100, 5000, 200, 300));
        _assertConfigSet(
            _configurationCaller,
            IBurnerLoansRisk.AssetFeeConfig(101, 5000, 200, 300)
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, overlap);
        _config.setConfigOperator(overlap);
        _assertConfigSet(overlap, IBurnerLoansRisk.AssetFeeConfig(102, 5000, 200, 300));
    }

    // Scenarios: BLCFG-FEE-CONFIG-I01.
    function test_whenBaseFeeBpsAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.baseFeeBps)
            )
        );
        cfg.baseFeeBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.baseFeeBps)
            )
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I02.
    function test_whenPreKinkSlopeBpsAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.preKinkSlopeBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.preKinkSlopeBps)
            )
        );
        cfg.preKinkSlopeBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.preKinkSlopeBps)
            )
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I03.
    function test_whenPostKinkSlopeBpsAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.postKinkSlopeBps = 10001;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.postKinkSlopeBps)
            )
        );
        cfg.postKinkSlopeBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.postKinkSlopeBps)
            )
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-I04.
    function test_whenKinkBpsAtOrAboveMaximumEndpointsAreSeeded_reverts() public {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.kinkBps = 10000;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
        cfg.kinkBps = 65535;
        _assertConfigurationRejected(
            address(_asset),
            cfg,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-A01, BLCFG-FEE-CONFIG-P01.
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
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        vm.expectCall(address(_config), _feeValidation(address(_asset), cfg));
        uint64 id = timelock.queueSetAssetFeeConfig(address(_asset), cfg);
        vm.warp(timelock.getQueuedAction(id).executableAt);
        timelock.executeQueuedAction(id);
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset)))),
            keccak256(abi.encode(cfg)),
            "Queued complete fee curve applied"
        );
    }

    // Scenarios: BLCFG-FEE-CONFIG-P01.
    function test_givenExistingLoan_whenConfigurationChanged() public givenDebtBearingPosition {
        uint256 payerBalance = _asset.balanceOf(_borrower);
        _assertConfigSet(_configurationCaller, _feeConfig());
        assertEq(
            _asset.balanceOf(_borrower),
            payerBalance,
            "Fee configuration does not collect a fee"
        );
        assertEq(_floan.getMarketPrincipalDue(_market), 100e9, "Existing debt unchanged");
        assertEq(_floan.getMarketCollateral(_market), 2000e6, "Existing collateral unchanged");
    }

    // Scenarios: BLCFG-FEE-CONFIG-D01.
    function test_givenNondefaultShareMode_whenConfigurationChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _useShareCollateral();
        _assertConfigSet(_configurationCaller, _feeConfig());
        assertTrue(
            _config.getAssetConfig(address(_asset)).withdrawAsShares,
            "Unrelated nondefault share-output bit preserved"
        );
    }
}
