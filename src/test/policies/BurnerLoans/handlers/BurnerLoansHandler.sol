// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {BurnerLoansPositions} from "src/policies/libraries/BurnerLoansPositions.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";
import {BurnerLoansComposites} from "src/periphery/BurnerLoansComposites.sol";
import {BurnerLoansConfig} from "src/policies/BurnerLoansConfig.sol";
import {BurnerLoansSeizer} from "src/policies/BurnerLoansSeizer.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";
import {MockYieldRecipient} from "src/test/policies/BurnerLoans/fixtures/MockYieldRecipient.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";

contract BurnerLoansHandler is Test {
    uint256 internal constant _WAD = 1e18;
    uint256 internal constant _OHM_SCALE = 1e9;

    BurnerLoansHarness public immutable burnerLoans;
    BurnerLoansConfig public immutable burnerLoansConfig;
    BurnerLoansComposites public immutable composites;
    OlympusFixedTermLoan public immutable floan;
    BurnerLoansSeizer public immutable seizer;
    MockPrice public immutable price;
    MockOhm public immutable ohm;
    MockERC20 public immutable collateral;
    IDepositManager public immutable depositManager;
    address public immutable admin;
    address public immutable treasury;
    address public immutable inventoryProvider;
    MockYieldRecipient public immutable yieldRecipient;

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
    uint256 public sameBlockRepayViolations;
    uint256 public claimYieldBoundViolations;
    uint256 public claimYieldConservationViolations;
    uint256 public claimYieldResidualViolations;
    uint256 public backingViolations;
    uint256 public seizureEligibilityViolations;
    uint256 public seizureClosureViolations;
    uint256 public positionReuseViolations;

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
        MockYieldRecipient yieldRecipient;
        address[] actors;
    }

    constructor(Dependencies memory dependencies_) {
        burnerLoans = dependencies_.burnerLoans;
        burnerLoansConfig = dependencies_.burnerLoansConfig;
        composites = dependencies_.composites;
        floan = dependencies_.floan;
        seizer = dependencies_.seizer;
        price = dependencies_.price;
        ohm = dependencies_.ohm;
        collateral = dependencies_.collateral;
        depositManager = dependencies_.depositManager;
        admin = dependencies_.admin;
        treasury = dependencies_.treasury;
        inventoryProvider = dependencies_.inventoryProvider;
        yieldRecipient = dependencies_.yieldRecipient;
        _actors = dependencies_.actors;

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
        collateral.mint(actor, amount);

        try burnerLoans.previewDepositCollateral(address(collateral), amount, actor) returns (
            uint256,
            uint256
        ) {} catch {
            return;
        }

        vm.prank(actor);
        (bool success, ) = address(burnerLoans).call(
            abi.encodeCall(burnerLoans.depositCollateral, (address(collateral), amount, actor))
        );
        if (!success) ++unexpectedDepositFailures;
    }

    function borrow(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        uint128 amount = uint128(bound(amountSeed_, 1, 1_000e9));
        collateral.mint(actor, 10_000e18);

        try burnerLoans.previewBorrow(address(collateral), amount, actor) returns (
            IBurnerLoans.BorrowPreview memory
        ) {} catch {
            return;
        }

        uint256 supplyBefore = ohm.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        uint256 debtBefore = burnerLoans.getPosition(address(collateral), actor).debtOhm;
        vm.prank(actor);
        (bool success, ) = address(burnerLoans).call(
            abi.encodeCall(
                burnerLoans.borrow,
                (address(collateral), amount, actor, actor, type(uint256).max)
            )
        );
        if (!success) {
            ++unexpectedBorrowFailures;
            return;
        }

        uint256 debtAfter = burnerLoans.getPosition(address(collateral), actor).debtOhm;
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (ohm.totalSupply() - supplyBefore + (idleBefore - idleAfter) != debtAfter - debtBefore) {
            ++fundingDebtViolations;
        }
        _probeSameBlockRepay(actor);
        _checkBacking();
    }

    function repay(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(
            address(collateral),
            actor
        );
        uint256 available = ohm.balanceOf(actor) < beforePosition.debtOhm
            ? ohm.balanceOf(actor)
            : beforePosition.debtOhm;
        if (available == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, available));
        if (block.number <= beforePosition.lastBorrowBlock) {
            vm.roll(uint256(beforePosition.lastBorrowBlock) + 1);
        }

        uint256 supplyBefore = ohm.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        vm.startPrank(actor);
        ohm.approve(address(burnerLoans), amount);
        (bool success, ) = address(burnerLoans).call(
            abi.encodeCall(burnerLoans.repay, (address(collateral), amount, actor))
        );
        vm.stopPrank();
        if (!success) {
            ++unexpectedRepayFailures;
            return;
        }

        IBurnerLoans.Position memory afterPosition = burnerLoans.getPosition(
            address(collateral),
            actor
        );
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (supplyBefore - ohm.totalSupply() + (idleAfter - idleBefore) != amount) {
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
        collateral.mint(actor, uint256(collateralAmount) + maxFee);

        uint256 supplyBefore = ohm.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        uint256 debtBefore = burnerLoans.getPosition(address(collateral), actor).debtOhm;
        IBurnerLoansComposites.DepositAndBorrowParams memory params = IBurnerLoansComposites
            .DepositAndBorrowParams({
                asset: address(collateral),
                collateralAmount: collateralAmount,
                ohmAmount: debtAmount,
                recipient: actor,
                maxFee: maxFee
            });
        vm.prank(actor);
        (bool success, ) = address(composites).call(
            abi.encodeCall(
                composites.depositAndBorrow,
                (_emptyAuthorization(), _emptySignature(), params)
            )
        );
        if (!success) return;

        uint256 debtAfter = burnerLoans.getPosition(address(collateral), actor).debtOhm;
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (ohm.totalSupply() - supplyBefore + (idleBefore - idleAfter) != debtAfter - debtBefore) {
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
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(
            address(collateral),
            actor
        );
        uint256 available = ohm.balanceOf(actor) < beforePosition.debtOhm
            ? ohm.balanceOf(actor)
            : beforePosition.debtOhm;
        uint128 repayAmount = available == 0 ? 0 : uint128(bound(repaySeed_, 1, available));
        uint128 withdrawAmount = beforePosition.depositedCollateral == 0
            ? 0
            : uint128(bound(withdrawSeed_, 0, beforePosition.depositedCollateral));
        if (repayAmount == 0 && withdrawAmount == 0) return;
        if (repayAmount != 0 && block.number <= beforePosition.lastBorrowBlock) {
            vm.roll(uint256(beforePosition.lastBorrowBlock) + 1);
        }

        uint256 supplyBefore = ohm.totalSupply();
        uint256 idleBefore = _inventory().suppliedIdleOhm();
        vm.prank(actor);
        ohm.approve(address(composites), repayAmount);
        IBurnerLoansComposites.RepayAndWithdrawParams memory params = IBurnerLoansComposites
            .RepayAndWithdrawParams({
                asset: address(collateral),
                maxRepayOhm: repayAmount,
                collateralAmount: withdrawAmount,
                recipient: actor
            });
        vm.prank(actor);
        (bool success, ) = address(composites).call(
            abi.encodeCall(
                composites.repayAndWithdraw,
                (_emptyAuthorization(), _emptySignature(), params)
            )
        );
        if (!success) return;

        IBurnerLoans.Position memory afterPosition = burnerLoans.getPosition(
            address(collateral),
            actor
        );
        uint256 repaid = beforePosition.debtOhm - afterPosition.debtOhm;
        uint256 idleAfter = _inventory().suppliedIdleOhm();
        if (supplyBefore - ohm.totalSupply() + (idleAfter - idleBefore) != repaid) {
            ++repaymentBurnViolations;
        }
        if (repaid != repayAmount) ++repaymentDebtViolations;
        if (
            beforePosition.depositedCollateral - afterPosition.depositedCollateral != withdrawAmount
        ) {
            ++repaymentCollateralViolations;
        }
    }

    function withdraw(uint256 actorSeed_, uint128 amountSeed_) external {
        address actor = _actor(actorSeed_);
        uint256 deposited = burnerLoans.getPosition(address(collateral), actor).depositedCollateral;
        if (deposited == 0) return;
        uint128 amount = uint128(bound(amountSeed_, 1, deposited));

        IBurnerLoans.WithdrawPreview memory preview;
        try burnerLoans.previewWithdrawCollateral(address(collateral), amount, actor) returns (
            IBurnerLoans.WithdrawPreview memory preview_
        ) {
            preview = preview_;
        } catch {
            return;
        }
        if (!preview.executable) return;

        vm.prank(actor);
        (bool success, ) = address(burnerLoans).call(
            abi.encodeCall(
                burnerLoans.withdrawCollateral,
                (address(collateral), amount, actor, actor)
            )
        );
        if (!success) ++unexpectedWithdrawFailures;
    }

    function supplyInventory(uint128 amountSeed_) external {
        uint128 amount = uint128(bound(amountSeed_, 1, 1_000e9));
        IBurnerLoansInventory inventory_ = _inventory();
        ohm.mint(inventoryProvider, amount);
        vm.prank(inventoryProvider);
        inventory_.supply(amount);
    }

    function withdrawInventory(uint128 amountSeed_) external {
        IBurnerLoansInventory inventory_ = _inventory();
        uint256 available = inventory_.providerClaimOhm(inventoryProvider);
        uint256 idle = inventory_.suppliedIdleOhm();
        if (idle < available) available = idle;
        if (available == 0) return;

        vm.prank(inventoryProvider);
        inventory_.withdraw(uint128(bound(amountSeed_, 1, available)), inventoryProvider);
    }

    function extend(uint256 actorSeed_, uint16 termSeed_) external {
        address actor = _actor(actorSeed_);
        if (burnerLoans.getPosition(address(collateral), actor).debtOhm == 0) return;
        uint16 termCount = uint16(bound(termSeed_, 1, 2));
        collateral.mint(actor, 10_000e18);

        try burnerLoans.previewExtend(address(collateral), actor, termCount) returns (
            IBurnerLoans.ExtendPreview memory
        ) {} catch {
            return;
        }

        vm.prank(actor);
        (bool success, ) = address(burnerLoans).call(
            abi.encodeCall(
                burnerLoans.extend,
                (address(collateral), actor, termCount, type(uint256).max)
            )
        );
        if (!success) ++unexpectedExtendFailures;
    }

    function moveOhmPrice(uint256 priceSeed_) external {
        price.setPrice(address(ohm), bound(priceSeed_, 5e18, 30e18));
        price.setTimestamp(uint48(block.timestamp));
    }

    function moveCollateralPrice(uint256 priceSeed_) external {
        collateralPrice = bound(priceSeed_, 1e18, 2e18);
        price.setPrice(address(collateral), collateralPrice);
        price.setTimestamp(uint48(block.timestamp));
    }

    function moveTime(uint48 timeSeed_) external {
        vm.warp(block.timestamp + bound(timeSeed_, 1, 45 days));
        vm.roll(block.number + 1);
        price.setTimestamp(uint48(block.timestamp));
    }

    function seize() external {
        try burnerLoans.getSeizableBorrowers(address(collateral), 0, 8, 4) returns (
            address[] memory borrowers,
            uint256,
            uint256
        ) {
            if (borrowers.length == 0) return;
            for (uint256 i; i < borrowers.length; ++i) {
                if (!burnerLoans.isSeizable(address(collateral), borrowers[i])) {
                    ++seizureEligibilityViolations;
                }
            }
            try burnerLoans.seize(address(collateral), borrowers) {
                _checkSeizureClosure(borrowers);
                _checkBacking();
            } catch {}
        } catch {}
    }

    function reuseDebtFreePosition(uint256 actorSeed_) external {
        address actor = _actor(actorSeed_);
        uint32 marketId = burnerLoansConfig.marketId(address(collateral));
        (bool exists, uint64 positionIdBefore) = BurnerLoansPositions.find(floan, marketId, actor);
        if (!exists) return;
        if (floan.getPosition(positionIdBefore).principalDue != 0) return;

        IBurnerLoans.AssetConfig memory config = burnerLoansConfig.getAssetConfig(
            address(collateral)
        );
        if (!config.originationsEnabled) return;
        if (
            burnerLoans.totalActiveDebtOhm() + _OHM_SCALE >
            IBurnerLoansInventory(burnerLoans.inventory()).globalDebtCapOhm()
        ) {
            return;
        }
        if (burnerLoans.assetActiveDebtOhm(address(collateral)) + _OHM_SCALE > config.debtCap) {
            return;
        }

        uint256 positionCountBefore = floan.getPositionCount();
        collateral.mint(actor, 200e18);
        vm.prank(actor);
        try burnerLoans.depositCollateral(address(collateral), 100e18, actor) {} catch {
            ++positionReuseViolations;
            return;
        }

        try burnerLoans.previewBorrow(address(collateral), uint128(_OHM_SCALE), actor) returns (
            IBurnerLoans.BorrowPreview memory preview
        ) {
            vm.prank(actor);
            try
                burnerLoans.borrow(
                    address(collateral),
                    uint128(_OHM_SCALE),
                    actor,
                    actor,
                    preview.fee
                )
            {} catch {
                ++positionReuseViolations;
                return;
            }
        } catch {
            ++positionReuseViolations;
            return;
        }

        IFLOANv1.Position memory positionAfter = floan.getPosition(positionIdBefore);
        if (
            floan.getPositionCount() != positionCountBefore ||
            positionAfter.principalDue != _OHM_SCALE
        ) {
            ++positionReuseViolations;
        }
        _probeSameBlockRepay(actor);
        _checkBacking();
    }

    function executePeriodicSeizer() external {
        seizer.execute();
        _checkBacking();
    }

    function addYield(uint128 amountSeed_) external {
        collateral.mint(address(depositManager), bound(amountSeed_, 1, 10_000e18));
    }

    function claimYield() external {
        IBurnerLoans.AssetCollateralStatus memory beforeStatus = burnerLoans
            .getAssetCollateralStatus(address(collateral));
        uint256 treasuryBefore = collateral.balanceOf(treasury);
        uint256 recipientBefore = collateral.balanceOf(address(yieldRecipient));
        uint256 facilityBefore = collateral.balanceOf(address(burnerLoans));
        try burnerLoans.claimYield() {
            uint256 distributed = collateral.balanceOf(treasury) -
                treasuryBefore +
                collateral.balanceOf(address(yieldRecipient)) -
                recipientBefore;
            IBurnerLoans.AssetCollateralStatus memory afterStatus = burnerLoans
                .getAssetCollateralStatus(address(collateral));
            uint256 claimed = beforeStatus.assets - afterStatus.assets;
            if (claimed > beforeStatus.claimableYield) ++claimYieldBoundViolations;
            if (distributed != claimed) ++claimYieldConservationViolations;
            if (collateral.balanceOf(address(burnerLoans)) != facilityBefore) {
                ++claimYieldResidualViolations;
            }
        } catch {}
    }

    function setYieldBps(uint16 bpsSeed_) external {
        uint16 bps = uint16(bound(bpsSeed_, 0, 10_000));
        vm.prank(admin);
        try burnerLoansConfig.setYieldRecipientAssetBps(address(collateral), bps) {} catch {}
    }

    function toggleYieldRecipient(bool enable_) external {
        yieldRecipient.setEnabled(enable_);
    }

    function toggleAsset(bool enable_) external {
        IBurnerLoans.AssetConfig memory config = burnerLoansConfig.getAssetConfig(
            address(collateral)
        );
        if (enable_ == config.originationsEnabled) return;
        vm.prank(admin);
        if (enable_) {
            try burnerLoansConfig.setAssetOriginationsEnabled(address(collateral), true) {} catch {}
        } else {
            try
                burnerLoansConfig.setAssetOriginationsEnabled(address(collateral), false)
            {} catch {}
        }
    }

    function _actor(uint256 seed_) private view returns (address) {
        return _actors[seed_ % _actors.length];
    }

    function _inventory() private view returns (IBurnerLoansInventory) {
        return IBurnerLoansInventory(burnerLoans.inventory());
    }

    function _probeSameBlockRepay(address actor_) private {
        vm.startPrank(actor_);
        ohm.approve(address(burnerLoans), 1);
        (bool success, ) = address(burnerLoans).call(
            abi.encodeCall(burnerLoans.repay, (address(collateral), uint128(1), actor_))
        );
        vm.stopPrank();
        if (success) ++sameBlockRepayViolations;
    }

    function _emptyAuthorization()
        private
        pure
        returns (IOperatorAuth.Authorization memory authorization)
    {}

    function _emptySignature() private pure returns (IOperatorAuth.Signature memory signature) {}

    function _checkBacking() private {
        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(collateral)
        );
        uint256 liquidCollateral = status.assets + status.borrowed + collateral.balanceOf(treasury);
        uint256 liquidBackingUsd = FullMath.mulDiv(liquidCollateral, collateralPrice, _WAD);
        uint256 totalBackedDebt = burnerLoans.totalActiveDebtOhm() +
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(collateral)));
        uint256 requiredBackingUsd = FullMath.mulDiv(totalBackedDebt, _WAD, _OHM_SCALE);
        if (liquidBackingUsd < requiredBackingUsd) ++backingViolations;
    }

    function _checkSeizureClosure(address[] memory borrowers_) private {
        uint32 marketId = burnerLoansConfig.marketId(address(collateral));
        address[] memory activeBorrowers = burnerLoans.getActiveBorrowers(address(collateral));

        for (uint256 i; i < borrowers_.length; ++i) {
            address borrower = borrowers_[i];
            (bool exists, uint64 positionId) = BurnerLoansPositions.find(floan, marketId, borrower);
            bool invalidClosure = !exists;

            if (!invalidClosure) {
                IFLOANv1.Position memory floanPosition = floan.getPosition(positionId);
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
