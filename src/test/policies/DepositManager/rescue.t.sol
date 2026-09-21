// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Scenario-specific literals and established test variable names remain inline for auditability.
// Setup calls intentionally ignore return values when subsequent assertions verify their effects.
// forge-lint: disable-start(literal-instead-of-constant, mixed-case-variable, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ReentrantFeeToken} from "src/test/policies/BurnerLoans/fixtures/ReentrantFeeToken.sol";
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract DepositManagerRescueTest is DepositManagerTest {
    MockERC20 public randomToken;

    function setUp() public override {
        super.setUp();

        randomToken = new MockERC20("Random", "RAND", 18);
    }

    // ========== rescue ==========

    function test_givenRescuedTokenCallback_whenBorrowingWithdrawal() public givenIsEnabled {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", address(callbackToken));
        depositManager.setOperatorName(address(callbackToken), "rsc");
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max, 0);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, address(callbackToken));
        vm.stopPrank();

        asset.mint(DEPOSITOR, 100);
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), 100);
        vm.prank(address(callbackToken));
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 100,
                shouldWrap: false
            })
        );
        IDepositManager.BorrowingWithdrawParams memory params = IDepositManager
            .BorrowingWithdrawParams({asset: iAsset, recipient: RECIPIENT, amount: 1});
        callbackToken.mint(address(depositManager), 10);
        callbackToken.setCallback(
            address(depositManager),
            abi.encodeCall(IDepositManager.borrowingWithdraw, (params))
        );

        vm.prank(ADMIN);
        depositManager.rescue(address(callbackToken));

        assertFalse(callbackToken.callbackSucceeded(), "nested borrowing must fail");
        assertEq(
            callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "guard must reject callback"
        );
        assertEq(callbackToken.balanceOf(address(trsry)), 10, "Treasury receives rescue once");
        assertEq(
            callbackToken.balanceOf(address(depositManager)),
            0,
            "rescue empties stray token balance"
        );
        assertEq(asset.balanceOf(address(depositManager)), 100, "managed custody unchanged");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, address(callbackToken)),
            0,
            "no nested debt"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, address(callbackToken)),
            100,
            "liabilities unchanged"
        );

        // The same authorized, funded action succeeds once the outer rescue has released the guard.
        vm.prank(address(callbackToken));
        depositManager.borrowingWithdraw(params);
        assertEq(asset.balanceOf(RECIPIENT), 1, "nested action is otherwise executable");
    }

    function test_givenUtilizationExceedsLoweredCap_whenRescuingUnmanagedToken_succeeds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        vm.prank(DEPOSIT_OPERATOR);
        (, uint256 creditedAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 0);
        randomToken.mint(address(depositManager), 100e18);

        vm.prank(ADMIN);
        depositManager.rescue(address(randomToken));

        assertEq(randomToken.balanceOf(address(trsry)), 100e18, "Treasury rescued balance");
        assertEq(
            _assetDepositCapUtilization(iAsset),
            creditedAmount,
            "rescue should preserve utilization"
        );
    }

    // given the contract is disabled
    //  when the caller is admin
    //   [X] it transfers the balance to TRSRY
    //   [X] it emits a TokenRescued event
    function test_givenContractDisabled_whenCallerIsAdmin() public {
        _rescueAndAssert(ADMIN);
    }

    //  when the caller is Deposit Manager admin
    //   [X] it transfers the balance to TRSRY
    //   [X] it emits a TokenRescued event
    function test_givenContractDisabled_whenCallerIsDepositManagerAdmin() public {
        _rescueAndAssert(DEPOSIT_MANAGER_ADMIN);
    }

    // given the caller is neither admin nor Deposit Manager admin
    //  [X] it reverts
    function test_whenCallerIsUnauthorized_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != ADMIN && caller_ != DEPOSIT_MANAGER_ADMIN);
        randomToken.mint(address(depositManager), 100e18);

        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
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
        vm.expectRevert(bytes(""));

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
        vm.expectRevert(bytes(""));

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

    function test_givenTokenIsConfiguredExternalShareToken_reverts() public givenIsEnabled {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            true,
            true
        );
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        IERC20 shareToken = IERC20(externalVault.share());

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_CannotRescueAsset.selector,
                address(shareToken)
            )
        );
        vm.prank(ADMIN);
        depositManager.rescue(address(shareToken));
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
        _rescueAndAssert(ADMIN);
    }

    // given the contract is enabled
    //  when the caller is Deposit Manager admin
    //   [X] it transfers the balance to TRSRY
    //   [X] it emits a TokenRescued event
    function test_givenContractEnabled_whenCallerIsDepositManagerAdmin() public givenIsEnabled {
        _rescueAndAssert(DEPOSIT_MANAGER_ADMIN);
    }

    function _rescueAndAssert(address caller_) internal {
        uint256 tokenAmount = 100e18;
        randomToken.mint(address(depositManager), tokenAmount);

        vm.expectEmit(address(depositManager));
        emit IDepositManager.TokenRescued(address(randomToken), tokenAmount);

        vm.prank(caller_);
        depositManager.rescue(address(randomToken));

        assertEq(
            randomToken.balanceOf(address(depositManager)),
            0,
            "DepositManager should not retain rescued tokens"
        );
        assertEq(
            randomToken.balanceOf(address(trsry)),
            tokenAmount,
            "Treasury should receive the rescued tokens"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, mixed-case-variable, unused-return)
