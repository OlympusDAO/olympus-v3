// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {Actions, Policy} from "src/Kernel.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

/// @dev Config scenarios require the token to propagate the original settlement-guard error.
contract ConfigCallbackToken is ReentrantFeeToken {
    function _revertCallbackFailure(bytes memory reason_) internal pure override {
        assembly ("memory-safe") {
            revert(add(reason_, 32), mload(reason_))
        }
    }
}

/// @notice Config tests use the existing real Kernel/FLOAN/accounting deployment.
abstract contract BurnerLoansConfigTest is BurnerLoansModularTest {
    address internal _configurationCaller;
    uint32 internal _market;

    function setUp() public virtual override {
        super.setUp();
        _configurationCaller = makeAddr("configOperator");
        _config.setConfigOperator(_configurationCaller);
        _market = _core.marketId(address(_asset));
    }

    modifier givenConfigDisabled() {
        _config.disable("");
        _;
    }

    modifier givenConfigInactive() {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_config));
        _;
    }

    modifier givenConfigurationCaller(
        address caller_,
        bool admin_,
        bool operator_
    ) {
        _grantConfigCaller(caller_, admin_, operator_);
        _configurationCaller = caller_;
        _;
    }

    modifier givenListingAdmin(address caller_) {
        _grantAdmin(caller_);
        _;
    }

    function _grantAdmin(address caller_) internal {
        vm.assume(caller_ != address(0));
        if (!_roles.hasRole(caller_, ADMIN_ROLE)) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
    }

    function _grantConfigCaller(address caller_, bool admin_, bool operator_) internal {
        vm.assume(caller_ != address(0));
        vm.assume(admin_ || operator_);
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(caller_ != _config.configOperator());
        if (admin_) _rolesAdmin.grantRole(ADMIN_ROLE, caller_);
        if (operator_) _config.setConfigOperator(caller_);
    }

    function _excludeConfigCallers(address caller_) internal view {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        vm.assume(caller_ != _config.configOperator());
    }

    function _riskConfig() internal pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return IBurnerLoansRisk.AssetRiskConfigInput(7500, 12000, 100, 30 days, 90 days, 1e6);
    }

    function _feeConfig() internal pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return IBurnerLoansRisk.AssetFeeConfig(100, 5000, 200, 300);
    }

    function _listingToken(uint8 decimals_) internal returns (MockERC20 token) {
        token = new MockERC20("Collateral", "COL", decimals_);
        _price.setPrice(address(token), 1e18);
    }

    function _registerDepositAsset(MockERC20 token_, address vault_) internal {
        _depositManager.addAsset(IERC20(address(token_)), IERC4626(vault_), type(uint256).max, 0);
        _depositManager.addAssetPeriod(IERC20(address(token_)), 1, address(_core));
    }

    function _prepareCollateral(uint8 decimals_) internal returns (MockERC20 token) {
        token = _listingToken(decimals_);
        _registerDepositAsset(token, address(0));
    }

    function _useShareCollateral() internal {
        MockERC20 token = _listingToken(18);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _registerDepositAsset(token, address(vault));
        _config.addAsset(
            address(token),
            100000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900),
            true
        );
        _asset = token;
        _market = _core.marketId(address(token));
    }

    function _capCall(uint128 cap_) internal view returns (bytes memory) {
        return abi.encodeCall(_config.setAssetDebtCap, (address(_asset), cap_));
    }

    function _capValidation(uint128 cap_) internal view returns (bytes memory) {
        return abi.encodeCall(_config.validateAssetDebtCap, (address(_asset), cap_));
    }

    function _feeValidation(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig memory cfg_
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(IBurnerLoansConfig.validateFeeConfig, (asset_, cfg_));
    }

    function _riskValidation(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg_
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(IBurnerLoansConfig.validateAssetRiskConfig, (asset_, cfg_));
    }

    function _economicDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _floan.getMarket(_market),
                    _floan.getMarketConfigData(_market),
                    _inventory.globalDebtCapOhm(),
                    _inventory.activePrincipalOhm(),
                    _ohm.balanceOf(address(_inventory)),
                    _asset.balanceOf(address(_core)),
                    _asset.balanceOf(address(_payout)),
                    _asset.balanceOf(_borrower)
                )
            );
    }

    function _stateDigest() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _economicDigest(),
                    _config.isEnabled(),
                    _config.lastTransitionAt(),
                    _config.gracePeriod(),
                    _config.configOperator(),
                    _kernel.isPolicyActive(_config)
                )
            );
    }

    function _setPolicyState(Policy policy_, bool active_, bool enabled_) internal {
        if (!enabled_) IEnabler(address(policy_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(policy_));
    }

    function _mutationReverts(address caller_, bytes memory data_, bytes memory error_) internal {
        bytes32 beforeState = _stateDigest();
        vm.prank(caller_);
        (bool success, bytes memory result) = address(_config).call(data_);
        assertFalse(success, "Mutation must revert");
        assertEq(result, error_, "Mutation exact revert data");
        assertEq(
            _stateDigest(),
            beforeState,
            "Rejected mutation preserves authoritative state and balances"
        );
    }

    function _validationReverts(address caller_, bytes memory data_, bytes memory error_) internal {
        bytes32 beforeState = _stateDigest();
        vm.prank(caller_);
        (bool success, bytes memory result) = address(_config).staticcall(data_);
        assertFalse(success, "Preflight must revert");
        assertEq(result, error_, "Preflight exact revert data");
        assertEq(_stateDigest(), beforeState, "Rejected preflight has no effects");
    }

    function _validationSucceeds(address caller_, bytes memory data_) internal {
        bytes32 beforeState = _stateDigest();
        vm.prank(caller_);
        (bool success, bytes memory result) = address(_config).staticcall(data_);
        assertTrue(success, "Preflight must accept the same valid state and input");
        assertEq(result.length, 0, "Validation has no return payload");
        assertEq(_stateDigest(), beforeState, "Successful preflight has no effects");
    }

    function _bothRevert(
        address caller_,
        bytes memory action_,
        bytes memory view_,
        bytes memory error_
    ) internal {
        _mutationReverts(caller_, action_, error_);
        _validationReverts(caller_, view_, error_);
    }

    function _armConfigurationCallback(
        bytes memory data_,
        bool admin_,
        bool operator_,
        address tokenDeployer_
    ) internal returns (ReentrantFeeToken token) {
        vm.prank(tokenDeployer_);
        token = new ConfigCallbackToken();
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
        token.mint(_borrower, 1e18);
        vm.prank(_borrower);
        token.approve(address(_core), type(uint256).max);
        vm.assume(admin_ || operator_);
        if (admin_) _rolesAdmin.grantRole(ADMIN_ROLE, address(token));
        if (operator_) _config.setConfigOperator(address(token));
        token.setCallbackFrom(address(_core), address(_config), data_);
    }

    function _assertConfigurationCallbackCaught(ReentrantFeeToken token_) internal {
        uint32 markets = _floan.getMarketCount();
        bytes32 beforeConfig = keccak256(
            abi.encode(_floan.getMarket(_market), _floan.getMarketConfigData(_market))
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(token_), 1e18, _borrower);
        assertFalse(token_.callbackSucceeded(), "Nested authorized configuration rejected");
        assertEq(
            token_.callbackRevertData(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Callback reaches Core settlement guard"
        );
        assertEq(_floan.getMarketCount(), markets, "Nested listing cannot leave an orphan market");
        assertEq(
            keccak256(abi.encode(_floan.getMarket(_market), _floan.getMarketConfigData(_market))),
            beforeConfig,
            "Nested market changes roll back"
        );
        assertEq(token_.balanceOf(_borrower), 0, "Outer collateral movement occurs once");
        // Direct-custody input and credit both use the token's 18-decimal units.
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token_)), address(_core)),
            1e18,
            "Custody liability created once"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(token_))),
            1e18,
            "Canonical collateral credited once"
        );
    }

    function _assertConfigurationCallbackPropagated(ReentrantFeeToken token_) internal {
        token_.setBubbleCallbackFailure(true);
        uint32 markets = _floan.getMarketCount();
        bytes32 beforeState = _stateDigest();
        vm.prank(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        _collateral.depositCollateral(address(token_), 1e18, _borrower);
        assertEq(_stateDigest(), beforeState, "Callback failure rolls back outer and nested state");
        assertEq(_floan.getMarketCount(), markets, "No market ID consumed");
        assertEq(token_.balanceOf(_borrower), 1e18, "Payer transfer rolls back");
        assertEq(token_.balanceOf(address(_core)), 0, "Core holds no residual collateral");
        assertEq(token_.balanceOf(address(_depositManager)), 0, "No custody credit on rollback");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(token_)), address(_core)),
            0,
            "No liability on rollback"
        );
        assertEq(
            _floan.getMarketCollateral(_core.marketId(address(token_))),
            0,
            "No canonical collateral on rollback"
        );
    }

    function _inactiveError(address policy_) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                policy_
            );
    }

    function _setPrincipal(uint128 principal_) internal {
        vm.mockCall(
            address(_floan),
            abi.encodeCall(_floan.getMarketPrincipalDue, (_market)),
            abi.encode(principal_)
        );
    }
}
