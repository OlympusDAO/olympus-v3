// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetAssetRiskConfigTest is BurnerLoansTest {
    uint16 internal constant _MAX_BPS = 10_000;
    uint16 internal constant _MAX_LTV_BPS = 10_000;
    uint16 internal constant _MAX_BACKING_MULTIPLIER_BPS = 50_000;
    uint48 internal constant _EXPECTED_MAX_TERM_LENGTH = 365 days;
    uint48 internal constant _EXPECTED_MAX_MATURITY_HORIZON = 366 days;
    uint256 internal constant _MAX_KEEPER_REWARD = type(uint128).max;

    event AssetRiskConfigSet(address indexed asset, IBurnerLoans.AssetRiskConfigInput config);

    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
        _setDefaultConfigOperator();
        _enableConfigTimelock();
    }

    // setAssetRiskConfig
    // given caller is neither admin nor timelock
    //  when setAssetRiskConfig is called
    //   then it reverts before validating the config
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxLtvBps = 0;

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
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

        _setMarketFacilityForTest(marketId, makeAddr("otherFacility"));

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
    // given maxLtvBps is zero
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaximumLtvIsZero_reverts() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxLtvBps = 0;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, 0));
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given maxLtvBps is greater than the protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaximumLtvIsAboveMax_reverts(uint16 maxLtvBps_) public {
        maxLtvBps_ = uint16(bound(maxLtvBps_, _MAX_LTV_BPS + 1, type(uint16).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxLtvBps = maxLtvBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, maxLtvBps_)
        );
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
            bound(backingMultiplierBps_, _MAX_BACKING_MULTIPLIER_BPS + 1, type(uint16).max)
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
        maxKeeperReward_ = bound(maxKeeperReward_, _MAX_KEEPER_REWARD + 1, type(uint256).max);
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxKeeperReward = maxKeeperReward_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
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
    // given termLength equals the expected protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it updates the config
    function test_givenTermLengthAtMaximum_updatesConfig() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.termLength = _EXPECTED_MAX_TERM_LENGTH;
        config.maxMaturityHorizon = _EXPECTED_MAX_MATURITY_HORIZON;

        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.termLength, _EXPECTED_MAX_TERM_LENGTH, "term length");
        assertEq(stored.maxMaturityHorizon, _EXPECTED_MAX_MATURITY_HORIZON, "max maturity horizon");
    }

    // setAssetRiskConfig
    // given termLength is one second above the expected protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenTermLengthOneAboveMaximum_reverts() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.termLength = _EXPECTED_MAX_TERM_LENGTH + 1;
        config.maxMaturityHorizon = _EXPECTED_MAX_MATURITY_HORIZON;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given termLength is above max
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenTermLengthAboveMax_reverts(uint48 termLength_) public {
        termLength_ = uint48(bound(termLength_, _EXPECTED_MAX_TERM_LENGTH + 1, type(uint48).max));
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.termLength = termLength_;
        config.maxMaturityHorizon = _EXPECTED_MAX_MATURITY_HORIZON;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);
    }

    // setAssetRiskConfig
    // given maxMaturityHorizon equals termLength
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaxMaturityHorizonEqualsTermLength_reverts() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxMaturityHorizon = config.termLength;

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
    // given maxMaturityHorizon equals the expected protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it updates the config
    function test_givenMaxMaturityHorizonAtMaximum_updatesConfig() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxMaturityHorizon = _EXPECTED_MAX_MATURITY_HORIZON;

        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.maxMaturityHorizon, _EXPECTED_MAX_MATURITY_HORIZON, "max maturity horizon");
    }

    // setAssetRiskConfig
    // given maxMaturityHorizon is one second above the expected protocol maximum
    //  when setAssetRiskConfig is called by admin
    //   then it reverts
    function test_givenMaxMaturityHorizonOneAboveMaximum_reverts() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();
        config.maxMaturityHorizon = _EXPECTED_MAX_MATURITY_HORIZON + 1;

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
            bound(maxMaturityHorizon_, _EXPECTED_MAX_MATURITY_HORIZON + 1, type(uint48).max)
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
        uint16 maxLtvBps_,
        uint16 backingMultiplierBps_,
        uint16 keeperRewardBps_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint256 maxKeeperReward_
    ) public {
        maxLtvBps_ = uint16(bound(maxLtvBps_, 1, _MAX_LTV_BPS));
        backingMultiplierBps_ = uint16(
            bound(backingMultiplierBps_, _MAX_BPS, _MAX_BACKING_MULTIPLIER_BPS)
        );
        keeperRewardBps_ = uint16(bound(keeperRewardBps_, 0, _MAX_BPS));
        termLength_ = uint48(bound(termLength_, 1, _EXPECTED_MAX_TERM_LENGTH));
        maxMaturityHorizon_ = uint48(
            bound(maxMaturityHorizon_, termLength_ + 1, _EXPECTED_MAX_MATURITY_HORIZON)
        );
        maxKeeperReward_ = bound(maxKeeperReward_, 0, _MAX_KEEPER_REWARD);

        IBurnerLoans.AssetRiskConfigInput memory config = IBurnerLoans.AssetRiskConfigInput({
            maxLtvBps: maxLtvBps_,
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
        assertEq(stored.maxLtvBps, maxLtvBps_, "maximum LTV");
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
        config.maxLtvBps = 9_500;
        config.maxKeeperReward = 500e6;

        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.originationsEnabled, beforeConfig.originationsEnabled, "enabled");
        assertEq(stored.collateralDecimals, beforeConfig.collateralDecimals, "decimals");
        assertEq(stored.debtCap, beforeConfig.debtCap, "debt cap");
        assertEq(stored.maxLtvBps, 9_500, "maximum LTV");
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
        otherConfig.maxLtvBps = 8_500;
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
        config.maxLtvBps = 9_250;

        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory targetStored = burnerLoansConfig.getAssetConfig(
            address(usds)
        );
        assertEq(targetStored.maxLtvBps, 9_250, "target maximum LTV");

        IBurnerLoans.AssetConfig memory otherStored = burnerLoansConfig.getAssetConfig(
            address(otherAsset)
        );
        assertEq(otherStored.maxLtvBps, otherConfig.maxLtvBps, "other maximum LTV");
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
    // given caller is the timelock
    //  when setAssetRiskConfig is called with valid config
    //   then all risk fields change
    function test_givenTimelockCaller_updatesRiskConfig() public {
        IBurnerLoans.AssetRiskConfigInput memory config = _validRiskConfig();

        vm.prank(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetRiskConfigSet(address(usds), config);
        burnerLoansConfig.setAssetRiskConfig(address(usds), config);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertEq(stored.maxLtvBps, 9_500, "maximum LTV");
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
            maxLtvBps: 9_500,
            backingMultiplierBps: 11_000,
            keeperRewardBps: 500,
            termLength: 14 days,
            maxMaturityHorizon: 120 days,
            maxKeeperReward: 500e6
        });
    }
}
