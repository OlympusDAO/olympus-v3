// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";
import {ReentrantFeeToken} from "./fixtures/ReentrantFeeToken.sol";

abstract contract BurnerLoansWithdrawCollateralBoundaryTestBase is BurnerLoansTest {
    struct BoundaryScenario {
        uint128 disabledInitialCollateral;
        uint128 disabledWithdrawal;
        uint128 aboveInitialCollateral;
        uint128 aboveWithdrawal;
        uint128 aboveRemainingCollateral;
        uint256 aboveHealth;
        uint128 boundaryInitialCollateral;
        uint128 boundaryWithdrawal;
        uint128 boundaryRemainingCollateral;
        uint256 boundaryHealth;
        uint128 belowInitialCollateral;
        uint128 belowWithdrawal;
        uint128 belowRemainingCollateral;
        uint256 belowHealth;
    }

    function setUp() public virtual override {
        super.setUp();
        _addDefaultUsdsAsset();
    }

    function _boundaryScenario() internal pure virtual returns (BoundaryScenario memory);

    // Condition tree:
    // - Caller: owner
    // - Collateral decimals and fixed values: supplied by the concrete boundary scenario
    // - Position state: active debt with fresh PRICE and healthy remaining collateral
    // - Asset state: disabled after configuration
    // - Expected branch: withdrawal succeeds because asset disable only blocks new exposure
    function test_withdrawCollateral_givenAssetOriginationsDisabledAndActiveDebt_succeeds() public {
        BoundaryScenario memory scenario = _boundaryScenario();
        _depositBoundaryCollateral(scenario.disabledInitialCollateral);
        _setBoundaryPosition(scenario.disabledInitialCollateral);
        _setBoundaryPrices();
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            scenario.disabledWithdrawal,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), scenario.disabledWithdrawal, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, scenario.disabledWithdrawal, "amount out");
        assertEq(remaining, scenario.boundaryRemainingCollateral, "remaining");
        assertEq(health, scenario.boundaryHealth, "health");
    }

    // Condition tree:
    // - Caller: owner
    // - Collateral decimals and fixed values: supplied by the concrete boundary scenario
    // - Position state: 1 OHM debt with OHM at $100 and collateral at $1
    // - Withdrawal amount: leaves one whole collateral token above the minimum healthy amount
    // - Expected branch: preview and write succeed with the fixed rounded health factor
    function test_withdrawCollateral_givenActiveDebtAboveHealthBoundary_succeeds() public {
        BoundaryScenario memory scenario = _boundaryScenario();
        _depositBoundaryCollateral(scenario.aboveInitialCollateral);
        _setBoundaryPosition(scenario.aboveInitialCollateral);
        _setBoundaryPrices();

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            scenario.aboveWithdrawal,
            alice
        );

        assertTrue(preview.executable, "preview executable");
        assertEq(preview.resultingHealthFactor, scenario.aboveHealth, "preview health");

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), scenario.aboveWithdrawal, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(remaining, scenario.aboveRemainingCollateral, "remaining");
        assertEq(health, scenario.aboveHealth, "health");
    }

    // Condition tree:
    // - Caller: owner
    // - Collateral decimals and fixed values: supplied by the concrete boundary scenario
    // - Position state: 1 OHM debt with OHM at $100 and collateral at $1
    // - Withdrawal amount: leaves the minimum healthy collateral amount
    // - Expected branch: preview and write succeed with the fixed rounded health factor
    function test_withdrawCollateral_givenActiveDebtAtMinimumHealthyCollateral_succeeds() public {
        BoundaryScenario memory scenario = _boundaryScenario();
        _depositBoundaryCollateral(scenario.boundaryInitialCollateral);
        _setBoundaryPosition(scenario.boundaryInitialCollateral);
        _setBoundaryPrices();

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            scenario.boundaryWithdrawal,
            alice
        );

        assertTrue(preview.executable, "preview executable");
        assertEq(preview.resultingHealthFactor, scenario.boundaryHealth, "preview health");

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), scenario.boundaryWithdrawal, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(remaining, scenario.boundaryRemainingCollateral, "remaining");
        assertEq(health, scenario.boundaryHealth, "health");
    }

    // Condition tree:
    // - Caller: owner
    // - Collateral decimals and fixed values: supplied by the concrete boundary scenario
    // - Position state: 1 OHM debt with OHM at $100 and collateral at $1
    // - Withdrawal amount: leaves one native collateral unit below the healthy amount
    // - Expected branch: preview is non-executable and write reverts with the fixed health factor
    function test_withdrawCollateral_givenActiveDebtBelowHealthBoundary_reverts() public {
        BoundaryScenario memory scenario = _boundaryScenario();
        _depositBoundaryCollateral(scenario.belowInitialCollateral);
        _setBoundaryPosition(scenario.belowInitialCollateral);
        _setBoundaryPrices();

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            scenario.belowWithdrawal,
            alice
        );

        assertFalse(preview.executable, "preview executable");
        assertEq(preview.resultingHealthFactor, scenario.belowHealth, "preview health");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnhealthyWithdrawal.selector,
                scenario.belowHealth
            )
        );
        burnerLoans.withdrawCollateral(address(usds), scenario.belowWithdrawal, alice, alice);

        assertEq(usds.balanceOf(alice), 0, "alice balance");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            scenario.belowInitialCollateral,
            "position"
        );
    }

    function _depositBoundaryCollateral(uint128 amount_) internal {
        usds.mint(alice, amount_);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), amount_);
        burnerLoans.depositCollateral(address(usds), amount_, alice);
        vm.stopPrank();
    }

    function _setBoundaryPosition(uint128 collateral_) internal {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: collateral_,
                debtOhm: 1e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: uint48(block.number)
            })
        );
        burnerLoans.setActiveDebtForTest(address(usds), 1e9);
    }

    function _setBoundaryPrices() internal {
        price.setTimestamp(uint48(block.timestamp));
        _configurePrice(address(ohm), 100e18);
        _configurePrice(address(usds), 1e18);
    }
}

