// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetAssetRiskConfigTest is BurnerLoansTest {
    uint16 internal constant MAX_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_FACTOR_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_RATIO_BPS = 50_000;
    uint16 internal constant MAX_BACKING_MULTIPLIER_BPS = 50_000;
    uint48 internal constant MAX_TERM_LENGTH = 365 days;
    uint48 internal constant MAX_MATURITY_HORIZON = 366 days;
    uint256 internal constant MAX_KEEPER_REWARD = type(uint128).max;

    event AssetRiskConfigSet(address indexed asset, IBurnerLoans.AssetRiskConfigInput config);

    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
        _setDefaultConfigurator();
        _enableConfigTimelock();
    }

    // setAssetRiskConfig
    // given caller is neither admin nor configurator
    //  when setAssetRiskConfig is called
    //   then it reverts before validating the config
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.collateralFactorBps = 0;

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnauthorizedConfigurator.selector,
                caller_
            )
        );
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given the policy is disabled
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), _validRiskConfig());
    }

    // setAssetRiskConfig
    // given asset is not configured
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts() public {
        address unknownAsset = makeAddr("unknownAsset");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unknownAsset
            )
        );
        burnerLoansConfig.setAssetRiskConfig(unknownAsset, _validRiskConfig());
    }

    // setAssetRiskConfig
    // given the asset/token pair exists only under another facility
    //  when setAssetRiskConfig is called by admin
    //   then it reverts because the bound facility has no market
    function test_givenBoundFacilityMarketDoesNotExist_reverts() public {
        uint32 marketId = burnerLoansConfig.marketId(address(usds));

        vm.prank(address(burnerLoansConfig));
        floan.setMarketFacility(marketId, makeAddr("otherFacility"));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.setAssetRiskConfig(address(usds), _validRiskConfig());
    }

    // setAssetRiskConfig
    // given collateralFactorBps is zero
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenCollateralFactorBpsIsZero_reverts() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.collateralFactorBps = 0;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, 0));
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given collateralFactorBps is greater than the protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenCollateralFactorBpsAboveMax_reverts(uint16 collateralFactorBps_) public {
        collateralFactorBps_ = uint16(
            bound(collateralFactorBps_, MAX_COLLATERAL_FACTOR_BPS + 1, type(uint16).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.collateralFactorBps = collateralFactorBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidBps.selector,
                collateralFactorBps_
            )
        );
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given minCollateralRatioBps is below 100%
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMinCollateralRatioBpsBelowMin_reverts(uint16 minCollateralRatioBps_) public {
        minCollateralRatioBps_ = uint16(bound(minCollateralRatioBps_, 0, 9_999));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.minCollateralRatioBps = minCollateralRatioBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given minCollateralRatioBps is above the protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMinCollateralRatioBpsAboveMax_reverts(uint16 minCollateralRatioBps_) public {
        minCollateralRatioBps_ = uint16(
            bound(minCollateralRatioBps_, MAX_COLLATERAL_RATIO_BPS + 1, type(uint16).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.minCollateralRatioBps = minCollateralRatioBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given backingMultiplierBps is below 100%
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenBackingMultiplierBpsBelowMin_reverts(uint16 backingMultiplierBps_) public {
        backingMultiplierBps_ = uint16(bound(backingMultiplierBps_, 0, 9_999));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.backingMultiplierBps = backingMultiplierBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given backingMultiplierBps is above the protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenBackingMultiplierBpsAboveMax_reverts(uint16 backingMultiplierBps_) public {
        backingMultiplierBps_ = uint16(
            bound(backingMultiplierBps_, MAX_BACKING_MULTIPLIER_BPS + 1, type(uint16).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.backingMultiplierBps = backingMultiplierBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given keeperRewardBps is greater than 100%
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenKeeperRewardBpsAboveMax_reverts(uint16 keeperRewardBps_) public {
        keeperRewardBps_ = uint16(bound(keeperRewardBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.keeperRewardBps = keeperRewardBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, keeperRewardBps_)
        );
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given maxKeeperReward is above the protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaxKeeperRewardAboveMax_reverts(uint256 maxKeeperReward_) public {
        maxKeeperReward_ = bound(maxKeeperReward_, MAX_KEEPER_REWARD + 1, type(uint256).max);
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxKeeperReward = maxKeeperReward_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given protocol-level term and maturity horizon constants
    //  when the bounds are compared
    //   then the max maturity horizon is strictly greater than the max term length
    function test_givenProtocolTermConstants_maxMaturityHorizonExceedsMaxTermLength() public pure {
        assertGt(MAX_MATURITY_HORIZON, MAX_TERM_LENGTH, "max horizon must exceed max term");
    }

    // setAssetRiskConfig
    // given termLength is zero
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenTermLengthIsZero_reverts() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.termLength = 0;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given termLength is above max
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenTermLengthAboveMax_reverts(uint48 termLength_) public {
        termLength_ = uint48(bound(termLength_, MAX_TERM_LENGTH + 1, type(uint48).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.termLength = termLength_;
        config.maxMaturityHorizon = MAX_MATURITY_HORIZON;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given maxMaturityHorizon is below or equal to termLength
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaxMaturityHorizonBelowOrEqualToTermLength_reverts(
        uint48 maxMaturityHorizon_
    ) public {
        maxMaturityHorizon_ = uint48(bound(maxMaturityHorizon_, 1, 14 days));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxMaturityHorizon = maxMaturityHorizon_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given maxMaturityHorizon is above max
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaxMaturityHorizonAboveMax_reverts(uint48 maxMaturityHorizon_) public {
        maxMaturityHorizon_ = uint48(
            bound(maxMaturityHorizon_, MAX_MATURITY_HORIZON + 1, type(uint48).max)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxMaturityHorizon = maxMaturityHorizon_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given risk values are inside the valid combined range
    //  when setAssetRiskConfig is called by admin
    //   then every risk field is replaced
    function test_givenRiskConfigInValidRange_updatesConfig(
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_,
        uint16 backingMultiplierBps_,
        uint16 keeperRewardBps_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint256 maxKeeperReward_
    ) public {
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
        maxKeeperReward_ = bound(maxKeeperReward_, 0, MAX_KEEPER_REWARD);

        IBurnerLoans.AssetRiskConfigInput memory config = IBurnerLoans.AssetRiskConfigInput({
            collateralFactorBps: collateralFactorBps_,
            minCollateralRatioBps: minCollateralRatioBps_,
            backingMultiplierBps: backingMultiplierBps_,
            keeperRewardBps: keeperRewardBps_,
            termLength: termLength_,
            maxMaturityHorizon: maxMaturityHorizon_,
            maxKeeperReward: maxKeeperReward_
        });

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetRiskConfigSet(address(usds), config);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.collateralFactorBps, collateralFactorBps_, "collateral factor");
        assertEq(stored.minCollateralRatioBps, minCollateralRatioBps_, "min collateral ratio");
        assertEq(stored.backingMultiplierBps, backingMultiplierBps_, "backing multiplier");
        assertEq(stored.keeperRewardBps, keeperRewardBps_, "reward");
        assertEq(stored.termLength, termLength_, "term length");
        assertEq(stored.maxMaturityHorizon, maxMaturityHorizon_, "max maturity horizon");
        assertEq(stored.maxKeeperReward, maxKeeperReward_, "max reward");
    }

    // setAssetRiskConfig
    // given an asset has admin-only config fields
    //  when setAssetRiskConfig is called by admin
    //   then enabled state, decimals, and debt cap are preserved
    function test_givenRiskConfigUpdates_preservesAdminOnlyFields() public {
        IBurnerLoans.AssetConfig memory beforeConfig = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.collateralFactorBps = 9_500;
        config.maxKeeperReward = 500e6;

        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.originationsEnabled, beforeConfig.originationsEnabled, "enabled");
        assertEq(stored.collateralDecimals, beforeConfig.collateralDecimals, "decimals");
        assertEq(stored.debtCap, beforeConfig.debtCap, "debt cap");
        assertEq(stored.collateralFactorBps, 9_500, "collateral factor");
        assertEq(stored.maxKeeperReward, 500e6, "max reward");
    }

    // setAssetRiskConfig
    // given multiple assets are configured
    //  when setAssetRiskConfig is called for one asset
    //   then the other asset risk config is unchanged
    function test_givenMultipleAssets_updatesOnlySpecifiedAsset() public {
        MockERC20 otherAsset = new MockERC20("Other Asset", "OTHER", USDS_DECIMALS);
        _configurePrice(address(otherAsset), 1e18);
        _configureDepositManagerAsset(address(otherAsset));

        IBurnerLoans.AssetConfig memory otherConfig = _defaultAssetConfig(USDS_DECIMALS);
        otherConfig.collateralFactorBps = 8_500;
        otherConfig.minCollateralRatioBps = 13_000;
        otherConfig.backingMultiplierBps = 12_000;
        otherConfig.keeperRewardBps = 200;
        otherConfig.termLength = 21 days;
        otherConfig.maxMaturityHorizon = 180 days;
        otherConfig.maxKeeperReward = 750e6;

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(otherAsset),
            uint128(otherConfig.debtCap),
            _assetRiskConfigInputFromConfig(otherConfig),
            _defaultAssetFeeConfig()
        );

        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.collateralFactorBps = 9_250;

        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory targetStored = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        assertEq(targetStored.collateralFactorBps, 9_250, "target collateral factor");

        IBurnerLoans.AssetConfig memory otherStored = burnerLoansConfig.getAssetConfig(
            address(otherAsset)
        );
        assertEq(
            otherStored.collateralFactorBps,
            otherConfig.collateralFactorBps,
            "other collateral factor"
        );
        assertEq(
            otherStored.minCollateralRatioBps,
            otherConfig.minCollateralRatioBps,
            "other min cr"
        );
        assertEq(
            otherStored.backingMultiplierBps,
            otherConfig.backingMultiplierBps,
            "other backing multiplier"
        );
        assertEq(otherStored.keeperRewardBps, otherConfig.keeperRewardBps, "other keeper reward");
        assertEq(otherStored.termLength, otherConfig.termLength, "other term length");
        assertEq(
            otherStored.maxMaturityHorizon,
            otherConfig.maxMaturityHorizon,
            "other maturity horizon"
        );
        assertEq(
            otherStored.maxKeeperReward,
            otherConfig.maxKeeperReward,
            "other max keeper reward"
        );
    }

    // setAssetRiskConfig
    // given caller is the configurator
    //  when setAssetRiskConfig is called with valid config
    //   then all risk fields change
    function test_givenConfiguratorCaller_updatesRiskConfig() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();

        vm.prank(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetRiskConfigSet(address(usds), config);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.minCollateralRatioBps, 12_000, "min collateral ratio");
        assertEq(stored.backingMultiplierBps, 11_000, "backing multiplier");
        assertEq(stored.termLength, 14 days, "term length");
        assertEq(stored.maxMaturityHorizon, 120 days, "max maturity horizon");
        assertEq(stored.maxKeeperReward, 500e6, "max reward");
    }

    function _validRiskConfig()
        internal
        pure
        returns (IBurnerLoans.AssetRiskConfigInput memory config)
    {
        config = IBurnerLoans.AssetRiskConfigInput({
            collateralFactorBps: 9_500,
            minCollateralRatioBps: 12_000,
            backingMultiplierBps: 11_000,
            keeperRewardBps: 500,
            termLength: 14 days,
            maxMaturityHorizon: 120 days,
            maxKeeperReward: 500e6
        });
    }
}
