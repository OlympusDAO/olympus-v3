// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetAssetFeeConfigTest is BurnerLoansTest {
    event AssetFeeConfigSet(address indexed asset, IBurnerLoans.AssetFeeConfig config);

    function setUp() public override {
        super.setUp();
        _addDefaultUsdsAsset();
        _setDefaultConfigOperator();
        _enableConfigTimelock();

        vm.prank(admin);
        burnerLoansConfig.setAssetFeeConfig(address(usds), _defaultAssetFeeConfig());
    }

    // setAssetFeeConfig
    // given caller is neither admin nor timelock
    //  when setAssetFeeConfig is called
    //   then it reverts before validating the config
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.baseFeeBps = 10_001;

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given the policy is disabled
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setAssetFeeConfig(address(usds), _defaultAssetFeeConfig());
    }

    // setAssetFeeConfig
    // given asset is not configured
    //  when setAssetFeeConfig is called by admin
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
        burnerLoansConfig.setAssetFeeConfig(unknownAsset, _defaultAssetFeeConfig());
    }

    // setAssetFeeConfig
    // given the asset/token pair exists only under another facility
    //  when setAssetFeeConfig is called by admin
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
        burnerLoansConfig.setAssetFeeConfig(address(usds), _defaultAssetFeeConfig());
    }

    // setAssetFeeConfig
    // given baseFeeBps is greater than 100%
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenBaseFeeBpsAboveMax_reverts(uint16 baseFeeBps_) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.baseFeeBps = baseFeeBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, baseFeeBps_)
        );
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given kinkBps is zero and postKinkSlopeBps is non-zero
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenKinkBpsIsZeroAndPostKinkSlopeBpsIsNonZero_reverts(
        uint16 postKinkSlopeBps_
    ) public {
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 1, 10_000));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.kinkBps = 0;
        config.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given kinkBps is zero and preKinkSlopeBps is non-zero
    //  when setAssetFeeConfig is called by admin
    //   then it reverts because a sloped curve requires a kink
    function test_givenKinkBpsIsZeroAndPreKinkSlopeBpsIsNonZero_reverts(
        uint16 preKinkSlopeBps_
    ) public {
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 1, 10_000));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.kinkBps = 0;
        config.preKinkSlopeBps = preKinkSlopeBps_;
        config.postKinkSlopeBps = 0;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given kinkBps is greater than or equal to 100%
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenKinkBpsAtOrAboveMax_reverts(uint16 kinkBps_) public {
        kinkBps_ = uint16(bound(kinkBps_, 10_000, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.kinkBps = kinkBps_;

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given preKinkSlopeBps is greater than 100%
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenPreKinkSlopeBpsAboveMax_reverts(uint16 preKinkSlopeBps_) public {
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.preKinkSlopeBps = preKinkSlopeBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, preKinkSlopeBps_)
        );
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given postKinkSlopeBps is greater than 100%
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenPostKinkSlopeBpsAboveMax_reverts(uint16 postKinkSlopeBps_) public {
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, postKinkSlopeBps_)
        );
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given fee rate at full utilization exceeds 100%
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenFullUtilizationFeeRateAboveOneWad_reverts(
        uint16 baseFeeBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
    ) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 1, 10_000));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 0, 10_000 - baseFeeBps_));
        postKinkSlopeBps_ = uint16(
            bound(postKinkSlopeBps_, 10_001 - baseFeeBps_ - preKinkSlopeBps_, 10_000)
        );
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: 5_000,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: postKinkSlopeBps_
        });

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given baseFeeBps plus preKinkSlopeBps exceeds 100% on a single-slope curve
    //  when setAssetFeeConfig is called by admin
    //   then it reverts
    function test_givenBaseFeePlusSingleSlopeAboveOneWad_reverts(
        uint16 baseFeeBps_,
        uint16 preKinkSlopeBps_
    ) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 1, 10_000));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 10_001 - baseFeeBps_, 10_000));
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: 0,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: 0
        });

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);
    }

    // setAssetFeeConfig
    // given fee config values are in the valid range
    //  when setAssetFeeConfig is called by admin
    //   then it updates for every valid full config
    function test_givenFeeConfigInValidRange_updatesConfig(
        uint16 baseFeeBps_,
        uint16 kinkBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
    ) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 0, 10_000));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 0, 10_000 - baseFeeBps_));
        postKinkSlopeBps_ = uint16(
            bound(postKinkSlopeBps_, 0, 10_000 - baseFeeBps_ - preKinkSlopeBps_)
        );
        if (preKinkSlopeBps_ == 0 && postKinkSlopeBps_ == 0) {
            kinkBps_ = uint16(bound(kinkBps_, 0, 9_999));
        } else {
            kinkBps_ = uint16(bound(kinkBps_, 1, 9_999));
        }
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: kinkBps_,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: postKinkSlopeBps_
        });

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetFeeConfigSet(address(usds), config);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);

        IBurnerLoans.AssetFeeConfig memory stored = burnerLoansConfig.getAssetFeeConfig(
            address(usds)
        );
        assertEq(stored.baseFeeBps, baseFeeBps_, "base fee");
        assertEq(stored.kinkBps, kinkBps_, "kink");
        assertEq(stored.preKinkSlopeBps, preKinkSlopeBps_, "pre-kink slope");
        assertEq(stored.postKinkSlopeBps, postKinkSlopeBps_, "post-kink slope");
    }

    // setAssetFeeConfig
    // given preKinkSlopeBps is greater than postKinkSlopeBps but the full-utilization fee is within the cap
    //  when setAssetFeeConfig is called by admin
    //   then it updates because Aave-style slopes are segment deltas, not ordered gradients
    function test_givenPreKinkSlopeBpsGreaterThanPostKinkSlopeBps_updatesConfig() public {
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.preKinkSlopeBps = 900;
        config.postKinkSlopeBps = 100;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetFeeConfigSet(address(usds), config);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);

        assertEq(
            burnerLoansConfig.getAssetFeeConfig(address(usds)).preKinkSlopeBps,
            900,
            "pre-kink slope"
        );
        assertEq(
            burnerLoansConfig.getAssetFeeConfig(address(usds)).postKinkSlopeBps,
            100,
            "post-kink slope"
        );
    }

    // setAssetFeeConfig
    // given multiple assets are configured
    //  when setAssetFeeConfig is called for one asset
    //   then the other asset fee config is unchanged
    function test_givenMultipleAssets_updatesOnlySpecifiedAsset() public {
        MockERC20 otherAsset = new MockERC20("Other Asset", "OTHER", USDS_DECIMALS);
        _configurePrice(address(otherAsset), 1e18);
        _configureDepositManagerAsset(address(otherAsset));

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(otherAsset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        IBurnerLoans.AssetFeeConfig memory otherFeeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 40,
            kinkBps: 7_500,
            preKinkSlopeBps: 200,
            postKinkSlopeBps: 700
        });
        vm.prank(admin);
        burnerLoansConfig.setAssetFeeConfig(address(otherAsset), otherFeeConfig);

        IBurnerLoans.AssetFeeConfig memory targetConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 75,
            kinkBps: 6_000,
            preKinkSlopeBps: 300,
            postKinkSlopeBps: 600
        });

        vm.prank(admin);
        burnerLoansConfig.setAssetFeeConfig(address(usds), targetConfig);

        IBurnerLoans.AssetFeeConfig memory targetStored = burnerLoansConfig.getAssetFeeConfig(
            address(usds)
        );
        assertEq(targetStored.baseFeeBps, targetConfig.baseFeeBps, "target base fee");
        assertEq(targetStored.kinkBps, targetConfig.kinkBps, "target kink");
        assertEq(
            targetStored.preKinkSlopeBps,
            targetConfig.preKinkSlopeBps,
            "target pre-kink slope"
        );
        assertEq(
            targetStored.postKinkSlopeBps,
            targetConfig.postKinkSlopeBps,
            "target post-kink slope"
        );

        IBurnerLoans.AssetFeeConfig memory otherStored = burnerLoansConfig.getAssetFeeConfig(
            address(otherAsset)
        );
        assertEq(otherStored.baseFeeBps, otherFeeConfig.baseFeeBps, "other base fee");
        assertEq(otherStored.kinkBps, otherFeeConfig.kinkBps, "other kink");
        assertEq(
            otherStored.preKinkSlopeBps,
            otherFeeConfig.preKinkSlopeBps,
            "other pre-kink slope"
        );
        assertEq(
            otherStored.postKinkSlopeBps,
            otherFeeConfig.postKinkSlopeBps,
            "other post-kink slope"
        );
    }

    // setAssetFeeConfig
    // given kinkBps and both slope fields are zero
    //  when setAssetFeeConfig is called by admin
    //   then a flat base-fee curve is accepted
    function test_givenKinkBpsAndSlopesAreZero_setsFlatFeeConfig() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 100,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetFeeConfigSet(address(usds), config);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);

        IBurnerLoans.AssetFeeConfig memory stored = burnerLoansConfig.getAssetFeeConfig(
            address(usds)
        );
        assertEq(stored.kinkBps, 0, "kink");
        assertEq(stored.preKinkSlopeBps, 0, "pre-kink slope");
        assertEq(stored.postKinkSlopeBps, 0, "post-kink slope");
    }

    // setAssetFeeConfig
    // given caller is the timelock
    //  when a valid full config is provided
    //   then the fee config is updated
    function test_givenTimelockCaller_setsFullConfig() public {
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.baseFeeBps = 30;

        vm.prank(address(configTimelock));
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetFeeConfigSet(address(usds), config);
        burnerLoansConfig.setAssetFeeConfig(address(usds), config);

        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 30, "base fee");
    }
}