contract BurnerLoansWithdrawCollateralBoundaryTest is
    BurnerLoansWithdrawCollateralBoundaryTestBase
{
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _boundaryScenario() internal pure override returns (BoundaryScenario memory) {
        // debtValueUsd = 1e9 OHM * $100e18 / 1e9 = $100e18.
        // requiredUsd = ceil($100e18 * 10_000 / 8_500) = $117_647_058_823_529_411_765.
        // At $1e18 per collateral token, minimumCollateral = requiredUsd * 1e18 / $1e18
        // = 117_647_058_823_529_411_765.
        // boundaryRemainingCollateral = minimumCollateral = 117_647_058_823_529_411_765.
        // boundaryInitialCollateral = boundaryRemainingCollateral + 1e18
        //                           = 118_647_058_823_529_411_765.
        // aboveRemainingCollateral = minimumCollateral + 1e18
        //                          = 118_647_058_823_529_411_765.
        // aboveInitialCollateral = aboveRemainingCollateral + 1e18
        //                        = 119_647_058_823_529_411_765.
        // disabledInitialCollateral = minimumCollateral + 5e18
        //                           = 122_647_058_823_529_411_765.
        // belowRemainingCollateral = minimumCollateral - 1
        //                          = 117_647_058_823_529_411_764.
        // belowInitialCollateral = minimumCollateral + 1e18
        //                        = 118_647_058_823_529_411_765, so withdrawing 1e18 + 1
        // leaves belowRemainingCollateral.
        // boundaryHealth = floor(requiredUsd * 1e18 / requiredUsd) = 1e18.
        // aboveHealth = floor($118_647_058_823_529_411_765 * 1e18 / requiredUsd)
        //             = 1_008_499_999_999_999_999.
        // belowHealth = floor($117_647_058_823_529_411_764 * 1e18 / requiredUsd)
        //             = 999_999_999_999_999_999.
        return
            BoundaryScenario({
                disabledInitialCollateral: 122_647_058_823_529_411_765,
                disabledWithdrawal: 5e18,
                aboveInitialCollateral: 119_647_058_823_529_411_765,
                aboveWithdrawal: 1e18,
                aboveRemainingCollateral: 118_647_058_823_529_411_765,
                aboveHealth: 1_008_499_999_999_999_999,
                boundaryInitialCollateral: 118_647_058_823_529_411_765,
                boundaryWithdrawal: 1e18,
                boundaryRemainingCollateral: 117_647_058_823_529_411_765,
                boundaryHealth: 1e18,
                belowInitialCollateral: 118_647_058_823_529_411_765,
                belowWithdrawal: 1e18 + 1,
                belowRemainingCollateral: 117_647_058_823_529_411_764,
                belowHealth: 999_999_999_999_999_999
            });
    }
}

