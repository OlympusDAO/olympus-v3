// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {BurnerLoansCollateralActionTest} from "./fixtures/BurnerLoansCollateralActionTest.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {Actions} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralTest is BurnerLoansCollateralActionTest {
    error TransferFailed();
    error MockDepositManager_TransferFailed();
    error UnexpectedPricingCall();

    // Scenarios: BLCOL-DEPOSIT-I01.
    function test_whenAmountIsZero_reverts() public {
        _expectDepositRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            _borrower,
            0
        );
    }

    // Scenarios: BLCOL-DEPOSIT-I02.
    function test_whenAssetIsUnregistered_reverts(address asset_) public {
        vm.assume(!_core.isAssetRegistered(asset_));
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        // No return tuple exists on this expected-revert path.
        // forge-lint: disable-next-line(unused-return)
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(asset_, 1, _borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured.selector,
                asset_
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(asset_, 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P15.
    function test_givenOriginationsDisabled_whenBorrowerFirstDeposits(
        uint128 amount_,
        uint128 minimum_
    ) public givenOriginationsDisabled {
        _depositManager.setAssetMinimumDeposit(IERC20(address(_asset)), minimum_);
        amount_ = uint128(bound(amount_, minimum_ == 0 ? 1 : minimum_, type(uint128).max));
        _blockPricing();
        _assertPausedFirstDeposit(_borrower, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-P15.
    function test_givenOriginationsDisabled_whenOperatorFirstDeposits(
        uint128 amount_,
        uint128 minimum_
    ) public givenOriginationsDisabled {
        _depositManager.setAssetMinimumDeposit(IERC20(address(_asset)), minimum_);
        amount_ = uint128(bound(amount_, minimum_ == 0 ? 1 : minimum_, type(uint128).max));
        _grantOperator(type(uint48).max);
        _blockPricing();
        _assertPausedFirstDeposit(_recipient, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-P15.
    function test_givenOriginationsDisabled_whenFirstDepositAmountSeeds()
        public
        givenOriginationsDisabled
    {
        _grantOperator(type(uint48).max);
        _blockPricing();
        address[2] memory callers = [_borrower, _recipient];
        uint128[2] memory amounts = [uint128(1), type(uint128).max];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < amounts.length; ++j) {
                uint256 snapshot = vm.snapshotState();
                _depositManager.setAssetMinimumDeposit(IERC20(address(_asset)), amounts[j]);
                _assertPausedFirstDeposit(callers[i], amounts[j]);
                assertTrue(vm.revertToState(snapshot), "Restore absent-position seed state");
            }
        }
    }

    function _assertPausedFirstDeposit(address caller_, uint128 amount_) internal {
        uint64 positions = _floan.getPositionCount();
        (bool exists, , ) = LoanPositions.forCore(_core, address(_asset), _borrower);
        assertFalse(exists, "First deposit starts without a canonical position");
        _assertDirectDeposit(caller_, amount_, 0);
        assertEq(_floan.getPositionCount(), positions + 1, "Exactly one position is created");
        (, , IFLOANv1.Position memory position) = LoanPositions.forCore(
            _core,
            address(_asset),
            _borrower
        );
        assertEq(position.principalDue, 0, "First deposit creates no debt");
        assertEq(position.maturity, 0, "Collateral-only position has no maturity");
        assertEq(_inventory.activePrincipalOhm(), 0, "Inventory debt remains zero");
        assertFalse(
            _floan.getMarket(position.marketId).originationsEnabled,
            "First deposit does not re-enable originations"
        );
        assertEq(
            _floan.getMarketCollateral(position.marketId),
            amount_,
            "Market collateral records actual credit once"
        );
    }

    modifier givenOriginationsDisabled() {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _;
    }

    modifier givenEmptyCollateralPosition() {
        _depositAsset(_asset, 1, _borrower);
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1, _borrower, _recipient);
        _;
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenDebtFreePosition_whenTopUpQuoted_thenCreditReturned()
        public
        givenDebtFreeCollateral
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpQuote(1e6, type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenDebtFreePosition_whenToppedUp_thenExistingPositionCredited()
        public
        givenDebtFreeCollateral
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpDeposit(1e6, type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenEmptyPosition_whenTopUpQuoted_thenExistenceAllowsDeposit()
        public
        givenEmptyCollateralPosition
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpQuote(type(uint128).max, type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenEmptyPosition_whenToppedUp_thenSamePositionReused()
        public
        givenEmptyCollateralPosition
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpDeposit(type(uint128).max, type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P13.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenTopUpQuoted_thenPartialHealthReturned()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _mockTopUpHealth(0.95e18);
        _assertExistingTopUpQuote(1e6, 0.95e18);
    }

    // Scenarios: BLCOL-DEPOSIT-P13.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenPartialImprovementAllowed()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _mockTopUpHealth(0.95e18);
        _assertExistingTopUpDeposit(1e6, 0.95e18);
    }

    // Scenarios: BLCOL-DEPOSIT-P14.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenTopUpQuoted_thenCuredHealthReturned()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _mockTopUpHealth(1.2e18);
        _assertExistingTopUpQuote(1e6, 1.2e18);
    }

    // Scenarios: BLCOL-DEPOSIT-P14.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenHealthCuredWithoutNewDebt()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _mockTopUpHealth(1.2e18);
        _assertExistingTopUpDeposit(1e6, 1.2e18);
    }

    function _blockPricing() internal {
        bytes memory reason = abi.encodeWithSelector(UnexpectedPricingCall.selector);
        vm.mockCallRevert(address(_risk), bytes(""), reason);
        vm.mockCallRevert(address(_price), bytes(""), reason);
    }

    function _mockTopUpHealth(uint256 resultingHealth_) internal {
        IBurnerLoansCore.PriceSnapshot memory snapshot = _risk.snapshot(address(_asset));
        uint32 market = _core.marketId(address(_asset));
        bytes memory beforeHealth = abi.encodeCall(
            IBurnerLoansRisk.health,
            (snapshot, market, 2000e6, 100e9)
        );
        vm.mockCall(address(_risk), beforeHealth, abi.encode(uint256(0.9e18)));
        assertEq(
            _risk.health(snapshot, market, 2000e6, 100e9),
            0.9e18,
            "Position starts below full health"
        );
        bytes memory afterHealth = abi.encodeCall(
            IBurnerLoansRisk.health,
            (snapshot, market, 2001e6, 100e9)
        );
        vm.mockCall(address(_risk), afterHealth, abi.encode(resultingHealth_));
        vm.expectCall(address(_risk), afterHealth, uint64(1));
    }

    function _assertExistingTopUpQuote(uint128 amount_, uint256 expectedHealth_) internal {
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        uint64 positions = _floan.getPositionCount();
        (bool exists, , IFLOANv1.Position memory beforePosition) = LoanPositions.forCore(
            _core,
            address(_asset),
            _borrower
        );
        assertTrue(exists, "Canonical position already exists, including an empty position");
        vm.prank(_borrower);
        (uint256 credit, uint256 collateral, uint256 health) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(credit, amount_, "Direct-custody preview credits actual input");
        assertEq(
            collateral,
            uint256(beforePosition.collateral) + amount_,
            "Preview adds Q to existing collateral"
        );
        assertEq(health, expectedHealth_, "Preview returns independent configured health");
        assertEq(
            _accountingDigest(address(_asset)),
            beforeQuote,
            "Top-up quote changes no accounting, custody or allowances"
        );
        assertEq(_floan.getPositionCount(), positions, "Quote creates no position");
    }

    function _assertExistingTopUpDeposit(uint128 amount_, uint256 expectedHealth_) internal {
        (bool exists, uint64 id, IFLOANv1.Position memory beforePosition) = LoanPositions.forCore(
            _core,
            address(_asset),
            _borrower
        );
        assertTrue(exists, "Canonical position already exists, including an empty position");
        uint64 positions = _floan.getPositionCount();
        _asset.mint(_borrower, amount_);
        uint256 wallet = _asset.balanceOf(_borrower);
        vm.expectEmit(address(_collateral));
        emit IBurnerLoansCollateral.CollateralDeposited(
            _borrower,
            address(_asset),
            _borrower,
            amount_,
            amount_
        );
        vm.prank(_borrower);
        (uint128 credit, uint128 collateral, uint256 health) = _collateral.depositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(credit, amount_, "Actual direct credit equals Q");
        beforePosition.collateral += amount_;
        assertEq(collateral, beforePosition.collateral, "Return adds Q exactly once");
        assertEq(health, expectedHealth_, "Execution returns independent configured health");
        assertEq(_asset.balanceOf(_borrower), wallet - amount_, "Borrower funds the exact top-up");
        assertEq(
            keccak256(abi.encode(_floan.getPosition(id))),
            keccak256(abi.encode(beforePosition)),
            "Only collateral changes; debt, expiry and debt episode remain unchanged"
        );
        assertEq(_floan.getPositionCount(), positions, "Top-up creates no new position");
        assertFalse(
            _floan.getMarket(beforePosition.marketId).originationsEnabled,
            "Top-up does not re-enable originations"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            beforePosition.principalDue,
            "Top-up creates no Inventory debt"
        );
        assertEq(
            _floan.getMarketPrincipalDue(beforePosition.marketId),
            beforePosition.principalDue,
            "Market principal stays unchanged"
        );
        assertEq(
            _floan.getMarketCollateral(beforePosition.marketId),
            collateral,
            "Market collateral adds actual credit once"
        );
        _assertDirectCollateral(collateral);
    }

    // Scenarios: BLCOL-DEPOSIT-A06.
    function test_whenCallerIsUnauthorized_reverts(address caller_) public {
        vm.assume(!_core.isSenderAuthorized(caller_, _borrower));
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            caller_,
            1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N06.
    function test_givenDepositCap_whenActualCreditExceedsCap_reverts(
        uint64 cap_,
        uint64 amount_
    ) public {
        cap_ = uint64(bound(cap_, 0, 10_000e6 - 1));
        amount_ = uint64(bound(amount_, uint256(cap_) + 1, 10_000e6));
        _depositManager.setAssetDepositCap(IERC20(address(_asset)), cap_);
        _expectDepositRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(_asset),
                0,
                cap_
            ),
            _borrower,
            amount_
        );
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "Cap failure creates no collateral"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T03.
    function test_givenInexactCoreReceipt_whenDeposited_reverts() public {
        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(_asset.transferFrom.selector, _borrower, address(_core), 1),
            abi.encode(true)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        _assertInitialDepositQuote(address(_asset), 1, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(_asset),
                address(_core),
                1,
                0
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T08.
    function test_givenZeroDepositManagerCredit_whenDeposited_reverts() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(_depositManager.deposit.selector),
            abi.encode(uint256(0), uint256(0))
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralCredit.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P07.
    function test_givenDebt_whenRiskHealthFails_thenDepositRollsBack()
        public
        givenDebtBearingPosition
    {
        uint256 balance = _asset.balanceOf(_borrower);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(_asset), 1e6, _borrower);
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1e6, _borrower);
        assertEq(_asset.balanceOf(_borrower), balance, "Risk failure restores payer funds");
        vm.clearMockedCalls();
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Risk failure restores FLOAN collateral"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A08.
    function test_givenAuthorizationExpired_whenOperatorDeposits_reverts(uint48 elapsed_) public {
        elapsed_ = uint48(bound(elapsed_, 1, type(uint48).max - block.timestamp - 1));
        vm.prank(_borrower);
        _core.setAuthorization(_recipient, uint48(block.timestamp + 1));
        vm.warp(block.timestamp + 1 + elapsed_);
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(_recipient);
        _collateral.depositCollateral(address(_asset), 1e6, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N07.
    function test_givenMaximumCollateral_whenAnotherUnitDeposited_thenSameOverflowAndRollback()
        public
    {
        _asset.mint(_borrower, type(uint128).max);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), type(uint128).max, _borrower);
        bytes memory overflow = abi.encodeWithSignature("Panic(uint256)", uint256(0x11));
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(overflow);
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(_asset), 1, _borrower);
        vm.expectRevert(overflow);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            type(uint128).max,
            "Overflow restores DM balance"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            type(uint128).max,
            "Overflow restores DM credit"
        );
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            type(uint128).max,
            "Overflow leaves canonical collateral unchanged"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T04.
    function test_givenIncomingOverReceipt_whenDeposited_thenExactTransferBoundaryRejects() public {
        ReentrantFeeToken token = new ReentrantFeeToken();
        _price.setPrice(address(token), 1e18);
        _admit(address(token));
        token.mint(_borrower, 1);
        vm.prank(_borrower);
        token.approve(address(_core), 1);
        token.setCallbackFrom(
            address(_core),
            address(token),
            abi.encodeCall(token.mint, (address(_core), uint256(1)))
        );
        bytes32 rollbackState = _accountingDigest(address(token));
        _assertInitialDepositQuote(address(token), 1, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(token),
                address(_core),
                uint256(1),
                uint256(2)
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(token), 1, _borrower);
        assertEq(token.balanceOf(_borrower), 1, "Over-receipt restores payer");
        assertEq(token.balanceOf(address(_core)), 0, "Callback mint rolled back");
        assertEq(
            _lens.getPosition(address(token), _borrower).depositedCollateral,
            0,
            "No over-receipt credit"
        );
        assertEq(
            _accountingDigest(address(token)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P06.
    function test_givenDebt_whenSnapshotRefreshFails_thenIndependentViewAndRollback()
        public
        givenDebtBearingPosition
    {
        bytes memory failure = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_InvalidParam.selector
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            failure
        );
        vm.prank(_borrower);
        (uint256 quotedCredit, , ) = _collateral.previewDepositCollateral(
            address(_asset),
            1,
            _borrower
        );
        assertEq(quotedCredit, 1, "Stored-snapshot quote can remain readable when refresh fails");
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(failure);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            failure
        );
        vm.expectRevert(failure);
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            2000e6,
            "Snapshot failures leave collateral unchanged"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    function _expectDeposit(bytes memory reason_, uint128 amount_) internal {
        _expectDepositRevert(reason_, _borrower, amount_);
    }

    function _invalidManager() internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_InvalidDepositManager.selector,
                address(_depositManager)
            );
    }

    // Scenarios: BLCOL-DEPOSIT-D04.
    function test_givenDepositManagerInactive_whenDeposited_reverts() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_depositManager));
        _expectDeposit(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_depositManager)
            ),
            1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-I04.
    function test_givenDepositManagerDisabled_whenDeposited_reverts() public {
        IEnabler(address(_depositManager)).disable("");
        _expectDeposit(_invalidManager(), 1);
    }

    // Scenarios: BLCOL-DEPOSIT-I05.
    function test_givenAssetNoLongerConfiguredInManager_whenDeposited_reverts() public {
        IAssetManager.AssetConfiguration memory cfg = _depositManager.getAssetConfiguration(
            IERC20(address(_asset))
        );
        cfg.isConfigured = false;
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature("getAssetConfiguration(address)", address(_asset)),
            abi.encode(cfg)
        );
        _expectDeposit(_invalidManager(), 1);
    }

    // Scenarios: BLCOL-DEPOSIT-I06.
    function test_givenOnlyAnotherOperatorPeriod_whenDeposited_reverts() public {
        bytes memory coreQuery = abi.encodeCall(
            IDepositManager.isAssetPeriod,
            (IERC20(address(_asset)), uint8(1), address(_core))
        );
        vm.mockCall(
            address(_depositManager),
            coreQuery,
            abi.encode(IDepositManager.AssetPeriodStatus(false, false))
        );
        vm.mockCall(
            address(_depositManager),
            abi.encodeCall(
                IDepositManager.isAssetPeriod,
                (IERC20(address(_asset)), uint8(1), _recipient)
            ),
            abi.encode(IDepositManager.AssetPeriodStatus(true, true))
        );
        vm.expectCall(address(_depositManager), coreQuery, 2);
        _expectDeposit(_invalidManager(), 1);
    }

    // Scenarios: BLCOL-DEPOSIT-I07.
    function test_givenCoreDepositPeriodDisabled_whenDeposited_reverts() public {
        _depositManager.disableAssetPeriod(IERC20(address(_asset)), 1, address(_core));
        _expectDeposit(_invalidManager(), 1);
    }

    // Scenarios: BLCOL-DEPOSIT-I08.
    function test_givenMinimumDeposit_whenInputBelowMinimum_reverts(
        uint256 minimum_,
        uint128 amount_
    ) public {
        minimum_ = bound(minimum_, 2, type(uint256).max);
        uint256 upper = minimum_ - 1;
        if (upper > type(uint128).max) upper = type(uint128).max;
        amount_ = uint128(bound(amount_, 1, upper));
        _depositManager.setAssetMinimumDeposit(IERC20(address(_asset)), minimum_);
        _expectDeposit(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(_asset),
                uint256(amount_),
                minimum_
            ),
            amount_
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N05.
    function test_givenExactDepositCapRoom_whenDeposited_thenCapReached(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        _asset.mint(_borrower, amount_);
        _depositManager.setAssetDepositCap(IERC20(address(_asset)), amount_);
        vm.prank(_borrower);
        (uint256 quote, , ) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        vm.prank(_borrower);
        (uint128 credit, , ) = _collateral.depositCollateral(address(_asset), amount_, _borrower);
        assertEq(quote, amount_, "Exact cap quote");
        assertEq(credit, amount_, "Exact cap accepted");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            amount_,
            "Exact cap utilization"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T01.
    function test_whenTransferFromReturnsFalse_thenNoCredit() public {
        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(
                _asset.transferFrom.selector,
                _borrower,
                address(_core),
                uint256(1)
            ),
            abi.encode(false)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        _assertInitialDepositQuote(address(_asset), 1, 1);
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(_asset))
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "False transfer creates no credit"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T02.
    function test_whenTransferFromReverts_thenExactErrorAndNoCredit() public {
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(
                _asset.transferFrom.selector,
                _borrower,
                address(_core),
                uint256(1)
            ),
            abi.encodeWithSelector(TransferFailed.selector)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        _assertInitialDepositQuote(address(_asset), 1, 1);
        vm.expectRevert(TransferFailed.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "Reverted transfer creates no credit"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T06.
    function test_givenReceiptBurnApprovalRejected_whenDeposited_thenFullRollback() public {
        IReceiptTokenManager receipts = _depositManager.getReceiptTokenManager();
        vm.mockCall(
            address(receipts),
            abi.encodeWithSignature(
                "approve(address,uint256,uint256)",
                address(_depositManager),
                _depositManager.getReceiptTokenId(IERC20(address(_asset)), 1, address(_core)),
                type(uint256).max
            ),
            abi.encode(false)
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        _assertInitialDepositQuote(address(_asset), 1, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_ReceiptApprovalFailed.selector,
                address(receipts)
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            0,
            "Receipt approval failure restores deposit"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            0,
            "Receipt liability restored"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T08.
    function test_givenProjectedZeroCredit_whenPreviewed_reverts() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewDeposit.selector),
            abi.encode(uint256(0), uint256(0))
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansCore.BurnerLoansCore_ZeroCollateralCredit.selector);
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T09.
    function test_givenUnrepresentableProjectedCredit_whenPreviewed_reverts(
        uint256 credit_
    ) public {
        credit_ = bound(credit_, uint256(type(uint128).max) + 1, type(uint256).max);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.previewDeposit.selector),
            abi.encode(credit_, uint256(1))
        );
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, credit_)
        );
        vm.prank(_borrower);
        _collateral.previewDepositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T07.
    function test_givenCoreIncomingPull_whenDepositManagerRejects_thenPullRollsBack() public {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManager.deposit.selector),
            abi.encodeWithSelector(MockDepositManager_TransferFailed.selector)
        );
        uint256 beforeBalance = _asset.balanceOf(_borrower);
        bytes32 rollbackState = _accountingDigest(address(_asset));
        _assertInitialDepositQuote(address(_asset), 1, 1);
        vm.expectRevert(MockDepositManager_TransferFailed.selector);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(_asset.balanceOf(_borrower), beforeBalance, "Earlier incoming Core pull restored");
        assertEq(_asset.balanceOf(address(_core)), 0, "No transient receipt remains");
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            0,
            "Failed DM call creates no position credit"
        );
        assertEq(
            _accountingDigest(address(_asset)),
            rollbackState,
            "Rejected action restores complete accounting"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A11.
    function test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts(
        address caller_,
        uint48 deadline_,
        uint48 now_
    ) public {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        deadline_ = uint48(bound(deadline_, 2, type(uint48).max));
        _grantOperator(deadline_);
        vm.warp(bound(now_, 1, deadline_));
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            caller_,
            1
        );
        assertEq(
            _core.authorizationDeadlines(_borrower, _recipient),
            deadline_,
            "Unrelated caller preserves valid grant"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A07.
    function test_givenCancelledGrant_whenOperatorActs_reverts(address caller_) public {
        vm.assume(caller_ != _borrower);
        vm.startPrank(_borrower);
        _core.setAuthorization(caller_, type(uint48).max);
        _core.cancelAuthorization(caller_);
        vm.stopPrank();
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            caller_,
            1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A08.
    function test_givenExpiredGrant_whenOperatorActs_reverts(
        uint48 deadline_,
        uint256 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        vm.warp(1);
        vm.prank(_borrower);
        _core.setAuthorization(_recipient, deadline_);
        now_ = bound(now_, uint256(deadline_) + 1, type(uint256).max);
        vm.warp(now_);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-L06, BLCOL-DEPOSIT-L07, BLCOL-DEPOSIT-L08, BLCOL-DEPOSIT-L09, BLCOL-DEPOSIT-L10, BLCOL-DEPOSIT-L11, BLCOL-DEPOSIT-L12, BLCOL-DEPOSIT-L13.
    function test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified(
        address caller_,
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _setPolicyState(_collateral, false, enabled_);
        _setPolicyState(_core, coreActive_, coreEnabled_);
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
            address(_collateral)
        );
        _expectDepositRevert(reason, caller_, 1);
        _expectDepositRevert(reason, caller_, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-L02, BLCOL-DEPOSIT-L03, BLCOL-DEPOSIT-L04, BLCOL-DEPOSIT-L05.
    function test_givenDisabledAction_whenInvoked_thenLocalPauseWins(
        address caller_,
        bool coreActive_,
        bool coreEnabled_
    ) public {
        _collateral.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectDepositRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, 1);
        _expectDepositRevert(abi.encodeWithSelector(IEnabler.NotEnabled.selector), caller_, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-D01, BLCOL-DEPOSIT-D02, BLCOL-DEPOSIT-D03.
    function test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified(
        address caller_,
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_core, active_, enabled_);
        _expectDepositRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            caller_,
            1
        );
        _expectDepositRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            caller_,
            0
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A10.
    function test_givenReportedKernelMismatch_whenDeposited_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCall(
            address(_collateral),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        _assertActionWithoutKernelRead(operator_);
    }

    // Scenarios: BLCOL-DEPOSIT-A10.
    function test_givenActionKernelGetterReverts_whenDeposited_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCallRevert(address(_collateral), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _assertActionWithoutKernelRead(operator_);
    }

    function _assertActionWithoutKernelRead(bool operator_) private {
        address caller = operator_ ? _recipient : _borrower;
        if (operator_) _grantOperator(type(uint48).max);
        vm.expectCall(address(_collateral), abi.encodeWithSignature("kernel()"), uint64(0));
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 7, _borrower);
        _assertDirectDeposit(caller, 1, 7);
    }

    // Scenarios: BLCOL-DEPOSIT-P03, BLCOL-DEPOSIT-P04, BLCOL-DEPOSIT-P05.
    function test_givenDebt_whenHealthBoundarySeedsUsed_thenNoCureThreshold() public {
        uint256[5] memory seeds = [
            uint256(0),
            uint256(1e18 - 1),
            uint256(1e18),
            uint256(1e18 + 1),
            type(uint256).max
        ];
        for (uint256 i; i < seeds.length; ++i) {
            uint256 checkpoint = vm.snapshotState();
            test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff(
                uint128(1000e6 + i),
                uint128(1e9 + i),
                uint128(i + 1),
                seeds[i]
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore position between independent health seeds"
            );
        }
    }

    // Scenarios: BLCOL-DEPOSIT-N02, BLCOL-DEPOSIT-P02.
    function test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition(
        uint128 prior_,
        uint128 amount_
    ) public {
        prior_ = uint128(bound(prior_, 1, type(uint128).max - 1));
        amount_ = uint128(bound(amount_, 1, uint256(type(uint128).max) - prior_));
        _asset.mint(_borrower, uint256(prior_) + amount_);
        _blockPricing();
        vm.startPrank(_borrower);
        _collateral.depositCollateral(address(_asset), prior_, _borrower);
        (uint256 quotedCredit, uint256 quotedTotal, uint256 quotedHealth) = _collateral
            .previewDepositCollateral(address(_asset), amount_, _borrower);
        (uint128 credit, uint128 total, uint256 health) = _collateral.depositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        vm.stopPrank();
        assertEq(credit, amount_, "Exact top-up credit");
        assertEq(total, uint256(prior_) + amount_, "Existing collateral plus actual credit");
        assertEq(quotedCredit, credit, "Top-up credit quote");
        assertEq(quotedTotal, total, "Top-up total quote");
        assertEq(health, type(uint256).max, "Debt-free health");
        assertEq(quotedHealth, health, "No price-dependent quote");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            total,
            "Aggregate credit updated"
        );
        _assertDirectCollateral(total);
    }

    // Scenarios: BLCOL-DEPOSIT-N02, BLCOL-DEPOSIT-P02.
    function test_givenNearMaximumDebtFreeCollateral_whenOneUnitAdded_thenMaximumReached() public {
        test_givenDebtFreeCollateral_whenToppedUp_thenActualCreditAddsToExistingPosition(
            type(uint128).max - 1,
            1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-L01, BLCOL-DEPOSIT-A01, BLCOL-DEPOSIT-N01, BLCOL-DEPOSIT-P01.
    function test_whenDirectDepositAcrossFullRange_thenAllReturnsAndCustodyAgree(
        uint128 amount_
    ) public {
        _blockPricing();
        _assertDirectDeposit(_borrower, uint128(bound(amount_, 1, type(uint128).max)), 0);
    }

    // Scenarios: BLCOL-DEPOSIT-N01.
    function test_whenOneUnitDeposited_thenFullCredit() public {
        _assertDirectDeposit(_borrower, 1, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-N01.
    function test_whenMaximumDeposited_thenAllReturnsAndCustodyAgree() public {
        _assertDirectDeposit(_borrower, type(uint128).max, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-A02.
    function test_givenOperatorGrant_whenBeforeDeadline_thenAllDepositEffectsAgree(
        uint48 deadline_,
        uint48 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 2, type(uint48).max));
        _grantOperator(deadline_);
        vm.warp(bound(now_, 1, uint256(deadline_) - 1));
        uint256 borrowerWallet = _asset.balanceOf(_borrower);
        _assertDirectDeposit(_recipient, 7, 0);
        assertEq(_asset.balanceOf(_borrower), borrowerWallet, "Operator spends its own wallet");
    }

    // Scenarios: BLCOL-DEPOSIT-A03.
    function test_givenOperatorGrant_whenAtDeadline_thenDepositSucceeds(uint48 deadline_) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        _grantOperator(deadline_);
        vm.warp(deadline_);
        _assertDirectDeposit(_recipient, 7, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-A02, BLCOL-DEPOSIT-A03, BLCOL-DEPOSIT-A04.
    function test_givenMaximumOperatorDeadline_whenDepositBoundaryTimesUsed() public {
        _grantOperator(type(uint48).max);
        vm.warp(1);
        _assertDirectDeposit(_recipient, 1, 0);
        vm.warp(type(uint48).max - 1);
        _assertDirectDeposit(_recipient, 1, 1);
        vm.warp(type(uint48).max);
        _assertDirectDeposit(_recipient, 1, 2);
    }

    // Scenarios: BLCOL-DEPOSIT-A05.
    function test_whenBorrowerIsZero_thenPreviewAndExecutionReject(address caller_) public {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector);
        vm.prank(caller_);
        _collateral.previewDepositCollateral(address(_asset), 1, address(0));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector);
        vm.prank(caller_);
        _collateral.depositCollateral(address(_asset), 1, address(0));
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Zero borrower leaves all accounting unchanged"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A09.
    function test_givenSettlementRoleRevoked_whenDepositing_thenBothPathsReject() public {
        _rolesAdmin.revokeRole(BL_COLLATERAL_POLICY_ROLE, address(_collateral));
        _expectDepositRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_COLLATERAL_POLICY_ROLE),
            _borrower,
            1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T03.
    function test_givenPreexistingCoreSurplus_whenIncomingReceiptIsShort_reverts() public {
        _asset.mint(address(_core), 17);
        vm.mockCall(
            address(_asset),
            abi.encodeCall(_asset.transferFrom, (_borrower, address(_core), uint256(1))),
            abi.encode(true)
        );
        bytes32 beforeState = _accountingDigest(address(_asset));
        _assertInitialDepositQuote(address(_asset), 1, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(_asset),
                address(_core),
                1,
                0
            )
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Surplus cannot subsidize an inexact receipt"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-I08.
    function test_givenMinimumDeposit_whenImmediatelyBelowMinimum_reverts(uint128 minimum_) public {
        minimum_ = uint128(bound(minimum_, 2, type(uint128).max));
        _depositManager.setAssetMinimumDeposit(IERC20(address(_asset)), minimum_);
        _expectDepositRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(_asset),
                uint256(minimum_) - 1,
                uint256(minimum_)
            ),
            _borrower,
            minimum_ - 1
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N01, BLCOL-DEPOSIT-I08.
    function test_givenMinimumDeposit_whenExactMinimum_thenAllReturnsAndCustodyAgree(
        uint128 minimum_
    ) public {
        minimum_ = uint128(bound(minimum_, 1, type(uint128).max));
        _depositManager.setAssetMinimumDeposit(IERC20(address(_asset)), minimum_);
        _assertDirectDeposit(_borrower, minimum_, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-T09.
    function test_givenOversizedActualCredit_whenDeposited_reverts(uint256 credit_) public {
        credit_ = bound(credit_, uint256(type(uint128).max) + 1, type(uint256).max);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(_depositManager.deposit.selector),
            abi.encode(uint256(0), credit_)
        );
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, credit_)
        );
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Unrepresentable actual credit fully rolls back"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T09.
    function test_givenMaximumActualCredit_whenDeposited_reverts() public {
        test_givenOversizedActualCredit_whenDeposited_reverts(type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-L01.
    function test_givenReEnabledAction_whenDeposited_thenOperational() public {
        _collateral.disable("");
        _collateral.reEnable();
        _assertDirectDeposit(_borrower, 1, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-L01.
    function test_givenReactivatedAction_whenDeposited_thenOperational() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_collateral));
        _kernel.executeAction(Actions.ActivatePolicy, address(_collateral));
        _assertDirectDeposit(_borrower, 1, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-L06, BLCOL-DEPOSIT-L07, BLCOL-DEPOSIT-L08, BLCOL-DEPOSIT-L09, BLCOL-DEPOSIT-L10, BLCOL-DEPOSIT-L11, BLCOL-DEPOSIT-L12, BLCOL-DEPOSIT-L13.
    function test_givenInactive_whenAllLifecycleSeedsUsed_thenAdmissionWins() public {
        for (uint256 flags; flags < 8; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenInactiveAction_whenInvoked_thenOwnAddressIdentified(
                address(0),
                flags & 1 != 0,
                flags & 2 != 0,
                flags & 4 != 0
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore lifecycle between equivalent rejection seeds"
            );
        }
    }

    // Scenarios: BLCOL-DEPOSIT-L02, BLCOL-DEPOSIT-L03, BLCOL-DEPOSIT-L04, BLCOL-DEPOSIT-L05.
    function test_givenDisabled_whenAllLifecycleSeedsUsed_thenAdmissionWins() public {
        for (uint256 flags; flags < 4; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenDisabledAction_whenInvoked_thenLocalPauseWins(
                address(0),
                flags & 1 != 0,
                flags & 2 != 0
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore lifecycle between equivalent rejection seeds"
            );
        }
    }

    // Scenarios: BLCOL-DEPOSIT-D01, BLCOL-DEPOSIT-D02, BLCOL-DEPOSIT-D03.
    function test_givenUnavailableCore_whenAllLifecycleSeedsUsed_thenAdmissionWins() public {
        for (uint256 flags; flags < 3; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenCoreUnavailable_whenInvoked_thenDependencyIdentified(
                address(0),
                flags == 1,
                flags == 2
            );
            assertTrue(
                vm.revertToState(checkpoint),
                "Restore lifecycle between equivalent rejection seeds"
            );
        }
    }

    // Scenarios: BLCOL-DEPOSIT-P03, BLCOL-DEPOSIT-P04, BLCOL-DEPOSIT-P05.
    function test_givenVariableDebtAndCollateral_whenToppedUp_thenExactHealthHandoff(
        uint128 prior_,
        uint128 debt_,
        uint128 amount_,
        uint256 health_
    ) public {
        prior_ = uint128(bound(prior_, 1000e6, 10_000e6));
        debt_ = uint128(bound(debt_, 1, 100e9));
        amount_ = uint128(bound(amount_, 1, uint256(type(uint128).max) - prior_));
        _depositAsset(_asset, prior_, _borrower);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), debt_, _borrower, _borrower, type(uint256).max);
        _asset.mint(_borrower, amount_);
        IBurnerLoansCore.PriceSnapshot memory snapshot = _risk.snapshot(address(_asset));
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encode(health_)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.health,
                (
                    snapshot,
                    _core.marketId(address(_asset)),
                    uint256(prior_) + amount_,
                    uint256(debt_)
                )
            ),
            uint64(2)
        );
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        vm.prank(_borrower);
        (uint256 q, uint256 c, uint256 h) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(q, amount_, "Independent direct credit");
        assertEq(c, uint256(prior_) + amount_, "Independent projected collateral");
        assertEq(h, health_, "Configured quote health handed through");
        assertEq(
            _accountingDigest(address(_asset)),
            beforeQuote,
            "Debt-bearing preview makes no changes"
        );
        vm.prank(_borrower);
        (uint128 actualCredit, uint128 actualCollateral, uint256 actualHealth) = _collateral
            .depositCollateral(address(_asset), amount_, _borrower);
        assertEq(actualCredit, amount_, "Actual direct credit");
        assertEq(actualCollateral, c, "Actual post-settlement collateral");
        assertEq(
            actualHealth,
            health_,
            "Configured Risk health returned unchanged, including unhealthy values"
        );
        _assertDirectCollateral(actualCollateral);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            debt_,
            "Top-up preserves arbitrary principal"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-T09.
    function test_givenFirstUnrepresentableCredit_whenDeposited_reverts() public {
        test_givenOversizedActualCredit_whenDeposited_reverts(uint256(type(uint128).max) + 1);
    }

    // Scenarios: BLCOL-DEPOSIT-T09.
    function test_givenProjectedCreditEndpoints_whenPreviewed_reverts() public {
        test_givenUnrepresentableProjectedCredit_whenPreviewed_reverts(
            uint256(type(uint128).max) + 1
        );
        test_givenUnrepresentableProjectedCredit_whenPreviewed_reverts(type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-A08.
    function test_givenExpiredGrant_whenDeadlineBoundarySeedsUsed_thenUnauthorized() public {
        test_givenExpiredGrant_whenOperatorActs_reverts(1, 2);
        test_givenExpiredGrant_whenOperatorActs_reverts(
            type(uint48).max,
            uint256(type(uint48).max) + 1
        );
        test_givenExpiredGrant_whenOperatorActs_reverts(1, type(uint256).max);
    }

    // Scenarios: BLCOL-DEPOSIT-A11.
    function test_givenAnotherOperatorGrant_whenIndependentBoundaryTimesUsed_thenUnrelatedCallerRejected()
        public
    {
        test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts(
            address(0),
            type(uint48).max,
            1
        );
        test_givenOtherOperatorGrant_whenUnrelatedCallerActs_reverts(
            address(0),
            type(uint48).max,
            type(uint48).max
        );
    }

    // Scenarios: BLCOL-DEPOSIT-N07.
    function test_givenExistingCollateral_whenTopUpOverflowsUint128_thenBothPathsRollBack(
        uint128 prior_,
        uint128 amount_
    ) public {
        prior_ = uint128(bound(prior_, 1, type(uint128).max));
        amount_ = uint128(
            bound(amount_, uint256(type(uint128).max) - prior_ + 1, type(uint128).max)
        );
        _depositAsset(_asset, prior_, _borrower);
        _asset.mint(_borrower, amount_);
        _expectDepositRevert(
            abi.encodeWithSignature("Panic(uint256)", uint256(0x11)),
            _borrower,
            amount_
        );
    }

    // Scenarios: BLCOL-DEPOSIT-I02.
    function test_whenZeroAsset_thenExactRegistrationError() public {
        test_whenAssetIsUnregistered_reverts(address(0));
    }

    // Scenarios: BLCOL-DEPOSIT-A01, BLCOL-DEPOSIT-A02, BLCOL-DEPOSIT-A03, BLCOL-DEPOSIT-A04, BLCOL-DEPOSIT-A06, BLCOL-DEPOSIT-A07, BLCOL-DEPOSIT-A08, BLCOL-DEPOSIT-A11, BLCOL-DEPOSIT-A12.
    function test_whenAnyViewerQuotesWithoutAuthorizationRead(
        address viewer_,
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        // Poison the complete authorization selector: neither viewer nor borrower grants may be read.
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IOperatorAuth.isSenderAuthorized.selector),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector)
        );
        _assertPermissionlessQuote(viewer_, amount_);
    }

    function _assertPermissionlessQuote(address viewer_, uint128 amount_) private {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.recordLogs();
        vm.prank(viewer_);
        (uint256 credit, uint256 total, uint256 health) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(credit, amount_, "quote credits explicit amount");
        assertEq(total, amount_, "quote uses borrower's initially empty position");
        assertEq(health, type(uint256).max, "debt-free quote health");
        assertEq(vm.getRecordedLogs().length, 0, "quote emits no logs");
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "quote preserves all custody and positions"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A06, BLCOL-DEPOSIT-A13.
    function test_givenNoGrant_whenUnrelatedViewerQuotes() public {
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A02, BLCOL-DEPOSIT-A11, BLCOL-DEPOSIT-A13.
    function test_givenValidGrant_whenUnrelatedViewerQuotes() public {
        _grantOperator(10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _assertDirectDeposit(_recipient, 7, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-A03, BLCOL-DEPOSIT-A13.
    function test_givenGrantDeadline_whenUnrelatedViewerQuotes() public {
        _grantOperator(10);
        vm.warp(10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _assertDirectDeposit(_recipient, 7, 0);
    }

    // Scenarios: BLCOL-DEPOSIT-A08, BLCOL-DEPOSIT-A13.
    function test_givenExpiredGrant_whenUnrelatedViewerQuotes() public {
        _grantOperator(10);
        vm.warp(11);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A07, BLCOL-DEPOSIT-A13.
    function test_givenRevokedGrant_whenUnrelatedViewerQuotes() public {
        _grantOperator(10);
        vm.prank(_borrower);
        _core.cancelAuthorization(_recipient);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A14.
    function test_whenViewerHasAnotherPosition_thenSpecifiedBorrowerQuoted() public {
        _depositAsset(_asset, 100, _borrower);
        _depositAsset(_asset, 50, _OTHER_BORROWER);
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.prank(_OTHER_BORROWER);
        (uint256 credit, uint256 total, uint256 health) = _collateral.previewDepositCollateral(
            address(_asset),
            7,
            _borrower
        );
        assertEq(credit, 7, "explicit deposit amount quoted");
        assertEq(total, 107, "borrower position, not viewer position, receives projected credit");
        assertEq(health, type(uint256).max, "specified position is debt-free");
        assertEq(_accountingDigest(address(_asset)), beforeState, "neither position changes");
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
