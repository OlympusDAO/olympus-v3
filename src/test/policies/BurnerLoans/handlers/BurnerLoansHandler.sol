// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";
import {PriceCache} from "src/policies/price/PriceCache.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";
import {MockYieldRepurchaseRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRepurchaseRecipient.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

// Test actions assert effects directly; test inputs prove casts fit or select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unused-return,unsafe-typecast,calls-loop)

// The MockPrice getter shares IOracle.price's selector but returns an address.
// forge-lint: disable-next-line(missing-inheritance)
contract BurnerLoansHandler is Test {
    uint256 internal constant _WAD = 1e18;
    uint256 internal constant _OHM_SCALE = 1e9;

    BurnerLoansHarness internal immutable _BURNER_LOANS;
    BurnerLoansConfig internal immutable _BURNER_LOANS_CONFIG;
    BurnerLoansComposites internal immutable _COMPOSITES;
    OlympusFixedTermLoan internal immutable _FLOAN;
    BurnerLoansSeizer internal immutable _SEIZER;
    MockPrice internal immutable _PRICE;
    MockOhm internal immutable _OHM;
    MockERC20 internal immutable _COLLATERAL;
    uint256 internal immutable _COLLATERAL_SCALE;
    IDepositManager internal immutable _DEPOSIT_MANAGER;
    address internal immutable _ADMIN;
    address internal immutable _TREASURY;
    address internal immutable _INVENTORY_PROVIDER;
    MockYieldRepurchaseRecipient internal immutable _YIELD_RECIPIENT;
    PriceCache internal immutable _PRIMARY_PRICE_CACHE;
    PriceCache internal immutable _SECONDARY_PRICE_CACHE;

    address[] internal _actors;
    uint256 public collateralPrice = _WAD;

    uint256 public repaymentBurnViolations;
    uint256 public fundingDebtViolations;
    uint256 public repaymentDebtViolations;
    uint256 public repaymentCollateralViolations;
    uint256 public unexpectedDepositFailures;
    uint256 public unexpectedBorrowFailures;
    uint256 public unexpectedRepayFailures;
    uint256 public unexpectedWithdrawFailures;
    uint256 public unexpectedExtendFailures;
    uint256 public unexecutableBorrowAttempts;
    uint256 public unexecutableWithdrawAttempts;
    uint256 public unexecutableExtendAttempts;
    uint256 public unexpectedUnexecutableBorrowSuccesses;
    uint256 public unexpectedUnexecutableWithdrawSuccesses;
    uint256 public unexpectedUnexecutableExtendSuccesses;
    uint256 public sameBlockRepayViolations;
    uint256 public claimYieldBoundViolations;
    uint256 public claimYieldConservationViolations;
    uint256 public claimYieldResidualViolations;
    uint256 public claimYieldFailureMutationViolations;
    uint256 public claimYieldPreviewConsistencyViolations;
    uint256 public routingFailureMutationViolations;
    uint256 public repurchaseRecipientClearViolations;
    uint256 public cumulativeClaimedYield;
    uint256 public cumulativeDistributedYield;
    uint256 public modelActiveRepurchaseRouteCount;
    address public modelYieldRepurchaseRecipient;
    bytes32 public modelAssetYieldRoutingHash;
    uint256 public backingViolations;
    uint256 public seizureEligibilityViolations;
    uint256 public seizureClosureViolations;
    uint256 public seizureOutputConservationViolations;
    uint256 public withdrawalOutputConservationViolations;
    uint256 public compositeWithdrawalOutputConservationViolations;
    uint256 public withdrawAsSharesTransitionViolations;
    uint256 public positionReuseViolations;

    address[5] internal _directYieldRecipients;

    struct Dependencies {
        BurnerLoansHarness burnerLoans;
        BurnerLoansConfig burnerLoansConfig;
        BurnerLoansComposites composites;
        OlympusFixedTermLoan floan;
        BurnerLoansSeizer seizer;
        MockPrice price;
        MockOhm ohm;
        MockERC20 collateral;
        IDepositManager depositManager;
        address admin;
        address treasury;
        address inventoryProvider;
        MockYieldRepurchaseRecipient yieldRecipient;
        PriceCache primaryPriceCache;
        PriceCache secondaryPriceCache;
        address[] actors;
    }

    struct ClaimObservation {
        IBurnerLoans.AssetCollateralStatus collateralStatus;
        IERC20 outputToken;
        uint256 treasuryBalance;
        uint256 repurchaseBalance;
        uint256 facilityBalance;
        uint256[5] directBalances;
        bytes32 routeHash;
        address globalRecipient;
        bool previewReturned;
        bool previewExecutable;
        bool withdrawalModeValid;
        uint256 previewRequestedAssets;
        uint256 previewAmountOut;
    }

    struct CompositeWithdrawalObservation {
        IERC20 outputToken;
        uint256 recipientBalanceBefore;
    }

    struct CompositeRepayObservation {
        IBurnerLoans.Position beforePosition;
        uint256 supplyBefore;
        uint256 idleBefore;
        CompositeWithdrawalObservation withdrawal;
    }

    constructor(Dependencies memory dependencies_) {
        _BURNER_LOANS = dependencies_.burnerLoans;
        _BURNER_LOANS_CONFIG = dependencies_.burnerLoansConfig;
        _COMPOSITES = dependencies_.composites;
        _FLOAN = dependencies_.floan;
        _SEIZER = dependencies_.seizer;
        _PRICE = dependencies_.price;
        _OHM = dependencies_.ohm;
        _COLLATERAL = dependencies_.collateral;
        _COLLATERAL_SCALE = 10 ** uint256(dependencies_.collateral.decimals());
        _DEPOSIT_MANAGER = dependencies_.depositManager;
        _ADMIN = dependencies_.admin;
        _TREASURY = dependencies_.treasury;
        _INVENTORY_PROVIDER = dependencies_.inventoryProvider;
        _YIELD_RECIPIENT = dependencies_.yieldRecipient;
        _PRIMARY_PRICE_CACHE = dependencies_.primaryPriceCache;
        _SECONDARY_PRICE_CACHE = dependencies_.secondaryPriceCache;
        _actors = dependencies_.actors;

        for (uint256 i; i < _directYieldRecipients.length; ++i) {
            _directYieldRecipients[i] = address(
                uint160(uint256(keccak256(abi.encode("BurnerLoansDirectYieldRecipient", i))))
            );
        }
        modelYieldRepurchaseRecipient = dependencies_.burnerLoans.getYieldRepurchaseRecipient();
        IBurnerLoans.AssetYieldRouting memory initialRouting = dependencies_
            .burnerLoans
            .getYieldAssetRouting(address(dependencies_.collateral));
        modelActiveRepurchaseRouteCount = initialRouting.repurchaseRecipientBps == 0 ? 0 : 1;
        modelAssetYieldRoutingHash = keccak256(abi.encode(initialRouting));

        address inventory_ = dependencies_.burnerLoans.inventory();
        vm.prank(dependencies_.inventoryProvider);
        dependencies_.ohm.approve(inventory_, type(uint256).max);

        for (uint256 i; i < dependencies_.actors.length; ++i) {
            vm.startPrank(dependencies_.actors[i]);
            dependencies_.collateral.approve(address(dependencies_.burnerLoans), type(uint256).max);
            dependencies_.collateral.approve(address(dependencies_.composites), type(uint256).max);
            dependencies_.burnerLoans.setAuthorization(
                address(dependencies_.composites),
                type(uint48).max
            );
            vm.stopPrank();
        }
    }

    function actorCount() external view returns (uint256) {
        return _actors.length;
    }

    function actorAt(uint256 index_) external view returns (address) {
        return _actors[index_];
    }

    function deposit(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        uint128 amount = uint128(bound(amountSeed_, 1e15, 100_000e18));
        _COLLATERAL.mint(actor, amount);

        try _BURNER_LOANS.previewDepositCollateral(address(_COLLATERAL), amount, actor) returns (
            uint256,
            uint256,
            uint256
        ) {} catch {
            return;
        }

        vm.prank(actor);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, ) = address(_BURNER_LOANS).call(
            abi.encodeCall(_BURNER_LOANS.depositCollateral, (address(_COLLATERAL), amount, actor))
        );
        // forge-lint: disable-end(low-level-calls)
        if (!success) ++unexpectedDepositFailures;
    }

    function borrow(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        uint128 amount = uint128(bound(amountSeed_, 1, 1_000e9));
        _COLLATERAL.mint(actor, 10_000e18);

        bool previewExecutable;
        try _BURNER_LOANS.previewBorrow(address(_COLLATERAL), amount, actor) returns (
            IBurnerLoans.BorrowPreview memory preview
        ) {
            previewExecutable = preview.executable;
        } catch {
            return;
        }

        uint256 supplyBefore = _OHM.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        uint256 debtBefore = _BURNER_LOANS.getPosition(address(_COLLATERAL), actor).debtOhm;
        vm.prank(actor);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, ) = address(_BURNER_LOANS).call(
            abi.encodeCall(
                _BURNER_LOANS.borrow,
                (address(_COLLATERAL), amount, actor, actor, type(uint256).max)
            )
        );
        // forge-lint: disable-end(low-level-calls)
        if (!previewExecutable) {
            ++unexecutableBorrowAttempts;
            if (success) ++unexpectedUnexecutableBorrowSuccesses;
            return;
        }
        if (!success) {
            ++unexpectedBorrowFailures;
            return;
        }

        uint256 debtAfter = _BURNER_LOANS.getPosition(address(_COLLATERAL), actor).debtOhm;
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (
            _OHM.totalSupply() - supplyBefore + (idleBefore - idleAfter) != debtAfter - debtBefore
        ) {
            ++fundingDebtViolations;
        }
        _probeSameBlockRepay(actor);
        _checkBacking();
    }

    function repay(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        IBurnerLoans.Position memory beforePosition = _BURNER_LOANS.getPosition(
            address(_COLLATERAL),
            actor
        );
        uint256 available = _OHM.balanceOf(actor) < beforePosition.debtOhm
            ? _OHM.balanceOf(actor)
            : beforePosition.debtOhm;
        if (available == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, available));
        if (block.number <= beforePosition.lastBorrowBlock) {
            vm.roll(uint256(beforePosition.lastBorrowBlock) + 1);
        }

        uint256 supplyBefore = _OHM.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        vm.startPrank(actor);
        _OHM.approve(address(_BURNER_LOANS), amount);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, ) = address(_BURNER_LOANS).call(
            abi.encodeCall(_BURNER_LOANS.repay, (address(_COLLATERAL), amount, actor))
        );
        // forge-lint: disable-end(low-level-calls)
        vm.stopPrank();
        if (!success) {
            ++unexpectedRepayFailures;
            return;
        }

        IBurnerLoans.Position memory afterPosition = _BURNER_LOANS.getPosition(
            address(_COLLATERAL),
            actor
        );
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (supplyBefore - _OHM.totalSupply() + (idleAfter - idleBefore) != amount) {
            ++repaymentBurnViolations;
        }
        if (beforePosition.debtOhm - afterPosition.debtOhm != amount) {
            ++repaymentDebtViolations;
        }
        if (beforePosition.depositedCollateral != afterPosition.depositedCollateral) {
            ++repaymentCollateralViolations;
        }
    }

    function compositeDepositAndBorrow(
        uint256 actorSeed_,
        uint128 collateralSeed_,
        uint128 debtSeed_
    ) external {
        address actor = _actor(actorSeed_);
        uint128 collateralAmount = uint128(bound(collateralSeed_, 1e15, 100_000e18));
        uint128 debtAmount = uint128(bound(debtSeed_, 1, 1_000e9));
        uint256 maxFee = 10_000e18;
        _COLLATERAL.mint(actor, uint256(collateralAmount) + maxFee);

        uint256 supplyBefore = _OHM.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        uint256 debtBefore = _BURNER_LOANS.getPosition(address(_COLLATERAL), actor).debtOhm;
        IBurnerLoansComposites.DepositAndBorrowParams memory params = IBurnerLoansComposites
            .DepositAndBorrowParams({
                asset: address(_COLLATERAL),
                collateralAmount: collateralAmount,
                ohmAmount: debtAmount,
                recipient: actor,
                maxFee: maxFee
            });
        vm.prank(actor);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, ) = address(_COMPOSITES).call(
            abi.encodeCall(
                _COMPOSITES.depositAndBorrow,
                (_emptyAuthorization(), _emptySignature(), params)
            )
        );
        // forge-lint: disable-end(low-level-calls)
        if (!success) return;

        uint256 debtAfter = _BURNER_LOANS.getPosition(address(_COLLATERAL), actor).debtOhm;
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (
            _OHM.totalSupply() - supplyBefore + (idleBefore - idleAfter) != debtAfter - debtBefore
        ) {
            ++fundingDebtViolations;
        }
        _probeSameBlockRepay(actor);
        _checkBacking();
    }

    function compositeRepayAndWithdraw(
        uint256 actorSeed_,
        uint128 repaySeed_,
        uint128 withdrawSeed_
    ) external {
        address actor = _actor(actorSeed_);
        CompositeRepayObservation memory observation;
        observation.beforePosition = _BURNER_LOANS.getPosition(address(_COLLATERAL), actor);
        uint256 available = _OHM.balanceOf(actor) < observation.beforePosition.debtOhm
            ? _OHM.balanceOf(actor)
            : observation.beforePosition.debtOhm;
        uint128 repayAmount = available == 0 ? 0 : uint128(bound(repaySeed_, 1, available));
        uint128 withdrawAmount = observation.beforePosition.depositedCollateral == 0
            ? 0
            : uint128(bound(withdrawSeed_, 0, observation.beforePosition.depositedCollateral));
        if (repayAmount == 0 && withdrawAmount == 0) return;
        if (repayAmount != 0 && block.number <= observation.beforePosition.lastBorrowBlock) {
            vm.roll(uint256(observation.beforePosition.lastBorrowBlock) + 1);
        }

        observation.supplyBefore = _OHM.totalSupply();
        observation.idleBefore = _inventory().suppliedIdleOhm();
        if (withdrawAmount != 0) {
            IERC20 outputToken = _outputToken();
            observation.withdrawal = CompositeWithdrawalObservation({
                outputToken: outputToken,
                recipientBalanceBefore: outputToken.balanceOf(actor)
            });
        }
        vm.prank(actor);
        _OHM.approve(address(_COMPOSITES), repayAmount);
        IBurnerLoansComposites.RepayAndWithdrawParams memory params = IBurnerLoansComposites
            .RepayAndWithdrawParams({
                asset: address(_COLLATERAL),
                maxRepayOhm: repayAmount,
                collateralAmount: withdrawAmount,
                recipient: actor
            });
        vm.prank(actor);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, bytes memory returnData) = address(_COMPOSITES).call(
            abi.encodeCall(
                _COMPOSITES.repayAndWithdraw,
                (_emptyAuthorization(), _emptySignature(), params)
            )
        );
        // forge-lint: disable-end(low-level-calls)
        if (!success) return;

        _checkCompositeRepayAndWithdraw(actor, params, observation, returnData);
    }

    function withdraw(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        uint256 deposited = _BURNER_LOANS
            .getPosition(address(_COLLATERAL), actor)
            .depositedCollateral;
        if (deposited == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, deposited));

        bool previewExecutable;
        address previewTokenOut;
        uint256 previewAmountOut;
        try _BURNER_LOANS.previewWithdrawCollateral(address(_COLLATERAL), amount, actor) returns (
            IBurnerLoans.WithdrawPreview memory preview_
        ) {
            previewExecutable = preview_.executable;
            previewTokenOut = preview_.returnToken;
            previewAmountOut = preview_.returnAmount;
            if (previewTokenOut != address(_outputToken())) {
                ++withdrawalOutputConservationViolations;
            }
        } catch {
            return;
        }
        bool withdrawalModeValid = _withdrawalModeIsValid();

        uint256 recipientBalanceBefore = IERC20(previewTokenOut).balanceOf(actor);
        // Diagnostic counters intentionally update after observing this test-only external action.
        // forge-lint: disable-start(reentrancy-no-eth)
        vm.prank(actor);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, bytes memory returnData) = address(_BURNER_LOANS).call(
            abi.encodeCall(
                _BURNER_LOANS.withdrawCollateral,
                (address(_COLLATERAL), amount, actor, actor)
            )
        );
        // forge-lint: disable-end(low-level-calls)
        // forge-lint: disable-end(reentrancy-no-eth)
        if (!previewExecutable) {
            ++unexecutableWithdrawAttempts;
            if (success) ++unexpectedUnexecutableWithdrawSuccesses;
            return;
        }
        if (!success) {
            if (withdrawalModeValid) ++unexpectedWithdrawFailures;
            return;
        }

        uint256 recipientBalanceAfter = IERC20(previewTokenOut).balanceOf(actor);
        uint256 depositedAfter = _BURNER_LOANS
            .getPosition(address(_COLLATERAL), actor)
            .depositedCollateral;
        (address tokenOut, uint256 amountOut, uint256 remainingCollateral, ) = abi.decode(
            returnData,
            (address, uint256, uint256, uint256)
        );
        if (
            recipientBalanceAfter - recipientBalanceBefore != previewAmountOut ||
            deposited - depositedAfter != amount ||
            tokenOut != previewTokenOut ||
            amountOut != previewAmountOut ||
            remainingCollateral != depositedAfter
        ) ++withdrawalOutputConservationViolations;
    }

    function supplyInventory(uint128 amountSeed_) external {
        uint128 amount = uint128(bound(amountSeed_, 1, 1_000e9));
        IBurnerLoansInventory inventory_ = _inventory();
        _OHM.mint(_INVENTORY_PROVIDER, amount);
        vm.prank(_INVENTORY_PROVIDER);
        inventory_.supply(amount);
    }

    function withdrawInventory(uint128 amountSeed_) external {
        IBurnerLoansInventory inventory_ = _inventory();
        uint256 available = inventory_.providerClaimOhm(_INVENTORY_PROVIDER);
        uint256 idle = inventory_.suppliedIdleOhm();
        if (idle < available) available = idle;
        if (available == 0) return;

        vm.prank(_INVENTORY_PROVIDER);
        inventory_.withdraw(uint128(bound(amountSeed_, 1, available)), _INVENTORY_PROVIDER);
    }

    function extend(uint256 actorSeed_, uint16 termSeed_) external {
        address actor = _actor(actorSeed_);
        if (_BURNER_LOANS.getPosition(address(_COLLATERAL), actor).debtOhm == 0) return;
        uint16 termCount = uint16(bound(termSeed_, 1, 2));
        _COLLATERAL.mint(actor, 10_000e18);

        bool previewExecutable;
        try _BURNER_LOANS.previewExtend(address(_COLLATERAL), actor, termCount) returns (
            IBurnerLoans.ExtendPreview memory preview
        ) {
            previewExecutable = preview.executable;
        } catch {
            return;
        }

        vm.prank(actor);
        // Allows the invariant handler to record action failure without reverting.
        // forge-lint: disable-start(low-level-calls)
        (bool success, ) = address(_BURNER_LOANS).call(
            abi.encodeCall(
                _BURNER_LOANS.extend,
                (address(_COLLATERAL), actor, termCount, type(uint256).max)
            )
        );
        // forge-lint: disable-end(low-level-calls)
        if (!previewExecutable) {
            ++unexecutableExtendAttempts;
            if (success) ++unexpectedUnexecutableExtendSuccesses;
            return;
        }
        if (!success) ++unexpectedExtendFailures;
    }

    function moveOhmPrice(uint256 priceSeed_) external {
        _PRICE.setPrice(address(_OHM), bound(priceSeed_, 5e18, 30e18));
        _PRICE.setTimestamp(uint48(block.timestamp));
    }

    function moveCollateralPrice(uint256 priceSeed_) external {
        collateralPrice = bound(priceSeed_, 1e18, 2e18);
        _PRICE.setPrice(address(_COLLATERAL), collateralPrice);
        _PRICE.setTimestamp(uint48(block.timestamp));
    }

    function moveTime(uint48 timeSeed_) external {
        vm.warp(block.timestamp + bound(timeSeed_, 1, 45 days));
        vm.roll(block.number + 1);
        _PRICE.setTimestamp(uint48(block.timestamp));
    }

    function configurePriceCache(
        uint8 modeSeed_,
        uint48 priceCacheMaxAge_,
        bool warmCache_
    ) external {
        uint8 mode = modeSeed_ % 5;
        PriceCache selectedCache = mode < 3 ? _PRIMARY_PRICE_CACHE : _SECONDARY_PRICE_CACHE;
        bool useCache = mode != 0;
        bool operational = mode == 1 || mode == 3;

        vm.startPrank(_ADMIN);
        if (useCache && !selectedCache.isEnabled()) selectedCache.enable("");
        _BURNER_LOANS.setPriceCache(useCache ? address(selectedCache) : address(0));
        _BURNER_LOANS_CONFIG.setPriceCacheMaxAge(priceCacheMaxAge_);
        vm.stopPrank();

        if (useCache && warmCache_) {
            selectedCache.cachePrice(address(_OHM), address(_COLLATERAL));
        }

        if (useCache && !operational) {
            vm.prank(_ADMIN);
            selectedCache.disable("");
        }
    }

    function seize() external {
        try _BURNER_LOANS.getSeizableBorrowers(address(_COLLATERAL), 0, 8, 4) returns (
            address[] memory borrowers,
            uint256,
            uint256
        ) {
            if (borrowers.length == 0) return;
            for (uint256 i; i < borrowers.length; ++i) {
                if (!_BURNER_LOANS.isSeizable(address(_COLLATERAL), borrowers[i])) {
                    ++seizureEligibilityViolations;
                }
            }
            IBurnerLoans.SeizePreview memory preview = _BURNER_LOANS.previewSeize(
                address(_COLLATERAL),
                borrowers
            );
            if (preview.tokenOut != address(_outputToken())) {
                ++seizureOutputConservationViolations;
            }
            uint256 keeperBalanceBefore = IERC20(preview.tokenOut).balanceOf(address(this));
            uint256 treasuryBalanceBefore = IERC20(preview.tokenOut).balanceOf(_TREASURY);
            // Diagnostic counters intentionally update after observing this test-only external action.
            // forge-lint: disable-next-line(reentrancy-no-eth)
            try _BURNER_LOANS.seize(address(_COLLATERAL), borrowers) returns (
                address tokenOut,
                uint256 keeperAmount,
                uint256 treasuryAmount
            ) {
                // Exact balance deltas enforce seizure output conservation in this invariant.
                // forge-lint: disable-start(incorrect-strict-equality)
                if (
                    tokenOut != preview.tokenOut ||
                    IERC20(tokenOut).balanceOf(address(this)) - keeperBalanceBefore !=
                    keeperAmount ||
                    IERC20(tokenOut).balanceOf(_TREASURY) - treasuryBalanceBefore !=
                    treasuryAmount ||
                    keeperAmount + treasuryAmount !=
                    preview.keeperReward + preview.collateralToTreasury
                ) ++seizureOutputConservationViolations;
                // forge-lint: disable-end(incorrect-strict-equality)
                _checkSeizureClosure(borrowers);
                _checkBacking();
            } catch {}
        } catch {}
    }

    function reuseDebtFreePosition(uint256 actorSeed_) external {
        address actor = _actor(actorSeed_);
        uint32 marketId = _BURNER_LOANS_CONFIG.marketId(address(_COLLATERAL));
        (bool exists, uint64 positionIdBefore) = BurnerLoansPositions.find(_FLOAN, marketId, actor);
        if (!exists) return;
        if (!_canReuseDebtFreePosition(positionIdBefore)) return;

        uint256 positionCountBefore = _FLOAN.getPositionCount();
        _COLLATERAL.mint(actor, 200e18);
        vm.prank(actor);
        try _BURNER_LOANS.depositCollateral(address(_COLLATERAL), 100e18, actor) {} catch {
            ++positionReuseViolations;
            return;
        }

        try _BURNER_LOANS.previewBorrow(address(_COLLATERAL), uint128(_OHM_SCALE), actor) returns (
            IBurnerLoans.BorrowPreview memory preview
        ) {
            if (!preview.executable) ++unexecutableBorrowAttempts;

            vm.prank(actor);
            try
                _BURNER_LOANS.borrow(
                    address(_COLLATERAL),
                    uint128(_OHM_SCALE),
                    actor,
                    actor,
                    preview.fee
                )
            {
                if (!preview.executable) {
                    ++unexpectedUnexecutableBorrowSuccesses;
                    return;
                }
            } catch {
                if (!preview.executable) return;
                ++positionReuseViolations;
                return;
            }
        } catch {
            ++positionReuseViolations;
            return;
        }

        IFLOANv1.Position memory positionAfter = _FLOAN.getPosition(positionIdBefore);
        if (
            _FLOAN.getPositionCount() != positionCountBefore ||
            positionAfter.principalDue != _OHM_SCALE
        ) {
            ++positionReuseViolations;
        }
        _probeSameBlockRepay(actor);
        _checkBacking();
    }

    function _canReuseDebtFreePosition(uint64 positionId_) private view returns (bool) {
        if (_FLOAN.getPosition(positionId_).principalDue != 0) return false;

        IBurnerLoans.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(
            address(_COLLATERAL)
        );
        if (!config.originationsEnabled) return false;
        if (
            _BURNER_LOANS.totalActiveDebtOhm() + _OHM_SCALE >
            IBurnerLoansInventory(_BURNER_LOANS.inventory()).globalDebtCapOhm()
        ) {
            return false;
        }

        return
            _BURNER_LOANS.assetActiveDebtOhm(address(_COLLATERAL)) + _OHM_SCALE <= config.debtCap;
    }

    function executePeriodicSeizer() external {
        _SEIZER.execute();
        _checkBacking();
    }

    function addYield(uint128 amountSeed_) external {
        IAssetManager.AssetConfiguration memory configuration = _DEPOSIT_MANAGER
            .getAssetConfiguration(IERC20(address(_COLLATERAL)));
        address recipient = configuration.vault == address(0)
            ? address(_DEPOSIT_MANAGER)
            : configuration.vault;
        _COLLATERAL.mint(recipient, bound(amountSeed_, 1, 10_000e18));
    }

    function claimAssetYield() external {
        ClaimObservation memory observation = _claimYieldObservation();
        observation = _probeClaimYieldPreview(observation);

        // Allows the invariant handler to inspect both success and failure outcomes.
        // Diagnostic counters intentionally update after observing this test-only external action.
        // forge-lint: disable-start(reentrancy-no-eth)
        // forge-lint: disable-start(low-level-calls)
        (bool success, bytes memory returnData) = address(_BURNER_LOANS).call(
            abi.encodeWithSelector(bytes4(keccak256("claimYield(address)")), address(_COLLATERAL))
        );
        // forge-lint: disable-end(low-level-calls)
        // forge-lint: disable-end(reentrancy-no-eth)
        if (success) {
            _checkSuccessfulClaimYield(observation, returnData);
        } else {
            _checkFailedClaimYield(observation);
        }
    }

    function setYieldAssetRouting(
        uint16 repurchaseBpsSeed_,
        uint16 directBpsSeed_,
        uint8 directCountSeed_
    ) external {
        IBurnerLoans.AssetYieldRouting memory routing;
        uint256 directCount = bound(directCountSeed_, 0, _directYieldRecipients.length);
        bool repurchaseRecipientConfigured = _BURNER_LOANS.getYieldRepurchaseRecipient() !=
            address(0);
        uint256 maximumRepurchaseBps = BurnerLoansConstants.MAX_BPS - directCount;
        uint256 repurchaseBps = repurchaseRecipientConfigured
            ? bound(repurchaseBpsSeed_, 0, maximumRepurchaseBps)
            : 0;
        uint256 remainingBps = BurnerLoansConstants.MAX_BPS - repurchaseBps;
        uint256 directBps = directCount == 0 ? 0 : bound(directBpsSeed_, directCount, remainingBps);

        routing.repurchaseRecipientBps = uint16(repurchaseBps);
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](directCount);
        for (uint256 i; i < directCount; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: _directYieldRecipients[i],
                bps: uint16(i == 0 ? directBps - directCount + 1 : 1)
            });
        }

        bytes32 priorHash = keccak256(
            abi.encode(_BURNER_LOANS.getYieldAssetRouting(address(_COLLATERAL)))
        );
        vm.prank(_ADMIN);
        try _BURNER_LOANS_CONFIG.setYieldAssetRouting(address(_COLLATERAL), routing) {
            modelActiveRepurchaseRouteCount = routing.repurchaseRecipientBps == 0 ? 0 : 1;
            modelAssetYieldRoutingHash = keccak256(abi.encode(routing));
        } catch {
            if (
                priorHash !=
                keccak256(abi.encode(_BURNER_LOANS.getYieldAssetRouting(address(_COLLATERAL))))
            ) {
                ++routingFailureMutationViolations;
            }
        }
    }

    function setYieldRepurchaseRecipient(bool configure_) external {
        address requestedRecipient = configure_ ? address(_YIELD_RECIPIENT) : address(0);
        address priorRecipient = _BURNER_LOANS.getYieldRepurchaseRecipient();
        bytes32 priorRouteHash = keccak256(
            abi.encode(_BURNER_LOANS.getYieldAssetRouting(address(_COLLATERAL)))
        );

        vm.prank(_ADMIN);
        try _BURNER_LOANS_CONFIG.setYieldRepurchaseRecipient(requestedRecipient) {
            if (!configure_ && modelActiveRepurchaseRouteCount != 0) {
                ++repurchaseRecipientClearViolations;
            }
            modelYieldRepurchaseRecipient = requestedRecipient;
        } catch {
            if (
                _BURNER_LOANS.getYieldRepurchaseRecipient() != priorRecipient ||
                keccak256(abi.encode(_BURNER_LOANS.getYieldAssetRouting(address(_COLLATERAL)))) !=
                priorRouteHash
            ) ++routingFailureMutationViolations;
            if (!configure_ && modelActiveRepurchaseRouteCount == 0) {
                ++repurchaseRecipientClearViolations;
            }
        }
    }

    function toggleYieldRecipient(bool enable_) external {
        _YIELD_RECIPIENT.setEnabled(enable_);
    }

    function toggleAsset(bool enable_) external {
        IBurnerLoans.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(
            address(_COLLATERAL)
        );
        if (enable_ == config.originationsEnabled) return;
        vm.prank(_ADMIN);
        if (enable_) {
            try
                _BURNER_LOANS_CONFIG.setAssetOriginationsEnabled(address(_COLLATERAL), true)
            {} catch {}
        } else {
            try
                _BURNER_LOANS_CONFIG.setAssetOriginationsEnabled(address(_COLLATERAL), false)
            {} catch {}
        }
    }

    function toggleWithdrawAsShares(bool withdrawAsShares_) external {
        IBurnerLoans.AssetConfig memory beforeConfig = _BURNER_LOANS_CONFIG.getAssetConfig(
            address(_COLLATERAL)
        );
        if (beforeConfig.withdrawAsShares == withdrawAsShares_) return;

        vm.prank(_ADMIN);
        try _BURNER_LOANS_CONFIG.setAssetWithdrawAsShares(address(_COLLATERAL), withdrawAsShares_) {
            if (
                _BURNER_LOANS_CONFIG.getAssetConfig(address(_COLLATERAL)).withdrawAsShares !=
                withdrawAsShares_
            ) ++withdrawAsSharesTransitionViolations;
        } catch {
            if (
                _BURNER_LOANS_CONFIG.getAssetConfig(address(_COLLATERAL)).withdrawAsShares !=
                beforeConfig.withdrawAsShares
            ) ++withdrawAsSharesTransitionViolations;
        }
    }

    function _actor(uint256 seed_) private view returns (address) {
        return _actors[seed_ % _actors.length];
    }

    function _inventory() private view returns (IBurnerLoansInventory) {
        return IBurnerLoansInventory(_BURNER_LOANS.inventory());
    }

    function _directYieldRecipientBalances(
        IERC20 token_
    ) private view returns (uint256[5] memory balances) {
        for (uint256 i; i < _directYieldRecipients.length; ++i) {
            balances[i] = token_.balanceOf(_directYieldRecipients[i]);
        }
    }

    function _checkCompositeRepayAndWithdraw(
        address actor_,
        IBurnerLoansComposites.RepayAndWithdrawParams memory params_,
        CompositeRepayObservation memory observation_,
        bytes memory returnData_
    ) private {
        IBurnerLoans.Position memory afterPosition = _BURNER_LOANS.getPosition(
            address(_COLLATERAL),
            actor_
        );
        uint256 repaid = observation_.beforePosition.debtOhm - afterPosition.debtOhm;
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (
            observation_.supplyBefore -
                _OHM.totalSupply() +
                (idleAfter - observation_.idleBefore) !=
            repaid
        ) {
            ++repaymentBurnViolations;
        }
        if (repaid != params_.maxRepayOhm) ++repaymentDebtViolations;
        if (
            observation_.beforePosition.depositedCollateral - afterPosition.depositedCollateral !=
            params_.collateralAmount
        ) {
            ++repaymentCollateralViolations;
        }
        if (params_.collateralAmount != 0) {
            _checkCompositeWithdrawalOutput(
                actor_,
                observation_.withdrawal,
                returnData_,
                afterPosition.depositedCollateral
            );
        }
    }

    function _checkCompositeWithdrawalOutput(
        address actor_,
        CompositeWithdrawalObservation memory observation_,
        bytes memory returnData_,
        uint256 remainingCollateral_
    ) private {
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = abi.decode(
            returnData_,
            (IBurnerLoansComposites.RepayAndWithdrawResult)
        );
        // Exact balance deltas enforce composite output conservation and zero residual custody.
        // forge-lint: disable-start(incorrect-strict-equality)
        if (
            result.tokenOut != address(observation_.outputToken) ||
            result.remainingCollateral != remainingCollateral_ ||
            observation_.outputToken.balanceOf(actor_) - observation_.recipientBalanceBefore !=
            result.amountOut ||
            observation_.outputToken.balanceOf(address(_COMPOSITES)) != 0
        ) ++compositeWithdrawalOutputConservationViolations;
        // forge-lint: disable-end(incorrect-strict-equality)
    }

    function _claimYieldObservation() private view returns (ClaimObservation memory observation) {
        observation.collateralStatus = _BURNER_LOANS.getAssetCollateralStatus(address(_COLLATERAL));
        observation.outputToken = _outputToken();
        observation.withdrawalModeValid = _withdrawalModeIsValid();
        observation.treasuryBalance = observation.outputToken.balanceOf(_TREASURY);
        observation.repurchaseBalance = observation.outputToken.balanceOf(
            address(_YIELD_RECIPIENT)
        );
        observation.facilityBalance = observation.outputToken.balanceOf(address(_BURNER_LOANS));
        observation.directBalances = _directYieldRecipientBalances(observation.outputToken);
        observation.routeHash = keccak256(
            abi.encode(_BURNER_LOANS.getYieldAssetRouting(address(_COLLATERAL)))
        );
        observation.globalRecipient = _BURNER_LOANS.getYieldRepurchaseRecipient();
    }

    function _probeClaimYieldPreview(
        ClaimObservation memory observation_
    ) private returns (ClaimObservation memory) {
        try _BURNER_LOANS.previewClaimYield(address(_COLLATERAL)) returns (
            IBurnerLoans.ClaimYieldPreview memory preview_
        ) {
            observation_.previewReturned = true;
            observation_.previewExecutable = preview_.executable;
            observation_.previewRequestedAssets = preview_.requestedAssetAmount;
            observation_.previewAmountOut = preview_.amountOut;
            if (preview_.tokenOut != address(observation_.outputToken)) {
                ++claimYieldPreviewConsistencyViolations;
            }
        } catch {}
        return observation_;
    }

    function _checkSuccessfulClaimYield(
        ClaimObservation memory observation_,
        bytes memory returnData_
    ) private {
        (address tokenOut, uint256 amountOut) = abi.decode(returnData_, (address, uint256));
        uint256 distributed = observation_.outputToken.balanceOf(_TREASURY) -
            observation_.treasuryBalance +
            observation_.outputToken.balanceOf(address(_YIELD_RECIPIENT)) -
            observation_.repurchaseBalance;
        for (uint256 i; i < _directYieldRecipients.length; ++i) {
            distributed +=
                observation_.outputToken.balanceOf(_directYieldRecipients[i]) -
                observation_.directBalances[i];
        }
        if (!_yieldRequestIsCovered(observation_)) ++claimYieldBoundViolations;
        if (distributed != amountOut || tokenOut != address(observation_.outputToken)) {
            ++claimYieldConservationViolations;
        }
        cumulativeClaimedYield += amountOut;
        cumulativeDistributedYield += distributed;
        // Exact equality detects residual output tokens held by Burner Loans.
        // forge-lint: disable-start(incorrect-strict-equality)
        if (
            observation_.outputToken.balanceOf(address(_BURNER_LOANS)) !=
            observation_.facilityBalance
        ) {
            ++claimYieldResidualViolations;
        }
        // forge-lint: disable-end(incorrect-strict-equality)
        if (
            !observation_.previewReturned ||
            !observation_.previewExecutable ||
            observation_.previewAmountOut != amountOut
        ) {
            ++claimYieldPreviewConsistencyViolations;
        }
    }

    function _checkFailedClaimYield(ClaimObservation memory observation_) private {
        if (_claimYieldStateChanged(observation_)) ++claimYieldFailureMutationViolations;
        if (
            observation_.withdrawalModeValid &&
            observation_.previewReturned &&
            observation_.previewExecutable
        ) {
            ++claimYieldPreviewConsistencyViolations;
        }
    }

    function _claimYieldStateChanged(
        ClaimObservation memory observation_
    ) private view returns (bool mutated) {
        IBurnerLoans.AssetCollateralStatus memory afterStatus = _BURNER_LOANS
            .getAssetCollateralStatus(address(_COLLATERAL));
        // Atomic failure must restore every observed balance exactly.
        // forge-lint: disable-start(incorrect-strict-equality)
        mutated =
            keccak256(abi.encode(observation_.collateralStatus)) !=
            keccak256(abi.encode(afterStatus)) ||
            observation_.outputToken.balanceOf(_TREASURY) != observation_.treasuryBalance ||
            observation_.outputToken.balanceOf(address(_YIELD_RECIPIENT)) !=
            observation_.repurchaseBalance ||
            observation_.outputToken.balanceOf(address(_BURNER_LOANS)) !=
            observation_.facilityBalance ||
            observation_.routeHash !=
            keccak256(abi.encode(_BURNER_LOANS.getYieldAssetRouting(address(_COLLATERAL)))) ||
            observation_.globalRecipient != _BURNER_LOANS.getYieldRepurchaseRecipient();
        for (uint256 i; i < _directYieldRecipients.length; ++i) {
            if (
                observation_.outputToken.balanceOf(_directYieldRecipients[i]) !=
                observation_.directBalances[i]
            ) {
                mutated = true;
            }
        }
        // forge-lint: disable-end(incorrect-strict-equality)
    }

    function _outputToken() private view returns (IERC20) {
        IBurnerLoans.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(
            address(_COLLATERAL)
        );
        return
            IAssetManagerV1_1(address(_DEPOSIT_MANAGER)).getAssetWithdrawalToken(
                IERC20(address(_COLLATERAL)),
                config.withdrawAsShares
            );
    }

    function _withdrawalModeIsValid() private view returns (bool) {
        IBurnerLoans.AssetConfig memory config = _BURNER_LOANS_CONFIG.getAssetConfig(
            address(_COLLATERAL)
        );
        try
            IAssetManagerV1_1(address(_DEPOSIT_MANAGER)).validateAssetWithdrawAsShares(
                IERC20(address(_COLLATERAL)),
                config.withdrawAsShares
            )
        {
            return true;
        } catch {
            return false;
        }
    }

    function _yieldRequestIsCovered(
        ClaimObservation memory observation_
    ) private view returns (bool) {
        uint256 request = observation_.previewRequestedAssets;
        IBurnerLoans.AssetCollateralStatus memory status = observation_.collateralStatus;
        if (request > status.assets) return false;
        if (status.liabilities > status.assets + status.borrowed - request) return false;
        if (!_BURNER_LOANS_CONFIG.getAssetConfig(address(_COLLATERAL)).withdrawAsShares) {
            return request <= status.claimableYield;
        }
        return true;
    }

    function _probeSameBlockRepay(address actor_) private {
        vm.startPrank(actor_);
        _OHM.approve(address(_BURNER_LOANS), 1);
        // Allows the invariant handler to detect an unexpected successful action.
        // forge-lint: disable-start(low-level-calls)
        (bool success, ) = address(_BURNER_LOANS).call(
            abi.encodeCall(_BURNER_LOANS.repay, (address(_COLLATERAL), uint128(1), actor_))
        );
        // forge-lint: disable-end(low-level-calls)
        vm.stopPrank();
        if (success) ++sameBlockRepayViolations;
    }

    function _emptyAuthorization()
        private
        pure
        returns (IOperatorAuth.Authorization memory authorization)
    {
        return authorization;
    }

    function _emptySignature() private pure returns (IOperatorAuth.Signature memory signature) {
        return signature;
    }

    function _checkBacking() private {
        IBurnerLoans.AssetCollateralStatus memory status = _BURNER_LOANS.getAssetCollateralStatus(
            address(_COLLATERAL)
        );
        uint256 liquidCollateral = status.assets + status.borrowed + _balanceInAssets(_TREASURY);
        // liquidCollateral: collateral decimals; collateralPrice: 18 decimals.
        // Expected: collateral decimals + 18 - collateral decimals = 18-decimal USD value,
        // rounded down.
        uint256 liquidBackingUsd = FullMath.mulDiv(
            liquidCollateral,
            collateralPrice,
            _COLLATERAL_SCALE
        );
        uint256 totalBackedDebt = _BURNER_LOANS.totalActiveDebtOhm() +
            _FLOAN.getMarketPrincipalDefaulted(_BURNER_LOANS_CONFIG.marketId(address(_COLLATERAL)));
        // totalBackedDebt: 9 decimals; backing floor: 18 decimals per OHM.
        // Expected: 9 + 18 - 9 = 18-decimal required backing, rounded down.
        uint256 requiredBackingUsd = FullMath.mulDiv(totalBackedDebt, _WAD, _OHM_SCALE);
        if (liquidBackingUsd < requiredBackingUsd) ++backingViolations;
    }

    function _balanceInAssets(address account_) private view returns (uint256) {
        IAssetManager.AssetConfiguration memory configuration = _DEPOSIT_MANAGER
            .getAssetConfiguration(IERC20(address(_COLLATERAL)));
        if (configuration.vault == address(0)) return _COLLATERAL.balanceOf(account_);
        return
            _COLLATERAL.balanceOf(account_) +
            IERC4626(configuration.vault).previewRedeem(
                IERC20(configuration.vault).balanceOf(account_)
            );
    }

    function _checkSeizureClosure(address[] memory borrowers_) private {
        uint32 marketId = _BURNER_LOANS_CONFIG.marketId(address(_COLLATERAL));
        address[] memory activeBorrowers = _BURNER_LOANS.getActiveBorrowers(address(_COLLATERAL));

        for (uint256 i; i < borrowers_.length; ++i) {
            address borrower = borrowers_[i];
            (bool exists, uint64 positionId) = BurnerLoansPositions.find(
                _FLOAN,
                marketId,
                borrower
            );
            bool invalidClosure = !exists;

            if (!invalidClosure) {
                IFLOANv1.Position memory floanPosition = _FLOAN.getPosition(positionId);
                invalidClosure =
                    floanPosition.collateral != 0 ||
                    floanPosition.principalDrawn != 0 ||
                    floanPosition.principalDue != 0 ||
                    floanPosition.interestDue != 0 ||
                    floanPosition.maturity != 0 ||
                    floanPosition.lastBorrowBlock != 0;
            }

            for (uint256 j; j < activeBorrowers.length; ++j) {
                if (activeBorrowers[j] != borrower) continue;
                invalidClosure = true;
                break;
            }
            if (invalidClosure) ++seizureClosureViolations;
        }
    }
}

// forge-lint: disable-end(unused-return,unsafe-typecast,calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
