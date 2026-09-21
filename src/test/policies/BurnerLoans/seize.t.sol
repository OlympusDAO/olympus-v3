// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";
import {BurnerLoansSeizureTestBase} from "./fixtures/BurnerLoansSeizureTestBase.sol";
import {MockERC7540ExternalShareToken, MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault} from "src/test/policies/DepositManager/fixtures/MockERC7575Vault.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// Scenario-specific contracts and fixtures have no cross-file consumers.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop,multi-contract-file)

contract BurnerLoansSeizeTest is BurnerLoansSeizureTestBase {
    // keeper reward = 2,000e18 seized collateral * 1% = 20e18 share units because this
    // external share token has the same decimals and one-to-one conversion as the asset.
    uint256 internal constant _SAME_DECIMAL_KEEPER_REWARD = 20e18;

    struct ShareSeizureState {
        MockERC20 asset;
        MockERC4626 vault;
        uint128 collateral;
        uint256 vaultSupplyBefore;
        uint256 vaultAssetsBefore;
        uint256 totalSharesOut;
        uint256 expectedKeeperShares;
        uint256 expectedTreasuryShares;
        uint256 operatorSharesBefore;
        uint256 keeperSharesBefore;
        uint256 treasurySharesBefore;
        uint256 keeperAssetsBefore;
        uint256 treasuryAssetsBefore;
    }

    // seize
    // given unhealthy position
    //  when seize is called
    //   then it closes position and routes collateral
    function test_givenUnhealthyPosition_seizeClosesPositionAndRoutesCollateral() public {
        _makeUnhealthy(alice);
        uint256 mintApprovalBefore = mintr.mintApproval(address(inventory));
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        assertEq(preview.seizedDebtOhm, 100e9, "preview seized debt");
        assertEq(preview.seizedCollateral, 2_000e18, "preview seized collateral");
        assertEq(preview.keeperReward, 20e18, "preview one percent reward");
        assertEq(preview.collateralToTreasury, 1_980e18, "preview treasury collateral");
        assertTrue(preview.executable, "preview executable");
        uint256 keeperBefore = usds.balanceOf(keeper);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));

        vm.expectEmit(false, false, false, true, address(inventory));
        emit IBurnerLoansInventory.PrincipalDefaulted(100e9);
        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(reward, preview.keeperReward, "reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "treasury amount");
        assertEq(usds.balanceOf(keeper), keeperBefore + reward, "keeper balance");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBefore + treasuryAmount,
            "treasury balance"
        );
        assertEq(position.debtOhm, 0, "debt cleared");
        assertEq(position.depositedCollateral, 0, "collateral cleared");
        assertEq(position.maturity, 0, "maturity cleared");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "global active debt");
        assertEq(burnerLoans.assetActiveDebtOhm(address(usds)), 0, "asset active debt");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            100e9,
            "market defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active borrowers");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "no residual collateral");
        assertEq(
            mintr.mintApproval(address(inventory)),
            mintApprovalBefore + 100e9,
            "seizure restores defaulted capacity"
        );
        assertEq(inventory.activePrincipalOhm(), 0, "Burner Loans Inventory active principal");
        assertEq(
            _assetDepositCapUtilization(IERC20(address(usds))),
            0,
            "seizure releases deposit-cap utilization"
        );
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    function test_givenUnhealthyPosition_whenCallerIsArbitrary(address caller_) public {
        vm.assume(caller_ != protocolSeizer);
        vm.assume(caller_ != address(burnerLoans));
        _makeUnhealthy(alice);

        vm.prank(caller_);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.prank(caller_);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );

        assertEq(reward, preview.keeperReward, "permissionless reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "permissionless Treasury amount");
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "debt cleared");
    }

    function test_givenVaultYield_whenWithdrawAsShares_routesShareToken() public {
        (MockERC20 asset, MockERC4626 vault) = _addVaultAssetForTest();
        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral + 100e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();

        asset.mint(address(vault), collateral);
        _configurePrice(address(ohm), 20e18);
        price.setTimestamp(uint48(block.timestamp));
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(asset), true);
        _makeVaultAsynchronous(vault);

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(asset),
            _single(alice)
        );

        // 2,000 assets convert to 1,000 shares after the vault doubles in asset value.
        // The 1% keeper reward is 20 underlying units, mapped proportionally to 10 shares.
        assertEq(preview.tokenOut, address(vault), "preview token");
        assertEq(preview.seizedCollateral, collateral, "underlying seized");
        assertEq(preview.keeperReward, 10e18, "keeper shares");
        assertEq(preview.collateralToTreasury, 990e18, "Treasury shares");

        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 treasuryAmount) = burnerLoans.seize(
            address(asset),
            _single(alice)
        );

        assertEq(keeperReward, preview.keeperReward, "keeper output");
        assertEq(tokenOut, address(vault), "seizure token");
        assertEq(treasuryAmount, preview.collateralToTreasury, "Treasury output");
        assertEq(vault.balanceOf(keeper), keeperReward, "keeper share balance");
        assertEq(vault.balanceOf(address(trsry)), treasuryAmount, "Treasury share balance");
        assertEq(asset.balanceOf(keeper), 0, "keeper underlying balance");
        assertEq(burnerLoans.getPosition(address(asset), alice).debtOhm, 0, "debt defaulted");
    }

    function test_givenExternalShareTokenWithSameDecimals_whenSeizing_routesExternalToken() public {
        (
            MockERC20 asset,
            MockERC7575Vault externalVault,
            IERC20 shareToken
        ) = _addSameDecimalExternalShareAssetForTest();
        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral + 100e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();
        _configurePrice(address(ohm), 20e18);
        price.setTimestamp(uint48(block.timestamp));

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(asset),
            _single(alice)
        );
        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 treasuryAmount) = burnerLoans.seize(
            address(asset),
            _single(alice)
        );

        assertNotEq(address(shareToken), address(externalVault), "external token should differ");
        assertEq(asset.decimals(), shareToken.decimals(), "token decimals should match");
        assertEq(preview.tokenOut, address(shareToken), "preview external token");
        assertEq(tokenOut, address(shareToken), "external token out");
        assertEq(keeperReward, _SAME_DECIMAL_KEEPER_REWARD, "keeper external shares");
        assertEq(treasuryAmount, 1_980e18, "Treasury external shares");
        assertEq(shareToken.balanceOf(keeper), keeperReward, "keeper share balance");
        assertEq(shareToken.balanceOf(address(trsry)), treasuryAmount, "Treasury share balance");
        assertEq(burnerLoans.getPosition(address(asset), alice).debtOhm, 0, "debt defaulted");
    }

    function test_givenExternalShareTokenWithDifferentDecimals_whenSeizing_routesExternalToken()
        public
    {
        (
            MockERC20 asset,
            MockERC7540ExternalShareVault vault,
            MockERC7540ExternalShareToken shareToken
        ) = _addAsyncExternalShareAssetForTest();
        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral + 100e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();

        _configurePrice(address(ohm), 20e18);
        price.setTimestamp(uint48(block.timestamp));

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(asset),
            _single(alice)
        );

        // seized = 2,000e18 assets / 1e12 = 2,000e6 raw shares.
        // keeper reward = 1% of underlying collateral = 20e18, represented by 20e6 shares.
        assertNotEq(address(shareToken), address(vault), "external token should differ");
        assertEq(asset.decimals(), 18, "underlying decimals");
        assertEq(shareToken.decimals(), 6, "share decimals");
        assertEq(preview.tokenOut, address(shareToken), "preview external token");
        assertEq(preview.seizedCollateral, collateral, "underlying seized");
        assertEq(preview.keeperReward, 20e6, "keeper raw shares");
        assertEq(preview.collateralToTreasury, 1_980e6, "Treasury raw shares");

        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 treasuryAmount) = burnerLoans.seize(
            address(asset),
            _single(alice)
        );

        assertEq(tokenOut, address(shareToken), "external token out");
        assertEq(keeperReward, preview.keeperReward, "keeper output");
        assertEq(treasuryAmount, preview.collateralToTreasury, "Treasury output");
        assertEq(shareToken.balanceOf(keeper), keeperReward, "keeper external shares");
        assertEq(shareToken.balanceOf(address(trsry)), treasuryAmount, "Treasury external shares");
        assertEq(shareToken.balanceOf(address(burnerLoans)), 0, "policy share residual");
        assertEq(vault.convertToAssets(keeperReward), 20e18, "underlying reward value");
        assertEq(burnerLoans.getPosition(address(asset), alice).debtOhm, 0, "debt defaulted");
    }

    function test_givenVaultYield_givenWithdrawAsShares_whenKeeperSeizes(
        uint128 yieldSeed_
    ) public {
        uint256 yieldAmount = bound(yieldSeed_, 1, 20_000e18);
        ShareSeizureState memory state = _createShareSeizureState(yieldAmount);

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(state.asset),
            _single(alice)
        );
        assertEq(preview.tokenOut, address(state.vault), "preview token");
        assertEq(preview.seizedCollateral, state.collateral, "preview seized assets");
        assertEq(preview.keeperReward, state.expectedKeeperShares, "preview keeper shares");
        assertEq(
            preview.collateralToTreasury,
            state.expectedTreasuryShares,
            "preview Treasury shares"
        );

        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 treasuryAmount) = burnerLoans.seize(
            address(state.asset),
            _single(alice)
        );

        assertEq(tokenOut, address(state.vault), "token out");
        assertEq(keeperReward, state.expectedKeeperShares, "keeper shares out");
        assertEq(treasuryAmount, state.expectedTreasuryShares, "Treasury shares out");
        assertEq(
            state.vault.balanceOf(keeper) - state.keeperSharesBefore,
            state.expectedKeeperShares,
            "keeper share delta"
        );
        assertEq(
            state.vault.balanceOf(address(trsry)) - state.treasurySharesBefore,
            state.expectedTreasuryShares,
            "Treasury share delta"
        );
        assertEq(
            state.asset.balanceOf(keeper),
            state.keeperAssetsBefore,
            "keeper underlying unchanged"
        );
        assertEq(
            state.asset.balanceOf(address(trsry)),
            state.treasuryAssetsBefore,
            "Treasury underlying unchanged"
        );
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            IERC20(address(state.asset)),
            address(burnerLoans)
        );
        assertEq(
            state.operatorSharesBefore - operatorSharesAfter,
            state.totalSharesOut,
            "custody share debit"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(state.asset)),
                address(burnerLoans)
            ),
            0,
            "liabilities cleared"
        );
        assertEq(
            _assetDepositCapUtilization(IERC20(address(state.asset))),
            0,
            "share seizure releases deposit-cap utilization"
        );
        assertEq(state.vault.totalSupply(), state.vaultSupplyBefore, "vault supply unchanged");
        assertEq(state.vault.totalAssets(), state.vaultAssetsBefore, "vault assets unchanged");
        assertEq(state.vault.balanceOf(address(burnerLoans)), 0, "Burner Loans share residual");
        assertEq(state.asset.balanceOf(address(burnerLoans)), 0, "Burner Loans asset residual");
        assertEq(burnerLoans.getPosition(address(state.asset), alice).debtOhm, 0, "debt defaulted");
        assertEq(
            burnerLoans.getPosition(address(state.asset), alice).depositedCollateral,
            0,
            "position collateral cleared"
        );
        _assertFloanPositionMatchesBurnerLoans(address(state.asset), alice);
    }

    function _createShareSeizureState(
        uint256 yieldAmount_
    ) internal returns (ShareSeizureState memory state) {
        (state.asset, state.vault) = _addVaultAssetForTest();
        state.collateral = 2_000e18;
        state.asset.mint(alice, state.collateral + 100e18);
        vm.startPrank(alice);
        state.asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(state.asset), state.collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(state.asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(state.asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();

        state.asset.mint(address(state.vault), yieldAmount_);
        _configurePrice(address(ohm), 20e18);
        price.setTimestamp(uint48(block.timestamp));
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(state.asset), true);
        _makeVaultAsynchronous(state.vault);

        state.vaultSupplyBefore = state.vault.totalSupply();
        state.vaultAssetsBefore = state.vault.totalAssets();
        // collateral (asset decimals) * vaultSupplyBefore (share decimals)
        // / vaultAssetsBefore (asset decimals) = totalSharesOut (share decimals), rounded down.
        state.totalSharesOut =
            (uint256(state.collateral) * state.vaultSupplyBefore) /
            state.vaultAssetsBefore;
        // Default configuration pays 1% of seized collateral in underlying-denominated reward.
        // The reward's proportional share allocation is rounded down in favor of Treasury.
        uint256 rewardAssets = uint256(state.collateral) / 100;
        // mulDiv preserves floor division while preventing phantom overflow in the intermediate
        // totalSharesOut * rewardAssets product.
        state.expectedKeeperShares = FullMath.mulDiv(
            state.totalSharesOut,
            rewardAssets,
            state.collateral
        );
        state.expectedTreasuryShares = state.totalSharesOut - state.expectedKeeperShares;
        (state.operatorSharesBefore, ) = depositManager.getOperatorAssets(
            IERC20(address(state.asset)),
            address(burnerLoans)
        );
        state.keeperSharesBefore = state.vault.balanceOf(keeper);
        state.treasurySharesBefore = state.vault.balanceOf(address(trsry));
        state.keeperAssetsBefore = state.asset.balanceOf(keeper);
        state.treasuryAssetsBefore = state.asset.balanceOf(address(trsry));
    }

    function test_givenUnderlyingRedemptionFee_seizureDoesNotPayRewardFromRequiredBacking() public {
        MockERC20 asset = new MockERC20("Fee Collateral", "fCOLL", _collateralDecimals());
        MutableRedeemFeeVault vault = new MutableRedeemFeeVault(ERC20(address(asset)));
        _configurePrice(address(asset), 1e18);
        vm.startPrank(admin);
        depositManager.addAsset(
            IERC20(address(asset)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(
            IERC20(address(asset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        vm.stopPrank();

        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(asset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig(),
            false
        );

        uint128 collateral = 2_000e18;
        asset.mint(alice, collateral + 100e18);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(asset), collateral, alice);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(asset),
            100e9,
            alice
        );
        burnerLoans.borrow(address(asset), 100e9, alice, alice, borrowPreview.fee);
        vm.stopPrank();

        vault.setRedeemFeeBps(1_000);
        backingOracle.setBacking(15e18);
        _configurePrice(address(ohm), 20e18);
        price.setTimestamp(uint48(block.timestamp));

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(asset),
            _single(alice)
        );

        // 2,000e18 collateral redeems to 1,800e18 after the 10% fee.
        // Required backing = 100e9 OHM * $15e18 * 12,500 / (1e9 * 10,000)
        //                  = 1,875e18 collateral at $1e18 per collateral token.
        // The actual output has no surplus over required backing, so the keeper receives zero.
        assertEq(preview.keeperReward, 0, "keeper cannot receive required backing");
        assertEq(preview.collateralToTreasury, 1_800e18, "Treasury receives actual output");

        vm.prank(keeper);
        (, uint256 keeperReward, uint256 treasuryAmount) = burnerLoans.seize(
            address(asset),
            _single(alice)
        );
        assertEq(keeperReward, 0, "executed keeper reward");
        assertEq(treasuryAmount, 1_800e18, "executed Treasury output");
    }

    function test_givenWithdrawAsShares_givenSeizureRoundsToZero_defaultsDebtAndLeavesYield()
        public
    {
        (MockERC20 asset, MockERC4626 vault) = _addVaultAssetForTest();
        asset.mint(alice, 1);
        vm.startPrank(alice);
        asset.approve(address(burnerLoans), 1);
        burnerLoans.depositCollateral(address(asset), 1, alice);
        vm.stopPrank();
        burnerLoans.setPositionForTest(
            address(asset),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 1,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0
            })
        );
        asset.mint(address(vault), 1e18);
        _configurePrice(address(ohm), 20e18);
        price.setTimestamp(uint48(block.timestamp));
        vm.prank(admin);
        burnerLoansConfig.setAssetWithdrawAsShares(address(asset), true);
        _makeVaultAsynchronous(vault);

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(asset),
            _single(alice)
        );
        assertEq(preview.tokenOut, address(vault), "preview token");
        assertEq(preview.keeperReward, 0, "zero keeper output");
        assertEq(preview.collateralToTreasury, 0, "zero Treasury output");
        assertTrue(preview.executable, "zero-output seizure executable");

        vm.prank(keeper);
        (address tokenOut, uint256 keeperReward, uint256 treasuryAmount) = burnerLoans.seize(
            address(asset),
            _single(alice)
        );

        assertEq(tokenOut, address(vault), "output token");
        assertEq(keeperReward, 0, "keeper output");
        assertEq(treasuryAmount, 0, "Treasury output");
        assertEq(burnerLoans.getPosition(address(asset), alice).debtOhm, 0, "debt defaulted");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt cleared");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(asset))),
            100e9,
            "principal defaulted"
        );
        assertEq(vault.balanceOf(address(depositManager)), 1, "share dust retained");
        assertEq(vault.balanceOf(keeper), 0, "keeper receives no shares");
        assertEq(vault.balanceOf(address(trsry)), 0, "Treasury receives no shares");
        assertEq(
            _assetDepositCapUtilization(IERC20(address(asset))),
            0,
            "zero-output seizure releases deposit-cap utilization"
        );
        _assertFloanPositionMatchesBurnerLoans(address(asset), alice);

        IBurnerLoans.ClaimYieldPreview memory yieldPreview = burnerLoans.previewClaimYield(
            address(asset)
        );
        assertGt(yieldPreview.requestedAssetAmount, 0, "dust reported as yield");
        assertEq(yieldPreview.amountOut, 1, "dust share claimable");
        burnerLoans.claimYield(address(asset));
        assertEq(vault.balanceOf(address(trsry)), 1, "dust share claimed to Treasury");
    }

    // seize
    // given two seizable borrowers
    //  when seize is called
    //   then it closes homogeneous batch
    function test_givenTwoSeizableBorrowers_seizeClosesHomogeneousBatch() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 200e9);
        _configurePrice(address(ohm), 20e18);

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _pair(alice, bob));

        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            300e9,
            "defaulted principal"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 0, "active set");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
        _assertFloanPositionMatchesBurnerLoans(address(usds), bob);
    }

    // setGlobalDebtCap
    // given defaulted principal
    //  when setGlobalDebtCap is called
    //   then it reconciles capacity against active principal only
    function test_givenDefaultedPrincipal_setGlobalDebtCap_reconcilesActiveCapacity() public {
        _makeUnhealthy(alice);
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        vm.startPrank(admin);
        burnerLoansConfig.setGlobalDebtCap(50e9);
        assertEq(mintr.mintApproval(address(inventory)), 50e9, "default releases capacity");

        burnerLoansConfig.setGlobalDebtCap(200e9);
        vm.stopPrank();

        assertEq(
            mintr.mintApproval(address(inventory)),
            200e9,
            "capacity depends only on active principal"
        );
    }

    // seize
    // given matured healthy position
    //  when seize is called
    //   then it succeeds
    function test_givenMaturedHealthyPosition_seizeSucceeds() public {
        _makeMatured(alice);

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "debt cleared");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "collateral cleared"
        );
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // seize
    // given zero collateral debt position
    //  when seize is called
    //   then it closes position
    function test_givenZeroCollateralDebtPosition_seizeClosesPosition() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: 0,
                debtOhm: 100e9,
                maturity: uint48(block.timestamp + 30 days),
                lastBorrowBlock: 0
            })
        );

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );

        assertEq(reward, 0, "reward");
        assertEq(treasuryAmount, 0, "treasury amount");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }

    // seize
    // given protocol seizer
    //  when seize is called
    //   then it routes all collateral to treasury
    function test_givenProtocolSeizer_seizeRoutesAllCollateralToTreasury() public {
        _makeUnhealthy(alice);
        uint256 treasuryBefore = usds.balanceOf(address(trsry));
        vm.prank(protocolSeizer);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        assertEq(preview.keeperReward, 0, "preview protocol reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "preview treasury collateral");

        vm.prank(protocolSeizer);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );

        assertEq(reward, preview.keeperReward, "protocol reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "all collateral to treasury");
        assertEq(usds.balanceOf(address(trsry)), treasuryBefore + 2_000e18, "treasury balance");
    }

    // seize
    // given invalid borrower in batch
    //  when seize is called
    //   then it reverts atomically
    function test_givenInvalidBorrowerInBatch_seizeRevertsAtomically() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);
        uint256 activeDebtBefore = burnerLoans.totalActiveDebtOhm();
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PositionNotSeizable.selector,
            bob
        );

        vm.prank(keeper);
        vm.expectRevert(error);
        burnerLoans.previewSeize(address(usds), _pair(alice, bob));

        vm.prank(keeper);
        vm.expectRevert(error);
        burnerLoans.seize(address(usds), _pair(alice, bob));

        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "alice debt");
        assertEq(burnerLoans.getPosition(address(usds), bob).debtOhm, 100e9, "bob debt");
        assertEq(burnerLoans.totalActiveDebtOhm(), activeDebtBefore, "active debt unchanged");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            0,
            "defaulted principal unchanged"
        );
    }

    // seize
    // given deposit manager withdraw failure
    //  when seize is called
    //   then it rolls back all state
    function test_givenDepositManagerWithdrawFailure_seizeRollsBackAllState() public {
        _makeUnhealthy(alice);
        IDepositManager.WithdrawParams memory params = IDepositManager.WithdrawParams({
            asset: IERC20(address(usds)),
            depositPeriod: 1,
            depositor: address(burnerLoans),
            recipient: address(burnerLoans),
            amount: 2_000e18,
            isWrapped: false
        });
        bytes memory failure = bytes("forced withdraw failure");
        // The literal explicitly selects underlying output in the mocked V1.1 overload.
        // forge-lint: disable-start(boolean-cst)
        vm.mockCallRevert(
            address(depositManager),
            abi.encodeCall(IDepositManagerV1_1.withdraw, (params, false)),
            failure
        );
        // forge-lint: disable-end(boolean-cst)

        vm.prank(keeper);
        vm.expectRevert(failure);
        burnerLoans.seize(address(usds), _single(alice));

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 100e9, "debt rolled back");
        assertEq(position.depositedCollateral, 2_000e18, "collateral rolled back");
        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt rolled back");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "active set rolled back");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            0,
            "defaulted principal rolled back"
        );
    }

    // seize
    // given collateral transfers report success without moving the withdrawn collateral
    //  when seize is called
    //   then the residual-balance guard reverts and rolls back all seizure state
    function test_givenCollateralTransferLeavesResidualBalance_seizeRevertsAndRollsBack() public {
        _makeUnhealthy(alice);
        uint256 burnerLoansBalanceBefore = usds.balanceOf(address(burnerLoans));
        uint256 keeperBalanceBefore = usds.balanceOf(keeper);
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));
        vm.mockCall(
            address(usds),
            abi.encodeCall(ERC20.transfer, (keeper, 20e18)),
            abi.encode(true)
        );
        vm.mockCall(
            address(usds),
            abi.encodeCall(ERC20.transfer, (address(trsry), 1_980e18)),
            abi.encode(true)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_ResidualCollateralBalance.selector,
                address(usds),
                2_000e18
            )
        );
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 100e9, "position debt rolled back");
        assertEq(position.depositedCollateral, 2_000e18, "position collateral rolled back");
        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt rolled back");
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "active set rolled back");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            0,
            "defaulted principal rolled back"
        );
        assertEq(
            usds.balanceOf(address(burnerLoans)),
            burnerLoansBalanceBefore,
            "Burner Loans balance rolled back"
        );
        assertEq(usds.balanceOf(keeper), keeperBalanceBefore, "keeper balance rolled back");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore,
            "treasury balance rolled back"
        );
    }

    // seize
    // given a position has been seized and its episode state cleared
    //  when the borrower deposits collateral and borrows again
    //   then Burner Loans reuses the same FLOAN position ID
    //   then the reused position receives a fresh maturity
    function test_givenSeizedPosition_borrowerCanStartNewEpisodeWithSamePositionId() public {
        _makeUnhealthy(alice);
        uint48 firstMaturity = burnerLoans.getPosition(address(usds), alice).maturity;
        uint32 marketId = burnerLoansConfig.marketId(address(usds));
        uint256[] memory positionIdsBefore = floan.getPositionIdsForMarketAndBorrower(
            marketId,
            alice
        );
        uint256 positionCountBefore = floan.getPositionCount();

        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        IFLOANv1.Position memory closedPosition = floan.getPosition(uint64(positionIdsBefore[0]));
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
        assertEq(closedPosition.principalDrawn, 0, "seized principal drawn cleared");
        assertEq(closedPosition.maturity, 0, "seized maturity cleared");

        vm.warp(block.timestamp + 1 days);
        _configurePrice(address(ohm), 10e18);
        price.setTimestamp(uint48(block.timestamp));
        usds.mint(alice, 2_100e18);
        vm.startPrank(alice);
        burnerLoans.depositCollateral(address(usds), 2_000e18, alice);
        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e9,
            alice
        );
        assertEq(preview.maturity, block.timestamp + 30 days, "new episode maturity");
        assertGt(preview.maturity, firstMaturity, "new maturity should not reuse old maturity");
        burnerLoans.borrow(address(usds), 100e9, alice, alice, preview.fee);
        vm.stopPrank();

        uint256[] memory positionIdsAfter = floan.getPositionIdsForMarketAndBorrower(
            marketId,
            alice
        );
        assertEq(floan.getPositionCount(), positionCountBefore, "position count unchanged");
        assertEq(positionIdsAfter.length, 1, "one position retained");
        assertEq(positionIdsAfter[0], positionIdsBefore[0], "same position ID reused");
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 100e9, "new debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).maturity,
            preview.maturity,
            "stored new episode maturity"
        );
        assertEq(burnerLoans.getActiveBorrowers(address(usds)).length, 1, "borrower active");
        _assertFloanPositionMatchesBurnerLoans(address(usds), alice);
    }

    // seize
    // given policy disabled
    //  when seize is called
    //   then it reverts
    function test_givenPolicyDisabled_seizeReverts() public {
        _makeUnhealthy(alice);
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.prank(keeper);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.prank(keeper);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(burnerLoans.totalActiveDebtOhm(), 100e9, "active debt unchanged");
    }

    // seize
    // given Burner Loans Inventory is globally disabled after a position becomes unhealthy
    //  when seizure is previewed or executed
    //   then both report the strict Burner Loans Inventory pause
    function test_givenInventoryDisabled_previewAndSeizeRevert() public {
        _makeUnhealthy(alice);
        vm.prank(emergency);
        inventory.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given asset originations disabled
    //  when seize is called
    //   then it still succeeds
    function test_givenAssetOriginationsDisabled_seizeStillSucceeds() public {
        _makeUnhealthy(alice);
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        assertTrue(preview.executable, "disabled asset seizure preview");

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );

        assertEq(reward, preview.keeperReward, "keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "treasury collateral");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt");
    }

    // seize
    // given multiple markets for the facility and token pair
    //  when seizure is previewed and executed
    //   then Burner Loans uses the first market
    function test_givenMultipleMarkets_previewAndSeizeUseFirstMarket() public {
        _makeUnhealthy(alice);
        uint32 firstMarketId = burnerLoansConfig.marketId(address(usds));
        uint32 secondMarketId = _createDuplicateUsdsMarketForTest();

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );
        vm.prank(keeper);
        burnerLoans.seize(address(usds), _single(alice));

        assertEq(preview.seizedDebtOhm, 100e9, "preview first-market debt");
        assertEq(floan.getMarketPrincipalDefaulted(firstMarketId), 100e9, "first-market default");
        assertEq(floan.getMarketPrincipalDefaulted(secondMarketId), 0, "second-market default");
    }

    // seize
    // given heart caller
    //  when seizure is previewed and executed
    //   then it returns zero reward and routes all collateral to treasury
    function test_givenHeartCaller_seizeRoutesAllCollateralToTreasury() public {
        _makeUnhealthy(alice);
        vm.prank(admin);
        rolesAdmin.grantRole(HEART_ROLE, keeper);

        vm.prank(keeper);
        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "heart reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(reward, preview.keeperReward, "executed heart reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given empty batch
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenEmptyBatch_seizeReverts() public {
        address[] memory borrowers = new address[](0);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.previewSeize(address(usds), borrowers);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.seize(address(usds), borrowers);
    }

    // seize
    // given batch above maximum
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenBatchAboveMaximum_seizeReverts(uint256 batchLength_) public {
        uint256 batchLength = bound(batchLength_, 51, 100);
        address[] memory borrowers = new address[](batchLength);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.previewSeize(address(usds), borrowers);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.seize(address(usds), borrowers);
    }

    // seize
    // given exact maximum batch
    //  when seizure is previewed and executed
    //   then both succeed with matching totals
    function test_givenExactMaximumBatch_seizeSucceeds() public {
        address[] memory borrowers = new address[](50);
        for (uint256 i; i < borrowers.length; ++i) {
            address borrower = address(uint160(i + 100));
            borrowers[i] = borrower;
            burnerLoans.setPositionForTest(
                address(usds),
                borrower,
                IBurnerLoans.Position({
                    depositedCollateral: 0,
                    debtOhm: 1e9,
                    maturity: uint48(block.timestamp + 30 days),
                    lastBorrowBlock: 0
                })
            );
        }

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            borrowers
        );

        assertEq(preview.seizedDebtOhm, 50e9, "seized debt");
        assertEq(preview.seizedCollateral, 0, "seized collateral");
        assertEq(preview.keeperReward, 0, "keeper reward");
        assertTrue(preview.executable, "executable");

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(address(usds), borrowers);
        assertEq(reward, preview.keeperReward, "executed keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given duplicate borrower
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenDuplicateBorrower_seizeReverts() public {
        _makeUnhealthy(alice);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_DuplicateBorrower.selector,
            alice
        );

        vm.expectRevert(error);
        burnerLoans.previewSeize(address(usds), _pair(alice, alice));

        vm.expectRevert(error);
        burnerLoans.seize(address(usds), _pair(alice, alice));
    }

    // seize
    // given zero borrower
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenZeroBorrower_seizeReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.previewSeize(address(usds), _single(address(0)));

        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAddress.selector);
        burnerLoans.seize(address(usds), _single(address(0)));
    }

    // seize
    // given healthy position
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenHealthyPosition_seizeReverts() public {
        _borrow(alice, 2_000e18, 100e9);
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_PositionNotSeizable.selector,
            alice
        );

        vm.expectRevert(error);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(error);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given debt free position
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenDebtFreePosition_seizeReverts() public {
        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(IBurnerLoans.BurnerLoans_NoDebt.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given stale prices
    //  when seizure is previewed and executed
    //   then both revert
    function test_givenStalePrices_seizeReverts() public {
        _makeUnhealthy(alice);
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.previewSeize(address(usds), _single(alice));

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.seize(address(usds), _single(alice));
    }

    // seize
    // given zero reward BPS
    //  when seizure is previewed and executed
    //   then both return zero reward
    function test_givenZeroRewardBps_seizeReturnsZeroReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.keeperRewardBps = 0;
        riskConfig.maxKeeperReward = 1_000e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "keeper reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(reward, preview.keeperReward, "executed keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given zero max reward
    //  when seizure is previewed and executed
    //   then both return zero reward
    function test_givenZeroMaxReward_seizeReturnsZeroReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 0;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 0, "keeper reward");
        assertEq(preview.collateralToTreasury, 2_000e18, "treasury collateral");

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(reward, preview.keeperReward, "executed keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }

    // seize
    // given max reward below BPS reward
    //  when seizure is previewed and executed
    //   then both cap the reward
    function test_givenMaxRewardBelowBpsReward_seizeCapsReward() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxKeeperReward = 5e18;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);
        _makeUnhealthy(alice);

        IBurnerLoans.SeizePreview memory preview = burnerLoans.previewSeize(
            address(usds),
            _single(alice)
        );

        assertEq(preview.keeperReward, 5e18, "capped keeper reward");

        vm.prank(keeper);
        (, uint256 reward, uint256 treasuryAmount) = burnerLoans.seize(
            address(usds),
            _single(alice)
        );
        assertEq(reward, preview.keeperReward, "executed capped keeper reward");
        assertEq(treasuryAmount, preview.collateralToTreasury, "executed treasury collateral");
    }
}

