// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockOlympusBackingOracle} from "src/test/mocks/MockOlympusBackingOracle.sol";
import {BurnerLoansSeizeIntegrationTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeIntegrationTestBase.sol";
import {SeizeRedemptionFeeVault} from "src/test/policies/BurnerLoansSeize/fixtures/SeizeRedemptionFeeVault.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// Nonzero role recipients are constrained with vm.assume.
// forge-lint: disable-start(literal-instead-of-constant, missing-zero-check, reentrancy-no-eth, unsafe-typecast, unused-return)

contract BurnerLoansSeizeIntegrationTest is BurnerLoansSeizeIntegrationTestBase {
    // Scenarios: BLLIQ-SEIZE-N01, BLLIQ-SEIZE-P18.
    function test_givenSubUnitReward_whenUnderlyingSeized_thenZeroReward() public {
        _configure(address(_asset), 100);
        _open(address(_asset), _borrower, 99, 1);
        // 99 raw assets * 100/10000 = 0.99, floored to 0. Backing ceil(1 OHM-wei / 1000)=1 asset-wei.
        _expire();
        _assertSeizure(address(_asset), address(_asset), 0, 99);
    }

    // Scenarios: BLLIQ-SEIZE-N03, BLLIQ-SEIZE-P18.
    function test_givenSubUnitPercentageRemainder_whenSeized_thenIntegerConservation() public {
        _configure(address(_asset), 9999);
        _open(address(_asset), _borrower, 2, 1);
        // floor(2 * 9999/10000)=1; Treasury=2-1=1. Never separately round the remainder fraction.
        _expire();
        _assertSeizure(address(_asset), address(_asset), 1, 1);
    }

    // Scenarios: BLLIQ-SEIZE-P13, BLLIQ-SEIZE-P14.
    function test_givenProtocolKeeper_whenSeized_thenNoReward(
        bool heart_,
        bool overlap_,
        address keeper_,
        address viewCaller_
    ) public {
        vm.assume(keeper_ != address(0));
        _keeper = keeper_;
        _configure(address(_asset), 9999);
        _open(address(_asset), _borrower, 2, 1);
        _rolesAdmin.grantRole(heart_ ? HEART_ROLE : BURNER_LOANS_SEIZER_ROLE, _keeper);
        if (overlap_)
            _rolesAdmin.grantRole(heart_ ? BURNER_LOANS_SEIZER_ROLE : HEART_ROLE, _keeper);
        _expire();
        vm.prank(viewCaller_);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            address(_asset),
            _single(_borrower)
        );
        assertEq(
            quote.keeperReward,
            0,
            "Explicit actor roles determine quote independently of view caller"
        );
        _assertSeizure(address(_asset), address(_asset), 0, 2);
    }

    // Scenarios: BLLIQ-SEIZE-I04, BLLIQ-SEIZE-P19.
    function test_givenAllDebtExpiredAndRealPriceStale_whenSeized_thenSnapshotStillRequired()
        public
    {
        _open(address(_asset), _borrower, 2000e6, 100e9);
        vm.warp(block.timestamp + 30 days);
        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        bytes32 beforeState = _stateDigestFor(address(_asset), _keeper);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        _liquidation.previewSeizeFor(_keeper, address(_asset), borrowers);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(_keeper);
        _liquidation.seize(address(_asset), borrowers);
        assertEq(
            _stateDigestFor(address(_asset), _keeper),
            beforeState,
            "Real price failure restores every ledger and custody component"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9,
            "Price rejection leaves funding ledger unchanged"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2000e6,
            "No redemption without snapshot"
        );
    }

    // Scenarios: BLLIQ-SEIZE-P13, BLLIQ-SEIZE-P14.
    function test_givenEachProtocolRole_whenSeized_thenNoReward() public {
        uint256 checkpoint = vm.snapshotState();
        test_givenProtocolKeeper_whenSeized_thenNoReward(true, false, address(0x101), address(0));
        assertTrue(vm.revertToState(checkpoint), "Restore for seizer-only role");
        test_givenProtocolKeeper_whenSeized_thenNoReward(false, false, address(0x102), _borrower);
        assertTrue(vm.revertToState(checkpoint), "Restore for overlapping roles");
        test_givenProtocolKeeper_whenSeized_thenNoReward(
            false,
            true,
            address(0x103),
            address(this)
        );
    }

    // Scenarios: BLLIQ-SEIZE-R02, BLLIQ-SEIZE-P18.
    function test_givenRedemptionFeeConsumesSurplus_whenSeized_thenKeeperCannotTakeBacking()
        public
    {
        MockERC20 token = new MockERC20("Fee collateral", "FC", 6);
        SeizeRedemptionFeeVault vault = new SeizeRedemptionFeeVault(OZERC20(address(token)));
        _admitVault(
            address(token),
            address(vault),
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6),
            false
        );
        _open(address(token), _borrower, 2000e6, 100e9);
        // Vault yield keeps total operator custody solvent even after the redemption fee.
        // Two assets per share makes the 2000e6 withdrawal convert to exactly 1000e6 shares.
        token.mint(address(vault), 2000e6);
        vault.chargeRedemptionFee();
        MockOlympusBackingOracle(_risk.backingOracle()).setBacking(15e18);
        // 2000e6 collateral redeems to 1800e6 after 10% fee.
        // Required backing = 100e9 OHM * $15 * 12500/10000 / 1e9 = $1875 -> 1875e6 assets.
        // Actual output is below backing, so reward = 0 and Treasury receives all 1800e6.
        _expire();
        _assertSeizure(address(token), address(token), 0, 1800e6);
    }

    // Scenarios: BLLIQ-SEIZE-R01.
    function test_givenZeroCollateralDebt_whenSeized_thenDebtDefaultsWithoutRedemption() public {
        // Historical/injected debt state: use Core module authority to create zero-collateral debt.
        // Public borrowing does not originate unsecured loans; module/Inventory accounting stays real.
        vm.startPrank(address(_core));
        uint64 id = _floan.createPosition(_core.marketId(address(_asset)), _borrower);
        _floan.increaseDebt(id, 100e9, 0, uint48(block.timestamp + 30 days));
        _inventory.draw(_borrower, 100e9);
        vm.stopPrank();
        _expire();
        _assertSeizure(address(_asset), address(_asset), 0, 0);
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            0,
            "No custody transfer for zero credit"
        );
    }

    // Scenarios: BLLIQ-SEIZE-R04.
    function test_givenDefaultedPosition_whenBorrowerReopens_thenPositionIdReused() public {
        _open(address(_asset), _borrower, 2000e6, 100e9);
        (, uint64 beforeId, ) = LoanPositions.forCore(_core, address(_asset), _borrower);
        _expire();
        _assertSeizure(address(_asset), address(_asset), 20e6, 1980e6);
        _open(address(_asset), _borrower, 2000e6, 100e9);
        (, uint64 afterId, IFLOANv1.Position memory reopened) = LoanPositions.forCore(
            _core,
            address(_asset),
            _borrower
        );
        assertEq(afterId, beforeId, "Reopening reuses canonical position ID");
        assertEq(reopened.principalDue, 100e9, "Reopened episode has new debt");
        assertEq(reopened.collateral, 2000e6, "Reopened episode has new collateral");
        assertEq(_inventory.activePrincipalOhm(), 100e9, "New funding exposure recorded");
        assertEq(
            _floan.getActiveBorrowerCount(_core.marketId(address(_asset))),
            1,
            "Borrower reinserted once"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_asset))),
            100e9,
            "Historical default remains recorded once"
        );
    }

    // Scenarios: BLLIQ-SEIZE-R05.
    function test_givenOriginationsDisabled_whenSeized_thenDefaultStillSucceeds() public {
        _open(address(_asset), _borrower, 2000e6, 100e9);
        _config.setAssetOriginationsEnabled(address(_asset), false);
        _expire();
        _assertSeizure(address(_asset), address(_asset), 20e6, 1980e6);
    }

    // Scenarios: BLLIQ-SEIZE-P18.
    function test_givenRealUnhealthyUnexpiredDebt_whenSeized_thenHealthAndBalancesMatch() public {
        _config.setAssetRiskConfig(
            address(_asset),
            IBurnerLoansRisk.AssetRiskConfigInput(10000, 10000, 100, 30 days, 90 days, 1000e6)
        );
        _open(address(_asset), _borrower, 2000e6, 100e9);
        _price.setPrice(address(_ohm), 25e18);
        // Collateral value = 2000e6 * $1e18 / 1e6 = 2000e18 USD.
        // Required collateral = 100e9 OHM * $25e18 / 1e9 at 100% LTV = 2500e18 USD.
        // Health = 2000e18 * 1e18 / 2500e18 = 0.8e18, below one WAD before expiry.
        assertEq(
            _risk.health(
                _risk.snapshot(address(_asset)),
                _core.marketId(address(_asset)),
                2000e6,
                100e9
            ),
            0.8e18,
            "Independent real health calculation"
        );
        assertLt(
            block.timestamp,
            _lens.getPosition(address(_asset), _borrower).maturity,
            "Fixture has not matured"
        );
        // Reward = floor(2000e6 * 100/10000) = 20e6; Treasury receives 1980e6.
        _assertSeizure(address(_asset), address(_asset), 20e6, 1980e6);
    }
}

// forge-lint: disable-end(literal-instead-of-constant, missing-zero-check, reentrancy-no-eth, unsafe-typecast, unused-return)
