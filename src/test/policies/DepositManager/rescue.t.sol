// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract DepositManagerRescueTest is DepositManagerTest {
    MockERC20 public randomToken;
    address public NON_ADMIN;

    function setUp() public override {
        super.setUp();

        NON_ADMIN = makeAddr("NON_ADMIN");
        randomToken = new MockERC20("Random", "RAND", 18);
    }

    // ========== rescue ==========

    // given the contract is disabled
    //  [X] it reverts
    function test_rescue_givenContractDisabled_reverts() public {
        randomToken.mint(address(depositManager), 100e18);

        vm.expectRevert(abi.encodeWithSignature("NotEnabled()"));
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));
    }

    // given the caller is not an admin
    //  [X] it reverts
    function test_rescue_givenCallerNotAdmin_reverts() public givenIsEnabled {
        randomToken.mint(address(depositManager), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(NON_ADMIN);
        depositManager.rescue(address(randomToken));
    }

    // given the token address is zero
    //  given there are no managed assets
    //   [X] it reverts
    //  given the managed asset has a vault with the zero address
    //   [X] it reverts
    //  given the managed asset has a vault with a non-zero address
    //   [X] it reverts
    function test_rescue_givenNoManagedAssets_givenTokenAddressZero_reverts()
        public
        givenIsEnabled
    {
        vm.expectRevert("call to non-contract address 0x0000000000000000000000000000000000000000");

        vm.prank(ADMIN);
        depositManager.rescue(address(0));
    }

    function test_rescue_givenAssetWithZeroVault_givenTokenAddressZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(0)
            )
        );

        vm.prank(ADMIN);
        depositManager.rescue(address(0));
    }

    function test_rescue_givenAssetWithVault_givenTokenAddressZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.expectRevert("call to non-contract address 0x0000000000000000000000000000000000000000");

        vm.prank(ADMIN);
        depositManager.rescue(address(0));
    }

    // given the token address is a configured asset
    //  given the asset is disabled
    //   [X] it reverts
    //  [X] it reverts
    function test_rescue_givenTokenIsConfiguredAsset_givenAssetDisabled_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        asset.mint(address(depositManager), 100e18);

        // Disable the asset period
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(asset)
            )
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(asset));
    }

    function test_rescue_givenTokenIsConfiguredAsset_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(address(depositManager), 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(asset)
            )
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(asset));
    }

    // given the token address is a configured vault
    //  [X] it reverts
    function test_rescue_givenTokenIsConfiguredVault_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(vault)
            )
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(vault));
    }

    // given the token address is not a configured asset or vault
    //  given the token has zero balance
    //   [X] it does not revert
    //   [X] it does not emit an event
    function test_rescue_givenTokenNotConfigured_givenZeroBalance_doesNotRevertOrEmit()
        public
        givenIsEnabled
    {
        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));

        assertEq(randomToken.balanceOf(address(depositManager)), 0);
        assertEq(randomToken.balanceOf(address(trsry)), 0);
    }

    //  given the token has a balance
    //   [X] it transfers the balance to TRSRY
    //   [X] it emits a TokenRescued event
    function test_rescue_givenTokenNotConfigured_givenHasBalance_transfersToTrsryAndEmits()
        public
        givenIsEnabled
    {
        uint256 tokenAmount = 100e18;
        randomToken.mint(address(depositManager), tokenAmount);

        vm.expectEmit(address(depositManager));
        emit IDepositManager.TokenRescued(address(randomToken), tokenAmount);

        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));

        assertEq(randomToken.balanceOf(address(depositManager)), 0);
        assertEq(randomToken.balanceOf(address(trsry)), tokenAmount);
    }
}