contract MutableRedeemFeeVault is MockERC4626 {
    uint256 internal _redeemFeeBps;

    constructor(ERC20 asset_) MockERC4626(asset_, "Fee Vault", "fVAULT") {}

    function setRedeemFeeBps(uint256 redeemFeeBps_) external {
        _redeemFeeBps = redeemFeeBps_;
    }

    function previewRedeem(uint256 shares_) public view override returns (uint256) {
        return (super.previewRedeem(shares_) * (10_000 - _redeemFeeBps)) / 10_000;
    }
}

contract BurnerLoansGetSeizableBorrowersTest is BurnerLoansSeizureTestBase {
    // getSeizableBorrowers
    // given no active borrowers
    //  when getSeizableBorrowers is called
    //   then it returns empty
    function test_givenNoActiveBorrowers_getSeizableBorrowersReturnsEmpty() public view {
        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 10, 10);

        assertEq(borrowers.length, 0, "borrowers");
        assertEq(nextIndex, 0, "cursor");
        assertEq(reward, 0, "reward");
    }

    // getSeizableBorrowers
    // given return limit above maximum
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenReturnLimitAboveMaximum_getSeizableBorrowers_reverts(
        uint256 returnLimit_
    ) public {
        uint256 returnLimit = bound(returnLimit_, 51, 100);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidBatch.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 100, returnLimit);
    }

    // getSeizableBorrowers
    // given policy disabled
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenPolicyDisabled_getSeizableBorrowers_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable(bytes(""));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 10, 10);
    }

    // getSeizableBorrowers
    // given stale prices
    //  when getSeizableBorrowers is called
    //   then it reverts
    function test_givenStalePrices_getSeizableBorrowers_reverts() public {
        _makeUnhealthy(alice);
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.getSeizableBorrowers(address(usds), 0, 1, 1);
    }

    // getSeizableBorrowers
    // given mixed active borrowers
    //  when getSeizableBorrowers is called
    //   then it returns only eligible positions
    function test_givenMixedActiveBorrowers_getSeizableBorrowersReturnsOnlyEligiblePositions()
        public
    {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 4_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);

        vm.prank(keeper);
        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 2, 2);

        assertEq(borrowers.length, 1, "seizable count");
        assertEq(borrowers[0], alice, "seizable borrower");
        assertEq(nextIndex, 0, "wrapped cursor");
        // Alice contributes 2,000e18 seized USDS; the configured 1% reward is 20e18 USDS.
        // This is below both the 1,000e18 cap and the collateral surplus above required backing.
        assertEq(reward, 20e18, "keeper reward");
    }

    // getSeizableBorrowers
    // given protocol seizer
    //  when getSeizableBorrowers is called
    //   then it returns zero reward
    function test_givenProtocolSeizer_getSeizableBorrowersReturnsZeroReward() public {
        _makeUnhealthy(alice);

        vm.prank(protocolSeizer);
        (address[] memory borrowers, , uint256 reward) = burnerLoans.getSeizableBorrowers(
            address(usds),
            0,
            1,
            1
        );

        assertEq(borrowers.length, 1, "borrower count");
        assertEq(reward, 0, "protocol reward");
    }

    // getSeizableBorrowers
    // given return limit
    //  when getSeizableBorrowers is called
    //   then it stops at limit
    function test_givenReturnLimit_getSeizableBorrowersStopsAtLimit() public {
        _borrow(alice, 2_000e18, 100e9);
        _borrow(bob, 2_000e18, 100e9);
        _configurePrice(address(ohm), 20e18);

        (address[] memory borrowers, uint256 nextIndex, ) = burnerLoans.getSeizableBorrowers(
            address(usds),
            0,
            2,
            1
        );

        assertEq(borrowers.length, 1, "return limit");
        assertEq(nextIndex, 1, "next cursor");
    }

    // getSeizableBorrowers
    // given zero check limit
    //  when getSeizableBorrowers is called
    //   then it returns empty without advancing
    function test_givenZeroCheckLimit_getSeizableBorrowersReturnsEmptyWithoutAdvancing() public {
        _makeUnhealthy(alice);

        (address[] memory borrowers, uint256 nextIndex, uint256 reward) = burnerLoans
            .getSeizableBorrowers(address(usds), 0, 0, 1);

        assertEq(borrowers.length, 0, "borrowers");
        assertEq(nextIndex, 0, "cursor");
        assertEq(reward, 0, "reward");
    }

    // getSeizableBorrowers
    // given start at end
    //  when getSeizableBorrowers is called
    //   then it wraps to zero
    function test_givenStartAtEnd_getSeizableBorrowersWrapsToZero() public {
        _makeUnhealthy(alice);

        (address[] memory borrowers, uint256 nextIndex, ) = burnerLoans.getSeizableBorrowers(
            address(usds),
            1,
            1,
            1
        );

        assertEq(borrowers.length, 1, "borrowers");
        assertEq(nextIndex, 0, "wrapped cursor");
    }
}

