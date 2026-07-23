// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Vm} from "forge-std/Vm.sol";

import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

import {BurnerLoansTest} from "src/test/policies/BurnerLoans/BurnerLoansTest.sol";

contract BurnerLoansConfigSetAssetOriginationsEnabledTest is BurnerLoansTest {
    event AssetOriginationsSet(address indexed asset, bool enabled);

    // setAssetOriginationsEnabled
    // given asset is not configured
    //  when setAssetOriginationsEnabled is called by admin
    //   then it reverts
    function test_givenAssetNotConfigured_reverts(address asset_) public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoansConfig.setAssetOriginationsEnabled(asset_, true);
    }

    // setAssetOriginationsEnabled
    // given caller is neither admin nor the configured timelock
    //  when setAssetOriginationsEnabled is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));
        vm.assume(caller_ != address(0));
        _addDefaultUsdsAsset();

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnauthorizedConfigurator.selector,
                caller_
            )
        );
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
    }

    // setAssetOriginationsEnabled
    // given caller has burner_loans_admin but is not the configured timelock
    //  when originations are disabled directly
    //   then it reverts because the role must use the queued timelock path
    function test_givenBurnerLoansAdminCallsDirectly_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnauthorizedConfigurator.selector,
                burnerLoansAdmin
            )
        );
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
    }

    // setAssetOriginationsEnabled
    // given the config policy is disabled
    //  when setAssetOriginationsEnabled is called by admin
    //   then it reverts
    function test_givenConfigDisabled_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.disable("");

        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
    }

    // setAssetOriginationsEnabled
    // given originations are enabled
    //  when admin disables them directly
    //   then the market rejects new originations
    function test_givenAdminCaller_disablesOriginations() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetOriginationsSet(address(usds), false);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations disabled"
        );
    }

    // setAssetOriginationsEnabled
    // given originations already have the requested state
    //  when admin sets the same state
    //   then it performs no writes or emits any events
    function test_givenRequestedStateAlreadySet_isNoOp(bool enabled_) public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), enabled_);

        vm.recordLogs();
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), enabled_);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            enabled_,
            "originations state"
        );
        assertEq(entries.length, 0, "no-op event count");
    }

    // setAssetOriginationsEnabled
    // given the asset/token pair exists only under another facility
    //  when setAssetOriginationsEnabled is called by admin
    //   then it reverts because the bound facility has no market
    function test_givenBoundFacilityMarketDoesNotExist_reverts() public {
        _addDefaultUsdsAsset();
        uint32 marketId_ = burnerLoansConfig.marketId(address(usds));

        vm.prank(address(burnerLoansConfig));
        floan.setMarketFacility(marketId_, makeAddr("otherFacility"));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(usds)
            )
        );
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
    }

    // setAssetOriginationsEnabled
    // given PRICE does not approve the disabled asset
    //  when setAssetOriginationsEnabled is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenPriceDoesNotApproveAsset_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.mockCall(
            address(price),
            abi.encodeWithSelector(IPRICEv2.isAssetApproved.selector, address(usds)),
            abi.encode(false)
        );

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
    }

    // setAssetOriginationsEnabled
    // given PRICE returns zero for the disabled asset
    //  when setAssetOriginationsEnabled is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenPriceIsZero_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        _configurePrice(address(usds), 0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
    }

    // setAssetOriginationsEnabled
    // given DepositManager does not support the disabled asset
    //  when setAssetOriginationsEnabled is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenMissingDepositManagerAssetSupport_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.mockCall(
            address(depositManager),
            abi.encodeWithSelector(
                IAssetManager.getAssetConfiguration.selector,
                IERC20(address(usds))
            ),
            abi.encode(
                IAssetManager.AssetConfiguration({
                    isConfigured: false,
                    depositCap: 0,
                    minimumDeposit: 0,
                    vault: address(0)
                })
            )
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
    }

    // setAssetOriginationsEnabled
    // given DepositManager does not configure the BurnerLoans deposit period for the disabled asset
    //  when setAssetOriginationsEnabled is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenMissingDepositManagerPeriodSupport_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.mockCall(
            address(depositManager),
            abi.encodeWithSelector(
                IDepositManager.isAssetPeriod.selector,
                IERC20(address(usds)),
                BurnerLoansConstants.DEPOSIT_PERIOD,
                address(burnerLoans)
            ),
            abi.encode(IDepositManager.AssetPeriodStatus({isConfigured: false, isEnabled: false}))
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
    }

    // setAssetOriginationsEnabled
    // given DepositManager disables the BurnerLoans deposit period for the asset
    //  when setAssetOriginationsEnabled is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenDepositManagerPeriodDisabled_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        depositManager.disableAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);
    }

    // setAssetOriginationsEnabled
    // given asset is configured with originations disabled
    //  when setAssetOriginationsEnabled is called by admin
    //   then the asset originations are enabled
    function test_givenAdminCaller_enablesDisabledAsset() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetOriginationsSet(address(usds), true);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations enabled"
        );
    }

    // setAssetOriginationsEnabled
    // given asset originations are disabled
    //  when setAssetOriginationsEnabled is called by admin
    //   then admin can recover the asset through the normal enable path
    function test_givenOriginationsDisabled_allowsAdminRecovery() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoansConfig));
        emit AssetOriginationsSet(address(usds), true);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), true);

        assertTrue(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations enabled"
        );
    }
}