contract BurnerLoansWithdrawCollateralSixDecimalCollateralBoundaryTest is
    BurnerLoansWithdrawCollateralBoundaryTestBase
{
    function _collateralDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _boundaryScenario() internal pure override returns (BoundaryScenario memory) {
        // debtValueUsd = 1e9 OHM * $100e18 / 1e9 = $100e18.
        // requiredUsd = ceil($100e18 * 10_000 / 8_500) = $117_647_058_823_529_411_765.
        // minimumCollateral = ceil(requiredUsd * 1e6 / $1e18) = 117_647_059.
        // boundaryRemainingCollateral = minimumCollateral = 117_647_059.
        // boundaryInitialCollateral = boundaryRemainingCollateral + 1e6 = 118_647_059.
        // aboveRemainingCollateral = minimumCollateral + 1e6 = 118_647_059.
        // aboveInitialCollateral = aboveRemainingCollateral + 1e6 = 119_647_059.
        // disabledInitialCollateral = minimumCollateral + 5e6 = 122_647_059.
        // belowRemainingCollateral = minimumCollateral - 1 = 117_647_058.
        // belowInitialCollateral = minimumCollateral + 1e6 = 118_647_059, so withdrawing 1e6 + 1
        // leaves belowRemainingCollateral.
        // The 6-decimal collateral USD value is collateral * $1e18 / 1e6 = collateral * $1e12.
        // boundaryHealth = floor($117_647_059e12 * 1e18 / requiredUsd)
        //                = 1_000_000_001_499_999_999.
        // aboveHealth = floor($118_647_059e12 * 1e18 / requiredUsd)
        //             = 1_008_500_001_499_999_999.
        // belowHealth = floor($117_647_058e12 * 1e18 / requiredUsd)
        //             = 999_999_992_999_999_999.
        return
            BoundaryScenario({
                disabledInitialCollateral: 122_647_059,
                disabledWithdrawal: 5e6,
                aboveInitialCollateral: 119_647_059,
                aboveWithdrawal: 1e6,
                aboveRemainingCollateral: 118_647_059,
                aboveHealth: 1_008_500_001_499_999_999,
                boundaryInitialCollateral: 118_647_059,
                boundaryWithdrawal: 1e6,
                boundaryRemainingCollateral: 117_647_059,
                boundaryHealth: 1_000_000_001_499_999_999,
                belowInitialCollateral: 118_647_059,
                belowWithdrawal: 1e6 + 1,
                belowRemainingCollateral: 117_647_058,
                belowHealth: 999_999_992_999_999_999
            });
    }
}