contract BurnerLoansIsSeizableTest is BurnerLoansBorrowTestBase {
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _position(
        uint256 collateral_,
        uint128 debt_,
        uint48 maturity_
    ) internal pure returns (IBurnerLoans.Position memory) {
        return
            IBurnerLoans.Position({
                depositedCollateral: collateral_,
                debtOhm: debt_,
                maturity: maturity_,
                lastBorrowBlock: 0
            });
    }

    // isSeizable
    // given healthy active position
    //  when isSeizable is called
    //   then it returns false
    function test_givenHealthyActivePosition_isSeizable_returnsFalse() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "healthy position");
    }

    // isSeizable
    // given health below one WAD
    //  when isSeizable is called
    //   then it returns true
    function test_givenHealthBelowOneWad_isSeizable_returnsTrue() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_149e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "unhealthy position");
    }

    // isSeizable
    // given health exactly one WAD
    //  when isSeizable is called
    //   then it returns false
    function test_givenHealthExactlyOneWad_isSeizable_returnsFalse() public {
        backingOracle.setBacking(10e18);
        // Launch parameters: maxLtvBps = 8,500 and backingMultiplierBps = 12,500.
        // Debt = 100e9 OHM (9 decimals); backing = $10e18 per OHM (18 decimals).
        // Backing debt value = 100e9 * $10e18 / 1e9 = $1,000e18.
        // Backing requirement = $1,000e18 * 12,500 / 10,000 = $1,250e18.
        // OHM market price is $10e18, below the $10.625e18 crossover, so backing dominates.
        // At $1e18 per collateral token, 1,250e18 collateral is exactly $1,250e18.
        // Health = floor($1,250e18 * 1e18 / $1,250e18) = 1e18.
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_250e18, 100e9, uint48(block.timestamp + 30 days))
        );

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "exact health boundary");
    }

    // isSeizable
    // given health one collateral unit below one WAD
    //  when isSeizable is called
    //   then it returns true
    function test_givenHealthOneCollateralUnitBelowOneWad_isSeizable_returnsTrue() public {
        backingOracle.setBacking(10e18);
        // Launch parameters: maxLtvBps = 8,500 and backingMultiplierBps = 12,500.
        // Debt = 100e9 OHM (9 decimals); backing = $10e18 per OHM (18 decimals).
        // Backing requirement = $1,250e18, as worked in the exact-boundary test above.
        // Collateral value = floor(($1,250e18 - 1) * $1e18 / 1e18) = $1,250e18 - 1.
        // Health = floor(($1,250e18 - 1) * 1e18 / $1,250e18)
        //        = 999_999_999_999_999_999, so the position is seizable.
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(1_250e18 - 1, 100e9, uint48(block.timestamp + 30 days))
        );

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "below health boundary");
    }

    // isSeizable
    // given matured healthy position
    //  when isSeizable is called
    //   then it returns true
    function test_givenMaturedHealthyPosition_isSeizable_returnsTrue() public {
        uint48 maturity = uint48(block.timestamp + 1 days);
        burnerLoans.setPositionForTest(address(usds), alice, _position(2_000e18, 100e9, maturity));
        vm.warp(maturity);
        price.setTimestamp(uint48(block.timestamp));

        assertTrue(burnerLoans.isSeizable(address(usds), alice), "matured position");
    }

    // isSeizable
    // given debt free position
    //  when isSeizable is called
    //   then it returns false without price read
    function test_givenDebtFreePosition_isSeizable_returnsFalseWithoutPriceRead() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 0, uint48(block.timestamp + 30 days))
        );
        vm.warp(block.timestamp + 9 hours);

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "debt-free position");
    }

    // isSeizable
    // given stale price
    //  when isSeizable is called
    //   then it reverts
    function test_givenStalePrice_isSeizable_reverts() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );
        vm.warp(block.timestamp + 9 hours);

        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidPrice.selector);
        burnerLoans.isSeizable(address(usds), alice);
    }

    // isSeizable
    // given missing market
    //  when isSeizable is called
    //   then it reverts
    function test_givenMissingMarket_isSeizable_reverts() public {
        address otherAsset = makeAddr("otherAsset");

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, otherAsset)
        );
        burnerLoans.isSeizable(otherAsset, alice);
    }

    // isSeizable
    // given multiple markets
    //  when isSeizable is called
    //   then it uses the first market
    function test_givenMultipleMarkets_isSeizableUsesFirstMarket() public {
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            _position(2_000e18, 100e9, uint48(block.timestamp + 30 days))
        );
        _createDuplicateUsdsMarketForTest();

        assertFalse(burnerLoans.isSeizable(address(usds), alice), "first-market health");
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast,calls-loop,multi-contract-file)

// forge-lint: disable-end(literal-instead-of-constant)
