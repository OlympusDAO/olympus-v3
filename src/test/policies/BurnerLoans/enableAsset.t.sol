// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansEnableAssetTest is BurnerLoansTest {
    event AssetEnabled(address indexed asset);

    // enableAsset
    // given asset is not configured
    //  when enableAsset is called by admin
    //   then it reverts
    function test_givenAssetNotConfigured_reverts(address asset_) public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        burnerLoans.enableAsset(asset_);
    }

    // enableAsset
    // given caller does not have the admin role
    //  when enableAsset is called
    //   then it reverts
    function test_givenNonAdminCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        _addDefaultUsdsAsset();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        burnerLoans.enableAsset(address(usds));
    }

    // enableAsset
    // given PRICE does not approve the disabled asset
    //  when enableAsset is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenPriceDoesNotApproveAsset_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));

        vm.mockCall(
            address(price),
            abi.encodeWithSelector(IPRICEv2.isAssetApproved.selector, address(usds)),
            abi.encode(false)
        );

        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.enableAsset(address(usds));
    }

    // enableAsset
    // given PRICE returns zero for the disabled asset
    //  when enableAsset is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenPriceIsZero_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));
        _configurePrice(address(usds), 0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.enableAsset(address(usds));
    }

    // enableAsset
    // given DepositManager does not support the disabled asset
    //  when enableAsset is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenMissingDepositManagerAssetSupport_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));

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
        burnerLoans.enableAsset(address(usds));
    }

    // enableAsset
    // given DepositManager does not configure the BurnerLoans deposit period for the disabled asset
    //  when enableAsset is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenMissingDepositManagerPeriodSupport_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));

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
        burnerLoans.enableAsset(address(usds));
    }

    // enableAsset
    // given DepositManager disables the BurnerLoans deposit period for the asset
    //  when enableAsset is called by admin
    //   then it revalidates dependencies and reverts
    function test_givenDepositManagerPeriodDisabled_reverts() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));
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
        burnerLoans.enableAsset(address(usds));
    }

    // enableAsset
    // given asset is configured but disabled
    //  when enableAsset is called by admin
    //   then the asset is enabled
    function test_givenAdminCaller_enablesDisabledAsset() public {
        _configureUsdsDependencies();
        _setDefaultGlobalDebtCap();

        vm.prank(admin);
        burnerLoans.addAsset(
            address(usds),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(address(usds));
        burnerLoans.enableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
    }

    // enableAsset
    // given asset is disabled
    //  when enableAsset is called by admin
    //   then admin can recover the asset through the normal enable path
    function test_givenAssetDisabled_allowsAdminRecovery() public {
        _addDefaultUsdsAsset();

        vm.prank(admin);
        burnerLoans.disableAsset(address(usds));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, address(burnerLoans));
        emit AssetEnabled(address(usds));
        burnerLoans.enableAsset(address(usds));

        assertTrue(burnerLoans.getAssetConfig(address(usds)).enabled, "enabled");
    }
}
