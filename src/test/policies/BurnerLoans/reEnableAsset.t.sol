// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansReEnableAssetTest is BurnerLoansTest {
    event AssetEnabled(address indexed asset);
    event AssetReenabled(address indexed asset);

    // reEnableAsset
    // given asset is not configured
    //  when reEnableAsset is called by burner_loans_admin
    //   then it reverts
    function test_givenAssetNotConfigured_reverts(address asset_) public {
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoans.reEnableAsset(asset_);
    }

    // reEnableAsset
    // given caller has neither admin nor burner_loans_admin role
    //  when reEnableAsset is called within the grace period
    //   then it reverts
    function test_givenNonAdminOrBurnerLoansAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        _addDefaultUsdsAsset();

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        burnerLoans.reEnableAsset(address(usds));
    }

    // reEnableAsset
    // given the asset re-enable grace period has elapsed
    //  when reEnableAsset is called by burner_loans_admin
    //   then it reverts
    function test_givenGracePeriodElapsed_reverts(
        uint32 gracePeriod_,
        uint48 elapsedAfterDeadline_
    ) public {
        uint32 gracePeriod = uint32(bound(gracePeriod_, 1, type(uint32).max));
        uint48 elapsedAfterDeadline = uint48(bound(elapsedAfterDeadline_, 1, 365 days));

        vm.prank(admin);
        burnerLoans.enable("");
        vm.prank(admin);
        burnerLoans.setGracePeriod(gracePeriod);

        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        uint48 deadline = uint48(1234 + uint48(gracePeriod));
        vm.warp(uint256(deadline) + elapsedAfterDeadline);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetReenableExpired.selector,
                address(usds),
                deadline
            )
        );
        burnerLoans.reEnableAsset(address(usds));
    }

    // reEnableAsset
    // given PRICE returns zero for the disabled asset
    //  when reEnableAsset is called by burner_loans_admin
    //   then it revalidates dependencies and reverts
    function test_givenPriceIsZero_reverts() public {
        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));
        _configurePrice(address(usds), 0);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.reEnableAsset(address(usds));
    }

    // reEnableAsset
    // given DepositManager disables the BurnerLoans deposit period for the asset
    //  when reEnableAsset is called by burner_loans_admin
    //   then it revalidates dependencies and reverts
    function test_givenDepositManagerPeriodDisabled_reverts() public {
        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));
        depositManager.disableAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.reEnableAsset(address(usds));
    }

    // reEnableAsset
    // given caller has burner_loans_admin role and the grace period is active
    //  when reEnableAsset is called
    //   then the asset is re-enabled
    function test_givenBurnerLoansAdminCallerWithinGracePeriod_reenablesAsset() public {
        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        vm.warp(1234 + BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetReenabled(address(usds));
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(address(usds));
        burnerLoans.reEnableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
        assertEq(burnerLoans.assetDisabledAt(address(usds)), 0, "disabled at");
    }

    // reEnableAsset
    // given caller has burner_loans_admin role and a fuzzed timestamp within the grace period
    //  when reEnableAsset is called
    //   then the asset is re-enabled
    function test_givenBurnerLoansAdminCallerWithinGracePeriod_reenablesAsset_fuzz(
        uint48 disabledAt_,
        uint32 elapsed_
    ) public {
        uint48 disabledAt = uint48(
            bound(
                disabledAt_,
                1,
                uint256(type(uint48).max) - BurnerLoansConstants.REENABLE_GRACE_PERIOD
            )
        );
        uint32 elapsed = uint32(bound(elapsed_, 0, BurnerLoansConstants.REENABLE_GRACE_PERIOD));

        _addDefaultUsdsAsset();
        vm.warp(disabledAt);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        assertEq(burnerLoans.assetDisabledAt(address(usds)), disabledAt, "disabled at before");

        vm.warp(uint256(disabledAt) + elapsed);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetReenabled(address(usds));
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(address(usds));
        burnerLoans.reEnableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
        assertEq(burnerLoans.assetDisabledAt(address(usds)), 0, "disabled at");
    }

    // reEnableAsset
    // given caller has burner_loans_admin role and a custom grace period is active
    //  when reEnableAsset is called
    //   then the asset is re-enabled
    function test_givenBurnerLoansAdminCallerWithinConfiguredGracePeriod_reenablesAsset() public {
        uint32 gracePeriod = 2 days;
        vm.prank(admin);
        burnerLoans.enable("");
        vm.prank(admin);
        burnerLoans.setGracePeriod(gracePeriod);

        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        vm.warp(1234 + gracePeriod);
        vm.prank(burnerLoansAdmin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetReenabled(address(usds));
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(address(usds));
        burnerLoans.reEnableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
        assertEq(burnerLoans.assetDisabledAt(address(usds)), 0, "disabled at");
    }

    // reEnableAsset
    // given multiple assets have different enabled and disabled states
    //  when reEnableAsset is called for one disabled asset
    //   then only the specified asset state is changed
    function test_givenMultipleAssets_reenablesOnlySpecifiedAsset() public {
        MockERC20 disabledAsset = new MockERC20("Disabled Asset", "DISABLED", USDS_DECIMALS);
        MockERC20 enabledAsset = new MockERC20("Enabled Asset", "ENABLED", USDS_DECIMALS);

        _configurePrice(address(disabledAsset), 1e18);
        _configurePrice(address(enabledAsset), 1e18);
        _configureDepositManagerAsset(address(disabledAsset));
        _configureDepositManagerAsset(address(enabledAsset));
        _addDefaultUsdsAsset();

        vm.startPrank(admin);
        burnerLoans.addAsset(
            address(disabledAsset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        burnerLoans.addAsset(
            address(enabledAsset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        vm.stopPrank();

        vm.warp(1234);
        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        vm.warp(2345);
        vm.prank(emergency);
        burnerLoans.disableAsset(address(disabledAsset));

        uint48 otherDisabledAt = burnerLoans.assetDisabledAt(address(disabledAsset));

        vm.warp(3456);
        vm.prank(burnerLoansAdmin);
        burnerLoans.reEnableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "target enabled");
        assertEq(burnerLoans.assetDisabledAt(address(usds)), 0, "target disabled at");

        assertFalse(
            burnerLoans.getAssetConfig(address(disabledAsset)).enabled,
            "other disabled enabled"
        );
        assertEq(
            burnerLoans.assetDisabledAt(address(disabledAsset)),
            otherDisabledAt,
            "other disabled timestamp"
        );

        assertTrue(
            burnerLoans.getAssetConfig(address(enabledAsset)).enabled,
            "other enabled enabled"
        );
        assertEq(
            burnerLoans.assetDisabledAt(address(enabledAsset)),
            0,
            "other enabled disabled at"
        );
    }

    // reEnableAsset
    // given caller has admin role and the grace period is active
    //  when reEnableAsset is called
    //   then the asset is re-enabled
    function test_givenAdminCallerWithinGracePeriod_reenablesAsset() public {
        _addDefaultUsdsAsset();
        vm.warp(1234);

        vm.prank(emergency);
        burnerLoans.disableAsset(address(usds));

        vm.warp(1234 + BurnerLoansConstants.REENABLE_GRACE_PERIOD);
        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetReenabled(address(usds));
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(address(usds));
        burnerLoans.reEnableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
        assertEq(burnerLoans.assetDisabledAt(address(usds)), 0, "disabled at");
    }
}
