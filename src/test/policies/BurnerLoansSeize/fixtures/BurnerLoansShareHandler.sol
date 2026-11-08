// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansDebt} from "src/policies/interfaces/burnerloans/IBurnerLoansDebt.sol";
import {IBurnerLoansYieldClaim} from "src/policies/interfaces/burnerloans/IBurnerLoansYieldClaim.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansCollateral} from "src/policies/burnerloans/BurnerLoansCollateral.sol";
import {BurnerLoansConfig} from "src/policies/burnerloans/BurnerLoansConfig.sol";
import {BurnerLoansDebt} from "src/policies/burnerloans/BurnerLoansDebt.sol";
import {BurnerLoansInventory} from "src/policies/burnerloans/BurnerLoansInventory.sol";
import {BurnerLoansLens} from "src/policies/burnerloans/BurnerLoansLens.sol";
import {BurnerLoansSeize} from "src/policies/burnerloans/BurnerLoansSeize.sol";
import {BurnerLoansSeizerTask} from "src/policies/burnerloans/BurnerLoansSeizerTask.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

/// @notice Three-borrower external-share model using real modular settlement.
/// @dev Prices vary; token balances and integer vault ratios independently determine expected output.
///      The invariant suite enables fail-on-revert, so failed assertions or unexpected action errors
///      cannot disappear as discarded handler calls. Empty balances and unavailable modeled
///      operations return without mutation.
contract BurnerLoansShareHandler is Test {
    struct Services {
        BurnerLoansCollateral collateral;
        BurnerLoansDebt debt;
        BurnerLoansSeize seize;
        BurnerLoansConfig config;
        BurnerLoansLens lens;
        BurnerLoansComposites composites;
        BurnerLoansSeizerTask seizer;
        BurnerLoansYieldClaimerTask claimer;
    }

    struct Exit {
        address token;
        uint256 amount;
        uint256 shares;
        uint256 recipientBalance;
        uint256 custodyBalance;
    }

    Services internal _services;
    IBurnerLoansCore internal immutable _CORE;
    BurnerLoansInventory internal immutable _INVENTORY;
    MockERC20 internal immutable _ASSET;
    MockERC20 internal immutable _OHM;
    MockERC7540ExternalShareVault internal immutable _VAULT;
    IERC20 internal immutable _SHARE;
    MockPrice internal immutable _PRICE;
    address internal immutable _CUSTODY;
    address internal immutable _TREASURY;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];
    mapping(address => uint128) public collateral;
    mapping(address => uint128) public principal;
    uint256 public defaulted;
    bool public asyncRedeem = true;

    constructor(
        Services memory services_,
        MockERC7540ExternalShareVault vault_,
        MockPrice price_,
        address treasury_
    ) {
        _services = services_;
        _CORE = IBurnerLoansCore(services_.collateral.core());
        _INVENTORY = BurnerLoansInventory(_CORE.inventory());
        _ASSET = MockERC20(vault_.asset());
        _OHM = MockERC20(_CORE.ohm());
        _VAULT = vault_;
        _SHARE = IERC20(vault_.share());
        _PRICE = price_;
        _CUSTODY = _CORE.depositManager();
        _TREASURY = treasury_;
        assertTrue(
            _OHM.approve(address(_INVENTORY), type(uint256).max),
            "Provider approves Inventory"
        );
        for (uint256 i; i < actors.length; ++i) {
            vm.startPrank(actors[i]);
            assertTrue(
                _ASSET.approve(address(_CORE), type(uint256).max),
                "Actor approves collateral"
            );
            assertTrue(_OHM.approve(address(_CORE), type(uint256).max), "Actor approves repayment");
            assertTrue(
                _OHM.approve(address(services_.composites), type(uint256).max),
                "Actor approves composite"
            );
            IOperatorAuth(address(_CORE)).setAuthorization(
                address(services_.composites),
                type(uint48).max
            );
            vm.stopPrank();
        }
    }

    function deposit(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = actors[actorSeed_ % actors.length];
        uint128 amount = uint128(bound(amountSeed_, 1e18, 100_000e18));
        uint256 expectedShares = _sharesForAssets(amount);
        if (expectedShares == 0) return;
        // share6 * post-deposit asset18 / post-deposit share6 -> asset18, rounded down.
        uint256 expectedCredit = (expectedShares * (_ASSET.balanceOf(address(_VAULT)) + amount)) /
            (_SHARE.totalSupply() + expectedShares);
        _ASSET.mint(actor, amount);
        uint256 custodyBefore = _SHARE.balanceOf(_CUSTODY);
        uint256 walletBefore = _ASSET.balanceOf(actor);
        (uint256 quotedCredit, uint256 quotedCollateral, uint256 quotedHealth) = _services
            .collateral
            .previewDepositCollateral(address(_ASSET), amount, actor);
        assertEq(
            quotedCredit,
            _assetsForShares(expectedShares),
            "Independent pre-deposit conversion"
        );
        assertEq(quotedCollateral, collateral[actor] + quotedCredit, "Quote adds estimated credit");
        vm.prank(actor);
        (uint128 credit, uint128 total, uint256 health) = _services.collateral.depositCollateral(
            address(_ASSET),
            amount,
            actor
        );
        assertEq(credit, expectedCredit, "Credit uses the post-deposit vault ratio");
        collateral[actor] += credit;
        assertEq(total, collateral[actor], "Returned collateral equals model");
        assertEq(
            _SHARE.balanceOf(_CUSTODY),
            custodyBefore + expectedShares,
            "Exact shares deposited"
        );
        assertEq(_ASSET.balanceOf(actor), walletBefore - amount, "Actor funds the deposit");
        if (principal[actor] == 0) {
            assertEq(quotedHealth, type(uint256).max, "Debt-free quote health");
            assertEq(health, type(uint256).max, "Debt-free deposit health");
        }
    }

    function borrow(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = actors[actorSeed_ % actors.length];
        uint128 amount = uint128(bound(amountSeed_, 1, 1000e9));
        IBurnerLoansDebt.BorrowPreview memory quote;
        try
            _services.debt.previewBorrow(
                address(_ASSET),
                amount,
                actor,
                actor,
                type(uint256).max,
                address(0)
            )
        returns (IBurnerLoansDebt.BorrowPreview memory preview) {
            quote = preview;
        } catch {
            return;
        }
        _ASSET.mint(actor, quote.fee);
        uint256 collateralWalletBefore = _ASSET.balanceOf(actor);
        uint256 treasuryBefore = _ASSET.balanceOf(_TREASURY);
        uint256 supplyBefore = _OHM.totalSupply();
        uint256 idleBefore = _INVENTORY.suppliedIdleOhm();
        uint256 walletBefore = _OHM.balanceOf(actor);
        vm.prank(actor);
        IBurnerLoansDebt.BorrowPreview memory result = _services.debt.borrow(
            address(_ASSET),
            amount,
            actor,
            actor,
            type(uint256).max,
            address(0)
        );
        principal[actor] += amount;
        assertEq(result.resultingDebtOhm, principal[actor], "Borrow updates modeled principal");
        assertEq(_OHM.balanceOf(actor), walletBefore + amount, "Borrower receives exact OHM");
        assertEq(result.fee, quote.fee, "Borrow fee agrees with unchanged pricing quote");
        assertEq(
            _ASSET.balanceOf(actor),
            collateralWalletBefore - result.fee,
            "Borrower pays only the fee outside custody"
        );
        assertEq(
            _ASSET.balanceOf(_TREASURY),
            treasuryBefore + result.fee,
            "Treasury receives the complete fee"
        );
        assertEq(
            _OHM.totalSupply() - supplyBefore + idleBefore - _INVENTORY.suppliedIdleOhm(),
            amount,
            "Minted and supplied funding conserve"
        );
    }

    function repay(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = actors[actorSeed_ % actors.length];
        uint256 available = _OHM.balanceOf(actor);
        if (available > principal[actor]) available = principal[actor];
        if (available == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, available));
        vm.roll(block.number + 1);
        (uint128 quotedDebt, uint256 quotedHealth) = _services.debt.previewRepay(
            address(_ASSET),
            amount,
            actor
        );
        uint256 supplyBefore = _OHM.totalSupply();
        uint256 idleBefore = _INVENTORY.suppliedIdleOhm();
        vm.prank(actor);
        (uint128 debt, uint256 health) = _services.debt.repay(address(_ASSET), amount, actor);
        principal[actor] -= amount;
        assertEq(debt, principal[actor], "Repayment reduces modeled debt");
        assertEq(debt, quotedDebt, "Repayment agrees with quote");
        assertEq(health, quotedHealth, "Repayment health agrees with quote");
        assertEq(
            supplyBefore - _OHM.totalSupply() + _INVENTORY.suppliedIdleOhm() - idleBefore,
            amount,
            "Burned and restored OHM conserve"
        );
    }

    function withdraw(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = actors[actorSeed_ % actors.length];
        if (collateral[actor] == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, collateral[actor]));
        IBurnerLoansCollateral.WithdrawPreview memory quote;
        try
            _services.collateral.previewWithdrawCollateral(address(_ASSET), amount, actor, actor)
        returns (IBurnerLoansCollateral.WithdrawPreview memory preview) {
            quote = preview;
        } catch {
            return;
        }
        Exit memory expected = _exit(amount, actor);
        assertEq(quote.returnToken, expected.token, "Withdrawal quote token");
        assertEq(quote.returnAmount, expected.amount, "Independent withdrawal conversion");
        vm.prank(actor);
        IBurnerLoansCollateral.WithdrawPreview memory result = _services
            .collateral
            .withdrawCollateral(address(_ASSET), amount, actor, actor);
        collateral[actor] -= amount;
        assertEq(result.remainingDepositedCollateral, collateral[actor], "Withdrawal debits model");
        assertEq(
            result.resultingHealthFactor,
            quote.resultingHealthFactor,
            "Withdrawal health agrees"
        );
        _assertExit(expected, actor, result.returnToken, result.returnAmount);
    }

    function compositeRepayAndWithdraw(
        uint256 actorSeed_,
        uint128 repaySeed_,
        uint128 amountSeed_
    ) external {
        address actor = actors[actorSeed_ % actors.length];
        uint128 debt = principal[actor];
        if (collateral[actor] == 0 || _OHM.balanceOf(actor) < debt || !_modeUsable()) return;
        uint128 repayment = uint128(bound(repaySeed_, 0, debt));
        // Prices span $0.50..$2 and the backing multiplier is 1.25. Retain at least
        // 5 asset18 units per OHM9 unit of remaining debt, independently of Risk's quote.
        uint256 retained = uint256(debt - repayment) * 5e9;
        if (collateral[actor] <= retained) return;
        uint128 amount = uint128(bound(amountSeed_, 1, collateral[actor] - retained));
        Exit memory expected = _exit(amount, actor);
        if (expected.amount == 0) return;
        vm.roll(block.number + 1);
        uint256 walletBefore = _OHM.balanceOf(actor);
        vm.prank(actor);
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = _services
            .composites
            .repayAndWithdraw(
                IOperatorAuth.Authorization(address(0), address(0), 0, 0, 0),
                IOperatorAuth.Signature(0, bytes32(0), bytes32(0)),
                IBurnerLoansComposites.RepayAndWithdrawParams(
                    address(_ASSET),
                    repayment,
                    amount,
                    actor
                )
            );
        principal[actor] -= repayment;
        collateral[actor] -= amount;
        assertEq(result.repaidOhm, repayment, "Composite repays modeled amount");
        assertEq(result.resultingDebtOhm, principal[actor], "Composite preserves remaining debt");
        if (principal[actor] != 0)
            assertGe(result.healthFactor, 1e18, "Partial composite exit stays healthy");
        assertEq(result.remainingCollateral, collateral[actor], "Composite collateral debit");
        assertEq(
            _OHM.balanceOf(actor),
            walletBefore - repayment,
            "Composite charges only actual repayment"
        );
        _assertExit(expected, actor, result.tokenOut, result.amountOut);
    }

    function seize() external {
        if (!_modeUsable()) return;
        (address[] memory borrowers, , ) = _services.lens.getSeizableBorrowersFor(
            address(this),
            address(_ASSET),
            0,
            actors.length
        );
        if (borrowers.length == 0) return;
        uint256 amount = _selectedCollateral(borrowers);
        Exit memory expected = _exit(amount, address(this));
        uint256 treasuryBefore = IERC20(expected.token).balanceOf(_TREASURY);
        IBurnerLoansCore.SeizePreview memory quote = _services.seize.previewSeizeFor(
            address(this),
            address(_ASSET),
            borrowers
        );
        (address output, uint256 reward, uint256 treasury) = _services.seize.seize(
            address(_ASSET),
            borrowers
        );
        assertEq(output, expected.token, "Seizure output token");
        assertEq(reward + treasury, expected.amount, "Seizure conserves converted output");
        assertEq(reward, quote.keeperReward, "Keeper quote matches payout");
        assertEq(treasury, quote.collateralToTreasury, "Treasury quote matches payout");
        assertEq(
            IERC20(output).balanceOf(address(this)),
            expected.recipientBalance + reward,
            "Keeper receives reward"
        );
        assertEq(
            IERC20(output).balanceOf(_TREASURY),
            treasuryBefore + treasury,
            "Treasury receives remainder"
        );
        assertEq(
            _SHARE.balanceOf(_CUSTODY),
            expected.custodyBalance - expected.shares,
            "Seizure consumes exact custody shares"
        );
        _closeSelected(borrowers);
    }

    function executePeriodicSeizer() external {
        if (!_modeUsable()) return;
        (address[] memory borrowers, , ) = _services.lens.getSeizableBorrowersFor(
            address(_services.seizer),
            address(_ASSET),
            0,
            actors.length
        );
        Exit memory expected = _exit(_selectedCollateral(borrowers), _TREASURY);
        _services.seizer.execute();
        _assertExit(expected, _TREASURY, expected.token, expected.amount);
        _closeSelected(borrowers);
    }

    function claimYield() external {
        if (!_modeUsable()) {
            bytes memory reason = abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(_ASSET),
                address(_VAULT)
            );
            uint256 custodyBefore = _SHARE.balanceOf(_CUSTODY);
            vm.expectRevert(reason);
            _services.claimer.previewClaimYield(address(_ASSET));
            vm.expectRevert(reason);
            _services.claimer.claimYield(address(_ASSET));
            assertEq(_SHARE.balanceOf(_CUSTODY), custodyBefore, "Rejected claim preserves custody");
            return;
        }
        uint256 assets = _assetsForShares(_SHARE.balanceOf(_CUSTODY));
        uint256 liabilities;
        for (uint256 i; i < actors.length; ++i) liabilities += collateral[actors[i]];
        uint256 request = assets > liabilities ? assets - liabilities : 0;
        if (!_services.config.getAssetConfig(address(_ASSET)).withdrawAsShares && request != 0)
            --request;
        Exit memory expected = _exit(request, _TREASURY);
        IBurnerLoansYieldClaim.ClaimYieldPreview memory quote = _services.claimer.previewClaimYield(
            address(_ASSET)
        );
        assertEq(
            quote.requestedAssetAmount,
            request,
            "Yield request equals independent surplus minus buffer"
        );
        assertEq(quote.amountOut, expected.amount, "Independent yield conversion");
        (address output, uint256 amount) = _services.claimer.claimYield(address(_ASSET));
        _assertExit(expected, _TREASURY, output, amount);
    }

    function addYield(uint128 amountSeed_) external {
        _ASSET.mint(address(_VAULT), bound(amountSeed_, 1, 1000e18));
    }

    function movePrices(uint256 collateralSeed_, uint256 ohmSeed_) external {
        _PRICE.setPrice(address(_ASSET), bound(collateralSeed_, 0.5e18, 2e18));
        _PRICE.setPrice(address(_OHM), bound(ohmSeed_, 0.5e18, 2e18));
    }

    function moveTime(uint32 elapsed_) external {
        vm.warp(vm.getBlockTimestamp() + bound(elapsed_, 1, 31 days));
        vm.roll(block.number + 1);
        _PRICE.setTimestamp(uint48(vm.getBlockTimestamp()));
    }

    function setAsyncRedeem(bool enabled_) external {
        _VAULT.setCapabilities(false, enabled_, true, true);
        asyncRedeem = enabled_;
    }

    function setWithdrawAsShares(bool shares_) external {
        bool beforeMode = _services.config.getAssetConfig(address(_ASSET)).withdrawAsShares;
        try _services.config.setAssetWithdrawAsShares(address(_ASSET), shares_) {
            assertEq(
                _services.config.getAssetConfig(address(_ASSET)).withdrawAsShares,
                shares_,
                "Successful mode transition"
            );
        } catch {
            assertTrue(asyncRedeem && !shares_, "Only unsupported underlying mode may reject");
            assertEq(
                _services.config.getAssetConfig(address(_ASSET)).withdrawAsShares,
                beforeMode,
                "Rejected mode transition is atomic"
            );
        }
    }

    function setOriginations(bool enabled_) external {
        if (enabled_ && !_modeUsable()) return;
        _services.config.setAssetOriginationsEnabled(address(_ASSET), enabled_);
    }

    function supplyInventory(uint128 amountSeed_) external {
        uint128 amount = uint128(bound(amountSeed_, 1, 1000e9));
        _OHM.mint(address(this), amount);
        _INVENTORY.supply(amount);
    }

    function withdrawInventory(uint128 amountSeed_) external {
        uint256 available = _INVENTORY.suppliedIdleOhm();
        if (available > _INVENTORY.providerClaimOhm(address(this)))
            available = _INVENTORY.providerClaimOhm(address(this));
        if (available == 0) return;
        _INVENTORY.withdraw(uint128(bound(amountSeed_, 1, available)), address(this));
    }

    function _modeUsable() private view returns (bool) {
        return !asyncRedeem || _services.config.getAssetConfig(address(_ASSET)).withdrawAsShares;
    }

    function _selectedCollateral(address[] memory borrowers_) private view returns (uint256 total) {
        for (uint256 i; i < borrowers_.length; ++i) {
            assertTrue(
                _services.lens.isSeizable(address(_ASSET), borrowers_[i]),
                "Selected borrower is eligible"
            );
            total += collateral[borrowers_[i]];
        }
    }

    function _closeSelected(address[] memory borrowers_) private {
        for (uint256 i; i < borrowers_.length; ++i) {
            defaulted += principal[borrowers_[i]];
            principal[borrowers_[i]] = 0;
            collateral[borrowers_[i]] = 0;
            IBurnerLoansCore.Position memory position = _services.lens.getPosition(
                address(_ASSET),
                borrowers_[i]
            );
            assertEq(position.debtOhm, 0, "Seizure closes debt");
            assertEq(position.depositedCollateral, 0, "Seizure closes collateral");
            assertEq(position.maturity, 0, "Seizure clears maturity");
            assertEq(position.lastBorrowBlock, 0, "Seizure clears the debt episode block");
        }
    }

    function _exit(uint256 assets_, address recipient_) private view returns (Exit memory result) {
        result.shares = _sharesForAssets(assets_);
        bool shares = _services.config.getAssetConfig(address(_ASSET)).withdrawAsShares;
        result.token = shares ? address(_SHARE) : address(_ASSET);
        result.amount = shares ? result.shares : _assetsForShares(result.shares);
        result.recipientBalance = IERC20(result.token).balanceOf(recipient_);
        result.custodyBalance = _SHARE.balanceOf(_CUSTODY);
    }

    function _assertExit(
        Exit memory expected_,
        address recipient_,
        address output_,
        uint256 amount_
    ) private view {
        assertEq(output_, expected_.token, "Output token matches custody mode");
        assertEq(amount_, expected_.amount, "Output matches independent vault ratio");
        assertEq(
            IERC20(output_).balanceOf(recipient_),
            expected_.recipientBalance + amount_,
            "Actual output delivery conserves"
        );
        assertEq(
            _SHARE.balanceOf(_CUSTODY),
            expected_.custodyBalance - expected_.shares,
            "Exact custody share debit"
        );
    }

    function _sharesForAssets(uint256 assets_) private view returns (uint256) {
        uint256 supply = _SHARE.totalSupply();
        uint256 assets = _ASSET.balanceOf(address(_VAULT));
        // asset18 * share6 / asset18 -> share6, rounded down. Empty vault starts at 1e12.
        return supply == 0 || assets == 0 ? assets_ / 1e12 : (assets_ * supply) / assets;
    }

    function _assetsForShares(uint256 shares_) private view returns (uint256) {
        uint256 supply = _SHARE.totalSupply();
        // share6 * asset18 / share6 -> asset18, rounded down.
        return
            supply == 0 ? shares_ * 1e12 : (shares_ * _ASSET.balanceOf(address(_VAULT))) / supply;
    }
}
