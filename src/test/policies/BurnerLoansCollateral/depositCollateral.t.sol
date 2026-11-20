// SPDX-License-Identifier: Unlicense
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
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";
import {Actions} from "src/Kernel.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_COLLATERAL_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";

// Contracts
import {MockBackingOracle} from "src/test/mocks/MockBackingOracle.sol";
import {BurnerLoansCollateralActionTest} from "./fixtures/BurnerLoansCollateralActionTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

contract BurnerLoansCollateralDepositCollateralTest is BurnerLoansCollateralActionTest {
    error TransferFailed();
    error MockDepositManager_TransferFailed();
    error UnexpectedPricingCall();

    // Scenarios: BLCOL-DEPOSIT-P22.
    function test_whenDeposited_thenOnlyCreditAndCollateralReturned() public {
        vm.prank(_borrower);
        (bool success, bytes memory result) = address(_collateral).call(
            abi.encodeCall(_collateral.depositCollateral, (address(_asset), uint128(1), _borrower))
        );
        assertTrue(success, "Valid deposit succeeds");
        assertEq(result.length, 64, "Deposit execution returns exactly two ABI words");
        (uint128 credit, uint128 total) = abi.decode(result, (uint128, uint128));
        assertEq(credit, 1, "Actual credit is one raw unit");
        assertEq(total, 1, "First deposit records one raw unit");
        _assertDirectCollateral(total);
    }

    // Scenarios: BLCOL-DEPOSIT-D05.
    function test_givenDebtAndBackingPaused_whenDeposited() public givenDebtBearingPosition {
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        uint256 wallet = _asset.balanceOf(_borrower);
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1e6, _borrower);
        _assertDirectCollateral(2001e6);
        assertEq(_asset.balanceOf(_borrower), wallet - 1e6, "Borrower funds the protective top-up");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Top-up preserves aggregate principal");
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndPricingUnavailable_whenDeposited() public givenDebtBearingPosition {
        _blockPricing();
        vm.prank(_borrower);
        _collateral.depositCollateral(address(_asset), 1e6, _borrower);
        _assertDirectCollateral(2001e6);
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9,
            "Unavailable pricing does not change debt"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P22.
    function test_whenDepositQuoted_thenOnlyCreditAndCollateralReturned() public {
        (bool success, bytes memory result) = address(_collateral).staticcall(
            abi.encodeCall(_collateral.previewDepositCollateral, (address(_asset), 1, _borrower))
        );
        assertTrue(success, "Valid permissionless deposit quote succeeds");
        assertEq(result.length, 64, "Deposit quote returns exactly two ABI words");
        (uint256 credit, uint256 collateral) = abi.decode(result, (uint256, uint256));
        assertEq(credit, 1, "Quote credits one raw unit");
        assertEq(collateral, 1, "First deposit projects one raw unit collateral");
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndPricingUnavailable_whenDepositQuoted_thenNoPricingRead()
        public
        givenDebtBearingPosition
    {
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        _blockPricing();
        (bool success, bytes memory result) = address(_collateral).staticcall(
            abi.encodeCall(_collateral.previewDepositCollateral, (address(_asset), 1e6, _borrower))
        );
        assertTrue(success, "Debt-bearing quote does not consume Risk or PRICE");
        assertEq(result.length, 64, "Debt-bearing quote has no health output");
        (uint256 credit, uint256 collateral) = abi.decode(result, (uint256, uint256));
        assertEq(credit, 1e6, "Debt-bearing quote retains snapshot conversion");
        assertEq(collateral, 2001e6, "Debt-bearing quote adds credit to canonical collateral");
        vm.clearMockedCalls();
        assertEq(_accountingDigest(address(_asset)), beforeQuote, "Quote preserves accounting");
    }

    // Scenarios: BLCOL-DEPOSIT-P22.
    function test_whenAnyViewerQuotesCompatibleCollateral(
        address viewer_,
        uint128 prior_,
        uint128 amount_
    ) public {
        prior_ = uint128(bound(prior_, 0, type(uint128).max - 1));
        amount_ = uint128(bound(amount_, 1, uint256(type(uint128).max) - prior_));
        _assertRawDepositQuote(viewer_, prior_, amount_);
    }

    // Scenarios: BLCOL-DEPOSIT-P22.
    function test_whenDepositQuoteMaximumSeeds() public {
        _assertRawDepositQuote(address(0), 0, type(uint128).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P22.
    function test_givenExistingCollateral_whenDepositQuoteReachesMaximum() public {
        _assertRawDepositQuote(_OTHER_BORROWER, type(uint128).max - 1, 1);
    }

    function _assertRawDepositQuote(address viewer_, uint128 prior_, uint128 amount_) internal {
        if (prior_ != 0) _depositAsset(_asset, prior_, _borrower);
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        vm.prank(viewer_);
        (bool success, bytes memory result) = address(_collateral).staticcall(
            abi.encodeCall(
                _collateral.previewDepositCollateral,
                (address(_asset), amount_, _borrower)
            )
        );
        assertTrue(success, "Every viewer can quote compatible collateral");
        assertEq(result.length, 64, "Successful quote returns exactly two ABI words");
        (uint256 credit, uint256 collateral) = abi.decode(result, (uint256, uint256));
        assertEq(credit, amount_, "Raw quote preserves direct credit");
        assertEq(collateral, uint256(prior_) + amount_, "Raw quote adds canonical collateral");
        assertEq(_accountingDigest(address(_asset)), beforeQuote, "Raw quote preserves accounting");
        _asset.mint(_borrower, amount_);
        vm.prank(_borrower);
        (uint128 actualCredit, uint128 actualCollateral) = _collateral.depositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(actualCredit, credit, "Stable execution matches credit quote");
        assertEq(actualCollateral, collateral, "Stable execution matches collateral quote");
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskSnapshotUnavailable_whenDepositQuoted()
        public
        givenDebtBearingPosition
    {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            abi.encodeWithSelector(UnexpectedPricingCall.selector)
        );
        _assertExistingTopUpQuote(1e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskPointerUnavailable_whenDepositQuoted()
        public
        givenDebtBearingPosition
    {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.risk.selector),
            abi.encodeWithSelector(UnexpectedPricingCall.selector)
        );
        _assertExistingTopUpQuote(1e6);
    }

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
        _assertExistingTopUpQuote(1e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenDebtFreePosition_whenToppedUp_thenExistingPositionCredited()
        public
        givenDebtFreeCollateral
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpDeposit(1e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenEmptyPosition_whenTopUpQuoted_thenExistenceAllowsDeposit()
        public
        givenEmptyCollateralPosition
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpQuote(type(uint128).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P12.
    function test_givenOriginationsDisabled_givenEmptyPosition_whenToppedUp_thenSamePositionReused()
        public
        givenEmptyCollateralPosition
        givenOriginationsDisabled
    {
        _blockPricing();
        _assertExistingTopUpDeposit(type(uint128).max);
    }

    // Scenarios: BLCOL-DEPOSIT-P13.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenPartialTopUpQuoted()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _prepareUnhealthyTopUp();
        _blockPricing();
        _assertExistingTopUpQuote(100e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P13.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenPartialImprovementAllowed()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _prepareUnhealthyTopUp();
        _blockPricing();
        _assertExistingTopUpDeposit(100e6);
        vm.clearMockedCalls();
        // C=1500 assets at $0.075; D=100 OHM requires $125 backing.
        // After Q=100 or 500 assets, H is $120/$125=0.96 or $150/$125=1.2 WAD.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 1500e6 + 100e6, 100e9),
            0.96e18,
            "Independent post-deposit health query"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P14.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenCuringTopUpQuoted()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _prepareUnhealthyTopUp();
        _blockPricing();
        _assertExistingTopUpQuote(500e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P14.
    function test_givenOriginationsDisabled_givenUnhealthyDebt_whenToppedUp_thenHealthCuredWithoutNewDebt()
        public
        givenDebtBearingPosition
        givenOriginationsDisabled
    {
        _prepareUnhealthyTopUp();
        _blockPricing();
        _assertExistingTopUpDeposit(500e6);
        vm.clearMockedCalls();
        // C=1500 assets at $0.075; D=100 OHM requires $125 backing.
        // After Q=100 or 500 assets, H is $120/$125=0.96 or $150/$125=1.2 WAD.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 1500e6 + 500e6, 100e9),
            1.2e18,
            "Independent post-deposit health query"
        );
    }

    function _blockPricing() internal {
        bytes memory reason = abi.encodeWithSelector(UnexpectedPricingCall.selector);
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.risk.selector),
            reason
        );
        vm.mockCallRevert(address(_risk), bytes(""), reason);
        vm.mockCallRevert(address(_price), bytes(""), reason);
    }

    function _prepareUnhealthyTopUp() internal {
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 500e6, _borrower, _borrower);
        _price.setPrice(address(_asset), 75e15);
        // C=1500 (6 decimals) * $0.075 = $112.5; D=100 OHM requires $125.
        assertEq(
            _lens.positionHealthFactor(address(_asset), 1500e6, 100e9),
            0.9e18,
            "Position starts unhealthy"
        );
    }

    function _assertExistingTopUpQuote(uint128 amount_) internal {
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        uint64 positions = _floan.getPositionCount();
        (bool exists, , IFLOANv1.Position memory beforePosition) = LoanPositions.forCore(
            _core,
            address(_asset),
            _borrower
        );
        assertTrue(exists, "Canonical position already exists, including an empty position");
        vm.prank(_borrower);
        (uint256 credit, uint256 collateral) = _collateral.previewDepositCollateral(
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
        assertEq(
            _accountingDigest(address(_asset)),
            beforeQuote,
            "Top-up quote changes no accounting, custody or allowances"
        );
        assertEq(_floan.getPositionCount(), positions, "Quote creates no position");
    }

    function _assertExistingTopUpDeposit(uint128 amount_) internal {
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
        (uint128 credit, uint128 collateral) = _collateral.depositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(credit, amount_, "Actual direct credit equals Q");
        beforePosition.collateral += amount_;
        assertEq(collateral, beforePosition.collateral, "Return adds Q exactly once");
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
        vm.assume(!_isSenderAuthorized(caller_, _borrower));
        _expectDepositExecutionRevert(_unauthorizedOperatorError(caller_), caller_, 1);
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

    // Scenarios: BLCOL-DEPOSIT-P07, BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskHealthUnavailable_whenDeposited()
        public
        givenDebtBearingPosition
    {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            abi.encodeWithSelector(UnexpectedPricingCall.selector)
        );
        vm.expectCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.health.selector),
            uint64(0)
        );
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-A08.
    function test_givenAuthorizationExpired_whenOperatorDeposits_reverts(uint48 elapsed_) public {
        uint256 timestamp = vm.getBlockTimestamp();
        elapsed_ = uint48(bound(elapsed_, 1, type(uint48).max - timestamp - 1));
        uint48 deadline = uint48(timestamp + 1);
        vm.prank(_borrower);
        _approveOperator(_borrower, _recipient, deadline);
        vm.warp(timestamp + 1 + elapsed_);
        bytes32 rollbackState = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, deadline)
        );
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

    // Scenarios: BLCOL-DEPOSIT-P06, BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskSnapshotsUnavailable_whenDeposited()
        public
        givenDebtBearingPosition
    {
        bytes memory failure = abi.encodeWithSelector(UnexpectedPricingCall.selector);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.refreshSnapshot.selector),
            failure
        );
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            failure
        );
        vm.expectCall(address(_risk), bytes(""), uint64(0));
        _assertDirectDeposit(_borrower, 1, 2000e6);
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
        (uint256 quote, ) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        vm.prank(_borrower);
        (uint128 credit, ) = _collateral.depositCollateral(address(_asset), amount_, _borrower);
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
        _expectDepositExecutionRevert(_unauthorizedOperatorError(caller_), caller_, 1);
        assertEq(
            _authorizationDeadline(_borrower, _recipient),
            deadline_,
            "Unrelated caller preserves valid grant"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A07.
    function test_givenCancelledGrant_whenOperatorActs_reverts(address caller_) public {
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != _borrower);
        vm.startPrank(_borrower);
        _approveOperator(_borrower, caller_, type(uint48).max);
        _auth.cancelGrant(caller_);
        vm.stopPrank();
        _expectDepositExecutionRevert(_unauthorizedOperatorError(caller_), caller_, 1);
    }

    // Scenarios: BLCOL-DEPOSIT-A08.
    function test_givenExpiredGrant_whenOperatorActs_reverts(
        uint48 deadline_,
        uint256 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        vm.warp(1);
        vm.prank(_borrower);
        _approveOperator(_borrower, _recipient, deadline_);
        now_ = bound(now_, uint256(deadline_) + 1, type(uint256).max);
        vm.warp(now_);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, deadline_),
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
    function test_givenDebt_whenCollateralAndDebtBoundarySeedsUsed() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenVariableDebtAndCollateral_whenToppedUp(1000e6, 1, 1);
        vm.clearMockedCalls();
        assertTrue(vm.revertToState(checkpoint), "Restore position before maximum top-up seed");
        test_givenVariableDebtAndCollateral_whenToppedUp(
            10_000e6,
            100e9,
            type(uint128).max - 10_000e6
        );
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
        (uint256 quotedCredit, uint256 quotedTotal) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        (uint128 credit, uint128 total) = _collateral.depositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        vm.stopPrank();
        assertEq(credit, amount_, "Exact top-up credit");
        assertEq(total, uint256(prior_) + amount_, "Existing collateral plus actual credit");
        assertEq(quotedCredit, credit, "Top-up credit quote");
        assertEq(quotedTotal, total, "Top-up total quote");
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
    function test_givenVariableDebtAndCollateral_whenToppedUp(
        uint128 prior_,
        uint128 debt_,
        uint128 amount_
    ) public {
        prior_ = uint128(bound(prior_, 1000e6, 10_000e6));
        debt_ = uint128(bound(debt_, 1, 100e9));
        amount_ = uint128(bound(amount_, 1, uint256(type(uint128).max) - prior_));
        _depositAsset(_asset, prior_, _borrower);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), debt_, _borrower, _borrower, type(uint256).max, address(0));
        _blockPricing();
        _assertDirectDeposit(_borrower, amount_, prior_);
        assertEq(
            _lens.getPosition(address(_asset), _borrower).debtOhm,
            debt_,
            "Top-up preserves principal across the compatible range"
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
            address(_auth),
            abi.encodeWithSelector(IOperatorAuth.captureAuthorization.selector),
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector)
        );
        _assertPermissionlessQuote(viewer_, amount_);
    }

    function _assertPermissionlessQuote(address viewer_, uint128 amount_) private {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.recordLogs();
        vm.prank(viewer_);
        (uint256 credit, uint256 total) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(credit, amount_, "quote credits explicit amount");
        assertEq(total, amount_, "quote uses borrower's initially empty position");
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
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
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
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_ExpiredGrant.selector, uint48(10)),
            _recipient,
            7
        );
    }

    // Scenarios: BLCOL-DEPOSIT-A07, BLCOL-DEPOSIT-A13.
    function test_givenRevokedGrant_whenUnrelatedViewerQuotes() public {
        _grantOperator(10);
        vm.prank(_borrower);
        _auth.cancelGrant(_recipient);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
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
        (uint256 credit, uint256 total) = _collateral.previewDepositCollateral(
            address(_asset),
            7,
            _borrower
        );
        assertEq(credit, 7, "explicit deposit amount quoted");
        assertEq(total, 107, "borrower position, not viewer position, receives projected credit");
        assertEq(_accountingDigest(address(_asset)), beforeState, "neither position changes");
    }

    // Scenarios: BLCOL-DEPOSIT-D05, BLCOL-DEPOSIT-P23.
    function test_givenDebtAndBackingPaused_whenToppedUpBeforeWithdrawal()
        public
        givenDebtBearingPosition
    {
        address oracle = _risk.backingOracle();
        MockBackingOracle(oracle).setEnabled(false);
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
        bytes32 afterDeposit = _accountingDigest(address(_asset));
        vm.expectRevert(
            abi.encodeWithSelector(PolicyDependency.PolicyDependency_NotActive.selector, oracle)
        );
        _collateral.previewWithdrawCollateral(address(_asset), 1e6, _borrower, _recipient);
        vm.expectRevert(
            abi.encodeWithSelector(PolicyDependency.PolicyDependency_NotActive.selector, oracle)
        );
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), 1e6, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(_asset)),
            afterDeposit,
            "Withdrawal failure preserves the completed protective deposit"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-D06.
    function test_givenDebtFreeAndBackingPaused_whenDeposited() public givenDebtFreeCollateral {
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        _assertDirectDeposit(_borrower, 1e6, 100e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskPointerUnavailable_whenDeposited()
        public
        givenDebtBearingPosition
    {
        vm.mockCallRevert(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.risk.selector),
            abi.encodeWithSelector(UnexpectedPricingCall.selector)
        );
        vm.expectCall(
            address(_core),
            abi.encodeWithSelector(IBurnerLoansCore.risk.selector),
            uint64(0)
        );
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskDisabled_whenDeposited() public givenDebtBearingPosition {
        _risk.disable("");
        vm.expectCall(address(_risk), bytes(""), uint64(0));
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-P23.
    function test_givenDebtAndRiskInactive_whenDeposited() public givenDebtBearingPosition {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_risk));
        vm.expectCall(address(_risk), bytes(""), uint64(0));
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-D07.
    function test_givenDebtAndBackingInactive_whenDeposited() public givenDebtBearingPosition {
        address oracle = _risk.backingOracle();
        _kernel.executeAction(Actions.DeactivatePolicy, oracle);
        vm.expectCall(oracle, bytes(""), uint64(0));
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-D08.
    function test_givenDebtAndBackingReverting_whenDeposited() public givenDebtBearingPosition {
        address oracle = _risk.backingOracle();
        vm.mockCallRevert(
            oracle,
            abi.encodeWithSignature("backing()"),
            abi.encodeWithSelector(UnexpectedPricingCall.selector)
        );
        vm.expectCall(oracle, bytes(""), uint64(0));
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-D09.
    function test_givenDebtAndZeroBacking_whenDeposited() public givenDebtBearingPosition {
        address oracle = _risk.backingOracle();
        MockBackingOracle(oracle).setBacking(0);
        vm.expectCall(oracle, bytes(""), uint64(0));
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-D10.
    function test_givenDebtAndBothOraclesUnavailable_whenDeposited(
        bool delegated_,
        bool originationsDisabled_,
        bool backingReverts_
    ) public givenDebtBearingPosition {
        address oracle = _risk.backingOracle();
        if (backingReverts_)
            vm.mockCallRevert(
                oracle,
                abi.encodeWithSignature("backing()"),
                abi.encodeWithSelector(UnexpectedPricingCall.selector)
            );
        else MockBackingOracle(oracle).setEnabled(false);
        if (originationsDisabled_) _config.setAssetOriginationsEnabled(address(_asset), false);
        if (delegated_) _grantOperator(type(uint48).max);
        _blockPricing();
        _assertDirectDeposit(delegated_ ? _recipient : _borrower, 1e6, 2000e6);
    }

    // Scenarios: BLCOL-DEPOSIT-D11.
    function test_givenOracleOutage_whenUnauthorizedCallerDeposits_reverts(
        address caller_
    ) public givenDebtBearingPosition {
        vm.assume(caller_ != address(0) && caller_ != _borrower && caller_ != _recipient);
        _grantOperator(type(uint48).max);
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        _blockPricing();
        _assertExistingTopUpQuote(1e6);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidContext.selector),
            caller_,
            1e6
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P24.
    function test_givenDebtAndSnapshotUnavailable_whenHealthQueriedAfterDeposit_reverts()
        public
        givenDebtBearingPosition
    {
        bytes memory failure = abi.encodeWithSelector(UnexpectedPricingCall.selector);
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.snapshot.selector),
            failure
        );
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
        bytes32 afterDeposit = _accountingDigest(address(_asset));
        vm.expectRevert(failure);
        _lens.positionHealthFactor(address(_asset), 2001e6, 100e9);
        assertEq(
            _accountingDigest(address(_asset)),
            afterDeposit,
            "Independent failing health read preserves the completed deposit"
        );
    }

    // Scenarios: BLCOL-DEPOSIT-D10.
    function test_givenOracleOutageBoundarySeeds_whenDeposited() public {
        for (uint8 flags; flags < 8; ++flags) {
            uint256 checkpoint = vm.snapshotState();
            test_givenDebtAndBothOraclesUnavailable_whenDeposited(
                flags & 1 != 0,
                flags & 2 != 0,
                flags & 4 != 0
            );
            vm.clearMockedCalls();
            assertTrue(vm.revertToState(checkpoint), "Restore state between direct outage seeds");
        }
    }

    // Scenarios: BLCOL-DEPOSIT-D12.
    function test_givenOracleOutage_whenZeroCallerDeposits_reverts()
        public
        givenDebtBearingPosition
    {
        MockBackingOracle(_risk.backingOracle()).setEnabled(false);
        _blockPricing();
        _assertExistingTopUpQuote(1e6);
        _expectDepositExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_InvalidIdentity.selector),
            address(0),
            1e6
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P24.
    function test_givenBackingOutage_whenHealthQueriedAfterDeposit_reverts()
        public
        givenDebtBearingPosition
    {
        address oracle = _risk.backingOracle();
        MockBackingOracle(oracle).setEnabled(false);
        _assertHealthReadRevertsAfterDeposit(
            abi.encodeWithSelector(PolicyDependency.PolicyDependency_NotActive.selector, oracle)
        );
    }

    // Scenarios: BLCOL-DEPOSIT-P24.
    function test_givenPriceOutage_whenHealthQueriedAfterDeposit_reverts()
        public
        givenDebtBearingPosition
    {
        bytes memory failure = abi.encodeWithSelector(UnexpectedPricingCall.selector);
        vm.mockCallRevert(address(_price), bytes(""), failure);
        _assertHealthReadRevertsAfterDeposit(failure);
    }

    function _assertHealthReadRevertsAfterDeposit(bytes memory failure_) internal {
        _assertDirectDeposit(_borrower, 1e6, 2000e6);
        bytes32 afterDeposit = _accountingDigest(address(_asset));
        vm.expectRevert(failure_);
        _lens.positionHealthFactor(address(_asset), 2001e6, 100e9);
        assertEq(
            _accountingDigest(address(_asset)),
            afterDeposit,
            "Separate failing health query leaves protective collateral intact"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
