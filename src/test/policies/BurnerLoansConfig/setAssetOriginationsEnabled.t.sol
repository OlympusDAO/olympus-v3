// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {Actions} from "src/Kernel.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigSetAssetOriginationsEnabledTest is BurnerLoansConfigTest {
    function _assertOriginationsSet(address caller_, bool enabled_) internal {
        IBurnerLoansCore.AssetConfig memory expected = _config.getAssetConfig(address(_asset));
        bytes32 fee = keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset))));
        expected.originationsEnabled = enabled_;
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetOriginationsSet(address(_asset), enabled_);
        vm.prank(caller_);
        _config.setAssetOriginationsEnabled(address(_asset), enabled_);
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(_asset)))),
            keccak256(abi.encode(expected)),
            "Only originations flag changes"
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(_asset)))),
            fee,
            "Fee curve preserved"
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-A01, BLCFG-ORIGINATIONS-P03.
    function test_givenAuthorizedCaller_whenOriginationsDisabled(
        address caller_,
        bool admin_,
        bool operator_
    ) public {
        _grantConfigCaller(caller_, admin_, operator_);
        _assertOriginationsSet(caller_, false);
    }

    // Scenarios: BLCFG-ORIGINATIONS-A02.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        _excludeConfigCallers(caller_);
        _mutationReverts(
            caller_,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector)
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-L01.
    function test_givenCoreLifecycleVaries_whenFlagChanged(
        bool active_,
        bool enabled_,
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, active_, enabled_);
        _assertOriginationsSet(_configurationCaller, false);
    }

    // Scenarios: BLCFG-ORIGINATIONS-L04.
    function test_givenConfigActiveDisabled_whenFlagChanged_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-L08.
    function test_givenConfigInactiveEnabled_whenFlagChanged_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-L12.
    function test_givenConfigInactiveDisabled_whenFlagChanged_reverts(
        address caller_,
        bool admin_,
        bool operator_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _config.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-I01.
    function test_givenUnsupportedPrice_whenOriginationsEnabled_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(_risk.validatePriceSupport, (address(_asset))),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector)
        );
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), true)),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector)
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-I01.
    function test_givenDisabledDepositPeriod_whenOriginationsEnabled_reverts(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _depositManager.disableAssetPeriod(IERC20(address(_asset)), 1, address(_core));
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), true)),
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-P01, BLCFG-ORIGINATIONS-P05.
    function test_givenSameFlagAndBrokenDependencies_whenSet(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validatePriceSupport.selector),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("depositManager()"),
            hex"deadbeef"
        );
        bytes32 state = _stateDigest();
        vm.recordLogs();
        vm.prank(_configurationCaller);
        _config.setAssetOriginationsEnabled(address(_asset), true);
        assertEq(vm.getRecordedLogs().length, 0, "No-op has no writes or events");
        assertEq(_stateDigest(), state, "No-op preserves configuration and loans");
    }

    // Scenarios: BLCFG-ORIGINATIONS-P02.
    function test_givenPriceSupportBroken_whenOriginationsDisabled(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.validatePriceSupport.selector),
            hex"deadbeef"
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSignature("depositManager()"),
            hex"deadbeef"
        );
        _assertOriginationsSet(_configurationCaller, false);
    }

    // Scenarios: BLCFG-ORIGINATIONS-P03.
    function test_givenExistingLoan_whenFlagChanged() public givenDebtBearingPosition {
        uint128 principal = _floan.getMarketPrincipalDue(_market);
        uint256 collateral = _floan.getMarketCollateral(_market);
        _assertOriginationsSet(_configurationCaller, false);
        assertEq(_floan.getMarketPrincipalDue(_market), principal, "Principal unchanged");
        assertEq(_floan.getMarketCollateral(_market), collateral, "Existing collateral unchanged");
    }

    // Scenarios: BLCFG-ORIGINATIONS-P04.
    function test_givenOriginationsWriteFails_whenChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) {
        bytes memory reason = abi.encodeWithSignature("OriginationsWriteFailed()");
        vm.mockCallRevert(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.setMarketOriginationsEnabled.selector),
            reason
        );
        _mutationReverts(
            _configurationCaller,
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            reason
        );
    }

    // Scenarios: BLCFG-ORIGINATIONS-D01.
    function test_whenFlagChanged(
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
            abi.encodeWithSelector(IFLOANv1.setMarketConfigData.selector),
            abi.encodeWithSignature("UnexpectedWrite()")
        );
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.registerMarket.selector),
            abi.encodeWithSignature("UnexpectedRegistryWrite()")
        );
        _assertOriginationsSet(_configurationCaller, false);
    }

    // Scenarios: BLCFG-ORIGINATIONS-L16.
    function test_givenLocalRecovery_whenFlagChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _config.disable("");
        _config.enable("");
        _assertOriginationsSet(_configurationCaller, false);
    }

    // Scenarios: BLCFG-ORIGINATIONS-L17.
    function test_givenKernelRecovery_whenFlagChanged(
        address caller_,
        bool admin_,
        bool operator_
    ) public givenConfigurationCaller(caller_, admin_, operator_) givenDebtBearingPosition {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _kernel.executeAction(Actions.ActivatePolicy, address(_config));
        _assertOriginationsSet(_configurationCaller, false);
    }

    // Scenarios: BLCFG-ORIGINATIONS-C01.
    function test_givenCollateralCallback_whenNestedFlagChangeCaught(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackCaught(token);
    }

    // Scenarios: BLCFG-ORIGINATIONS-C01.
    function test_givenCollateralCallback_whenNestedFlagChangePropagated(
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) public {
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(_config.setAssetOriginationsEnabled, (address(_asset), false)),
            admin_,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackPropagated(token);
    }

    // Scenarios: BLCFG-ORIGINATIONS-A01.
    function test_whenPermittedCallerClassesSeeded() public {
        address adminOnly = makeAddr("adminOnly");
        address overlap = makeAddr("adminAndOperator");
        _rolesAdmin.grantRole(ADMIN_ROLE, adminOnly);
        _assertOriginationsSet(adminOnly, false);
        _assertOriginationsSet(_configurationCaller, true);
        _rolesAdmin.grantRole(ADMIN_ROLE, overlap);
        _config.setConfigOperator(overlap);
        _assertOriginationsSet(overlap, false);
    }
}
