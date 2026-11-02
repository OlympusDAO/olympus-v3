// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IConfigOperator} from "src/policies/interfaces/utils/IConfigOperator.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";

// Contracts
import {BurnerLoansConfigTest} from "./BurnerLoansConfigTest.sol";
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {Actions} from "src/Kernel.sol";
import {ADMIN_ROLE, DEPOSIT_OPERATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Scenario-specific constants and deliberate narrowing are exact test boundaries.
// forge-lint: disable-start(literal-instead-of-constant, unsafe-typecast)

contract BurnerLoansConfigAddAssetTest is BurnerLoansConfigTest {
    function _listingReverts(
        MockERC20 token_,
        IBurnerLoansRisk.AssetRiskConfigInput memory risk_,
        IBurnerLoansRisk.AssetFeeConfig memory fee_,
        bool shares_,
        bytes memory reason_
    ) internal {
        uint32 markets = _floan.getMarketCount();
        bool registered = _core.isAssetRegistered(address(token_));
        _mutationReverts(
            address(this),
            abi.encodeCall(_config.addAsset, (address(token_), uint128(1), risk_, fee_, shares_)),
            reason_
        );
        assertEq(_floan.getMarketCount(), markets, "Failed listing consumes no market ID");
        assertEq(
            _core.isAssetRegistered(address(token_)),
            registered,
            "Failed listing preserves Core registry"
        );
    }

    function _assertListed(
        address caller_,
        MockERC20 token_,
        uint128 cap_,
        IBurnerLoansRisk.AssetRiskConfigInput memory risk_,
        IBurnerLoansRisk.AssetFeeConfig memory fee_,
        bool shares_
    ) internal {
        uint32 beforeCount = _floan.getMarketCount();
        IBurnerLoansCore.AssetConfig memory expected = IBurnerLoansCore.AssetConfig(
            true,
            shares_,
            token_.decimals(),
            risk_.maxLtvBps,
            risk_.backingMultiplierBps,
            risk_.keeperRewardBps,
            risk_.termLength,
            risk_.maxMaturityHorizon,
            cap_,
            risk_.maxKeeperReward
        );
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetAdded(address(token_), expected);
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetFeeConfigSet(address(token_), fee_);
        vm.expectEmit(address(_config));
        emit IBurnerLoansConfig.AssetOriginationsSet(address(token_), true);
        vm.prank(caller_);
        _config.addAsset(address(token_), cap_, risk_, fee_, shares_);
        uint32 id = _core.marketId(address(token_));
        IFLOANv1.Market memory market = _floan.getMarket(id);
        assertEq(_floan.getMarketCount(), uint256(beforeCount) + 1, "Exactly one market created");
        assertEq(market.manager, address(_config), "Config owns market management");
        assertEq(market.facility, address(_core), "Core owns stable facility identity");
        assertEq(
            keccak256(abi.encode(_config.getAssetConfig(address(token_)))),
            keccak256(abi.encode(expected)),
            "Exact full asset configuration"
        );
        assertEq(
            keccak256(abi.encode(_config.getAssetFeeConfig(address(token_)))),
            keccak256(abi.encode(fee_)),
            "Exact full fee configuration"
        );
        assertEq(_floan.getMarketPrincipalDue(id), 0, "Listing creates no debt");
        assertEq(token_.balanceOf(address(_core)), 0, "Listing moves no collateral");
    }

    // Scenarios: BLCFG-ADD-ASSET-A02, BLCFG-ADD-ASSET-A03, BLCFG-ADD-ASSET-A04, BLCFG-ADD-ASSET-A05.
    function test_whenCallerIsNotAdmin_reverts(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!_roles.hasRole(caller_, ADMIN_ROLE));
        _setPolicyState(_core, active_, enabled_);
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-L09, BLCFG-ADD-ASSET-L10, BLCFG-ADD-ASSET-L11, BLCFG-ADD-ASSET-L12.
    function test_givenDisabled_whenAssetAdded_reverts(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigDisabled {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(IEnabler.NotEnabled.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-L01, BLCFG-ADD-ASSET-L02, BLCFG-ADD-ASSET-L03, BLCFG-ADD-ASSET-L04.
    function test_givenInactiveDisabled_whenAssetAdded_reverts(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public givenConfigDisabled givenConfigInactive {
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-L05, BLCFG-ADD-ASSET-L06, BLCFG-ADD-ASSET-L07, BLCFG-ADD-ASSET-L08.
    function test_givenInactiveEnabled_whenAssetAdded_reverts(
        bool active_,
        bool enabled_,
        address caller_
    ) public givenListingAdmin(caller_) givenConfigInactive {
        _setPolicyState(_core, active_, enabled_);
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            _inactiveError(address(_config))
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-D01.
    function test_givenCoreInactiveDisabled_whenAssetAdded_reverts(
        address caller_
    ) public givenListingAdmin(caller_) {
        _core.disable("");
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-D02.
    function test_givenCoreInactiveEnabled_whenAssetAdded_reverts(
        address caller_
    ) public givenListingAdmin(caller_) {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_core));
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-D03.
    function test_givenCoreActiveDisabled_whenAssetAdded_reverts(
        address caller_
    ) public givenListingAdmin(caller_) {
        _core.disable("");
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(0), uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I01.
    function test_whenCollateralIsZero_reverts() public {
        address token = address(0);
        _mutationReverts(
            address(this),
            abi.encodeCall(
                _config.addAsset,
                (token, uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                token
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I02.
    function test_whenCollateralIsOhm_reverts() public {
        address token = address(_ohm);
        _mutationReverts(
            address(this),
            abi.encodeCall(
                _config.addAsset,
                (token, uint128(0), _riskConfig(), _feeConfig(), false)
            ),
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                token
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I03.
    function test_whenCollateralDecimalsUnsupported_reverts(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 37, type(uint8).max));
        MockERC20 token = _listingToken(decimals_);
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                address(token)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I04.
    function test_givenDecimalsReadFails_whenAssetAdded_reverts() public {
        MockERC20 token = _listingToken(6);
        vm.mockCallRevert(
            address(token),
            abi.encodeCall(token.decimals, ()),
            abi.encodeWithSignature("DecimalsReadFailed()")
        );
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                address(token)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I04.
    function test_givenMalformedDecimals_whenAssetAdded_reverts() public {
        MockERC20 token = _listingToken(6);
        uint256[6] memory lengths = [uint256(0), 1, 31, 33, 64, 65_536];
        for (uint256 i; i < lengths.length; ++i) {
            vm.mockCall(address(token), abi.encodeCall(token.decimals, ()), new bytes(lengths[i]));
            _listingReverts(
                token,
                _riskConfig(),
                _feeConfig(),
                false,
                abi.encodeWithSelector(
                    IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                    address(token)
                )
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I05.
    function test_givenRiskRejectsPriceSupport_whenAssetAdded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeCall(_risk.validatePriceSupport, (address(token))),
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector)
        );
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I06.
    function test_givenAssetNotRegisteredInDepositManager_whenAssetAdded_reverts() public {
        MockERC20 token = _listingToken(6);
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_AssetNotRegisteredInDepositManager.selector,
                address(token),
                address(_depositManager)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I07.
    function test_givenCorePeriodAbsent_whenAssetAdded_reverts() public {
        MockERC20 token = _listingToken(6);
        _depositManager.addAsset(
            IERC20(address(token)),
            IERC4626(address(0)),
            type(uint256).max,
            0
        );
        _rolesAdmin.grantRole(DEPOSIT_OPERATOR_ROLE, _recipient);
        _depositManager.setOperatorName(_recipient, "oth");
        _depositManager.addAssetPeriod(IERC20(address(token)), 1, _recipient);
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_AssetNotRegisteredInDepositManager.selector,
                address(token),
                address(_depositManager)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-D04.
    function test_givenDepositManagerDisabled_whenAssetAdded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        _depositManager.disable("");
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-D05.
    function test_givenCorePeriodDisabled_whenAssetAdded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        _depositManager.disableAssetPeriod(IERC20(address(token)), 1, address(_core));
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I08.
    function test_whenZeroLtv_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = 0;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(0))
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I09.
    function test_whenLtvAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxLtvBps = uint16(bound(value_, 10001, type(uint16).max));
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.maxLtvBps)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I10.
    function test_whenBackingBelowMinimum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = uint16(bound(value_, 0, 9999));
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I11.
    function test_whenBackingAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.backingMultiplierBps = uint16(bound(value_, 50001, type(uint16).max));
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I12.
    function test_whenKeeperBpsAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.keeperRewardBps = uint16(bound(value_, 10001, type(uint16).max));
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.keeperRewardBps)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I13.
    function test_whenZeroTerm_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = 0;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I14.
    function test_whenTermAboveMaximum_reverts(uint48 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = uint48(bound(value_, 365 days + 1, type(uint48).max));
        cfg.maxMaturityHorizon = 366 days;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I15.
    function test_whenZeroHorizon_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxMaturityHorizon = 0;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I16.
    function test_whenHorizonBelowTerm_reverts(uint48 term_, uint48 horizon_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = uint48(bound(term_, 2, 365 days));
        cfg.maxMaturityHorizon = uint48(bound(horizon_, 1, cfg.termLength - 1));
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I17.
    function test_whenHorizonEqualsTerm_reverts(uint48 term_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = uint48(bound(term_, 1, 365 days));
        cfg.maxMaturityHorizon = cfg.termLength;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I18.
    function test_whenHorizonAboveMaximum_reverts(uint48 horizon_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.maxMaturityHorizon = uint48(bound(horizon_, 366 days + 1, type(uint48).max));
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I19.
    function test_whenBaseFeeAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = uint16(bound(value_, 10001, type(uint16).max));
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.baseFeeBps)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I20.
    function test_whenPreKinkSlopeAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.preKinkSlopeBps = uint16(bound(value_, 10001, type(uint16).max));
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.preKinkSlopeBps)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I21.
    function test_whenPostKinkSlopeAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.postKinkSlopeBps = uint16(bound(value_, 10001, type(uint16).max));
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                uint256(cfg.postKinkSlopeBps)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I22.
    function test_whenKinkAtOrAboveMaximum_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.kinkBps = uint16(bound(value_, 10000, type(uint16).max));
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I23.
    function test_whenZeroKinkAndPositivePreSlope_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg = IBurnerLoansRisk.AssetFeeConfig(0, 0, uint16(bound(value_, 1, 10000)), 0);
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I24.
    function test_whenZeroKinkAndPositivePostSlope_reverts(uint16 value_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg = IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, uint16(bound(value_, 1, 10000)));
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I25.
    function test_whenTotalAboveMaximum_reverts(uint16 base_, uint16 pre_, uint16 post_) public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _feeConfig();
        cfg.baseFeeBps = uint16(bound(base_, 0, 10000));
        cfg.preKinkSlopeBps = uint16(bound(pre_, 0, 10000));
        cfg.postKinkSlopeBps = uint16(bound(post_, 0, 10000));
        vm.assume(uint256(cfg.baseFeeBps) + cfg.preKinkSlopeBps + cfg.postKinkSlopeBps > 10000);
        _listingReverts(
            token,
            _riskConfig(),
            cfg,
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I29.
    function test_givenExistingAssetAndInvalidStruct_whenAdded_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        risk.maxLtvBps = 0;
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        fee.baseFeeBps = type(uint16).max;
        _listingReverts(
            _asset,
            risk,
            fee,
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_AssetAlreadyConfigured.selector,
                address(_asset)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I30.
    function test_givenInvalidRiskAndFee_whenAdded() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        risk.maxLtvBps = 0;
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        fee.baseFeeBps = type(uint16).max;
        _listingReverts(
            token,
            risk,
            fee,
            false,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, uint256(0))
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P01, BLCFG-ADD-ASSET-A01, BLCFG-ADD-ASSET-L13, BLCFG-ADD-ASSET-D06.
    function test_givenDirectCustody_whenAdminListsAsset(address caller_, uint128 cap_) public {
        MockERC20 token = _prepareCollateral(6);
        _grantAdmin(caller_);
        _assertListed(caller_, token, cap_, _riskConfig(), _feeConfig(), false);
    }

    // Scenarios: BLCFG-ADD-ASSET-P03, BLCFG-ADD-ASSET-A01, BLCFG-ADD-ASSET-L13, BLCFG-ADD-ASSET-D06.
    function test_givenSynchronousShares_whenAdminListsAsset(address caller_, uint128 cap_) public {
        MockERC20 token = _listingToken(18);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _registerDepositAsset(token, address(vault));
        _grantAdmin(caller_);
        _assertListed(caller_, token, cap_, _riskConfig(), _feeConfig(), true);
    }

    // Scenarios: BLCFG-ADD-ASSET-P02.
    function test_givenSynchronousVault_whenUnderlyingModeListed(
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _listingToken(18);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _registerDepositAsset(token, address(vault));
        _assertListed(caller_, token, 0, _riskConfig(), _feeConfig(), false);
    }

    // Scenarios: BLCFG-ADD-ASSET-I28, BLCFG-ADD-ASSET-I31.
    function test_givenDirectCustody_whenSharesRequested_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        fee.baseFeeBps = type(uint16).max;
        _listingReverts(
            token,
            _riskConfig(),
            fee,
            true,
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(token)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P09.
    function test_givenApprovedZeroPrice_whenListed(
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _prepareCollateral(6);
        _price.setPrice(address(token), 0);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            abi.encodeWithSignature("UnexpectedPriceRead()")
        );
        _assertListed(caller_, token, 1, _riskConfig(), _feeConfig(), false);
    }

    // Scenarios: BLCFG-ADD-ASSET-P10.
    function test_whenSupportedDecimalDomainListed(
        uint8 decimals_,
        address caller_
    ) public givenListingAdmin(caller_) {
        decimals_ = uint8(bound(decimals_, 0, 36));
        MockERC20 token = _prepareCollateral(decimals_);
        _assertListed(caller_, token, 1, _riskConfig(), _feeConfig(), false);
        assertEq(
            _config.getAssetConfig(address(token)).collateralDecimals,
            decimals_,
            "Exact asset decimals"
        );
        assertEq(
            _config.getAssetConfig(address(_asset)).collateralDecimals,
            6,
            "Other asset decimals preserved"
        );
        assertTrue(_core.marketId(address(token)) != _market, "Distinct market IDs");
    }

    // Scenarios: BLCFG-ADD-ASSET-P11, BLCFG-ADD-ASSET-P06.
    function test_whenMaximumRiskListed() public {
        MockERC20 token = _prepareCollateral(6);
        _assertListed(
            address(this),
            token,
            1,
            IBurnerLoansRisk.AssetRiskConfigInput(
                10000,
                50000,
                10000,
                365 days,
                366 days,
                type(uint128).max
            ),
            _feeConfig(),
            false
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P12, BLCFG-ADD-ASSET-P06.
    function test_whenMinimumRiskListed() public {
        MockERC20 token = _prepareCollateral(6);
        _assertListed(
            address(this),
            token,
            1,
            IBurnerLoansRisk.AssetRiskConfigInput(1, 10000, 0, 1, 2, 0),
            _feeConfig(),
            false
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P13.
    function test_whenFlatFeeListed(uint16 base_) public {
        base_ = uint16(bound(base_, 0, 10000));
        MockERC20 token = _prepareCollateral(6);
        _assertListed(
            address(this),
            token,
            1,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(base_, 0, 0, 0),
            false
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P14.
    function test_whenDecreasingSlopesAtTotalCapListed() public {
        MockERC20 token = _prepareCollateral(6);
        _assertListed(
            address(this),
            token,
            1,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(1000, 9999, 7000, 2000),
            false
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-D07.
    function test_givenRegistrationFailsAfterMarketCreation_whenAdded(
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _prepareCollateral(6);
        bytes memory error = abi.encodeWithSignature("RegistrationFailed()");
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.registerMarket.selector),
            error
        );
        uint32 markets = _floan.getMarketCount();
        _mutationReverts(
            caller_,
            abi.encodeCall(
                _config.addAsset,
                (address(token), uint128(1), _riskConfig(), _feeConfig(), false)
            ),
            error
        );
        assertEq(_floan.getMarketCount(), markets, "Failed registration consumes no market ID");
        assertFalse(_core.isAssetRegistered(address(token)), "No orphan registration");
    }

    // Scenarios: BLCFG-ADD-ASSET-C01.
    function test_givenCoreSelectsOtherConfig_whenAdded() public {
        MockERC20 token = _prepareCollateral(6);
        _risk.setConfigOperator(_recipient);
        _core.setConfigOperator(_recipient);
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IConfigOperator.ConfigOperator_Unauthorized.selector,
                address(_config)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I26.
    function test_givenAsynchronousVault_whenUnderlyingListed_reverts() public {
        MockERC20 token = _listingToken(18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            true,
            true
        );
        _registerDepositAsset(token, address(vault));
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(token),
                address(vault)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P04.
    function test_givenAsynchronousVault_whenSharesListed(
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _listingToken(18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            true,
            true
        );
        _registerDepositAsset(token, address(vault));
        _assertListed(caller_, token, 1, _riskConfig(), _feeConfig(), true);
    }

    // Scenarios: BLCFG-ADD-ASSET-I27.
    function test_givenExplicitSharesVault_whenUnderlyingListed_reverts() public {
        MockERC20 token = _listingToken(18);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Required shares", "RS");
        _registerDepositAsset(token, address(vault));
        _depositManager.setConfigOperator(_configurationCaller);
        vm.prank(_configurationCaller);
        _depositManager.setAssetShareWithdrawalRequired(IERC20(address(token)), true);
        _listingReverts(
            token,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(token),
                address(vault)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P05.
    function test_givenExplicitSharesVault_whenSharesListed(
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _listingToken(18);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Required shares", "RS");
        _registerDepositAsset(token, address(vault));
        _depositManager.setConfigOperator(_configurationCaller);
        vm.prank(_configurationCaller);
        _depositManager.setAssetShareWithdrawalRequired(IERC20(address(token)), true);
        _assertListed(caller_, token, 1, _riskConfig(), _feeConfig(), true);
    }

    // Scenarios: BLCFG-ADD-ASSET-P06.
    function test_whenFullRiskDomainListed(
        IBurnerLoansRisk.AssetRiskConfigInput memory risk_,
        uint128 cap_,
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _prepareCollateral(6);
        risk_.maxLtvBps = uint16(bound(risk_.maxLtvBps, 1, 10000));
        risk_.backingMultiplierBps = uint16(bound(risk_.backingMultiplierBps, 10000, 50000));
        risk_.keeperRewardBps = uint16(bound(risk_.keeperRewardBps, 0, 10000));
        risk_.termLength = uint48(bound(risk_.termLength, 1, 365 days));
        risk_.maxMaturityHorizon = uint48(
            bound(risk_.maxMaturityHorizon, risk_.termLength + 1, 366 days)
        );
        _assertListed(caller_, token, cap_, risk_, _feeConfig(), false);
    }

    // Scenarios: BLCFG-ADD-ASSET-P07.
    function test_whenFullFeeDomainListed(
        IBurnerLoansRisk.AssetFeeConfig memory fee_,
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _prepareCollateral(6);
        fee_.baseFeeBps = uint16(bound(fee_.baseFeeBps, 0, 10000));
        fee_.preKinkSlopeBps = uint16(bound(fee_.preKinkSlopeBps, 0, 10000 - fee_.baseFeeBps));
        fee_.postKinkSlopeBps = uint16(
            bound(fee_.postKinkSlopeBps, 0, 10000 - fee_.baseFeeBps - fee_.preKinkSlopeBps)
        );
        fee_.kinkBps = uint16(
            bound(
                fee_.kinkBps,
                fee_.preKinkSlopeBps == 0 && fee_.postKinkSlopeBps == 0 ? 0 : 1,
                9999
            )
        );
        _assertListed(caller_, token, 1, _riskConfig(), fee_, false);
    }

    // Scenarios: BLCFG-ADD-ASSET-P08.
    function test_whenIndependentRiskFeeAndVaultModeListed(
        IBurnerLoansRisk.AssetRiskConfigInput memory risk_,
        IBurnerLoansRisk.AssetFeeConfig memory fee_,
        bool shares_,
        address caller_
    ) public givenListingAdmin(caller_) {
        MockERC20 token = _listingToken(18);
        MockERC4626 vault = new MockERC4626(OZERC20(address(token)), "Vault", "V");
        _registerDepositAsset(token, address(vault));
        risk_.maxLtvBps = uint16(bound(risk_.maxLtvBps, 1, 10000));
        risk_.backingMultiplierBps = uint16(bound(risk_.backingMultiplierBps, 10000, 50000));
        risk_.keeperRewardBps = uint16(bound(risk_.keeperRewardBps, 0, 10000));
        risk_.termLength = uint48(bound(risk_.termLength, 1, 365 days));
        risk_.maxMaturityHorizon = uint48(
            bound(risk_.maxMaturityHorizon, risk_.termLength + 1, 366 days)
        );
        fee_.baseFeeBps = uint16(bound(fee_.baseFeeBps, 0, 10000));
        fee_.preKinkSlopeBps = uint16(bound(fee_.preKinkSlopeBps, 0, 10000 - fee_.baseFeeBps));
        fee_.postKinkSlopeBps = uint16(
            bound(fee_.postKinkSlopeBps, 0, 10000 - fee_.baseFeeBps - fee_.preKinkSlopeBps)
        );
        fee_.kinkBps = uint16(
            bound(
                fee_.kinkBps,
                fee_.preKinkSlopeBps == 0 && fee_.postKinkSlopeBps == 0 ? 0 : 1,
                9999
            )
        );
        _assertListed(caller_, token, 1, risk_, fee_, shares_);
    }

    // Scenarios: BLCFG-ADD-ASSET-C02.
    function test_givenCollateralCallback_whenNestedListingCaught(
        bool operator_,
        address tokenDeployer_
    ) public {
        MockERC20 candidate = _prepareCollateral(6);
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(
                _config.addAsset,
                (address(candidate), uint128(1), _riskConfig(), _feeConfig(), false)
            ),
            true,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackCaught(token);
        assertFalse(
            _core.isAssetRegistered(address(candidate)),
            "Nested listing leaves no Core registration"
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-C03.
    function test_givenCollateralCallback_whenNestedListingPropagated(
        bool operator_,
        address tokenDeployer_
    ) public {
        MockERC20 candidate = _prepareCollateral(6);
        ReentrantFeeToken token = _armConfigurationCallback(
            abi.encodeCall(
                _config.addAsset,
                (address(candidate), uint128(1), _riskConfig(), _feeConfig(), false)
            ),
            true,
            operator_,
            tokenDeployer_
        );
        _assertConfigurationCallbackPropagated(token);
        assertFalse(
            _core.isAssetRegistered(address(candidate)),
            "Nested listing leaves no Core registration"
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I03.
    function test_whenUnsupportedDecimalEndpointsSeeded_reverts() public {
        MockERC20 first = _listingToken(37);
        _listingReverts(
            first,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                address(first)
            )
        );
        MockERC20 last = _listingToken(type(uint8).max);
        _listingReverts(
            last,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_InvalidCollateralAsset.selector,
                address(last)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P10.
    function test_whenSupportedDecimalBoundariesSeeded() public {
        uint8[5] memory decimals = [uint8(0), 1, 6, 18, 36];
        for (uint256 i; i < decimals.length; ++i) {
            MockERC20 token = _prepareCollateral(decimals[i]);
            _assertListed(address(this), token, 1, _riskConfig(), _feeConfig(), false);
            assertEq(
                _config.getAssetConfig(address(token)).collateralDecimals,
                decimals[i],
                "Exact seeded token precision"
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I29.
    function test_givenExistingAssetWithOriginationsDisabled_whenAddedAgain_reverts() public {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _listingReverts(
            _asset,
            _riskConfig(),
            _feeConfig(),
            false,
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoans_AssetAlreadyConfigured.selector,
                address(_asset)
            )
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I09.
    function test_whenLtvAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(10001), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            risk.maxLtvBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                    uint256(values[i])
                )
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I10.
    function test_whenBackingBelowMinimumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[3] memory values = [uint16(0), 1, 9999];
        for (uint256 i; i < values.length; ++i) {
            risk.backingMultiplierBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I11.
    function test_whenBackingAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(50001), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            risk.backingMultiplierBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I12.
    function test_whenKeeperBpsAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(10001), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            risk.keeperRewardBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                    uint256(values[i])
                )
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I14.
    function test_whenTermAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint48[2] memory values = [uint48(365 days + 1), type(uint48).max];
        for (uint256 i; i < values.length; ++i) {
            risk.termLength = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I18.
    function test_whenHorizonAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint48[2] memory values = [uint48(366 days + 1), type(uint48).max];
        for (uint256 i; i < values.length; ++i) {
            risk.maxMaturityHorizon = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I19.
    function test_whenBaseFeeAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(10001), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            fee.baseFeeBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                    uint256(values[i])
                )
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I20.
    function test_whenPreKinkSlopeAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(10001), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            fee.preKinkSlopeBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                    uint256(values[i])
                )
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I21.
    function test_whenPostKinkSlopeAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(10001), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            fee.postKinkSlopeBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(
                    IBurnerLoansRisk.BurnerLoans_InvalidBps.selector,
                    uint256(values[i])
                )
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I22.
    function test_whenKinkAtOrAboveMaximumEndpointsSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory risk = _riskConfig();
        IBurnerLoansRisk.AssetFeeConfig memory fee = _feeConfig();
        uint16[2] memory values = [uint16(10000), type(uint16).max];
        for (uint256 i; i < values.length; ++i) {
            fee.kinkBps = values[i];
            _listingReverts(
                token,
                risk,
                fee,
                false,
                abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector)
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-I16, BLCFG-ADD-ASSET-I17.
    function test_whenHorizonRelationBoundariesSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _riskConfig();
        cfg.termLength = 365 days;
        cfg.maxMaturityHorizon = 1;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.maxMaturityHorizon = 365 days - 1;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.maxMaturityHorizon = 365 days;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        cfg.termLength = 1;
        cfg.maxMaturityHorizon = 1;
        _listingReverts(
            token,
            cfg,
            _feeConfig(),
            false,
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-P09.
    function test_givenStalePrice_whenListed(address caller_) public givenListingAdmin(caller_) {
        MockERC20 token = _prepareCollateral(6);
        vm.warp(vm.getBlockTimestamp() + 365 days);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            abi.encodeWithSignature("StalePrice()")
        );
        _assertListed(caller_, token, 1, _riskConfig(), _feeConfig(), false);
    }

    // Scenarios: BLCFG-ADD-ASSET-P13.
    function test_whenFlatFeeBoundariesSeeded() public {
        uint16[3] memory values = [uint16(0), 1, 10000];
        for (uint256 i; i < values.length; ++i) {
            MockERC20 token = _prepareCollateral(6);
            _assertListed(
                address(this),
                token,
                1,
                _riskConfig(),
                IBurnerLoansRisk.AssetFeeConfig(values[i], 0, 0, 0),
                false
            );
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-P06.
    function test_whenListingCapBoundariesSeeded() public {
        uint128[3] memory caps = [uint128(0), 1, type(uint128).max];
        for (uint256 i; i < caps.length; ++i) {
            MockERC20 token = _prepareCollateral(6);
            _assertListed(address(this), token, caps[i], _riskConfig(), _feeConfig(), false);
        }
    }

    // Scenarios: BLCFG-ADD-ASSET-P07.
    function test_whenSingleSlopeMaximumsSeeded() public {
        MockERC20 first = _prepareCollateral(6);
        _assertListed(
            address(this),
            first,
            1,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 10000, 0),
            false
        );
        MockERC20 second = _prepareCollateral(6);
        _assertListed(
            address(this),
            second,
            1,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(0, 9999, 0, 10000),
            false
        );
    }

    // Scenarios: BLCFG-ADD-ASSET-I25.
    function test_whenTotalFeeOverflowBoundariesSeeded_reverts() public {
        MockERC20 token = _prepareCollateral(6);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector
        );
        _listingReverts(
            token,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(5000, 1, 5001, 0),
            false,
            reason
        );
        _listingReverts(
            token,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(5000, 9999, 0, 5001),
            false,
            reason
        );
        _listingReverts(
            token,
            _riskConfig(),
            IBurnerLoansRisk.AssetFeeConfig(10000, 9999, 10000, 10000),
            false,
            reason
        );
    }
}
