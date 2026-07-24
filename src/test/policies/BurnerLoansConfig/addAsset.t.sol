// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansMarketConfig} from "src/policies/libraries/BurnerLoansMarketConfig.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigAddAssetTest is BurnerLoansTest {
    uint16 internal constant MAX_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_FACTOR_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_RATIO_BPS = 50_000;
    uint16 internal constant MAX_BACKING_MULTIPLIER_BPS = 50_000;
    uint48 internal constant MAX_TERM_LENGTH = 365 days;
    uint48 internal constant MAX_MATURITY_HORIZON = 366 days;
    uint256 internal constant MAX_KEEPER_REWARD = type(uint128).max;

    event AssetAdded(address indexed asset, IBurnerLoans.AssetConfig config);
    event AssetFeeConfigSet(address indexed asset, IBurnerLoans.AssetFeeConfig config);
    event AssetOriginationsSet(address indexed asset, bool enabled);

    function _expectAssetAdded(
        address asset_,
        IBurnerLoans.AssetConfig memory expectedConfig_,
        IBurnerLoans.AssetFeeConfig memory expectedFeeConfig_
    ) internal {
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetAdded(asset_, expectedConfig_);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetFeeConfigSet(asset_, expectedFeeConfig_);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetOriginationsSet(asset_, true);
    }

    // addAsset
    // given caller does not have the admin role
    //  when addAsset is called
    //   then it reverts before validating the asset
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given the policy is disabled
    //  when addAsset is called by admin
    //   then it reverts before validating the asset
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given asset address is zero
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenAssetIsZero_reverts() public {
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoansConfig.addAsset(
            address(0),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given asset debt cap is zero
    //  when addAsset is called by admin
    //   then the asset is configured with zero borrow capacity
    function test_givenZeroDebtCap_configuresAsset() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        IBurnerLoans.AssetRiskConfigInput memory input = _defaultAssetRiskConfigInput();
        uint128 debtCap = 0;
        IBurnerLoans.AssetConfig memory expected = _defaultAssetConfig(USDS_DECIMALS);
        expected.debtCap = debtCap;

        vm.prank(admin);
        _expectAssetAdded(address(usds), expected, _defaultAssetFeeConfig());
        burnerLoansConfig.addAsset(address(usds), debtCap, input, _defaultAssetFeeConfig());

        assertTrue(burnerLoansConfig.isAssetConfigured(address(usds)), "configured");
        assertEq(burnerLoansConfig.getAssetConfig(address(usds)).debtCap, 0, "debt cap");
    }

    // addAsset
    // given asset has already been added
    //  when addAsset is called by admin
    //   then it cannot be added a second time
    function test_givenAssetHasAlreadyBeenAdded_cannotAddAssetSecondTime() public {
        _addDefaultUsdsAsset();

        assertTrue(
            burnerLoansConfig.isAssetConfigured(address(usds)),
            "asset configured after first add"
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetAlreadyConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given asset has already been added and disabled
    //  when addAsset is called by admin
    //   then it still cannot be added a second time
    function test_givenAssetHasAlreadyBeenAddedAndDisabled_cannotAddAssetSecondTime() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertTrue(burnerLoansConfig.isAssetConfigured(address(usds)), "asset remains configured");
        assertFalse(stored.originationsEnabled, "originations disabled");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetAlreadyConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given collateral decimals exceed the supported maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenTokenDecimalsAboveMax_reverts(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 37, type(uint8).max));
        MockERC20 highDecimals = new MockERC20("HIGH", "HIGH", decimals_);
        _configurePrice(address(highDecimals), 1e18);
        _configureDepositManagerAsset(address(highDecimals));
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidDecimals.selector, decimals_)
        );
        burnerLoansConfig.addAsset(
            address(highDecimals),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given the asset debt cap exceeds the facility's global debt cap
    //  when addAsset is called by admin
    //   then the independent market cap is accepted
    function test_givenDebtCapAboveGlobalDebtCap_configuresMarket(uint128 debtCapOhm_) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        debtCapOhm_ = uint128(
            bound(debtCapOhm_, burnerLoans.globalDebtCapOhm() + 1, type(uint128).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();

        vm.prank(admin);
        burnerLoansConfig.addAsset(address(usds), debtCapOhm_, config, _defaultAssetFeeConfig());

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).debtCap,
            debtCapOhm_,
            "asset debt cap"
        );
    }

    // addAsset
    // given collateralFactorBps is zero or above the protocol maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenCollateralFactorBpsIsInvalid_reverts_fuzz(
        uint16 collateralFactorBps_,
        bool useZero_
    ) public {
        _setDefaultGlobalDebtCap();
        collateralFactorBps_ = useZero_
            ? 0
            : uint16(bound(collateralFactorBps_, MAX_COLLATERAL_FACTOR_BPS + 1, type(uint16).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.collateralFactorBps = collateralFactorBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidBps.selector,
                collateralFactorBps_
            )
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given minCollateralRatioBps is below 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenMinCollateralRatioBpsIsInvalid_reverts_fuzz(
        uint16 minCollateralRatioBps_
    ) public {
        _setDefaultGlobalDebtCap();
        minCollateralRatioBps_ = uint16(bound(minCollateralRatioBps_, 0, 9_999));
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.minCollateralRatioBps = minCollateralRatioBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given minCollateralRatioBps is above the protocol maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenMinCollateralRatioBpsAboveMax_reverts_fuzz(
        uint16 minCollateralRatioBps_
    ) public {
        _setDefaultGlobalDebtCap();
        minCollateralRatioBps_ = uint16(
            bound(minCollateralRatioBps_, MAX_COLLATERAL_RATIO_BPS + 1, type(uint16).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.minCollateralRatioBps = minCollateralRatioBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given backingMultiplierBps is below 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenBackingMultiplierBpsIsInvalid_reverts_fuzz(
        uint16 backingMultiplierBps_
    ) public {
        _setDefaultGlobalDebtCap();
        backingMultiplierBps_ = uint16(bound(backingMultiplierBps_, 0, 9_999));
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.backingMultiplierBps = backingMultiplierBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given backingMultiplierBps is above the protocol maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenBackingMultiplierBpsAboveMax_reverts_fuzz(
        uint16 backingMultiplierBps_
    ) public {
        _setDefaultGlobalDebtCap();
        backingMultiplierBps_ = uint16(
            bound(backingMultiplierBps_, MAX_BACKING_MULTIPLIER_BPS + 1, type(uint16).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.backingMultiplierBps = backingMultiplierBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given keeperRewardBps is above 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenKeeperRewardBpsIsInvalid_reverts_fuzz(uint16 keeperRewardBps_) public {
        _setDefaultGlobalDebtCap();
        keeperRewardBps_ = uint16(bound(keeperRewardBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.keeperRewardBps = keeperRewardBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, keeperRewardBps_)
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given maxKeeperReward is above the protocol maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenMaxKeeperRewardAboveMax_reverts_fuzz(uint256 maxKeeperReward_) public {
        _setDefaultGlobalDebtCap();
        maxKeeperReward_ = bound(maxKeeperReward_, MAX_KEEPER_REWARD + 1, type(uint256).max);
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.maxKeeperReward = maxKeeperReward_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given termLength is zero or above the protocol maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenTermLengthIsInvalid_reverts_fuzz(uint48 termLength_, bool useZero_) public {
        _setDefaultGlobalDebtCap();
        termLength_ = useZero_
            ? 0
            : uint48(bound(termLength_, MAX_TERM_LENGTH + 1, type(uint48).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.termLength = termLength_;
        config.maxMaturityHorizon = MAX_MATURITY_HORIZON;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given maxMaturityHorizon is below or equal to termLength
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenMaxMaturityHorizonBelowOrEqualToTermLength_reverts_fuzz(
        uint48 termLength_,
        uint48 maxMaturityHorizon_
    ) public {
        _setDefaultGlobalDebtCap();
        termLength_ = uint48(bound(termLength_, 1, MAX_TERM_LENGTH));
        maxMaturityHorizon_ = uint48(bound(maxMaturityHorizon_, 0, termLength_));
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.termLength = termLength_;
        config.maxMaturityHorizon = maxMaturityHorizon_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given maxMaturityHorizon is above the protocol maximum
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenMaxMaturityHorizonAboveMax_reverts_fuzz(uint48 maxMaturityHorizon_) public {
        _setDefaultGlobalDebtCap();
        maxMaturityHorizon_ = uint48(
            bound(maxMaturityHorizon_, MAX_MATURITY_HORIZON + 1, type(uint48).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();
        config.maxMaturityHorizon = maxMaturityHorizon_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            config,
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given the initial baseFeeBps is above 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenBaseFeeBpsIsInvalid_reverts_fuzz(uint16 baseFeeBps_) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        baseFeeBps_ = uint16(bound(baseFeeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();
        feeConfig.baseFeeBps = baseFeeBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, baseFeeBps_)
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given the initial kinkBps is greater than or equal to 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenKinkBpsIsInvalid_reverts_fuzz(uint16 kinkBps_) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        kinkBps_ = uint16(bound(kinkBps_, 10_000, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();
        feeConfig.kinkBps = kinkBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given the initial preKinkSlopeBps is above 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenPreKinkSlopeBpsIsInvalid_reverts_fuzz(uint16 preKinkSlopeBps_) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();
        feeConfig.preKinkSlopeBps = preKinkSlopeBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, preKinkSlopeBps_)
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given the initial postKinkSlopeBps is above 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenPostKinkSlopeBpsIsInvalid_reverts_fuzz(uint16 postKinkSlopeBps_) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();
        feeConfig.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, postKinkSlopeBps_)
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given PRICE does not return a valid collateral price
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenPriceDoesNotApproveAsset_reverts() public {
        _configureDepositManagerAsset(address(usds));
        _setDefaultGlobalDebtCap();

        assertFalse(price.isAssetApproved(address(usds)), "asset should not be PRICE-approved");

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given PRICE approves the asset but returns zero
    //  when addAsset is called by admin
    //   then PRICE rejects the dependency check
    function test_givenPriceIsZero_reverts() public {
        _configurePrice(address(usds), 0);
        _configureDepositManagerAsset(address(usds));
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given DepositManager does not support the collateral asset
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenMissingDepositManagerSupport_reverts() public {
        _configurePrice(address(usds), 1e18);
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given kink is zero and the post-kink slope is non-zero
    //  when addAsset is called by admin
    //   then it reverts because a post-kink segment has no domain
    function test_givenZeroKinkAndNonZeroPostKinkSlope_reverts() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();
        feeConfig.kinkBps = 0;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given kink is zero and the pre-kink slope is non-zero
    //  when addAsset is called by admin
    //   then it reverts because a sloped curve requires a kink
    function test_givenZeroKinkAndNonZeroPreKinkSlope_reverts() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();
        feeConfig.kinkBps = 0;
        feeConfig.postKinkSlopeBps = 0;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given each fee component is valid but their full-utilization rate exceeds 100%
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenFullUtilizationFeeRateAboveOneWad_reverts_fuzz(
        uint16 baseFeeBps_,
        uint16 preKinkSlopeBps_
    ) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        baseFeeBps_ = uint16(bound(baseFeeBps_, 1, MAX_BPS));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, MAX_BPS + 1 - baseFeeBps_, MAX_BPS));
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: 0,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: 0
        });

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );
    }

    // addAsset
    // given the DepositManager asset and facility period are configured and enabled
    //  when addAsset is called by admin
    //   then dependency validation permits market creation
    function test_givenDepositManagerAssetAndPeriodAreEnabled_configuresAsset() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        assertTrue(
            depositManager.getAssetConfiguration(IERC20(address(usds))).isConfigured,
            "DepositManager asset configured"
        );
        assertTrue(
            depositManager
                .isAssetPeriod(
                    IERC20(address(usds)),
                    BurnerLoansConstants.DEPOSIT_PERIOD,
                    address(burnerLoans)
                )
                .isEnabled,
            "DepositManager period enabled"
        );

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        assertTrue(burnerLoansConfig.isAssetConfigured(address(usds)), "asset configured");
    }

    // addAsset
    // given a configured pair is replaced by a market with another config ID and malformed data
    //  when its asset and fee configurations are read
    //   then both reject the incompatible schema before decoding the data
    function test_givenDifferentConfigId_configGettersRevertBeforeDecoding() public {
        _addDefaultUsdsAsset();
        bytes16 incompatibleConfigId = bytes16("Different config");
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
            marketId,
            incompatibleConfigId
        );

        vm.expectRevert(expectedError);
        burnerLoansConfig.getAssetConfig(address(usds));

        vm.expectRevert(expectedError);
        burnerLoansConfig.getAssetFeeConfig(address(usds));
    }

    // addAsset
    // given a configured pair has the Burner Loans config ID but malformed data length
    //  when its asset and fee configurations are read
    //   then both reject the byte length before ABI decoding
    function test_givenInvalidConfigDataLength_configGettersRevertBeforeDecoding(
        uint16 configDataLength_
    ) public {
        configDataLength_ = uint16(bound(configDataLength_, 0, 384));
        vm.assume(configDataLength_ != 6 * 32);
        bytes memory configData = new bytes(configDataLength_);
        _addDefaultUsdsAsset();
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            bytes16("Burner Loans v1"),
            configData
        );
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
            marketId,
            configDataLength_
        );

        vm.expectRevert(expectedError);
        burnerLoansConfig.getAssetConfig(address(usds));

        vm.expectRevert(expectedError);
        burnerLoansConfig.getAssetFeeConfig(address(usds));
    }

    // addAsset
    // given asset dependencies and config are valid
    //  when addAsset is called by admin
    //   then the asset is configured and enabled
    function test_givenValidConfig_configuresAsset() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();

        IBurnerLoans.AssetRiskConfigInput memory input = _defaultAssetRiskConfigInput();
        IBurnerLoans.AssetConfig memory expected = _defaultAssetConfig(USDS_DECIMALS);

        assertFalse(
            burnerLoansConfig.isAssetConfigured(address(usds)),
            "not configured before add"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.getAssetConfig(address(usds));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.getAssetFeeConfig(address(usds));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.marketId(address(usds));

        vm.prank(admin);
        _expectAssetAdded(address(usds), expected, _defaultAssetFeeConfig());
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            input,
            _defaultAssetFeeConfig()
        );

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        IBurnerLoans.AssetFeeConfig memory storedFeeConfig = burnerLoansConfig.getAssetFeeConfig(
            address(usds)
        );
        assertTrue(burnerLoansConfig.isAssetConfigured(address(usds)), "configured");
        assertEq(burnerLoansConfig.marketId(address(usds)), 0, "market id");
        assertTrue(stored.originationsEnabled, "enabled");
        assertEq(stored.collateralDecimals, USDS_DECIMALS, "decimals");
        assertEq(stored.debtCap, _defaultAssetDebtCap(), "debt cap");
        assertEq(storedFeeConfig.baseFeeBps, _defaultAssetFeeConfig().baseFeeBps, "base fee");
        assertEq(storedFeeConfig.kinkBps, _defaultAssetFeeConfig().kinkBps, "kink");
        assertEq(
            storedFeeConfig.preKinkSlopeBps,
            _defaultAssetFeeConfig().preKinkSlopeBps,
            "pre-kink slope"
        );
        assertEq(
            storedFeeConfig.postKinkSlopeBps,
            _defaultAssetFeeConfig().postKinkSlopeBps,
            "post-kink slope"
        );

        IFLOANv1.Market memory market = floan.getMarket(0);
        assertEq(floan.getMarketCount(), 1, "FLOAN market count");
        assertEq(market.collateralToken, address(usds), "FLOAN collateral token");
        assertEq(market.debtToken, address(ohm), "FLOAN debt token");
        assertEq(market.manager, address(burnerLoansConfig), "FLOAN manager");
        assertEq(market.facility, address(burnerLoans), "FLOAN facility");
        assertEq(market.configId, bytes16("Burner Loans v1"), "FLOAN config id");
        assertEq(market.principalCap, expected.debtCap, "FLOAN principal cap");
        assertEq(market.termLength, expected.termLength, "FLOAN term length");
        assertEq(market.maxMaturityHorizon, expected.maxMaturityHorizon, "FLOAN maturity horizon");
        assertEq(
            market.collateralFactorBps,
            expected.collateralFactorBps,
            "FLOAN collateral factor"
        );
        assertEq(
            market.minCollateralRatioBps,
            expected.minCollateralRatioBps,
            "FLOAN collateral ratio"
        );
        assertEq(market.baseFeeBps, storedFeeConfig.baseFeeBps, "FLOAN base fee");
        assertEq(market.collateralDecimals, USDS_DECIMALS, "FLOAN collateral decimals");
        assertEq(market.debtDecimals, OHM_DECIMALS, "FLOAN debt decimals");
        assertTrue(market.originationsEnabled, "FLOAN originations enabled");

        BurnerLoansMarketConfig.Data memory marketData = BurnerLoansMarketConfig.decode(
            0,
            market,
            floan.getMarketConfigData(0)
        );
        assertEq(marketData.maxKeeperReward, expected.maxKeeperReward, "FLOAN keeper cap");
        assertEq(
            marketData.backingMultiplierBps,
            expected.backingMultiplierBps,
            "FLOAN backing multiplier"
        );
        assertEq(marketData.keeperRewardBps, expected.keeperRewardBps, "FLOAN keeper bps");
        assertEq(marketData.kinkBps, storedFeeConfig.kinkBps, "FLOAN kink");
        assertEq(
            marketData.preKinkSlopeBps,
            storedFeeConfig.preKinkSlopeBps,
            "FLOAN pre-kink slope"
        );
        assertEq(
            marketData.postKinkSlopeBps,
            storedFeeConfig.postKinkSlopeBps,
            "FLOAN post-kink slope"
        );
    }

    // addAsset
    // given asset dependencies and fuzzed risk values are valid
    //  when addAsset is called by admin
    //   then the asset stores the risk values with the fixed valid fee curve
    function test_givenValidRiskConfig_configuresAsset_fuzz(
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_,
        uint16 backingMultiplierBps_,
        uint16 keeperRewardBps_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint128 debtCap_,
        uint256 maxKeeperReward_
    ) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();

        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 1, MAX_COLLATERAL_FACTOR_BPS));
        minCollateralRatioBps_ = uint16(
            bound(minCollateralRatioBps_, MAX_BPS, MAX_COLLATERAL_RATIO_BPS)
        );
        backingMultiplierBps_ = uint16(
            bound(backingMultiplierBps_, MAX_BPS, MAX_BACKING_MULTIPLIER_BPS)
        );
        keeperRewardBps_ = uint16(bound(keeperRewardBps_, 0, MAX_BPS));
        termLength_ = uint48(bound(termLength_, 1, MAX_TERM_LENGTH));
        maxMaturityHorizon_ = uint48(
            bound(maxMaturityHorizon_, termLength_ + 1, MAX_MATURITY_HORIZON)
        );
        debtCap_ = uint128(bound(debtCap_, 0, type(uint128).max));
        maxKeeperReward_ = bound(maxKeeperReward_, 0, MAX_KEEPER_REWARD);

        IBurnerLoans.AssetRiskConfigInput memory input = IBurnerLoans.AssetRiskConfigInput({
            collateralFactorBps: collateralFactorBps_,
            minCollateralRatioBps: minCollateralRatioBps_,
            backingMultiplierBps: backingMultiplierBps_,
            keeperRewardBps: keeperRewardBps_,
            termLength: termLength_,
            maxMaturityHorizon: maxMaturityHorizon_,
            maxKeeperReward: maxKeeperReward_
        });
        IBurnerLoans.AssetConfig memory expected = IBurnerLoans.AssetConfig({
            originationsEnabled: true,
            collateralDecimals: USDS_DECIMALS,
            collateralFactorBps: collateralFactorBps_,
            minCollateralRatioBps: minCollateralRatioBps_,
            backingMultiplierBps: backingMultiplierBps_,
            keeperRewardBps: keeperRewardBps_,
            termLength: termLength_,
            maxMaturityHorizon: maxMaturityHorizon_,
            debtCap: debtCap_,
            maxKeeperReward: maxKeeperReward_
        });
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        vm.prank(admin);
        _expectAssetAdded(address(usds), expected, feeConfig);
        burnerLoansConfig.addAsset(address(usds), debtCap_, input, feeConfig);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.originationsEnabled, expected.originationsEnabled, "enabled");
        assertEq(stored.collateralDecimals, expected.collateralDecimals, "collateral decimals");
        assertEq(stored.collateralFactorBps, expected.collateralFactorBps, "collateral factor");
        assertEq(stored.minCollateralRatioBps, expected.minCollateralRatioBps, "min cr");
        assertEq(stored.backingMultiplierBps, expected.backingMultiplierBps, "backing multiplier");
        assertEq(stored.keeperRewardBps, expected.keeperRewardBps, "keeper reward bps");
        assertEq(stored.termLength, expected.termLength, "term length");
        assertEq(stored.maxMaturityHorizon, expected.maxMaturityHorizon, "max maturity horizon");
        assertEq(stored.debtCap, expected.debtCap, "debt cap");
        assertEq(stored.maxKeeperReward, expected.maxKeeperReward, "max keeper reward");
    }

    // addAsset
    // given asset dependencies and fuzzed fee values are valid
    //  when addAsset is called by admin
    //   then the market stores the fee curve with the fixed valid risk config
    // The fee model does not require pre-kink and post-kink slopes to be monotonic. It requires
    // each component to fit in bps, a non-zero kink when either slope is used, and the sum of
    // base plus both slopes (the full-utilization rate) to remain at or below 100%.
    function test_givenValidFeeConfig_configuresAsset_fuzz(
        uint16 baseFeeBps_,
        uint16 kinkBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
    ) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        baseFeeBps_ = uint16(bound(baseFeeBps_, 0, MAX_BPS));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 0, MAX_BPS - baseFeeBps_));
        postKinkSlopeBps_ = uint16(
            bound(postKinkSlopeBps_, 0, MAX_BPS - baseFeeBps_ - preKinkSlopeBps_)
        );
        kinkBps_ = preKinkSlopeBps_ == 0 && postKinkSlopeBps_ == 0
            ? uint16(bound(kinkBps_, 0, MAX_BPS - 1))
            : uint16(bound(kinkBps_, 1, MAX_BPS - 1));
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: kinkBps_,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: postKinkSlopeBps_
        });

        vm.prank(admin);
        _expectAssetAdded(address(usds), _defaultAssetConfig(USDS_DECIMALS), feeConfig);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            feeConfig
        );

        IBurnerLoans.AssetFeeConfig memory storedFeeConfig = burnerLoansConfig.getAssetFeeConfig(
            address(usds)
        );
        assertEq(storedFeeConfig.baseFeeBps, feeConfig.baseFeeBps, "base fee");
        assertEq(storedFeeConfig.kinkBps, feeConfig.kinkBps, "kink");
        assertEq(storedFeeConfig.preKinkSlopeBps, feeConfig.preKinkSlopeBps, "pre-kink slope");
        assertEq(storedFeeConfig.postKinkSlopeBps, feeConfig.postKinkSlopeBps, "post-kink slope");
    }

    // addAsset
    // given another collateral asset has a different decimal scale
    //  when addAsset is called for both assets by admin
    //   then each asset stores its own decimals
    function test_givenSecondCollateralWithDifferentDecimals_configuresAsset() public {
        MockERC20 weth = new MockERC20("WETH", "WETH", 18);
        _configureUsdsDependencies();
        _configurePrice(address(weth), 3_000e18);
        _configureDepositManagerAsset(address(weth));
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        _expectAssetAdded(
            address(usds),
            _defaultAssetConfig(USDS_DECIMALS),
            _defaultAssetFeeConfig()
        );
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        vm.prank(admin);
        _expectAssetAdded(address(weth), _defaultAssetConfig(18), _defaultAssetFeeConfig());
        burnerLoansConfig.addAsset(
            address(weth),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        assertTrue(burnerLoansConfig.isAssetConfigured(address(weth)), "configured");
        assertEq(
            burnerLoansConfig.getAssetConfig(address(weth)).collateralDecimals,
            18,
            "decimals"
        );
    }
}
