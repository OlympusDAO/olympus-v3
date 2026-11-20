// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

// Libraries
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {DepositManager} from "src/policies/deposits/DepositManager.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7575Vault} from "src/test/mocks/MockERC7575Vault.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {DepositManagerDonationActor, DepositManagerDonationVault} from "./fixtures/DepositManagerDonationActors.sol";
import {DepositManagerDonationTest} from "./fixtures/DepositManagerDonationTest.sol";

contract DepositManagerDonateTest is DepositManagerDonationTest {
    // Scenarios: DM-DONATE-A01, DM-DONATE-A02, DM-DONATE-A03, DM-DONATE-L01, DM-DONATE-P10.
    function test_whenCallerVaries(address caller_) public {
        vm.assume(caller_ != address(0) && caller_ != address(depositManager));
        _configureIdle();
        _setConfigOperator(CONFIG_OPERATOR);
        _donor = caller_;
        _fundDonor(_otherOperator, 11);
        _donate(_otherOperator, _otherOperator, 11);
        _fundDonor(_donor, 7);
        _assertDonation(7, 7, 7);
        _assertNamespace(_otherOperator, 11, 11, 0, 0);
    }

    // Scenarios: DM-DONATE-A01, DM-DONATE-A02, DM-DONATE-A03.
    function test_whenCallerRoleBoundarySeeds() public {
        address[8] memory callers = [
            _donor,
            ADMIN,
            CONFIG_OPERATOR,
            EMERGENCY,
            DEPOSIT_OPERATOR,
            _otherOperator,
            address(new DepositManagerDonationActor()),
            DEPOSIT_MANAGER_ADMIN
        ];
        for (uint256 i; i < callers.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            test_whenCallerVaries(callers[i]);
            vm.revertToState(snapshot);
        }
    }

    // Scenarios: DM-DONATE-A04.
    function test_givenVictimApproval_whenDonorHasNoFunds_reverts() public {
        _configureIdle();
        _fundDonor(DEPOSITOR, 10);
        vm.prank(_donor);
        asset.approve(address(depositManager), 10);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, _donor, 0, 10)
        );
        _donate(_donor, DEPOSIT_OPERATOR, 10);
        assertEq(_custodyState(), beforeState, "Victim funds and all custody unchanged");
        assertEq(
            asset.allowance(DEPOSITOR, address(depositManager)),
            10,
            "Victim standing allowance untouched"
        );
    }

    // Scenarios: DM-DONATE-A05.
    function test_givenTargetRoleRevoked_whenDonating() public {
        _configureIdle();
        _seedDeposit(10);
        vm.prank(ADMIN);
        rolesAdmin.revokeRole("deposit_operator", DEPOSIT_OPERATOR);
        _fundDonor(_donor, 3);
        _assertDonation(3, 3, 3);
        assertFalse(
            roles.hasRole(DEPOSIT_OPERATOR, "deposit_operator"),
            "Donation does not restore role"
        );
    }

    // Scenarios: DM-DONATE-A06.
    function test_givenForwardingContract_whenDonating() public {
        _configureIdle();
        DepositManagerDonationActor actor = new DepositManagerDonationActor();
        _fundDonor(DEPOSITOR, 10);
        asset.mint(address(actor), 7);
        vm.prank(DEPOSITOR, DEPOSITOR);
        (uint256 credit, uint256 shares) = actor.donate(
            IDepositManagerV1_1(address(depositManager)),
            iAsset,
            DEPOSIT_OPERATOR,
            7
        );
        assertEq(credit, 7, "Contract donation credit");
        assertEq(shares, 7, "Contract donation shares");
        assertEq(asset.balanceOf(address(actor)), 0, "Contract is payer");
        assertEq(asset.balanceOf(DEPOSITOR), 10, "Originator not charged");
        assertEq(
            asset.allowance(DEPOSITOR, address(depositManager)),
            10,
            "Originator allowance not spent"
        );
        _assertNamespace(DEPOSIT_OPERATOR, 7, 7, 0, 0);
    }

    // Scenarios: DM-DONATE-A07.
    function test_whenCallerZero_revertsWithFundingError() public {
        _configureIdle();
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(depositManager),
                0,
                1
            )
        );
        _donate(address(0), DEPOSIT_OPERATOR, 1);
    }

    // Scenarios: DM-DONATE-L02.
    function test_givenDisabled_whenDonating() public {
        _configureIdle();
        vm.prank(ADMIN);
        depositManager.disable("");
        _fundDonor(_donor, 7);
        _assertDonation(7, 7, 7);
        assertFalse(depositManager.isEnabled(), "Donation leaves pause intact");
        vm.expectRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector));
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1, false)
        );
    }

    // Scenarios: DM-DONATE-L03, DM-DONATE-L04.
    function test_givenPolicyInactive_whenDonating_reverts(bool enabled_) public {
        _configureIdle();
        _fundDonor(_donor, 1);
        if (!enabled_) {
            vm.prank(ADMIN);
            depositManager.disable("");
        }
        vm.prank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
        _donate(_donor, DEPOSIT_OPERATOR, 1);
        assertEq(_custodyState(), beforeState, "Inactive call changes nothing");
    }

    // Scenarios: DM-DONATE-L04.
    function test_givenPolicyInactiveAndDisabled_whenInvalidInputs_reverts() public {
        _configureIdle();
        vm.startPrank(ADMIN);
        depositManager.disable("");
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        vm.stopPrank();
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_PolicyInactive.selector)
        );
        _donate(_donor, address(0), 0);
        assertEq(_custodyState(), beforeState, "Inactive rejection precedes all invalid inputs");
    }

    // Scenarios: DM-DONATE-L03, DM-DONATE-L04.
    function test_givenPolicyInactive_whenEnabledBoundarySeeds_reverts() public {
        uint256 snapshot = vm.snapshotState();
        test_givenPolicyInactive_whenDonating_reverts(true);
        vm.revertToState(snapshot);
        test_givenPolicyInactive_whenDonating_reverts(false);
    }

    // Scenarios: DM-DONATE-L05, DM-DONATE-L06.
    function test_givenReactivatedAndReEnabled_whenDonating() public {
        _configureIdle();
        _seedDeposit(10);
        _fundDonor(_donor, 6);
        _assertDonation(2, 2, 2);
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.DeactivatePolicy, address(depositManager));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        vm.stopPrank();
        _assertDonation(2, 2, 2);
        vm.startPrank(ADMIN);
        depositManager.disable("");
        depositManager.reEnable();
        vm.stopPrank();
        _assertDonation(2, 2, 2);
        _assertNamespace(DEPOSIT_OPERATOR, 16, 16, 10, 0);
    }

    // Scenarios: DM-DONATE-L07, DM-DONATE-L08.
    function test_givenTargetPeriodsUnavailable_whenDonating(bool enabled_) public {
        _configureIdle();
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        if (!enabled_) {
            vm.prank(ADMIN);
            depositManager.disable("");
        }
        _fundDonor(_donor, 2);
        bytes32 periods = keccak256(abi.encode(depositManager.getAssetPeriods()));
        _assertDonation(1, 1, 1);
        _donate(_donor, _otherOperator, 1);
        assertEq(
            keccak256(abi.encode(depositManager.getAssetPeriods())),
            periods,
            "No new or enabled periods"
        );
    }

    // Scenarios: DM-DONATE-L07, DM-DONATE-L08.
    function test_givenUnavailablePeriods_whenEnabledBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenTargetPeriodsUnavailable_whenDonating(true);
        vm.revertToState(snapshot);
        test_givenTargetPeriodsUnavailable_whenDonating(false);
    }

    // Scenarios: DM-DONATE-L09.
    function test_givenProductTargetUnavailable_whenDonating(
        bool localEnabled_,
        bool targetActive_,
        bool targetEnabled_
    ) public {
        _configureIdle();
        DepositManager product = new DepositManager(address(kernel), address(receiptTokenManager));
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.ActivatePolicy, address(product));
        if (targetEnabled_) product.enable("");
        if (!targetActive_) kernel.executeAction(Actions.DeactivatePolicy, address(product));
        depositManager.setOperatorName(address(product), "prd");
        if (!localEnabled_) depositManager.disable("");
        vm.stopPrank();
        _fundDonor(_donor, 1);
        _donate(_donor, address(product), 1);
        _assertNamespace(address(product), 1, 1, 0, 0);
        assertEq(product.isEnabled(), targetEnabled_, "Target enablement unchanged");
        assertEq(
            kernel.isPolicyActive(product),
            targetActive_,
            "Target Kernel membership unchanged"
        );
        assertEq(depositManager.isEnabled(), localEnabled_, "Local pause unchanged");
        assertFalse(
            roles.hasRole(address(product), "deposit_operator"),
            "Donation grants no target role"
        );
    }

    // Scenarios: DM-DONATE-L09.
    function test_givenProductTargetUnavailable_whenLifecycleBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenProductTargetUnavailable_whenDonating(true, true, false);
        vm.revertToState(snapshot);
        test_givenProductTargetUnavailable_whenDonating(false, true, false);
        vm.revertToState(snapshot);
        test_givenProductTargetUnavailable_whenDonating(true, false, true);
        vm.revertToState(snapshot);
        test_givenProductTargetUnavailable_whenDonating(false, false, true);
    }

    // Scenarios: DM-DONATE-I01, DM-DONATE-I02, DM-DONATE-I06.
    function test_whenAssetUnconfigured_reverts(address asset_) public {
        _configureIdle();
        vm.assume(asset_ != address(iAsset));
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));
        vm.prank(_donor);
        IDepositManagerV1_1(address(depositManager)).donate(IERC20(asset_), address(0), 0);
        assertEq(_custodyState(), beforeState, "Asset validation precedes target and amount");
    }

    // Scenarios: DM-DONATE-I01, DM-DONATE-I02, DM-DONATE-I06.
    function test_whenUnconfiguredAssetBoundarySeeds_revert() public {
        uint256 snapshot = vm.snapshotState();
        test_whenAssetUnconfigured_reverts(address(0));
        vm.revertToState(snapshot);
        test_whenAssetUnconfigured_reverts(makeAddr("unconfigured"));
    }

    // Scenarios: DM-DONATE-I01, DM-DONATE-I02.
    function test_whenAssetUnconfigured_whenOtherInputsValid_reverts(address asset_) public {
        _configureIdle();
        vm.assume(asset_ != address(iAsset));
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_NotConfigured.selector));
        vm.prank(_donor);
        IDepositManagerV1_1(address(depositManager)).donate(IERC20(asset_), DEPOSIT_OPERATOR, 1);
        assertEq(_custodyState(), beforeState, "Unconfigured asset alone rejects");
    }

    // Scenarios: DM-DONATE-I03.
    function test_whenTargetZero_reverts() public {
        _configureIdle();
        _expectRevertZeroAddress();
        _donate(_donor, address(0), 1);
    }

    // Scenarios: DM-DONATE-I04, DM-DONATE-I07.
    function test_whenTargetUnregistered_reverts(address target_, uint256 amount_) public {
        vm.assume(
            target_ != address(0) && target_ != DEPOSIT_OPERATOR && target_ != _otherOperator
        );
        _configureIdle();
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_OperatorNameNotSet.selector,
                target_
            )
        );
        _donate(_donor, target_, amount_);
        assertEq(_custodyState(), beforeState, "Unregistered target rollback");
    }

    // Scenarios: DM-DONATE-I04, DM-DONATE-I07.
    function test_whenUnregisteredManagerTargetBoundarySeeds_revert() public {
        uint256 snapshot = vm.snapshotState();
        test_whenTargetUnregistered_reverts(address(depositManager), 0);
        vm.revertToState(snapshot);
        test_whenTargetUnregistered_reverts(address(depositManager), 1);
    }

    // Scenarios: DM-DONATE-I05.
    function test_whenAmountZero_reverts() public {
        _configureIdle();
        bytes32 beforeState = _custodyState();
        _expectRevertZeroAmount();
        _donate(_donor, DEPOSIT_OPERATOR, 0);
        assertEq(_custodyState(), beforeState, "Zero call makes no token or ledger changes");
    }

    // Scenarios: DM-DONATE-N01.
    function test_givenIdle_whenAmountVaries(uint256 amount_) public {
        _configureIdle();
        uint256 amount = bound(amount_, 1, type(uint256).max);
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, amount);
        _assertNamespace(DEPOSIT_OPERATOR, amount, amount, 0, 0);
        assertEq(asset.balanceOf(address(depositManager)), amount, "Idle custody exact");
    }

    // Scenarios: DM-DONATE-N02.
    function test_givenUnseededVault_whenAmountVaries(uint256 amount_) public {
        _configureVault();
        uint256 amount = bound(amount_, 1, type(uint256).max);
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, amount);
        assertEq(vault.totalSupply(), amount, "Exact vault supply");
        assertEq(asset.balanceOf(address(vault)), amount, "Exact vault backing");
    }

    // Scenarios: DM-DONATE-N01, DM-DONATE-N02.
    function test_whenFullNumericBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenIdle_whenAmountVaries(1);
        vm.revertToState(snapshot);
        test_givenIdle_whenAmountVaries(type(uint256).max);
        vm.revertToState(snapshot);
        test_givenUnseededVault_whenAmountVaries(1);
        vm.revertToState(snapshot);
        test_givenUnseededVault_whenAmountVaries(type(uint256).max);
    }

    // Scenarios: DM-DONATE-N03.
    function test_givenThreeToOneVault_whenRoundingDown() public {
        _configureVault();
        _seedExternalVault(2, 4);
        _fundDonor(_donor, 5);
        // floor(5*2/6)=1 raw share, then floor(1*11/3)=3 raw asset units.
        _assertDonation(5, 3, 1);
        assertEq(vault.totalSupply(), 3, "Rounded supply");
        assertEq(asset.balanceOf(address(vault)), 11, "All five donated underlying retained");
    }

    // Scenarios: DM-DONATE-N04.
    function test_givenThreeToOneVault_whenOneUnit_reverts() public {
        _zeroShareDonation(1);
    }

    // Scenarios: DM-DONATE-N04.
    function test_givenThreeToOneVault_whenTwoUnits_reverts() public {
        _zeroShareDonation(2);
    }

    function _zeroShareDonation(uint256 amount_) internal {
        _configureVault();
        _seedExternalVault(2, 4);
        _fundDonor(_donor, amount_);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSelector(MockERC4626.ZeroShares.selector));
        _donate(_donor, DEPOSIT_OPERATOR, amount_);
        assertEq(_custodyState(), beforeState, "Zero-share mint fully rolls back");
    }

    // Scenarios: DM-DONATE-N05.
    function test_givenZeroValuation_whenDonating_reverts() public {
        DepositManagerDonationVault faultVault = _configureFaultVault(false);
        faultVault.setFaults(false, false, true);
        _fundDonor(_donor, 1);
        bytes32 beforeState = _custodyState();
        _expectRevertZeroAmount();
        _donate(_donor, DEPOSIT_OPERATOR, 1);
        assertEq(_custodyState(), beforeState, "Zero valuation rolls back received shares");
    }

    // Scenarios: DM-DONATE-N06.
    function test_givenBorrowedPrincipal_whenMaximumDonation() public {
        _configureIdle();
        _seedDeposit(2);
        _borrow(2);
        asset.burn(RECIPIENT, 2);
        _fundDonor(_donor, type(uint256).max);
        _assertDonation(type(uint256).max, type(uint256).max, type(uint256).max);
        _assertNamespace(DEPOSIT_OPERATOR, type(uint256).max, type(uint256).max, 2, 2);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            type(uint256).max - 1,
            "Overflow-safe yield retains reserve"
        );
        assertEq(_claim(1), 1, "Solvency avoids overflowing assets plus borrowed");
    }

    // Scenarios: DM-DONATE-N06.
    function test_givenReceiptsRedeemedWithDebt_whenQuotingYield() public {
        _configureIdle();
        _seedDeposit(2);
        _borrow(2);
        asset.burn(RECIPIENT, 2);
        _fundDonor(_donor, 3);
        _assertDonation(3, 3, 3);
        uint256 id = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), id, 2);
        assertEq(_withdraw(2, false), 2, "Donation permits receipt redemption while debt persists");
        _assertNamespace(DEPOSIT_OPERATOR, 1, 1, 0, 2);
        // assets=1, borrowed=2, liabilities=0: 1 + 2 - 0 - reserve(1) = 2.
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            2,
            "Borrowed above liabilities keeps mathematical surplus"
        );
    }

    // Scenarios: DM-DONATE-N06.
    function test_givenReceiptsRedeemedWithDebt_whenYieldExceedsUintMaximum_saturates() public {
        _configureIdle();
        _seedDeposit(2);
        _borrow(2);
        asset.burn(RECIPIENT, 2);
        _fundDonor(_donor, type(uint256).max);
        _assertDonation(type(uint256).max, type(uint256).max, type(uint256).max);
        uint256 id = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), id, 2);
        assertEq(_withdraw(2, false), 2, "Receipts redeemed without repaying borrowed principal");
        asset.burn(DEPOSITOR, 2);
        _fundDonor(_donor, 2);
        _assertDonation(2, 2, 2);
        _assertNamespace(DEPOSIT_OPERATOR, type(uint256).max, type(uint256).max, 0, 2);
        // MAX assets + 2 borrowed - 0 liabilities - 1 reserve = MAX+1, unrepresentable.
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            type(uint256).max,
            "Unrepresentable theoretical surplus saturates"
        );
    }

    // Scenarios: DM-DONATE-N07.
    function test_givenExistingCustody_whenAmountVaries(uint256 amount_) public {
        _configureIdle();
        _seedDeposit(1);
        uint256 amount = bound(amount_, 1, type(uint256).max - 1);
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, amount);
        _assertNamespace(DEPOSIT_OPERATOR, amount + 1, amount + 1, 1, 0);
    }

    // Scenarios: DM-DONATE-N07.
    function test_givenExistingCustody_whenAmountBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenExistingCustody_whenAmountVaries(1);
        vm.revertToState(snapshot);
        test_givenExistingCustody_whenAmountVaries(type(uint256).max - 1);
    }

    // Scenarios: DM-DONATE-N07.
    function test_givenExistingVaultCustody_whenAmountVaries(uint256 amount_) public {
        _configureVault();
        _seedDeposit(1);
        uint256 amount = bound(amount_, 1, type(uint256).max - 1);
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, amount);
        _assertNamespace(DEPOSIT_OPERATOR, amount + 1, amount + 1, 1, 0);
        assertEq(vault.totalSupply(), amount + 1, "Existing vault supply increases once");
    }

    // Scenarios: DM-DONATE-N07.
    function test_givenExistingVaultCustody_whenAmountBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenExistingVaultCustody_whenAmountVaries(1);
        vm.revertToState(snapshot);
        test_givenExistingVaultCustody_whenAmountVaries(type(uint256).max - 1);
    }

    // Scenarios: DM-DONATE-N08.
    function test_givenTwoSharesPerAsset_whenConversionOverflows_reverts() public {
        _configureVault();
        _seedExternalVault(2, 0);
        asset.burn(address(vault), 1);
        _fundDonor(_donor, type(uint256).max - 1);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        _donate(_donor, DEPOSIT_OPERATOR, type(uint256).max - 1);
        assertEq(_custodyState(), beforeState, "Conversion overflow preserves original vault");
    }

    // Scenarios: DM-DONATE-P01.
    function test_givenERC7575SelfShare_whenDonating() public {
        _freshAsset();
        MockERC7575Vault route = new MockERC7575Vault(OZIERC20(address(asset)), false);
        _configureRoute(address(route));
        _fundDonor(_donor, 10e18);
        _assertDonation(10e18, 10e18, 10e18);
        assertEq(
            address(depositManager.getAssetWithdrawalToken(iAsset, true)),
            address(route),
            "Configured self-share custody"
        );
        assertEq(route.balanceOf(address(depositManager)), 10e18, "Physical self-share balance");
    }

    function _externalShareRoute(
        bool async_
    ) internal returns (MockERC7540ExternalShareVault route) {
        _freshAsset();
        route = new MockERC7540ExternalShareVault(OZIERC20(address(asset)), false, async_, true);
        _configureRoute(address(route));
    }

    // Scenarios: DM-DONATE-P02.
    function test_givenERC7575ExternalShares_whenDonating() public {
        MockERC7540ExternalShareVault route = _externalShareRoute(false);
        _fundDonor(_donor, 10e18);
        // 10e18 underlying / 1e12 raw underlying per raw share = 10e6 shares.
        _assertDonation(10e18, 10e18, 10e6);
        assertEq(
            IERC20(route.share()).balanceOf(address(depositManager)),
            10e6,
            "External share token receives custody"
        );
        assertEq(asset.balanceOf(address(route)), 10e18, "Vault holds underlying");
    }

    // Scenarios: DM-DONATE-P03.
    function test_givenAsyncRedeemExternalShares_whenDonating() public {
        MockERC7540ExternalShareVault route = _externalShareRoute(true);
        _fundDonor(_donor, 10e18);
        // previewRedeem and redeem revert natively; successful credit proves convertToAssets route.
        _assertDonation(10e18, 10e18, 10e6);
        assertEq(
            IERC20(route.share()).balanceOf(address(depositManager)),
            10e6,
            "Synchronous deposit creates external shares"
        );
        assertEq(asset.balanceOf(address(route)), 10e18, "No redemption or asynchronous request");
    }

    // Scenarios: DM-DONATE-P04.
    function test_givenAsyncRedeemSelfShares_whenDonating() public {
        DepositManagerDonationVault route = _configureFaultVault(true);
        _fundDonor(_donor, 10e18);
        _assertDonation(10e18, 10e18, 10e18);
        assertEq(route.balanceOf(address(depositManager)), 10e18, "Async self-shares held exactly");
        assertEq(asset.balanceOf(address(route)), 10e18, "No redemption");
    }

    // Scenarios: DM-DONATE-P05.
    function test_givenExplicitShareWithdrawalRequirement_whenDonating() public {
        _configureVault();
        vm.prank(ADMIN);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
        _fundDonor(_donor, 10);
        _assertDonation(10, 10, 10);
        assertTrue(
            depositManager.isAssetShareWithdrawalRequired(iAsset),
            "Donation preserves withdrawal restriction"
        );
    }

    // Scenarios: DM-DONATE-P06.
    function test_givenLoss_whenPartialRepair() public {
        _lossFixture();
        _fundDonor(_donor, 8);
        _assertDonation(8, 8, 10);
        _assertNamespace(DEPOSIT_OPERATOR, 110, 88, 100, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            0,
            "Partial repair is not yield"
        );
        bytes32 beforeState = _custodyState();
        _expectInsolvent(100, 84, 0);
        _claim(4);
        assertEq(_custodyState(), beforeState, "Failed yield preserves earlier donation");
        asset.mint(DEPOSITOR, 4);
        _approveSpendingAsset(DEPOSITOR, 4);
        _expectInsolvent(104, 92, 0);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 4, false)
        );
        uint256 id = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), id, 4);
        _expectInsolvent(96, 84, 0);
        _withdraw(4, false);
    }

    // Scenarios: DM-DONATE-P07.
    function test_givenLoss_whenExactRepair_thenNewDepositAndFullExit() public {
        _lossFixture();
        _fundDonor(_donor, 20);
        _assertDonation(20, 20, 25);
        _assertNamespace(DEPOSIT_OPERATOR, 125, 100, 100, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            0,
            "Exact repair creates no yield"
        );
        bytes32 beforeState = _custodyState();
        _expectInsolvent(100, 96, 0);
        _claim(4);
        assertEq(_custodyState(), beforeState, "Failed claim leaves exact repair intact");
        assertEq(_seedDeposit(20), 20, "Ordinary deposit available after repair");
        uint256 id = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), id, 120);
        assertEq(_withdraw(120, false), 120, "All receipt principal exits at par");
        _assertNamespace(DEPOSIT_OPERATOR, 0, 0, 0, 0);
    }

    // Scenarios: DM-DONATE-P08.
    function test_givenLoss_whenSurplusDonation() public {
        _lossFixture();
        _fundDonor(_donor, 24);
        _assertDonation(24, 24, 30);
        _assertNamespace(DEPOSIT_OPERATOR, 130, 104, 100, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            3,
            "Four-unit excess retains one-unit reserve"
        );
    }

    // Scenarios: DM-DONATE-P09.
    function test_givenZeroCapAndPositiveUtilization_whenDonating(uint256 amount_) public {
        _configureIdle();
        _seedDeposit(1);
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, 0);
        uint256 amount = bound(amount_, 1, type(uint256).max - 1);
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, amount);
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).utilization,
            1,
            "Donation consumes no cap"
        );
        assertEq(
            depositManager.getAssetConfiguration(iAsset).depositCap,
            0,
            "Donation leaves cap zero"
        );
    }

    // Scenarios: DM-DONATE-P10.
    function test_givenTwoBorrowingNamespacesShareVault_whenDonating() public {
        _configureVault();
        _seedDeposit(100);
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, _otherOperator);
        asset.mint(DEPOSITOR, 80);
        _approveSpendingAsset(DEPOSITOR, 80);
        vm.prank(_otherOperator);
        depositManager.deposit(
            IDepositManager.DepositParams(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 80, false)
        );
        _borrow(40);
        vm.prank(_otherOperator);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams(iAsset, RECIPIENT, 20)
        );
        uint256 otherId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD, _otherOperator);
        uint256 otherReceipts = receiptTokenManager.balanceOf(DEPOSITOR, otherId);
        _fundDonor(_donor, 8);
        _assertDonation(8, 8, 8);
        _assertNamespace(DEPOSIT_OPERATOR, 68, 68, 100, 40);
        _assertNamespace(_otherOperator, 60, 60, 80, 20);
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, otherId),
            otherReceipts,
            "Other namespace receipts unchanged"
        );
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).utilization,
            180,
            "Aggregate principal unchanged across namespaces"
        );
    }

    // Scenarios: DM-DONATE-P11.
    function test_givenMixedReceiptsAcrossPeriods_whenDonating() public {
        _configureIdle();
        _seedDeposit(10);
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, 2, DEPOSIT_OPERATOR);
        asset.mint(DEPOSITOR, 20);
        _approveSpendingAsset(DEPOSITOR, 20);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(IDepositManager.DepositParams(iAsset, 2, DEPOSITOR, 20, true));
        (uint256 id, address wrapper) = depositManager.getReceiptToken(iAsset, 2, DEPOSIT_OPERATOR);
        uint256 wrappedBalance = IERC20(wrapper).balanceOf(DEPOSITOR);
        uint256 wrappedSupply = IERC20(wrapper).totalSupply();
        uint256 backing = receiptTokenManager.balanceOf(wrapper, id);
        _fundDonor(_donor, 7);
        _assertDonation(7, 7, 7);
        assertEq(IERC20(wrapper).balanceOf(DEPOSITOR), wrappedBalance, "Wrapped holder unchanged");
        assertEq(IERC20(wrapper).totalSupply(), wrappedSupply, "Wrapped supply unchanged");
        assertEq(
            receiptTokenManager.balanceOf(wrapper, id),
            backing,
            "Wrapped receipt backing unchanged"
        );
        _assertNamespace(DEPOSIT_OPERATOR, 37, 37, 30, 0);
    }

    // Scenarios: DM-DONATE-P13.
    function test_givenLoss_whenRepeatedPartialDonationsRepair() public {
        _lossFixture();
        _fundDonor(_donor, 20);
        _assertDonation(8, 8, 10);
        _assertNamespace(DEPOSIT_OPERATOR, 110, 88, 100, 0);
        _assertDonation(12, 12, 15);
        _assertNamespace(DEPOSIT_OPERATOR, 125, 100, 100, 0);
    }

    // Scenarios: DM-DONATE-P14.
    function test_givenUnsolicitedUnderlyingAndShares_whenDonating() public {
        _configureVault();
        _seedExternalVault(10, 0);
        vault.transfer(address(depositManager), 5);
        asset.mint(address(depositManager), 7);
        _fundDonor(_donor, 3);
        _assertDonation(3, 3, 3);
        _assertNamespace(DEPOSIT_OPERATOR, 3, 3, 0, 0);
        assertEq(
            vault.balanceOf(address(depositManager)),
            8,
            "Unsolicited shares remain unallocated"
        );
        assertEq(asset.balanceOf(address(depositManager)), 7, "Unsolicited underlying not swept");
    }

    // Scenarios: DM-DONATE-P20.
    function test_givenPositiveMinimum_whenDonationBelowMinimum() public {
        _configureIdle();
        vm.prank(ADMIN);
        depositManager.setAssetMinimumDeposit(iAsset, 10);
        _fundDonor(_donor, 9);
        _assertDonation(9, 9, 9);
        assertEq(
            depositManager.getAssetConfiguration(iAsset).minimumDeposit,
            10,
            "Minimum preserved"
        );
    }

    // Scenarios: DM-DONATE-N09.
    function test_givenRoundingRepair_whenInputTwo_reverts() public {
        _roundingRepairFixture();
        _fundDonor(_donor, 2);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSelector(MockERC4626.ZeroShares.selector));
        _donate(_donor, DEPOSIT_OPERATOR, 2);
        assertEq(_custodyState(), beforeState, "Requested deficit plus one still mints no share");
    }

    // Scenarios: DM-DONATE-N10.
    function test_givenRoundingRepair_whenInputThree() public {
        _roundingRepairFixture();
        _fundDonor(_donor, 3);
        // floor(3*34/101)=1, floor(104/35)=2, floor(34*104/35)=101.
        _assertDonation(3, 2, 1);
        _assertNamespace(DEPOSIT_OPERATOR, 34, 101, 99, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            1,
            "One-unit theoretical quote"
        );
    }

    // Scenarios: DM-DONATE-P21.
    function test_givenRoundingRepair_whenInputSix_thenRoundedYield() public {
        _roundingRepairFixture();
        _fundDonor(_donor, 6);
        // floor(6*34/101)=2 shares; floor(2*107/36)=5 credited assets.
        _assertDonation(6, 5, 2);
        _assertNamespace(DEPOSIT_OPERATOR, 35, 104, 99, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            4,
            "Five-unit surplus less reserve"
        );
        bytes32 principalBefore = _principalState();
        // floor(4*36/107)=1 redeemed share pays floor(107/36)=2 assets.
        assertEq(_claim(4), 2, "Yield delivery uses actual redemption");
        assertEq(asset.balanceOf(RECIPIENT), 2, "Actual yield received");
        _assertNamespace(DEPOSIT_OPERATOR, 34, 102, 99, 0);
        assertEq(_principalState(), principalBefore, "Yield preserves receipts, borrowing and U");
    }

    // Scenarios: DM-DONATE-N11.
    function test_givenNominalOverpaymentConsumedByRounding_whenClaiming_reverts() public {
        _configureVault();
        _seedExternalVault(1, 2);
        assertEq(_seedDeposit(5), 4, "Initial rounded liability");
        asset.burn(address(vault), 4);
        _fundDonor(_donor, 3);
        // floor(3*2/4)=1 share; floor(7/3)=2 credit; total floor(2*7/3)=4.
        _assertDonation(3, 2, 1);
        _assertNamespace(DEPOSIT_OPERATOR, 2, 4, 4, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            0,
            "Nominal overpayment creates no surplus"
        );
        bytes32 beforeState = _custodyState();
        _expectInsolvent(4, 2, 0);
        _claim(3);
        assertEq(_custodyState(), beforeState, "Yield rollback retains previous donation");
    }

    // Scenarios: DM-DONATE-P22.
    function test_givenIdleAtPar_whenOverpaymentVaries_thenClaimsActualSurplus(
        uint256 amount_
    ) public {
        _configureIdle();
        _seedDeposit(100);
        uint256 amount = bound(amount_, 1, type(uint256).max - 100);
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, amount);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            amount - 1,
            "Quote reserves one underlying unit"
        );
        bytes32 principalBefore = _principalState();
        assertEq(_claim(amount), amount, "Explicit solvent surplus claim can exceed quote");
        assertEq(asset.balanceOf(RECIPIENT), amount, "Full idle surplus paid");
        _assertNamespace(DEPOSIT_OPERATOR, 100, 100, 100, 0);
        assertEq(
            _principalState(),
            principalBefore,
            "Yield creates and burns no receipt principal"
        );
    }

    // Scenarios: DM-DONATE-P22.
    function test_givenIdleAtPar_whenOverpaymentBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenIdleAtPar_whenOverpaymentVaries_thenClaimsActualSurplus(1);
        vm.revertToState(snapshot);
        test_givenIdleAtPar_whenOverpaymentVaries_thenClaimsActualSurplus(2);
        vm.revertToState(snapshot);
        test_givenIdleAtPar_whenOverpaymentVaries_thenClaimsActualSurplus(type(uint256).max - 100);
    }

    // Scenarios: DM-DONATE-P23.
    function test_givenLoss_whenProportionalOverpaymentVaries_thenClaimsRoundedQuote(
        uint256 k_
    ) public {
        _lossFixture();
        uint256 k = bound(k_, 1, (type(uint256).max - 125) / 5);
        uint256 amount = 20 + 4 * k;
        _fundDonor(_donor, amount);
        _assertDonation(amount, amount, 25 + 5 * k);
        _assertNamespace(DEPOSIT_OPERATOR, 125 + 5 * k, 100 + 4 * k, 100, 0);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            4 * k - 1,
            "Closed-form surplus reserve"
        );
        bytes32 principalBefore = _principalState();
        // Quote 4k-1 redeems 5k-2 shares, paying 4k-2 raw assets and retaining 127 shares.
        assertEq(_claim(4 * k - 1), 4 * k - 2, "Rounded quoted claim delivery");
        _assertNamespace(DEPOSIT_OPERATOR, 127, 102, 100, 0);
        assertEq(
            _principalState(),
            principalBefore,
            "Rounded yield preserves liabilities and borrowing"
        );
    }

    // Scenarios: DM-DONATE-P23.
    function test_givenLoss_whenProportionalOverpaymentBoundarySeeds() public {
        uint256 snapshot = vm.snapshotState();
        test_givenLoss_whenProportionalOverpaymentVaries_thenClaimsRoundedQuote(1);
        vm.revertToState(snapshot);
        test_givenLoss_whenProportionalOverpaymentVaries_thenClaimsRoundedQuote(
            (type(uint256).max - 125) / 5
        );
    }

    // Scenarios: DM-DONATE-P24.
    function test_givenBorrowedPrincipal_whenDonatingSurplus_thenClaimsYield() public {
        _configureIdle();
        _seedDeposit(100);
        _borrow(40);
        _fundDonor(_donor, 8);
        _assertDonation(8, 8, 8);
        _assertNamespace(DEPOSIT_OPERATOR, 68, 68, 100, 40);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            7,
            "Borrowing included in net solvency"
        );
        assertEq(_claim(7), 7, "Yield actually delivered");
        _assertNamespace(DEPOSIT_OPERATOR, 61, 61, 100, 40);
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).utilization,
            100,
            "No principal reduction"
        );
    }

    // Scenarios: DM-DONATE-P06, DM-DONATE-P07.
    function test_givenBorrowedPrincipalAndLoss_whenPartialThenCompleteRepair() public {
        _configureVault();
        _seedDeposit(100);
        _borrow(40);
        asset.burn(address(vault), 20);
        _fundDonor(_donor, 20);
        // 60 remaining shares / 40 assets: 8 mints 12 shares, 12 mints 18 shares.
        _assertDonation(8, 8, 12);
        _assertNamespace(DEPOSIT_OPERATOR, 72, 48, 100, 40);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            0,
            "Partial repair remains insolvent including debt"
        );
        _assertDonation(12, 12, 18);
        _assertNamespace(DEPOSIT_OPERATOR, 90, 60, 100, 40);
        assertEq(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            0,
            "Exact debt-backed repair creates no surplus"
        );
    }

    // Scenarios: DM-DONATE-T01.
    function test_whenAllowanceInsufficient_reverts(uint256 amount_, uint256 allowance_) public {
        _configureIdle();
        uint256 amount = bound(amount_, 1, type(uint256).max);
        uint256 allowed = bound(allowance_, 0, amount - 1);
        _fundDonor(_donor, amount);
        vm.prank(_donor);
        asset.approve(address(depositManager), allowed);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(depositManager),
                allowed,
                amount
            )
        );
        _donate(_donor, DEPOSIT_OPERATOR, amount);
        assertEq(_custodyState(), beforeState, "Allowance failure fully rolls back");
    }

    // Scenarios: DM-DONATE-T02.
    function test_whenBalanceInsufficient_reverts(uint256 amount_, uint256 balance_) public {
        _configureIdle();
        uint256 amount = bound(amount_, 1, type(uint256).max);
        uint256 balance = bound(balance_, 0, amount - 1);
        _fundDonor(_donor, balance);
        vm.prank(_donor);
        asset.approve(address(depositManager), amount);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                _donor,
                balance,
                amount
            )
        );
        _donate(_donor, DEPOSIT_OPERATOR, amount);
        assertEq(_custodyState(), beforeState, "Balance failure fully rolls back");
    }

    // Scenarios: DM-DONATE-T10.
    function test_whenBalanceAndAllowanceInsufficient_reverts(
        uint256 amount_,
        uint256 balance_,
        uint256 allowance_
    ) public {
        _configureIdle();
        uint256 amount = bound(amount_, 1, type(uint256).max);
        uint256 balance = bound(balance_, 0, amount - 1);
        uint256 allowed = bound(allowance_, 0, amount - 1);
        _fundDonor(_donor, balance);
        vm.prank(_donor);
        asset.approve(address(depositManager), allowed);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(depositManager),
                allowed,
                amount
            )
        );
        _donate(_donor, DEPOSIT_OPERATOR, amount);
        assertEq(_custodyState(), beforeState, "Allowance takes precedence over balance");
    }

    // Scenarios: DM-DONATE-T01, DM-DONATE-T02, DM-DONATE-T10.
    function test_whenFundingFailureBoundarySeeds_revert() public {
        uint256 snapshot = vm.snapshotState();
        test_whenAllowanceInsufficient_reverts(7, 0);
        vm.revertToState(snapshot);
        test_whenAllowanceInsufficient_reverts(7, 6);
        vm.revertToState(snapshot);
        test_whenBalanceInsufficient_reverts(7, 0);
        vm.revertToState(snapshot);
        test_whenBalanceInsufficient_reverts(7, 6);
        vm.revertToState(snapshot);
        test_whenBalanceAndAllowanceInsufficient_reverts(7, 0, 0);
        vm.revertToState(snapshot);
        test_whenBalanceAndAllowanceInsufficient_reverts(7, 6, 6);
    }

    // Scenarios: DM-DONATE-T03.
    function test_givenInexactUnderlying_whenDonating_reverts() public {
        MockERC20FeeOnTransfer token = new MockERC20FeeOnTransfer("Fee donation", "FEE", RECIPIENT);
        asset = MockERC20(address(token));
        iAsset = IERC20(address(token));
        _configureRoute(address(0));
        _fundDonor(_donor, 100);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(depositManager),
                100,
                90
            )
        );
        _donate(_donor, DEPOSIT_OPERATOR, 100);
        assertEq(
            _custodyState(),
            beforeState,
            "Fee transfer rolls back all balances and accounting"
        );
        assertEq(token.balanceOf(RECIPIENT), 0, "Fee also rolled back");
    }

    function _inexactShares(uint256 received_) internal {
        MockERC7540ExternalShareVault route = _externalShareRoute(false);
        route.setDepositResults(received_, 10e6);
        _fundDonor(_donor, 10e18);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InexactSharesReceived.selector,
                address(iAsset),
                route.share(),
                10e6,
                received_
            )
        );
        _donate(_donor, DEPOSIT_OPERATOR, 10e18);
        assertEq(_custodyState(), beforeState, "Inexact share receipt rolls back");
    }

    // Scenarios: DM-DONATE-T04.
    function test_givenVaultMintsTooFewShares_whenDonating_reverts() public {
        _inexactShares(10e6 - 1);
    }

    // Scenarios: DM-DONATE-T04.
    function test_givenVaultMintsTooManyShares_whenDonating_reverts() public {
        _inexactShares(10e6 + 1);
    }

    // Scenarios: DM-DONATE-T04.
    function test_givenVaultMintsNoShares_whenDonating_reverts() public {
        _inexactShares(0);
    }

    // Scenarios: DM-DONATE-T05.
    function test_givenVaultReturnsZeroShares_whenDonating_reverts() public {
        MockERC7540ExternalShareVault route = _externalShareRoute(false);
        route.setDepositResults(0, 0);
        _fundDonor(_donor, 10e18);
        bytes32 beforeState = _custodyState();
        _expectRevertZeroAmount();
        _donate(_donor, DEPOSIT_OPERATOR, 10e18);
        assertEq(_custodyState(), beforeState, "Zero return rolls back transfer");
    }

    // Scenarios: DM-DONATE-T06.
    function test_givenVaultSwitchesToAsyncDeposit_whenDonating_reverts() public {
        MockERC7540ExternalShareVault route = _externalShareRoute(false);
        route.setCapabilities(true, false, true, true);
        _fundDonor(_donor, 10e18);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(MockERC7540ExternalShareVault.AsyncDeposit.selector)
        );
        _donate(_donor, DEPOSIT_OPERATOR, 10e18);
        assertEq(_custodyState(), beforeState, "Async deposit refusal is atomic");
    }

    // Scenarios: DM-DONATE-T07.
    function test_givenVaultDepositFails_whenDonating_reverts() public {
        DepositManagerDonationVault route = _configureFaultVault(false);
        route.setFaults(true, false, false);
        _fundDonor(_donor, 1);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSelector(DepositManagerDonationVault.DepositFailed.selector));
        _donate(_donor, DEPOSIT_OPERATOR, 1);
        assertEq(_custodyState(), beforeState, "Deposit error rolls back mandatory transfer");
    }

    function _valuationFailure(bool async_) internal {
        DepositManagerDonationVault route = _configureFaultVault(async_);
        route.setFaults(false, true, false);
        _fundDonor(_donor, 1);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(DepositManagerDonationVault.ValuationFailed.selector)
        );
        _donate(_donor, DEPOSIT_OPERATOR, 1);
        assertEq(
            _custodyState(),
            beforeState,
            "Post-mint valuation error rolls back assets and shares"
        );
    }

    // Scenarios: DM-DONATE-T08.
    function test_givenSyncValuationFails_whenDonating_reverts() public {
        _valuationFailure(false);
    }

    // Scenarios: DM-DONATE-T08.
    function test_givenAsyncValuationFails_whenDonating_reverts() public {
        _valuationFailure(true);
    }

    // Scenarios: DM-DONATE-T09.
    function test_givenManagerSelfCaller_whenDonating_reverts() public {
        _configureIdle();
        asset.mint(address(depositManager), 3);
        vm.prank(address(depositManager));
        asset.approve(address(depositManager), 3);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(iAsset),
                address(depositManager),
                3,
                0
            )
        );
        _donate(address(depositManager), DEPOSIT_OPERATOR, 3);
        assertEq(_custodyState(), beforeState, "Existing manager funds are not allocated");
    }

    function _callbackToken() internal returns (ReentrantFeeToken token) {
        token = new ReentrantFeeToken();
        asset = MockERC20(address(token));
        iAsset = IERC20(address(token));
        _configureRoute(address(0));
        // The nested caller is the token; it is funded, approved, and targets a registered namespace.
        _fundDonor(address(token), 2);
        _fundDonor(_donor, 7);
        token.setCallback(
            address(depositManager),
            abi.encodeCall(IDepositManagerV1_1.donate, (iAsset, DEPOSIT_OPERATOR, 2))
        );
        token.setCallbackPhases(false, true);
    }

    // Scenarios: DM-DONATE-C01.
    function test_givenUnderlyingCallbackCaught_whenDonating() public {
        ReentrantFeeToken token = _callbackToken();
        _assertDonation(7, 7, 7);
        assertFalse(token.callbackSucceeded(), "Nested donation rejected");
        assertEq(
            token.callbackRevertData(),
            abi.encodeWithSignature("ReentrancyGuardReentrantCall()"),
            "Shared guard is the exact nested error"
        );
        assertEq(token.balanceOf(address(token)), 2, "Nested payer is not charged");
        _assertNamespace(DEPOSIT_OPERATOR, 7, 7, 0, 0);
    }

    // Scenarios: DM-DONATE-C02.
    function test_givenUnderlyingCallbackPropagates_whenDonating_reverts() public {
        ReentrantFeeToken token = _callbackToken();
        token.setBubbleCallbackFailure(true);
        bytes32 beforeState = _custodyState();
        vm.expectRevert(abi.encodeWithSelector(ReentrantFeeToken.CallbackFailed.selector));
        _donate(_donor, DEPOSIT_OPERATOR, 7);
        assertEq(_custodyState(), beforeState, "Propagated callback reverts entire donation");
        assertTrue(token.callbackEnabled(), "Callback state rolled back");
    }

    // Scenarios: DM-DONATE-C03.
    function test_givenOrdinaryDepositVaultCallback_whenNestedDonation() public {
        DepositManagerDonationVault route = _configureFaultVault(false);
        _fundDonor(address(route), 2);
        route.setCallback(
            address(depositManager),
            abi.encodeCall(IDepositManagerV1_1.donate, (iAsset, DEPOSIT_OPERATOR, 2))
        );
        assertEq(_seedDeposit(7), 9, "Outer ordinary deposit credits post-deposit value once");
        assertTrue(route.callbackAttempted(), "Vault callback attempted");
        assertEq(
            route.callbackError(),
            abi.encodeWithSignature("ReentrancyGuardReentrantCall()"),
            "Donation shares ordinary-deposit guard"
        );
        _assertNamespace(DEPOSIT_OPERATOR, 7, 9, 9, 0);
        assertEq(
            asset.balanceOf(address(route)),
            9,
            "Nested donation did not pull the vault's funded two units"
        );
    }

    // Scenarios: DM-DONATE-P18, DM-DONATE-P19.
    function test_whenQueryingInterfacesAndVersion() public {
        assertEq(
            type(IDepositManager).interfaceId,
            bytes4(0x7e3680dd),
            "Legacy pre-change interface ID pinned"
        );
        assertTrue(
            depositManager.supportsInterface(bytes4(0x7e3680dd)),
            "Legacy interface remains advertised"
        );
        assertTrue(
            depositManager.supportsInterface(type(IDepositManagerV1_1).interfaceId),
            "Compiled donation interface advertised"
        );
        assertTrue(
            depositManager.supportsInterface(type(IAssetManager).interfaceId),
            "Legacy asset manager remains advertised"
        );
        assertTrue(
            depositManager.supportsInterface(type(IAssetManagerV1_1).interfaceId),
            "V1.1 asset manager remains advertised"
        );
        MockDepositManager mock = new MockDepositManager(kernel, address(asset));
        assertTrue(
            mock.supportsInterface(type(IDepositManagerV1_1).interfaceId),
            "V1.1 integration mock advertises recompiled interface"
        );
        (uint8 major, uint8 minor) = depositManager.VERSION();
        assertEq(major, 1, "Version major unchanged");
        assertEq(minor, 1, "Version minor unchanged");
    }

    // Scenarios: DM-DONATE-A01, DM-DONATE-P12.
    function test_whenDonatingOwnUnderlying_thenCreditsOnlyTargetCustody() public {
        _configureIdle();
        _fundDonor(_donor, 10e18);
        (uint256 credit, uint256 shares) = _donate(_donor, DEPOSIT_OPERATOR, 10e18);
        assertEq(credit, 10e18, "Idle donation value");
        assertEq(shares, 10e18, "Idle custody units");
        (uint256 targetShares, uint256 targetAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertEq(targetShares, shares, "Target receives recorded custody");
        assertEq(targetAssets, credit, "Recorded idle value");
        assertEq(asset.balanceOf(_donor), 0, "Donor funds the donation");
        assertEq(asset.balanceOf(address(depositManager)), credit, "Physical custody agrees");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "Donation creates no claim"
        );
        assertEq(depositManager.getAssetDepositCapStatus(iAsset).utilization, 0, "No cap usage");
        (uint256 otherShares, ) = depositManager.getOperatorAssets(iAsset, _otherOperator);
        assertEq(otherShares, 0, "No credit to another operator");
    }
}
