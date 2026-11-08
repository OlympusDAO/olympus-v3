// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20Errors} from "@openzeppelin-5.7.0/interfaces/draft-IERC6093.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";
import {BL_DEBT_POLICY_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {Actions, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Test vectors use fixed expected values and bounds-checked casts. Seed loops exercise real dependencies.
// Setup and expected-revert calls are checked through authoritative state assertions.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)

contract BurnerLoansDebtBorrowTest is BurnerLoansDebtTest {
    error FundingFailed();
    error RiskFailed();

    function setUp() public override {
        super.setUp();
        _depositCollateral(type(uint128).max);
        _inventory.setGlobalDebtCap(type(uint128).max);
        _config.setAssetDebtCap(address(_asset), type(uint128).max);
        _mockRisk(0);
    }

    // Scenarios: BLDEBT-BORROW-N05, BLDEBT-BORROW-A01, BLDEBT-BORROW-L01.
    function test_whenBorrowed_thenPrincipalAndMaturityAreCanonical(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max));
        uint256 recipientBefore = _ohm.balanceOf(_recipient);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            amount_,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        assertEq(quote.resultingDebtOhm, amount_, "Independent quoted principal");
        assertEq(quote.resultingHealthFactor, _HEALTH, "Exact Risk-returned health");
        assertEq(quote.maturity, block.timestamp + 30 days, "First episode term");
        assertEq(_inventory.activePrincipalOhm(), 0, "Preview never draws funding");
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Borrowed(
            _borrower,
            address(_asset),
            _borrower,
            _recipient,
            amount_,
            0,
            address(0),
            0
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            amount_,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        assertEq(result.resultingDebtOhm, amount_, "Actual principal");
        assertEq(result.maturity, quote.maturity, "Preview expiry matches execution");
        assertEq(_position().principalDue, amount_, "FLOAN principal");
        assertEq(
            _position().collateral,
            type(uint128).max,
            "Borrow does not consume deposited collateral"
        );
        assertEq(_inventory.activePrincipalOhm(), amount_, "Inventory reconciled principal");
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            amount_,
            "Market aggregate"
        );
        assertEq(_ohm.balanceOf(_recipient), recipientBefore + amount_, "Principal delivered once");
    }

    // Scenarios: BLDEBT-BORROW-N05.
    function test_whenOneRawOhmBorrowed_thenNoTruncation() public {
        test_whenBorrowed_thenPrincipalAndMaturityAreCanonical(1);
    }

    // Scenarios: BLDEBT-BORROW-N05.
    function test_whenMaximumPrincipalBorrowed_thenNoTruncation() public {
        test_whenBorrowed_thenPrincipalAndMaturityAreCanonical(type(uint128).max);
    }

    // Scenarios: BLDEBT-BORROW-P09, BLDEBT-BORROW-N08, BLDEBT-BORROW-N09, BLDEBT-BORROW-A01, BLDEBT-BORROW-A12.
    function test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody(
        uint256 fee_,
        uint256 maxFee_
    ) public {
        _assertBorrowFeeHandoff(_borrower, fee_, maxFee_);
    }

    // Scenarios: BLDEBT-BORROW-P09, BLDEBT-BORROW-N08, BLDEBT-BORROW-N09, BLDEBT-BORROW-A02, BLDEBT-BORROW-A03, BLDEBT-BORROW-A04, BLDEBT-BORROW-A12.
    function test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody(
        uint256 fee_,
        uint256 maxFee_
    ) public {
        _authorizeOperator(_recipient, type(uint48).max);
        uint256 borrowerBalance = _asset.balanceOf(_borrower);
        _assertBorrowFeeHandoff(_recipient, fee_, maxFee_);
        assertEq(
            _asset.balanceOf(_borrower),
            borrowerBalance,
            "Operator cannot spend borrower wallet"
        );
    }

    function _assertBorrowFeeHandoff(address payer_, uint256 fee_, uint256 maxFee_) internal {
        {
            uint256 existingBalance = _asset.balanceOf(payer_);
            uint256 maximumFee = type(uint256).max - (_asset.totalSupply() - existingBalance);
            fee_ = bound(fee_, 1, maximumFee);
            maxFee_ = bound(maxFee_, fee_, type(uint256).max);
            _mockRisk(fee_);
            _retainFee();
        }
        _asset.burn(payer_, _asset.balanceOf(payer_));
        vm.prank(payer_);
        assertTrue(_asset.approve(address(_core), 0), "Quote needs no payer allowance");
        address viewer = makeAddr("unrelatedQuoteViewer");
        bytes32 beforeQuote = _stateDigest(viewer);
        uint256 liabilities = _depositManager.getOperatorLiabilities(
            IERC20(address(_asset)),
            address(_core)
        );
        IBurnerLoansCore.PriceSnapshot memory snapshot = IBurnerLoansCore.PriceSnapshot(
            1e18,
            1e18,
            1e18
        );
        vm.expectCall(
            address(_risk),
            abi.encodeCall(
                IBurnerLoansRisk.fee,
                (snapshot, _core.marketId(address(_asset)), uint256(100e9), uint16(1), address(0))
            )
        );
        vm.prank(viewer);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            100e9,
            _borrower,
            address(0xcafe),
            maxFee_,
            address(0)
        );
        assertEq(quote.fee, fee_, "Preview forwards arbitrary mock fee");
        assertEq(_stateDigest(viewer), beforeQuote, "Unfunded viewer quote preserves all state");
        _fundFeePayer(payer_, fee_);
        uint256 payerBefore = _asset.balanceOf(payer_);
        uint256 custodyBefore = _asset.balanceOf(address(_payout));
        vm.expectCall(
            address(_payout),
            abi.encodeCall(
                IBurnerLoansPayout.creditFee,
                (address(_asset), uint256(fee_), address(0), uint256(0))
            ),
            1
        );
        vm.expectEmit(address(_debt));
        emit IBurnerLoansDebt.Borrowed(
            payer_,
            address(_asset),
            _borrower,
            address(0xcafe),
            100e9,
            fee_,
            address(0),
            0
        );
        vm.prank(payer_);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            100e9,
            _borrower,
            address(0xcafe),
            maxFee_,
            address(0)
        );
        assertEq(result.fee, fee_, "Risk fee never recalculated or replaced by maxFee");
        assertEq(_asset.balanceOf(payer_), payerBefore - fee_, "Actual caller pays exact fee");
        assertEq(
            _asset.balanceOf(address(_payout)),
            custodyBefore + fee_,
            "Exact receipt at distribution owner"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            liabilities,
            "Fee is not collateral"
        );
        assertEq(
            _ohm.balanceOf(address(0xcafe)),
            100e9,
            "Independent recipient receives principal"
        );
    }

    // Scenarios: BLDEBT-BORROW-P09, BLDEBT-BORROW-N08, BLDEBT-BORROW-N09.
    function test_givenOneUnitFee_whenLimitEqualsFee_thenExactReceipt() public {
        test_givenArbitraryRiskFee_whenBorrowed_thenExactFeeHandedToCustody(1, 1);
    }

    // Scenarios: BLDEBT-BORROW-P09, BLDEBT-BORROW-N09.
    function test_givenMaximumUint128Fee_whenMaximumLimit_thenExactReceipt() public {
        test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody(
            type(uint128).max,
            type(uint256).max
        );
    }

    // Scenarios: BLDEBT-BORROW-P11.
    function test_givenZeroFee_whenBorrowed_thenNoApprovalOrFeeHandoff() public {
        _assertZeroFeeBorrow(_borrower);
    }

    // Scenarios: BLDEBT-BORROW-P11.
    function test_givenZeroFee_whenOperatorBorrows_thenNoApprovalOrFeeHandoff() public {
        _authorizeOperator(_recipient, type(uint48).max);
        _assertZeroFeeBorrow(_recipient);
    }

    function _assertZeroFeeBorrow(address payer_) internal {
        _asset.burn(payer_, _asset.balanceOf(payer_));
        vm.prank(payer_);
        _asset.approve(address(_core), 0);
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditFee.selector),
            abi.encodeWithSelector(RiskFailed.selector)
        );
        vm.mockCallRevert(
            address(_asset),
            abi.encodeWithSelector(_asset.transferFrom.selector),
            abi.encodeWithSelector(FundingFailed.selector)
        );
        vm.prank(payer_);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            1,
            _borrower,
            payer_,
            0,
            address(0)
        );
        assertEq(quote.fee, 0, "Zero fee preview needs neither funds nor allowance");
        vm.prank(payer_);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            1,
            _borrower,
            payer_,
            0,
            address(0)
        );
        assertEq(result.fee, 0, "No fee collection for zero Risk fee");
        assertEq(_asset.balanceOf(payer_), 0, "No collateral funds required");
    }

    // Scenarios: BLDEBT-BORROW-N01.
    function test_whenAmountZero_reverts() public {
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            0,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-I01.
    function test_whenRecipientZero_reverts() public {
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector),
            1,
            address(0),
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-I02.
    function test_whenRecipientIsAction_reverts() public {
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector),
            1,
            address(_debt),
            0,
            _borrower
        );
    }

    function test_whenRecipientIsCore_reverts() public {
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector),
            1,
            address(_core),
            0,
            _borrower
        );
    }

    function test_whenRecipientIsCustody_reverts() public {
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector),
            1,
            address(_payout),
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-N04.
    function test_givenFee_whenMaxFeeTooLow_reverts(uint128 fee_, uint256 maxFee_) public {
        fee_ = uint128(bound(fee_, 1, type(uint128).max));
        maxFee_ = bound(maxFee_, 0, uint256(fee_) - 1);
        _mockRisk(fee_);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_FeeExceedsMax.selector,
                uint256(fee_),
                maxFee_
            ),
            1,
            _recipient,
            maxFee_,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-N02, BLDEBT-BORROW-P03.
    function test_givenGlobalCap_whenRequestExceedsRoom_reverts(
        uint128 room_,
        uint128 amount_
    ) public {
        room_ = uint128(bound(room_, 0, type(uint128).max - 1));
        amount_ = uint128(bound(amount_, uint256(room_) + 1, type(uint128).max));
        _inventory.setGlobalDebtCap(room_);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                uint256(amount_),
                uint256(room_)
            ),
            amount_,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-P03.
    function test_givenBothCapsInsufficient_whenBorrowed_reverts() public {
        _inventory.setGlobalDebtCap(100e9);
        _config.setAssetDebtCap(address(_asset), 80e9);
        // 101 OHM exceeds Inventory's 100 OHM and the asset's 80 OHM room.
        // Inventory capacity is checked first by both the preview and the action.
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                uint256(101e9),
                uint256(100e9)
            ),
            101e9,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-P12.
    function test_givenMintApprovalLimitsCapacity_whenBorrowed_reverts() public {
        MINTRv1 minter = MINTRv1(address(_kernel.getModuleForKeycode(toKeycode("MINTR"))));
        vm.prank(address(_inventory));
        minter.decreaseMintApproval(address(_inventory), type(uint128).max - 50e9);
        // Cap room is still MAX128, but idle=0 and mint approval permits only 50 OHM.
        // Requesting 51 OHM is a funding-capacity error, not a global-cap breach.
        assertEq(_inventory.globalDebtCapOhm(), type(uint128).max, "Global cap remains unchanged");
        assertEq(_inventory.availableCapacity(), 50e9, "Mint approval bounds available funding");
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansInventory.BurnerLoansInventory_InsufficientCapacity.selector,
                uint256(51e9),
                uint256(50e9)
            ),
            51e9,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-N03.
    function test_givenAssetCap_whenRequestExceedsRoom_reverts(
        uint128 room_,
        uint128 amount_
    ) public {
        room_ = uint128(bound(room_, 0, type(uint128).max - 1));
        amount_ = uint128(bound(amount_, uint256(room_) + 1, type(uint128).max));
        _config.setAssetDebtCap(address(_asset), room_);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_AssetDebtCapExceeded.selector,
                address(_asset),
                uint256(amount_),
                uint256(room_)
            ),
            amount_,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-D04, BLDEBT-BORROW-D05, BLDEBT-BORROW-D06, BLDEBT-BORROW-P06.
    function test_givenInventoryUnavailable_whenBorrowed_reverts(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _ohm.mint(address(_inventory), 1); // Sufficient idle OHM must not bypass readiness.
        _setPolicyState(_inventory, active_, enabled_);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_inventory)
            ),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-A11.
    function test_givenOtherOperatorGrant_whenUnrelatedCallerBorrows_reverts(
        address caller_
    ) public {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        _authorizeOperator(_recipient, type(uint48).max);
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            1,
            caller_,
            0,
            caller_
        );
    }

    // Scenarios: BLDEBT-BORROW-P02.
    function test_givenExpiredDebt_whenBorrowed_reverts(uint256 now_) public {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 0, address(0));
        uint48 expiry = _position().maturity;
        now_ = bound(now_, expiry, type(uint256).max);
        vm.warp(now_);
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansDebt.BurnerLoans_PositionExpired.selector, expiry),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-N06.
    function test_givenExistingDebt_whenToppedUp_thenExpiryPreserved(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, type(uint128).max - 1));
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 0, address(0));
        uint48 expiry = _position().maturity;
        vm.warp(block.timestamp + 1);
        bytes32 beforeQuote = _stateDigest(_borrower);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            amount_,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        assertEq(quote.resultingDebtOhm, uint256(amount_) + 1, "Independent live debt quote");
        assertEq(quote.maturity, expiry, "Top-up preview preserves original episode");
        assertEq(_stateDigest(_borrower), beforeQuote, "Top-up preview is read only");
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            amount_,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        assertEq(result.resultingDebtOhm, uint256(amount_) + 1, "Top-up adds principal");
        assertEq(result.maturity, expiry, "Top-up never resets expiry");
        assertEq(_position().principalDue, uint256(amount_) + 1, "Top-up stores live debt exactly");
        assertEq(
            _inventory.activePrincipalOhm(),
            uint256(amount_) + 1,
            "Top-up reconciles funding"
        );
        assertEq(
            _floan.getMarketPrincipalDue(_core.marketId(address(_asset))),
            uint256(amount_) + 1,
            "Top-up reconciles aggregate debt"
        );
        assertEq(
            _ohm.balanceOf(_recipient),
            uint256(amount_) + 1,
            "Both principal deliveries occur once"
        );
    }

    // Scenarios: BLDEBT-BORROW-T04.
    function test_givenFeeDelivered_whenFundingFails_thenEverythingRollsBack(
        bool operator_
    ) public {
        address payer = _authorizeFeePayer(operator_);
        _fundFeePayer(payer, 7);
        _mockRisk(7);
        _retainFee();
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSelector(IBurnerLoansInventory.draw.selector),
            abi.encodeWithSelector(FundingFailed.selector)
        );
        uint256 payerBefore = _asset.balanceOf(payer);
        bytes32 rollbackBefore = _stateDigest(payer);
        vm.expectRevert(FundingFailed.selector);
        vm.prank(payer);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 7, address(0));
        assertEq(_asset.balanceOf(payer), payerBefore, "Fee restored after late funding error");
        assertEq(_asset.balanceOf(address(_payout)), 0, "Custody receipt rolled back");
        assertEq(_position().principalDue, 0, "Debt rolled back");
        assertEq(_inventory.activePrincipalOhm(), 0, "Funding ledger rolled back");
        assertEq(
            _stateDigest(payer),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-T05.
    function test_givenInsufficientFeeAllowance_whenBorrowed_reverts(
        uint128 fee_,
        uint256 allowance_
    ) public {
        fee_ = uint128(bound(fee_, 1, type(uint128).max));
        allowance_ = bound(allowance_, 0, uint256(fee_) - 1);
        _mockRisk(fee_);
        vm.prank(_borrower);
        _asset.approve(address(_core), allowance_);
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_core),
                allowance_,
                uint256(fee_)
            )
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, fee_, address(0));
        assertEq(_asset.allowance(_borrower, address(_core)), allowance_, "Allowance rollback");
        assertEq(_position().principalDue, 0, "No debt after fee failure");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-T06.
    function test_givenMaximumFee_whenPayerUnfunded_reverts() public {
        _mockRisk(type(uint256).max);
        uint256 balance = _asset.balanceOf(_borrower);
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                _borrower,
                balance,
                type(uint256).max
            )
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, type(uint256).max, address(0));
        assertEq(_position().principalDue, 0, "No debt after balance failure");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-T07.
    function test_givenRiskFeeFailure_whenBorrowed_reverts() public {
        vm.mockCallRevert(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encodeWithSelector(RiskFailed.selector)
        );
        _expectBorrowRevert(
            abi.encodeWithSelector(RiskFailed.selector),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-P01.
    function test_givenInsolventOperatorCustody_whenBorrowed_reverts() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSignature(
                "getOperatorAssets(address,address)",
                address(_asset),
                address(_core)
            ),
            abi.encode(uint256(type(uint128).max), uint256(type(uint128).max) - 1)
        );
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_Insolvent.selector,
                address(_asset),
                uint256(type(uint128).max),
                uint256(type(uint128).max) - 1,
                uint256(0)
            ),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-P04.
    function test_givenUnhealthyCurrentPosition_whenBorrowed_reverts(uint256 health_) public {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 0, address(0));
        health_ = bound(health_, 0, 1e18 - 1);
        bytes memory callData = abi.encodeCall(
            IBurnerLoansRisk.validateHealth,
            (
                IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18),
                _core.marketId(address(_asset)),
                uint256(type(uint128).max),
                uint256(1),
                // Explicit ABI flag selects current-position health validation.
                // forge-lint: disable-next-line(boolean-cst)
                false
            )
        );
        vm.mockCallRevert(
            address(_risk),
            callData,
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_UnhealthyPosition.selector, health_)
        );
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyPosition.selector,
                health_
            ),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-P05.
    function test_givenUnhealthyFinalPosition_whenBorrowed_reverts(uint256 health_) public {
        health_ = bound(health_, 0, 1e18 - 1);
        bytes memory callData = abi.encodeCall(
            IBurnerLoansRisk.validateHealth,
            (
                IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18),
                _core.marketId(address(_asset)),
                uint256(type(uint128).max),
                uint256(1),
                // Explicit ABI flag selects resulting-position health validation.
                // forge-lint: disable-next-line(boolean-cst)
                true
            )
        );
        vm.mockCallRevert(
            address(_risk),
            callData,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
                health_
            )
        );
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_UnhealthyFinalPosition.selector,
                health_
            ),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-I04.
    function test_givenNoCollateral_whenBorrowed_reverts() public {
        vm.prank(_borrower);
        _collateral.withdrawCollateral(address(_asset), type(uint128).max, _borrower, _borrower);
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansDebt.BurnerLoans_NoCollateral.selector),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-N07.
    function test_givenFullyRepaidEpisode_whenBorrowed_thenNewTermStartsNow() public {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 0, address(0));
        vm.roll(block.number + 1);
        vm.prank(_recipient);
        _ohm.approve(address(_core), 1);
        vm.prank(_recipient);
        _debt.repay(address(_asset), 1, _borrower);
        vm.warp(vm.getBlockTimestamp() + 10 days);
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            1,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        vm.prank(_borrower);
        IBurnerLoansDebt.BorrowPreview memory result = _debt.borrow(
            address(_asset),
            1,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        assertEq(
            result.maturity,
            block.timestamp + 30 days,
            "New debt episode starts current term"
        );
        assertEq(quote.maturity, result.maturity, "Preview agrees on episode restart");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            1,
            "One active index after reopening"
        );
    }

    // Scenarios: BLDEBT-BORROW-T02.
    function test_whenFeeTransferReturnsFalse_thenDebtRollsBack() public {
        _mockRisk(7);
        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(
                _asset.transferFrom.selector,
                _borrower,
                address(_payout),
                uint256(7)
            ),
            abi.encode(false)
        );
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(_asset))
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 7, address(0));
        assertEq(_position().principalDue, 0, "False transfer creates no debt");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-T03.
    function test_whenFeeReceiptInexact_thenDebtRollsBack() public {
        _mockRisk(7);
        vm.mockCall(
            address(_asset),
            abi.encodeWithSelector(
                _asset.transferFrom.selector,
                _borrower,
                address(_payout),
                uint256(7)
            ),
            abi.encode(true)
        );
        bytes32 rollbackBefore = _stateDigest(_borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Exact.SafeERC20Exact_InexactTransferFrom.selector,
                address(_asset),
                address(_payout),
                uint256(7),
                uint256(0)
            )
        );
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 7, address(0));
        assertEq(_position().principalDue, 0, "Inexact fee creates no debt");
        assertEq(
            _stateDigest(_borrower),
            rollbackBefore,
            "Rejected transaction restores accounting, balances, allowances and indexes"
        );
    }

    // Scenarios: BLDEBT-BORROW-A09.
    function test_givenActionRoleRevoked_whenBorrowed_reverts() public {
        _rolesAdmin.revokeRole(BL_DEBT_POLICY_ROLE, address(_debt));
        _expectBorrowRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BL_DEBT_POLICY_ROLE),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-A10.
    function test_givenActionReportedKernelMismatch_whenBorrowed_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCall(
            address(_debt),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0x1234))
        );
        _assertBorrowWithoutActionKernelRead(operator_);
    }

    // Scenarios: BLDEBT-BORROW-A10.
    function test_givenActionKernelGetterReverts_whenBorrowed_thenGetterIsNotRead(
        bool operator_
    ) public {
        vm.mockCallRevert(address(_debt), abi.encodeWithSignature("kernel()"), hex"deadbeef");
        _assertBorrowWithoutActionKernelRead(operator_);
    }

    function _assertBorrowWithoutActionKernelRead(bool operator_) private {
        address caller = operator_ ? _recipient : _borrower;
        if (operator_) _authorizeOperator(caller, type(uint48).max);
        vm.expectCall(address(_debt), abi.encodeWithSignature("kernel()"), uint64(0));
        _assertBorrowFeeHandoff(caller, 7, 8);
    }

    // Scenarios: BLDEBT-BORROW-A10.
    function test_givenBorrower_whenActionReportedKernelMismatches() public {
        test_givenActionReportedKernelMismatch_whenBorrowed_thenGetterIsNotRead(false);
    }

    // Scenarios: BLDEBT-BORROW-A10.
    function test_givenOperator_whenActionReportedKernelMismatches() public {
        test_givenActionReportedKernelMismatch_whenBorrowed_thenGetterIsNotRead(true);
    }

    // Scenarios: BLDEBT-BORROW-A10.
    function test_givenBorrower_whenActionKernelGetterReverts() public {
        test_givenActionKernelGetterReverts_whenBorrowed_thenGetterIsNotRead(false);
    }

    // Scenarios: BLDEBT-BORROW-A10.
    function test_givenOperator_whenActionKernelGetterReverts() public {
        test_givenActionKernelGetterReverts_whenBorrowed_thenGetterIsNotRead(true);
    }

    // Scenarios: BLDEBT-BORROW-P09, BLDEBT-BORROW-N09.
    function test_givenMaximumFundableUint256Fee_whenBorrowed_thenExactReceipt() public {
        uint256 maximumFee = type(uint256).max - _asset.totalSupply();
        test_givenArbitraryRiskFee_whenOperatorBorrows_thenExactFeeHandedToCustody(
            maximumFee,
            type(uint256).max
        );
    }

    // Scenarios: BLDEBT-BORROW-A02, BLDEBT-BORROW-A03, BLDEBT-BORROW-A04.
    function test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(
        uint48 deadline_,
        uint48 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        now_ = uint48(bound(now_, 1, deadline_));
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _expectBorrowRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_ZeroAmount.selector),
            0,
            _recipient,
            0,
            _recipient
        );
    }

    // Scenarios: BLDEBT-BORROW-A03, BLDEBT-BORROW-A04.
    function test_givenMaximumDeadline_whenAtEquality_thenOperatorAdmitted() public {
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(
            type(uint48).max,
            type(uint48).max
        );
    }

    // Scenarios: BLDEBT-BORROW-A08.
    function test_givenExpiredGrant_whenOperatorActs_reverts(
        uint48 deadline_,
        uint256 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        now_ = bound(now_, uint256(deadline_) + 1, type(uint256).max);
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            0,
            _recipient,
            0,
            _recipient
        );
        assertEq(
            _core.authorizationDeadlines(_borrower, _recipient),
            deadline_,
            "Failed use does not cancel grant"
        );
    }

    // Scenarios: BLDEBT-BORROW-A08.
    function test_givenMaximumTimestamp_whenGrantExpired_reverts() public {
        test_givenExpiredGrant_whenOperatorActs_reverts(type(uint48).max, type(uint256).max);
    }

    // Scenarios: BLDEBT-BORROW-A07.
    function test_givenCancelledGrant_whenOperatorActs_reverts() public {
        vm.startPrank(_borrower);
        _core.setAuthorization(_recipient, type(uint48).max);
        _core.cancelAuthorization(_recipient);
        vm.stopPrank();
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            0,
            _recipient,
            0,
            _recipient
        );
    }

    // Scenarios: BLDEBT-BORROW-A06.
    function test_givenNoGrant_whenUnrelatedCallerActs_reverts(address caller_) public {
        vm.assume(!_core.isSenderAuthorized(caller_, _borrower));
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            0,
            _recipient,
            0,
            caller_
        );
    }

    // Scenarios: BLDEBT-BORROW-A11.
    function test_givenAnotherValidOperator_whenUnrelatedCallerActs_reverts(
        address caller_,
        uint48 deadline_,
        uint48 now_
    ) public {
        vm.assume(caller_ != _borrower && caller_ != _recipient);
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        now_ = uint48(bound(now_, 1, deadline_));
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            0,
            _recipient,
            0,
            caller_
        );
    }

    // Scenarios: BLDEBT-BORROW-A05.
    function test_whenBorrowerZero_thenExplicitError(address caller_) public {
        bytes memory reason = abi.encodeWithSelector(
            IBurnerLoansErrors.BurnerLoans_ZeroAddress.selector
        );
        vm.expectRevert(reason);
        vm.prank(caller_);
        _debt.previewBorrow(address(_asset), 1, address(0), _recipient, 0, address(0));
        vm.expectRevert(reason);
        vm.prank(caller_);
        _debt.borrow(address(_asset), 1, address(0), _recipient, 0, address(0));
    }

    // Scenarios: BLDEBT-BORROW-L06, BLDEBT-BORROW-L07, BLDEBT-BORROW-L08, BLDEBT-BORROW-L09, BLDEBT-BORROW-L10, BLDEBT-BORROW-L11, BLDEBT-BORROW-L12, BLDEBT-BORROW-L13.
    function test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified(
        bool enabled_,
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool validInput_
    ) public {
        _setPolicyState(_debt, false, enabled_);
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_PolicyNotActive.selector,
                address(_debt)
            ),
            validInput_ ? 1 : 0,
            _recipient,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLDEBT-BORROW-L02, BLDEBT-BORROW-L03, BLDEBT-BORROW-L04, BLDEBT-BORROW-L05.
    function test_givenDisabledDebtAction_whenCalled_thenPauseWins(
        bool coreActive_,
        bool coreEnabled_,
        address caller_,
        bool validInput_
    ) public {
        _debt.disable("");
        _setPolicyState(_core, coreActive_, coreEnabled_);
        _expectBorrowRevert(
            abi.encodeWithSelector(IEnabler.NotEnabled.selector),
            validInput_ ? 1 : 0,
            _recipient,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLDEBT-BORROW-D01, BLDEBT-BORROW-D02, BLDEBT-BORROW-D03.
    function test_givenCoreUnavailable_whenCalled_thenDependencyIdentified(
        bool active_,
        bool enabled_,
        address caller_,
        bool validInput_
    ) public {
        vm.assume(!active_ || !enabled_);
        _setPolicyState(_core, active_, enabled_);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_NotActive.selector,
                address(_core)
            ),
            validInput_ ? 1 : 0,
            _recipient,
            type(uint256).max,
            caller_
        );
    }

    // Scenarios: BLDEBT-BORROW-D04.
    function test_givenOriginationsDisabled_whenBorrowed_reverts() public {
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _expectBorrowRevert(
            abi.encodeWithSelector(
                IBurnerLoansCore.BurnerLoansCore_AssetOriginationsDisabled.selector,
                address(_asset)
            ),
            1,
            _recipient,
            0,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-N02.
    function test_whenGlobalCapacityEndpointsRejected_thenExactError() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenGlobalCap_whenRequestExceedsRoom_reverts(0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore initial state for the other boundary");
        test_givenGlobalCap_whenRequestExceedsRoom_reverts(
            type(uint128).max - 1,
            type(uint128).max
        );
    }

    // Scenarios: BLDEBT-BORROW-N03.
    function test_whenAssetCapacityEndpointsRejected_thenExactError() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenAssetCap_whenRequestExceedsRoom_reverts(0, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore initial state for the other boundary");
        test_givenAssetCap_whenRequestExceedsRoom_reverts(type(uint128).max - 1, type(uint128).max);
    }

    // Scenarios: BLDEBT-BORROW-N04.
    function test_whenFeeLimitEndpointsRejected_thenExactError() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenFee_whenMaxFeeTooLow_reverts(1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore initial state for the other boundary");
        test_givenFee_whenMaxFeeTooLow_reverts(type(uint128).max, type(uint128).max - 1);
    }

    // Scenarios: BLDEBT-BORROW-P02.
    function test_whenExpiryEndpointsRejected_thenExactError() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenExpiredDebt_whenBorrowed_reverts(1 + 30 days);
        assertTrue(vm.revertToState(checkpoint), "Restore initial state for the other boundary");
        test_givenExpiredDebt_whenBorrowed_reverts(type(uint256).max);
    }

    // Scenarios: BLDEBT-BORROW-A02, BLDEBT-BORROW-A03, BLDEBT-BORROW-A04.
    function test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays(
        uint48 deadline_,
        uint48 now_
    ) public {
        deadline_ = uint48(bound(deadline_, 1, type(uint48).max));
        uint256 latest = deadline_ < type(uint48).max - 90 days
            ? deadline_
            : type(uint48).max - 90 days;
        now_ = uint48(bound(now_, 1, latest));
        vm.warp(1);
        _authorizeOperator(_recipient, deadline_);
        vm.warp(now_);
        _assertBorrowFeeHandoff(_recipient, 7, 8);
        assertEq(
            _core.authorizationDeadlines(_borrower, _recipient),
            deadline_,
            "Borrow preserves grant"
        );
    }

    // Scenarios: BLDEBT-BORROW-A02, BLDEBT-BORROW-A03, BLDEBT-BORROW-A04, BLDEBT-BORROW-A08.
    function test_whenAuthorizationEndpoints_thenAdmissionIsInclusive() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(2, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore empty principal and fee balances");
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(2, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore for maximum deadline");
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(type(uint48).max, 1);
        assertTrue(vm.revertToState(checkpoint), "Restore grant and time");
        test_givenValidGrant_whenOperatorAdmitted_thenInputValidationReached(
            type(uint48).max,
            type(uint48).max
        );
        assertTrue(vm.revertToState(checkpoint), "Restore for first expired timestamp");
        test_givenExpiredGrant_whenOperatorActs_reverts(1, 2);
        assertTrue(vm.revertToState(checkpoint), "Restore for widened expiration boundary");
        test_givenExpiredGrant_whenOperatorActs_reverts(
            type(uint48).max,
            uint256(type(uint48).max) + 1
        );
    }

    // Scenarios: BLDEBT-BORROW-T06.
    function test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack(
        uint256 fee_,
        uint256 balance_,
        bool operator_
    ) public {
        fee_ = bound(fee_, 1, type(uint256).max);
        address payer = _authorizeFeePayer(operator_);
        _asset.burn(payer, _asset.balanceOf(payer));
        uint256 availableSupply = type(uint256).max - _asset.totalSupply();
        uint256 maximumBalance = fee_ - 1 < availableSupply ? fee_ - 1 : availableSupply;
        balance_ = bound(balance_, 0, maximumBalance);
        _asset.mint(payer, balance_);
        vm.prank(payer);
        _asset.approve(address(_core), fee_);
        _mockRisk(fee_);
        vm.prank(payer);
        assertEq(
            _debt.previewBorrow(address(_asset), 1, _borrower, _recipient, fee_, address(0)).fee,
            fee_,
            "Quote requires no wallet funds"
        );
        bytes32 beforeState = _stateDigest(payer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                payer,
                uint256(balance_),
                uint256(fee_)
            )
        );
        vm.prank(payer);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, fee_, address(0));
        assertEq(
            _stateDigest(payer),
            beforeState,
            "Finite allowance debit and all accounting roll back"
        );
    }

    // Scenarios: BLDEBT-BORROW-T05, BLDEBT-BORROW-T06.
    function test_whenFeeCollectionEndpoints_thenCompleteRollback() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenInsufficientFeeAllowance_whenBorrowed_reverts(1, 0);
        assertTrue(vm.revertToState(checkpoint), "Restore allowance boundary");
        test_givenInsufficientFeeAllowance_whenBorrowed_reverts(
            type(uint128).max,
            type(uint128).max - 1
        );
        assertTrue(vm.revertToState(checkpoint), "Restore borrower balance");
        test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack(1, 0, false);
        assertTrue(vm.revertToState(checkpoint), "Restore operator balance");
        test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack(
            type(uint128).max,
            type(uint128).max - 1,
            true
        );
    }

    // Scenarios: BLDEBT-BORROW-D07, BLDEBT-BORROW-D08, BLDEBT-BORROW-D09.
    function test_givenPayoutUnavailable_whenFeeBearingOperation_reverts(
        bool active_,
        bool enabled_
    ) public {
        vm.assume(!active_ || !enabled_);
        _mockRisk(7);
        _setPolicyState(_payout, active_, enabled_);
        bytes memory reason = abi.encodeWithSelector(
            PolicyDependency.PolicyDependency_NotActive.selector,
            address(_payout)
        );
        _expectBorrowRevert(reason, 1, _recipient, 7, _borrower);
    }

    // Scenarios: BLDEBT-BORROW-D10.
    function test_givenPayoutReportsAnotherKernel_whenFeeBearingOperation_reverts() public {
        _mockRisk(7);
        address reported = makeAddr("foreignPayoutKernel");
        vm.mockCall(address(_payout), abi.encodeWithSignature("kernel()"), abi.encode(reported));
        _expectBorrowRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_payout),
                address(_kernel),
                reported
            ),
            1,
            _recipient,
            7,
            _borrower
        );
    }

    // Scenarios: BLDEBT-BORROW-A02.
    function test_givenBeforeDeadline_whenOperatorBorrowed_thenSuccessfulSettlement() public {
        test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays(2, 1);
    }

    // Scenarios: BLDEBT-BORROW-A03.
    function test_givenAtDeadline_whenOperatorBorrowed_thenSuccessfulSettlement() public {
        test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays(2, 2);
    }

    // Scenarios: BLDEBT-BORROW-A02, BLDEBT-BORROW-A04.
    function test_givenMaximumDeadline_whenOperatorBorrowed_thenSuccessfulSettlement() public {
        test_givenValidOperatorGrant_whenBorrowed_thenActualOperatorPays(type(uint48).max, 1);
    }

    // Scenarios: BLDEBT-BORROW-L06, BLDEBT-BORROW-L07, BLDEBT-BORROW-L08, BLDEBT-BORROW-L09, BLDEBT-BORROW-L10, BLDEBT-BORROW-L11, BLDEBT-BORROW-L12, BLDEBT-BORROW-L13.
    function test_givenInactiveSubject_whenAdmissionAxesSeeded_thenExactError() public {
        for (uint256 enabled; enabled < 2; ++enabled) {
            for (uint256 active; active < 2; ++active) {
                for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                    for (uint256 valid; valid < 2; ++valid) {
                        uint256 checkpoint = vm.snapshotState();
                        test_givenInactiveDebtAction_whenCalled_thenSubjectIdentified(
                            enabled != 0,
                            active != 0,
                            coreEnabled != 0,
                            address(0xbeef),
                            valid != 0
                        );
                        assertTrue(
                            vm.revertToState(checkpoint),
                            "Restore subject and dependency state for each admission seed"
                        );
                    }
                }
            }
        }
    }

    // Scenarios: BLDEBT-BORROW-L02, BLDEBT-BORROW-L03, BLDEBT-BORROW-L04, BLDEBT-BORROW-L05.
    function test_givenPausedSubject_whenAdmissionAxesSeeded_thenExactError() public {
        for (uint256 active; active < 2; ++active) {
            for (uint256 coreEnabled; coreEnabled < 2; ++coreEnabled) {
                for (uint256 valid; valid < 2; ++valid) {
                    uint256 checkpoint = vm.snapshotState();
                    test_givenDisabledDebtAction_whenCalled_thenPauseWins(
                        active != 0,
                        coreEnabled != 0,
                        address(0xbeef),
                        valid != 0
                    );
                    assertTrue(
                        vm.revertToState(checkpoint),
                        "Restore subject and dependency state for each admission seed"
                    );
                }
            }
        }
    }

    // Scenarios: BLDEBT-BORROW-L01.
    function test_givenPolicyReactivated_whenBorrowExecuted_thenSucceeds() public {
        _kernel.executeAction(Actions.DeactivatePolicy, address(_debt));
        _kernel.executeAction(Actions.ActivatePolicy, address(_debt));
        test_whenBorrowed_thenPrincipalAndMaturityAreCanonical(1);
    }

    // Scenarios: BLDEBT-BORROW-L01.
    function test_givenReEnabled_whenBorrowExecuted_thenSucceeds() public {
        _debt.disable("");
        _debt.reEnable();
        test_whenBorrowed_thenPrincipalAndMaturityAreCanonical(1);
    }

    // Scenarios: BLDEBT-BORROW-T05.
    function test_givenInsufficientAllowance_whenEitherPayerBorrows_thenFullFeeDomainRollsBack(
        uint256 fee_,
        uint256 allowance_,
        bool operator_
    ) public {
        address payer = _authorizeFeePayer(operator_);
        uint256 balance = _asset.balanceOf(payer);
        uint256 maximumFee = type(uint256).max - (_asset.totalSupply() - balance);
        fee_ = bound(fee_, 1, maximumFee);
        allowance_ = bound(allowance_, 0, fee_ - 1);
        if (fee_ > balance) _asset.mint(payer, fee_ - balance);
        _mockRisk(fee_);
        vm.prank(payer);
        _asset.approve(address(_core), allowance_);
        vm.prank(payer);
        assertEq(
            _debt.previewBorrow(address(_asset), 1, _borrower, _recipient, fee_, address(0)).fee,
            fee_,
            "Quote does not require fee approval"
        );
        bytes32 state = _stateDigest(payer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(_core),
                allowance_,
                fee_
            )
        );
        vm.prank(payer);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, fee_, address(0));
        assertEq(
            _stateDigest(payer),
            state,
            "Insufficient allowance preserves every ledger and fee bucket"
        );
    }

    // Scenarios: BLDEBT-BORROW-T05.
    function test_givenOperatorAllowanceOneBelowFee_whenBorrowed_reverts() public {
        test_givenInsufficientAllowance_whenEitherPayerBorrows_thenFullFeeDomainRollsBack(
            type(uint128).max,
            type(uint128).max - 1,
            true
        );
    }

    // Scenarios: BLDEBT-BORROW-T06.
    function test_givenMaximumFeeAndZeroBalance_whenOperatorBorrows_reverts() public {
        test_givenInsufficientFeeBalance_whenBorrowed_thenAllowanceAndLedgersRollBack(
            type(uint256).max,
            0,
            true
        );
    }

    // Scenarios: BLDEBT-BORROW-N06.
    function test_givenMaximumTopUp_whenBorrowed_thenNoPrincipalTruncation() public {
        test_givenExistingDebt_whenToppedUp_thenExpiryPreserved(type(uint128).max - 1);
    }

    // Scenarios: BLDEBT-BORROW-N06.
    function test_givenLaterBlockTopUp_whenRepaidInThatBlock_reverts() public {
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 0, address(0));
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(_borrower);
        _debt.borrow(address(_asset), 1, _borrower, _recipient, 0, address(0));
        assertEq(
            _position().lastBorrowBlock,
            block.number,
            "Top-up updates the latest borrow block"
        );
        _expectRepayRevert(
            abi.encodeWithSelector(
                IBurnerLoansDebt.BurnerLoans_SameBlockRepay.selector,
                uint48(block.number)
            ),
            1,
            _borrower,
            _recipient
        );
    }

    // Scenarios: BLDEBT-BORROW-A01, BLDEBT-BORROW-A02, BLDEBT-BORROW-A03, BLDEBT-BORROW-A04, BLDEBT-BORROW-A06, BLDEBT-BORROW-A07, BLDEBT-BORROW-A08, BLDEBT-BORROW-A11, BLDEBT-BORROW-A12.
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
        bytes32 beforeState = _stateDigest(viewer_);
        vm.recordLogs();
        vm.prank(viewer_);
        IBurnerLoansDebt.BorrowPreview memory quote = _debt.previewBorrow(
            address(_asset),
            amount_,
            _borrower,
            _recipient,
            0,
            address(0)
        );
        assertEq(quote.fee, 0, "independent zero-fee expectation");
        assertEq(quote.resultingDebtOhm, amount_, "quote uses specified borrower and principal");
        assertEq(quote.resultingHealthFactor, _HEALTH, "independent Risk health response");
        assertEq(quote.maturity, vm.getBlockTimestamp() + 30 days, "new debt episode maturity");
        assertEq(vm.getRecordedLogs().length, 0, "quote emits no logs");
        assertEq(_stateDigest(viewer_), beforeState, "quote preserves wallets, debt and custody");
    }

    // Scenarios: BLDEBT-BORROW-A06, BLDEBT-BORROW-A13.
    function test_givenNoGrant_whenUnrelatedViewerQuotes() public {
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            7,
            _recipient,
            0,
            _recipient
        );
    }

    // Scenarios: BLDEBT-BORROW-A02, BLDEBT-BORROW-A11, BLDEBT-BORROW-A13.
    function test_givenValidGrant_whenUnrelatedViewerQuotes() public {
        _authorizeOperator(_recipient, 10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        vm.prank(_recipient);
        _debt.borrow(address(_asset), 7, _borrower, _recipient, 0, address(0));
    }

    // Scenarios: BLDEBT-BORROW-A03, BLDEBT-BORROW-A13.
    function test_givenGrantDeadline_whenUnrelatedViewerQuotes() public {
        _authorizeOperator(_recipient, 10);
        vm.warp(10);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        vm.prank(_recipient);
        _debt.borrow(address(_asset), 7, _borrower, _recipient, 0, address(0));
    }

    // Scenarios: BLDEBT-BORROW-A08, BLDEBT-BORROW-A13.
    function test_givenExpiredGrant_whenUnrelatedViewerQuotes() public {
        _authorizeOperator(_recipient, 10);
        vm.warp(11);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            7,
            _recipient,
            0,
            _recipient
        );
    }

    // Scenarios: BLDEBT-BORROW-A07, BLDEBT-BORROW-A13.
    function test_givenRevokedGrant_whenUnrelatedViewerQuotes() public {
        _authorizeOperator(_recipient, 10);
        vm.prank(_borrower);
        _core.cancelAuthorization(_recipient);
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        _expectBorrowExecutionRevert(
            abi.encodeWithSelector(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector),
            7,
            _recipient,
            0,
            _recipient
        );
    }

    // Scenarios: BLDEBT-BORROW-A14.
    function test_whenViewerHasNoPosition_thenSpecifiedBorrowerQuoted() public {
        address viewer = makeAddr("unrelatedQuoteViewer");
        _assertPermissionlessQuote(viewer, 7);
        vm.expectRevert(IBurnerLoansDebt.BurnerLoans_NoCollateral.selector);
        vm.prank(viewer);
        _debt.previewBorrow(address(_asset), 7, viewer, _recipient, 0, address(0));
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant, unsafe-typecast, unused-return)
