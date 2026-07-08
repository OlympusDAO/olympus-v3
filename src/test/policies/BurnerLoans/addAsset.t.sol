// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansAddAssetTest is BurnerLoansTest {
    uint16 internal constant MAX_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_FACTOR_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_RATIO_BPS = 50_000;
    uint16 internal constant MAX_BACKING_MULTIPLIER_BPS = 50_000;
    uint48 internal constant MAX_TERM_LENGTH = 365 days;
    uint48 internal constant MAX_MATURITY_HORIZON = 366 days;
    uint256 internal constant MAX_KEEPER_REWARD = type(uint128).max;

    event AssetAdded(address indexed asset, IBurnerLoans.AssetConfig config);
    event AssetFeeConfigSet(address indexed asset, IBurnerLoans.AssetFeeConfig config);
    event AssetEnabled(address indexed asset);

    function _expectAssetAdded(
        address asset_,
        IBurnerLoans.AssetConfig memory expectedConfig_,
        IBurnerLoans.AssetFeeConfig memory expectedFeeConfig_
    ) internal {
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetAdded(asset_, expectedConfig_);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetFeeConfigSet(asset_, expectedFeeConfig_);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(asset_);
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
        burnerLoans.addAsset(
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
        burnerLoans.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.addAsset(
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
    function test_givenZeroAddress_reverts() public {
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.addAsset(
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
        uint256 debtCap = 0;
        IBurnerLoans.AssetConfig memory expected = _defaultAssetConfig(USDS_DECIMALS);
        expected.debtCap = debtCap;

        vm.prank(admin);
        _expectAssetAdded(address(usds), expected, _defaultAssetFeeConfig());
        burnerLoans.addAsset(address(usds), debtCap, input, _defaultAssetFeeConfig());

        assertTrue(burnerLoans.isAssetConfigured(address(usds)), "configured");
        assertEq(burnerLoans.getAssetConfig(address(usds)).debtCap, 0, "debt cap");
    }

    // addAsset
    // given asset has already been added
    //  when addAsset is called by admin
    //   then it cannot be added a second time
    function test_givenAssetHasAlreadyBeenAdded_cannotAddAssetSecondTime() public {
        _addDefaultUsdsAsset();

        assertTrue(
            burnerLoans.isAssetConfigured(address(usds)),
            "asset configured after first add"
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetAlreadyConfigured.selector,
                address(usds)
            )
        );
        burnerLoans.addAsset(
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
        burnerLoans.disableAsset(address(usds));

        IBurnerLoans.AssetConfig memory stored = burnerLoans.getAssetConfig(address(usds));
        assertTrue(burnerLoans.isAssetConfigured(address(usds)), "asset remains configured");
        assertFalse(stored.enabled, "asset disabled");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetAlreadyConfigured.selector,
                address(usds)
            )
        );
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
            address(highDecimals),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    // addAsset
    // given the asset debt cap exceeds the global debt cap
    //  when addAsset is called by admin
    //   then it reverts
    function test_givenDebtCapAboveGlobalDebtCap_reverts(uint256 debtCapOhm_) public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();
        debtCapOhm_ = bound(debtCapOhm_, burnerLoans.globalDebtCapOhm() + 1, type(uint128).max);
        IBurnerLoans.AssetRiskConfigInput memory config = _defaultAssetRiskConfigInput();

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidCap.selector);
        burnerLoans.addAsset(address(usds), debtCapOhm_, config, _defaultAssetFeeConfig());
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
    function test_givenMissingPrice_reverts() public {
        _configureDepositManagerAsset(address(usds));
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
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
        burnerLoans.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
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

        vm.prank(admin);
        _expectAssetAdded(address(usds), expected, _defaultAssetFeeConfig());
        burnerLoans.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            input,
            _defaultAssetFeeConfig()
        );

        IBurnerLoans.AssetConfig memory stored = burnerLoans.getAssetConfig(address(usds));
        IBurnerLoans.AssetFeeConfig memory storedFeeConfig = burnerLoans.getAssetFeeConfig(
            address(usds)
        );
        assertTrue(burnerLoans.isAssetConfigured(address(usds)), "configured");
        assertTrue(stored.enabled, "enabled");
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
    }

    // addAsset
    // given asset dependencies and fuzzed config values are valid
    //  when addAsset is called by admin
    //   then the asset stores the input values, enables the asset, and derives decimals
    function test_givenValidConfig_configuresAsset_fuzz(
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_,
        uint16 backingMultiplierBps_,
        uint16 keeperRewardBps_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint256 debtCap_,
        uint256 maxKeeperReward_,
        uint16 baseFeeBps_,
        uint16 kinkBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
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
        debtCap_ = bound(debtCap_, 0, burnerLoans.globalDebtCapOhm());
        maxKeeperReward_ = bound(maxKeeperReward_, 0, MAX_KEEPER_REWARD);
        baseFeeBps_ = uint16(bound(baseFeeBps_, 0, 10_000));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 0, 10_000 - baseFeeBps_));
        postKinkSlopeBps_ = uint16(
            bound(postKinkSlopeBps_, 0, 10_000 - baseFeeBps_ - preKinkSlopeBps_)
        );
        if (postKinkSlopeBps_ == 0) {
            kinkBps_ = uint16(bound(kinkBps_, 0, 9_999));
        } else {
            kinkBps_ = uint16(bound(kinkBps_, 1, 9_999));
        }

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
            enabled: true,
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
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: kinkBps_,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: postKinkSlopeBps_
        });

        vm.prank(admin);
        _expectAssetAdded(address(usds), expected, feeConfig);
        burnerLoans.addAsset(address(usds), debtCap_, input, feeConfig);

        IBurnerLoans.AssetConfig memory stored = burnerLoans.getAssetConfig(address(usds));
        IBurnerLoans.AssetFeeConfig memory storedFeeConfig = burnerLoans.getAssetFeeConfig(
            address(usds)
        );
        assertEq(stored.enabled, expected.enabled, "enabled");
        assertEq(stored.collateralDecimals, expected.collateralDecimals, "collateral decimals");
        assertEq(stored.collateralFactorBps, expected.collateralFactorBps, "collateral factor");
        assertEq(stored.minCollateralRatioBps, expected.minCollateralRatioBps, "min cr");
        assertEq(stored.backingMultiplierBps, expected.backingMultiplierBps, "backing multiplier");
        assertEq(stored.keeperRewardBps, expected.keeperRewardBps, "keeper reward bps");
        assertEq(stored.termLength, expected.termLength, "term length");
        assertEq(stored.maxMaturityHorizon, expected.maxMaturityHorizon, "max maturity horizon");
        assertEq(stored.debtCap, expected.debtCap, "debt cap");
        assertEq(stored.maxKeeperReward, expected.maxKeeperReward, "max keeper reward");
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
        burnerLoans.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        vm.prank(admin);
        _expectAssetAdded(address(weth), _defaultAssetConfig(18), _defaultAssetFeeConfig());
        burnerLoans.addAsset(
            address(weth),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        assertTrue(burnerLoans.isAssetConfigured(address(weth)), "configured");
        assertEq(burnerLoans.getAssetConfig(address(weth)).collateralDecimals, 18, "decimals");
    }
}