contract BurnerLoansWithdrawCollateralTest is BurnerLoansTest {
    address internal operator;
    address internal recipient;

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
        recipient = makeAddr("recipient");
        _addDefaultUsdsAsset();
    }

    modifier givenMockDepositManager() {
        _useMockDepositManager();
        _;
    }

    // Condition tree:
    // - Market schema: incompatible config ID with malformed data
    // - Action: preview and execute withdrawal
    // - Expected branch: both reject the schema before decoding
    function test_givenDifferentConfigId_previewAndWithdrawalRevertBeforeDecoding() public {
        bytes16 incompatibleConfigId = bytes16("Different config");
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
            marketId,
            incompatibleConfigId
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewWithdrawCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);
    }

    // Condition tree:
    // - Market schema: compatible config ID with malformed data length
    // - Action: preview and execute withdrawal
    // - Expected branch: both reject the byte length before decoding
    function test_givenInvalidConfigDataLength_previewAndWithdrawalRevertBeforeDecoding() public {
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            bytes16("Burner Loans v1"),
            hex"01"
        );
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
            marketId,
            1
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewWithdrawCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Position state: debt-free direct-custody collateral
    // - Recipient: owner
    // - Expected branch: withdrawal succeeds without PRICE health dependency
    function test_withdrawCollateral_givenZeroDebtAndStalePrice_succeeds() public {
        _depositForAlice(1_000e6);
        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        vm.warp(10 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            400e6,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), 400e6, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
        assertEq(usds.balanceOf(alice), 400e6, "alice balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            600e6,
            "receipt balance"
        );
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Position state: debt-free direct-custody collateral
    // - PRICE state: collateral price is zero
    // - Action: owner previews and withdraws collateral
    // - Expected branch: withdrawal succeeds without a PRICE health dependency
    function test_withdrawCollateral_givenZeroDebtAndZeroPrice_succeeds() public {
        _depositForAlice(1_000e6);
        price.setPrice(address(usds), 0);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            400e6,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), 400e6, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, 400e6, "amount out");
        assertEq(remaining, 600e6, "remaining");
        assertEq(health, type(uint256).max, "health");
        assertEq(usds.balanceOf(alice), 400e6, "alice balance");
    }

    // Condition tree:
    // - Caller: authorized operator
    // - Position state: debt-free direct-custody collateral
    // - Recipient: explicit third-party recipient
    // - Expected branch: operator withdraws owner collateral to recipient
    function test_withdrawCollateral_givenAuthorizedOperator_routesToRecipient() public {
        _depositForAlice(1_000e6);
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            250e6,
            alice
        );

        vm.prank(operator);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), 250e6, alice, recipient);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, 250e6, "amount out");
        assertEq(remaining, 750e6, "remaining");
        assertEq(health, type(uint256).max, "health");
        assertEq(usds.balanceOf(recipient), 250e6, "recipient balance");
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: no authorization from owner to operator
    // - Parameters: asset is configured, recipient is operator
    // - Expected branch: authorization check reverts before custody
    function test_withdrawCollateral_givenUnauthorizedOperator_reverts() public {
        _depositForAlice(1e6);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, operator);
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner authorization expired before call
    // - Parameters: asset is configured, recipient is operator
    // - Expected branch: authorization check reverts before custody
    function test_withdrawCollateral_givenExpiredAuthorization_reverts() public {
        _depositForAlice(1e6);
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1));
        vm.warp(block.timestamp + 2);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, operator);
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Recipient: zero address
    // - Parameters: asset is configured, amount is positive
    // - Expected branch: recipient validation reverts before custody
    function test_withdrawCollateral_givenZeroRecipient_reverts() public {
        _depositForAlice(1e6);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, address(0));
    }

    // Condition tree:
    // - Caller: owner
    // - Amount: zero
    // - Parameters: asset is configured, recipient is owner
    // - Expected branch: amount validation reverts before custody
    function test_withdrawCollateral_givenZeroAmount_reverts() public {
        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.withdrawCollateral(address(usds), 0, alice, alice);
    }

    // Condition tree:
    // - FLOAN markets: multiple markets for the facility and token pair
    // - Actions: preview and execute a collateral withdrawal
    // - Expected branch: both actions use the first market
    function test_givenMultipleMarkets_previewAndWithdrawalUseFirstMarket() public {
        _depositForAlice(100e6);
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            40e6,
            alice
        );
        vm.prank(alice);
        burnerLoans.withdrawCollateral(address(usds), 40e6, alice, alice);

        assertEq(preview.remainingDepositedCollateral, 60e6, "preview first-market collateral");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            60e6,
            "first-market position"
        );
        assertEq(
            floan.getPositionIdsForMarketAndBorrower(firstMarketId, alice).length,
            1,
            "first-market position count"
        );
        assertEq(
            floan.getPositionIdsForMarketAndBorrower(secondMarketId, alice).length,
            0,
            "second-market position count"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Asset: not configured in BurnerLoans
    // - Parameters: positive amount, recipient is owner
    // - Expected branch: asset configuration validation reverts
    function test_withdrawCollateral_givenUnsupportedAsset_reverts() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNSUP", USDS_DECIMALS);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(unsupported)
            )
        );
        burnerLoans.withdrawCollateral(address(unsupported), 1e6, alice, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - Position state: debt-free collateral
    // - BurnerLoans state: globally disabled after asset configuration
    // - Expected branch: withdrawal reverts because global disable blocks state changes
    function test_withdrawCollateral_givenGlobalDisabledAndZeroDebt_reverts() public {
        _depositForAlice(1e6);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewWithdrawCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            1e6,
            "position"
        );
    }

    // Condition tree:
    // - Custody implementation: real DepositManager disabled after collateral is deposited
    // - Position state: owner has debt-free direct-custody collateral
    // - Action: owner previews and then attempts withdrawal
    // - Expected branch: preview and write reject unavailable custody without debiting collateral
    function test_withdrawCollateral_givenDepositManagerDisabled_reverts() public {
        _depositForAlice(1_000e6);
        vm.prank(admin);
        _disableDepositManager();

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.previewWithdrawCollateral(address(usds), 400e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.withdrawCollateral(address(usds), 400e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            1_000e6,
            "position"
        );
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            1_000e6,
            "liabilities"
        );
        assertEq(usds.balanceOf(alice), 0, "alice balance");
    }

    // Condition tree:
    // - Caller: owner
    // - Position state: debt-free collateral
    // - Asset state: disabled after configuration
    // - Expected branch: cleanup withdrawal succeeds despite asset new-risk disable
    function test_withdrawCollateral_givenAssetOriginationsDisabledAndZeroDebt_succeeds() public {
        _depositForAlice(1e6);
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            1e6,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), 1e6, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, 1e6, "amount out");
        assertEq(remaining, 0, "remaining");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: configured period disabled after deposit
    // - Parameters: asset remains configured in BurnerLoans
    // - Expected branch: withdrawal still succeeds because period disable only blocks new deposits
    function test_withdrawCollateral_givenDepositManagerPeriodDisabled_succeeds() public {
        _depositForAlice(1e6);
        depositManager.disableAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            1e6,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), 1e6, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, 1e6, "amount out");
        assertEq(remaining, 0, "remaining");
        assertEq(health, type(uint256).max, "health");
        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            0,
            "liabilities"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Position state: active debt
    // - PRICE state: stale timestamp for active debt health check
    // - Expected branch: stale PRICE reverts before collateral is debited
    function test_withdrawCollateral_givenActiveDebtAndStalePrice_reverts() public {
        _depositForAlice(1_200e6);
        _setActiveDebtPosition(1_200e6, 1e9);
        _setFreshPrices(100e18, 1e18);
        vm.warp(10 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            1_200e6,
            "position"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Position state: active debt with healthy remaining collateral
    // - PRICE state: configured collateral price is zero
    // - Expected branch: preview and write reject the unavailable health-check price
    function test_withdrawCollateral_givenActiveDebtAndZeroPrice_reverts() public {
        _depositForAlice(120e6);
        _setActiveDebtPosition(120e6, 1e9);
        _setFreshPrices(100e18, 0);

        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.previewWithdrawCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPRICEv2.PRICE_PriceZero.selector, address(usds)));
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            120e6,
            "position"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Position state: debt-free collateral
    // - Withdrawal amount: greater than credited collateral
    // - Expected branch: debit validation reverts before custody
    function test_withdrawCollateral_givenAmountExceedsCollateral_reverts(
        uint128 collateral_,
        uint128 excess_
    ) public {
        collateral_ = uint128(bound(collateral_, 1, 1_000_000e6));
        excess_ = uint128(bound(excess_, 1, 1_000_000e6));
        _depositForAlice(collateral_);
        uint128 amount = collateral_ + excess_;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InsufficientCollateral.selector,
                amount,
                collateral_
            )
        );
        burnerLoans.withdrawCollateral(address(usds), amount, alice, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - Custody path: vault-backed DepositManager custody
    // - Withdrawal amount: fuzzed positive amount worth less than one vault share after yield
    // - Expected branch: preview marks withdrawal non-executable and write reverts before debiting accounting
    function test_givenAmountBelowOneVaultShare_reverts(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 1_000e6));
        uint128 depositedAmount = 1_000_000e6;
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _depositVaultForAlice(vaultAsset, depositedAmount);
        vaultAsset.mint(address(vault), amount_ * depositedAmount);

        assertEq(vault.convertToShares(amount_), 0, "withdrawal shares");

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            amount_,
            alice
        );

        assertEq(preview.returnAmount, 0, "preview amount");
        assertFalse(preview.executable, "preview executable");

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroCollateralWithdrawal.selector);
        burnerLoans.withdrawCollateral(address(vaultAsset), amount_, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            depositedAmount,
            "position"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            depositedAmount,
            "liabilities"
        );
        assertEq(vaultAsset.balanceOf(alice), 0, "alice balance");
        _assertFloanPositionMatchesBurnerLoans(address(vaultAsset), alice);
    }

    // Condition tree:
    // - Custody implementation: real DepositManager with a synchronous ERC4626 vault
    // - Position state: owner has credited vault-backed collateral
    // - Action: owner withdraws a positive partial amount
    // - Expected branch: underlying, vault assets, receipt liabilities, and BurnerLoans accounting remain consistent
    function test_withdrawCollateral_givenVaultCustody_succeeds() public {
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _depositVaultForAlice(vaultAsset, 1_000e6);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            400e6,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(vaultAsset), 400e6, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, 400e6, "amount out");
        assertEq(remaining, 600e6, "remaining");
        assertEq(health, type(uint256).max, "health");
        assertEq(vaultAsset.balanceOf(alice), 400e6, "alice balance");
        assertEq(vault.totalAssets(), 600e6, "vault assets");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            600e6,
            "liabilities"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Custody path: real DepositManager ERC4626 vault
    // - Vault state: fuzzed yield accrues after the caller reads the withdrawal preview
    // - Expected branch: write returns the current custody amount, which can differ from the stale quote
    function test_withdrawCollateral_givenVaultYieldAfterPreview_returnsCurrentActualAmount(
        uint256 yield_
    ) public {
        uint128 withdrawalAmount = 1e6;
        yield_ = bound(yield_, 1, 1_000_000e6);
        uint128 depositedAmount = uint128(yield_ * withdrawalAmount + 1);
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _depositVaultForAlice(vaultAsset, depositedAmount);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            withdrawalAmount,
            alice
        );
        vaultAsset.mint(address(vault), yield_);
        uint256 expectedAmountOut = vault.previewRedeem(vault.convertToShares(withdrawalAmount));

        assertTrue(preview.returnAmount != expectedAmountOut, "quote changes after yield");

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(vaultAsset), withdrawalAmount, alice, alice);

        assertEq(tokenOut, address(vaultAsset), "token out");
        assertEq(amountOut, expectedAmountOut, "amount out");
        assertEq(remaining, depositedAmount - withdrawalAmount, "remaining");
        assertEq(health, type(uint256).max, "health");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            depositedAmount - withdrawalAmount,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            depositedAmount - withdrawalAmount,
            "deposit manager liabilities"
        );
    }

    // Condition tree:
    // - Custody implementation: real DepositManager with an ERC4626 vault that rejects synchronous redeem
    // - Position state: owner has credited collateral from a successful deposit
    // - Action: owner attempts withdrawal
    // - Expected branch: unsupported warm-up/asynchronous vault reverts and BurnerLoans state rolls back
    function test_withdrawCollateral_givenWarmupVault_reverts() public {
        (MockERC20 vaultAsset, WarmupVault vault) = _addWarmupVaultAsset();
        _depositVaultForAlice(vaultAsset, 1_000e6);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            400e6,
            alice
        );
        assertTrue(preview.executable, "local preview executable");

        vm.prank(alice);
        vm.expectRevert(WarmupVault.WarmupVault_RedeemUnsupported.selector);
        burnerLoans.withdrawCollateral(address(vaultAsset), 400e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            1_000e6,
            "position"
        );
        assertEq(vaultAsset.balanceOf(alice), 0, "alice balance");
        assertEq(vault.totalAssets(), 1_000e6, "vault assets");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            1_000e6,
            "liabilities"
        );
    }

    // Condition tree:
    // - Custody implementation: real DepositManager with a synchronous ERC4626 vault
    // - Vault state: loss makes operator assets lower than receipt-token liabilities
    // - Action: owner previews and attempts a positive withdrawal
    // - Expected branch: local preview is executable, but write rolls back on DepositManager solvency
    function test_withdrawCollateral_givenVaultLoss_reverts() public {
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _depositVaultForAlice(vaultAsset, 1_000e6);
        vaultAsset.burn(address(vault), 500e6);

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(vaultAsset),
            100e6,
            alice
        );

        assertEq(preview.returnAmount, 100e6, "preview amount");
        assertTrue(preview.executable, "local preview executable");

        vm.prank(alice);
        vm.expectPartialRevert(IDepositManager.DepositManager_Insolvent.selector);
        burnerLoans.withdrawCollateral(address(vaultAsset), 100e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            1_000e6,
            "position"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            1_000e6,
            "liabilities"
        );
        assertEq(vault.totalAssets(), 500e6, "vault assets");
        assertEq(vaultAsset.balanceOf(alice), 0, "alice balance");
    }

    // Condition tree:
    // - Caller: owner
    // - Position state: debt-free collateral
    // - Withdrawal amount: fuzzed around zero through full collateral
    // - Expected branch: valid positive amounts reduce credited collateral exactly
    function test_withdrawCollateral_givenZeroThroughFullCollateral_succeeds(
        uint128 amount_
    ) public {
        _depositForAlice(1_000e6);
        amount_ = uint128(bound(amount_, 1, 1_000e6));

        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            address(usds),
            amount_,
            alice
        );

        vm.prank(alice);
        (address tokenOut, uint256 amountOut, uint256 remaining, uint256 health) = burnerLoans
            .withdrawCollateral(address(usds), amount_, alice, alice);

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining, health);
        assertEq(amountOut, amount_, "amount out");
        assertEq(remaining, 1_000e6 - amount_, "remaining");
        assertEq(health, type(uint256).max, "health");
    }

    // Condition tree:
    // - Custody path: real DepositManager direct custody with a receipt-token liability
    // - Withdrawal sequence: two distinct fuzzed partial withdrawals, then the position's full reported remainder
    // - Position state: debt-free, so stale PRICE cannot gate the cleanup withdrawal
    // - Expected branch: each preview matches its write and the final reported remainder clears all custody accounting
    function test_withdrawCollateral_givenMultiplePartialWithdrawals_clearsFullReportedRemainder(
        uint128 depositedAmount_,
        uint128 firstWithdrawal_,
        uint128 secondWithdrawal_
    ) public {
        depositedAmount_ = uint128(bound(depositedAmount_, 4, 1_000_000e6));
        firstWithdrawal_ = uint128(bound(firstWithdrawal_, 1, depositedAmount_ / 3));
        secondWithdrawal_ = uint128(
            bound(secondWithdrawal_, firstWithdrawal_ + 1, depositedAmount_ - firstWithdrawal_ - 1)
        );
        _depositForAlice(depositedAmount_);

        _withdrawAndAssertPreview(firstWithdrawal_);
        _withdrawAndAssertPreview(secondWithdrawal_);

        uint128 reportedRemainder = uint128(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral
        );
        uint256 finalRemaining = _withdrawAndAssertPreview(reportedRemainder);
        assertEq(finalRemaining, 0, "final remaining");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            0,
            "deposit manager liabilities"
        );
        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            0,
            "receipt balance"
        );
        assertEq(usds.balanceOf(address(depositManager)), 0, "deposit manager balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
        assertEq(usds.balanceOf(alice), depositedAmount_, "alice balance");
    }

    // Condition tree:
    // - Custody path: real DepositManager ERC4626 vault with fuzzed yield after deposit and partial withdrawals
    // - Withdrawal sequence: two fuzzed partial withdrawals, a second yield accrual, then the full reported remainder
    // - Position state: debt-free, so vault-share rounding cannot leave credited collateral dust
    // - Expected branch: each preview matches its write and the final reported remainder clears all liabilities
    function test_withdrawCollateral_givenVaultYieldAndMultiplePartialWithdrawals_clearsFullReportedRemainder(
        uint128 depositedAmount_,
        uint256 firstYield_,
        uint128 firstWithdrawal_,
        uint128 secondWithdrawal_,
        uint256 secondYield_
    ) public {
        depositedAmount_ = uint128(bound(depositedAmount_, 6e6, 1_000_000e6));
        firstYield_ = bound(firstYield_, 1, depositedAmount_ - 1);
        secondYield_ = bound(secondYield_, 1, depositedAmount_ - 1);
        firstWithdrawal_ = uint128(bound(firstWithdrawal_, 1e6, depositedAmount_ / 3));
        secondWithdrawal_ = uint128(
            bound(secondWithdrawal_, 1e6, (depositedAmount_ - firstWithdrawal_) / 2)
        );
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _depositVaultForAlice(vaultAsset, depositedAmount_);
        vaultAsset.mint(address(vault), firstYield_);

        _withdrawAndAssertPreview(address(vaultAsset), firstWithdrawal_);
        _withdrawAndAssertPreview(address(vaultAsset), secondWithdrawal_);
        vaultAsset.mint(address(vault), secondYield_);

        uint128 reportedRemainder = uint128(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral
        );
        uint256 finalRemaining = _withdrawAndAssertPreview(address(vaultAsset), reportedRemainder);
        assertEq(finalRemaining, 0, "final remaining");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            0,
            "deposit manager liabilities"
        );
        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            0,
            "receipt balance"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "burner loans residual");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: injected removal of the configured period after deposit
    // - Parameters: asset remains configured in BurnerLoans
    // - Expected branch: custody support validation reverts and position remains unchanged
    function test_withdrawCollateral_givenInjectedUnsupportedPeriod_reverts()
        public
        givenMockDepositManager
    {
        _depositForAlice(1e6);
        mockDepositManager.removeAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(mockDepositManager)
            )
        );
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            1e6,
            "position"
        );
        assertEq(usds.balanceOf(alice), 0, "alice balance");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: injected withdrawal failure after BurnerLoans debits position
    // - Parameters: valid debt-free withdrawal
    // - Expected branch: transaction rollback restores position and leaves balances unchanged
    function test_withdrawCollateral_givenInjectedDepositManagerFailure_reverts()
        public
        givenMockDepositManager
    {
        _depositForAlice(1e6);
        mockDepositManager.setWithdrawReverts(true);

        vm.prank(alice);
        vm.expectRevert(MockDepositManager.MockDepositManager_TransferFailed.selector);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            1e6,
            "position"
        );
        assertEq(usds.balanceOf(alice), 0, "alice balance");
    }

    // Condition tree:
    // - Token behavior: transfer returns false without reverting
    // - Position state: borrower has sufficient debt-free collateral
    // - Expected branch: TransferHelper reverts and both FLOAN and custody accounting roll back
    function test_givenTransferReturnsFalse_revertsWithoutRemovingCollateral() public {
        uint128 amount = 1_000e6;
        uint128 withdrawal = 400e6;
        _depositForAlice(amount);
        vm.mockCall(
            address(usds),
            abi.encodeWithSelector(ERC20.transfer.selector, alice, withdrawal),
            abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FAILED"));
        burnerLoans.withdrawCollateral(address(usds), withdrawal, alice, alice);

        _assertPositionAndActiveDebt(address(usds), alice, amount, 0, 0);
        assertEq(usds.balanceOf(alice), 0, "alice balance");
        assertEq(usds.balanceOf(address(depositManager)), amount, "custody balance");
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            amount,
            "custody liabilities"
        );
    }

    // Condition tree:
    // - Token behavior: DepositManager's outgoing transfer attempts a nested withdrawal
    // - Authorization: callback token is authorized for the same borrower
    // - Expected branch: the nested call hits the shared guard and the outer withdrawal applies once
    function test_givenCallbackToken_cannotReenterWithdrawal() public {
        ReentrantFeeToken callbackToken = new ReentrantFeeToken();
        _configurePrice(address(callbackToken), 1e18);
        _configureDepositManagerAsset(address(callbackToken));
        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(callbackToken),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );

        uint128 amount = 1_000e18;
        uint128 withdrawal = 400e18;
        callbackToken.mint(alice, amount);
        vm.prank(alice);
        callbackToken.approve(address(burnerLoans), amount);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(callbackToken), amount, alice);
        vm.prank(alice);
        burnerLoans.setAuthorization(address(callbackToken), uint48(block.timestamp + 1 days));
        callbackToken.setCallbackFrom(
            address(depositManager),
            address(burnerLoans),
            abi.encodeCall(
                burnerLoans.withdrawCollateral,
                (address(callbackToken), uint128(1), alice, alice)
            )
        );

        vm.prank(alice);
        (, uint256 amountOut, uint256 remaining, ) = burnerLoans.withdrawCollateral(
            address(callbackToken),
            withdrawal,
            alice,
            alice
        );

        assertFalse(callbackToken.callbackSucceeded(), "callback succeeded");
        assertEq(
            callbackToken.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "callback revert"
        );
        assertEq(amountOut, withdrawal, "withdrawn once");
        assertEq(remaining, amount - withdrawal, "remaining collateral");
        _assertPositionAndActiveDebt(address(callbackToken), alice, amount - withdrawal, 0, 0);
        assertEq(callbackToken.balanceOf(alice), withdrawal, "recipient balance");
        assertEq(
            callbackToken.balanceOf(address(depositManager)),
            amount - withdrawal,
            "custody balance"
        );
    }

    function _withdrawAndAssertPreview(uint128 amount_) internal returns (uint256 remaining_) {
        return _withdrawAndAssertPreview(address(usds), amount_);
    }

    function _withdrawAndAssertPreview(
        address asset_,
        uint128 amount_
    ) internal returns (uint256 remaining_) {
        IBurnerLoans.WithdrawPreview memory preview = burnerLoans.previewWithdrawCollateral(
            asset_,
            amount_,
            alice
        );

        vm.prank(alice);
        uint256 amountOut;
        uint256 health;
        address tokenOut;
        (tokenOut, amountOut, remaining_, health) = burnerLoans.withdrawCollateral(
            asset_,
            amount_,
            alice,
            alice
        );

        _assertWithdrawalMatchesPreview(preview, tokenOut, amountOut, remaining_, health);
        _assertFloanPositionMatchesBurnerLoans(asset_, alice);
    }

    function _depositForAlice(uint128 amount_) internal {
        usds.mint(alice, amount_);
        vm.prank(alice);
        usds.approve(address(burnerLoans), amount_);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(usds), amount_, alice);
    }

    function _depositVaultForAlice(MockERC20 asset_, uint128 amount_) internal {
        asset_.mint(alice, amount_);
        vm.prank(alice);
        asset_.approve(address(burnerLoans), amount_);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(asset_), amount_, alice);
    }

    function _setActiveDebtPosition(uint256 collateral_, uint256 debtOhm_) internal {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: collateral_,
                debtOhm: debtOhm_,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: uint48(block.number)
            })
        );
        burnerLoans.setActiveDebtForTest(address(usds), debtOhm_);
    }

    function _setFreshPrices(uint256 ohmPrice_, uint256 collateralPrice_) internal {
        price.setTimestamp(uint48(block.timestamp));
        _configurePrice(address(ohm), ohmPrice_);
        _configurePrice(address(usds), collateralPrice_);
    }

    function _addVaultAsset() internal returns (MockERC20 vaultAsset, MockERC4626 vault) {
        vaultAsset = new MockERC20("Vault USDS", "vUSDS", USDS_DECIMALS);
        vault = new MockERC4626(ERC20(address(vaultAsset)), "Vault", "VAULT");
        _configureVaultAsset(vaultAsset, IERC4626(address(vault)));
    }

    function _addWarmupVaultAsset() internal returns (MockERC20 vaultAsset, WarmupVault vault) {
        vaultAsset = new MockERC20("Warmup USDE", "sUSDE", USDS_DECIMALS);
        vault = new WarmupVault(ERC20(address(vaultAsset)));
        _configureVaultAsset(vaultAsset, IERC4626(address(vault)));
    }

    function _configureVaultAsset(MockERC20 vaultAsset_, IERC4626 vault_) internal {
        _configurePrice(address(vaultAsset_), 1e18);
        depositManager.addAsset(IERC20(address(vaultAsset_)), vault_, type(uint256).max, 0);
        depositManager.addAssetPeriod(
            IERC20(address(vaultAsset_)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(vaultAsset_),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }
}

contract WarmupVault is MockERC4626 {
    error WarmupVault_RedeemUnsupported();

    constructor(ERC20 underlying_) MockERC4626(underlying_, "Warmup Vault", "WARMUP") {}

    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert WarmupVault_RedeemUnsupported();
    }
}
