// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansCoreBound} from "src/policies/interfaces/burnerloans/IBurnerLoansCoreBound.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC165Checker} from "@openzeppelin-5.7.0/utils/introspection/ERC165Checker.sol";
import {LoanCustody} from "src/policies/burnerloans/libraries/LoanCustody.sol";
import {LoanMarket} from "src/policies/burnerloans/libraries/LoanMarket.sol";
import {LoanPositions} from "src/policies/burnerloans/libraries/LoanPositions.sol";
import {BURNER_LOANS_SEIZER_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {ERC165} from "@openzeppelin-5.7.0/utils/introspection/ERC165.sol";
import {Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

/// @notice Read-only views and bounded scanning. Every economic quote uses Core's currently selected Risk.
contract BurnerLoansLens is ERC165, IBurnerLoansLens, IVersioned, IBurnerLoansCoreBound {
    uint256 private constant _WAD = 1e18;

    /// @notice Permanent accounting and dependency read boundary.
    IBurnerLoansCore internal immutable _CORE;

    /// @notice Binds deployment dependencies and initializes the local contract state.
    /// @dev Reverts if:
    ///      - Core does not support the required IBurnerLoansCore ERC165 interface.
    /// @param core_ Permanent accounting and DepositManager operator contract.
    constructor(address core_) {
        if (!ERC165Checker.supportsInterface(core_, type(IBurnerLoansCore).interfaceId))
            revert IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(core_);
        _CORE = IBurnerLoansCore(core_);
    }

    /// @inheritdoc IBurnerLoansCoreBound
    function core() external view override returns (address) {
        return address(_CORE);
    }

    /// @notice Returns the selected typed Risk implementation.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @return IBurnerLoansRisk Currently selected Risk implementation.
    function _risk() private view returns (IBurnerLoansRisk) {
        return IBurnerLoansRisk(_CORE.risk());
    }

    /// @notice Returns Core's permanent DepositManager binding.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @return IDepositManager Permanent DepositManager.
    function _depositManager() private view returns (IDepositManager) {
        return IDepositManager(_CORE.depositManager());
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reads without state changes; errors from dependency views propagate.
    function getPosition(
        address asset_,
        address borrower_
    ) external view override returns (IBurnerLoansCore.Position memory) {
        (, , IFLOANv1.Position memory p) = LoanPositions.forCore(_CORE, asset_, borrower_);
        return
            IBurnerLoansCore.Position(p.collateral, p.principalDue, p.maturity, p.lastBorrowBlock);
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reads without state changes; errors from dependency views propagate.
    function getActiveBorrowers(address asset_) external view override returns (address[] memory) {
        return IFLOANv1(_CORE.floan()).getActiveBorrowers(_CORE.marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reverts if:
    ///      - The asset is unregistered.
    ///      - A required FLOAN read fails.
    ///
    /// @dev Core lifecycle does not gate this view.
    function getActiveBorrowerCount(address asset_) external view override returns (uint256) {
        return IFLOANv1(_CORE.floan()).getActiveBorrowerCount(_CORE.marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reads without state changes; errors from dependency views propagate.
    function assetActiveDebtOhm(address asset_) public view override returns (uint256) {
        return IFLOANv1(_CORE.floan()).getMarketPrincipalDue(_CORE.marketId(asset_));
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reads without state changes; errors from dependency views propagate.
    function positionHealthFactor(
        address asset_,
        uint256 collateral_,
        uint256 debt_
    ) public view override returns (uint256) {
        if (debt_ == 0) return type(uint256).max;
        IBurnerLoansRisk evaluator = _risk();
        return
            evaluator.health(
                evaluator.snapshot(asset_),
                _CORE.marketId(asset_),
                collateral_,
                debt_
            );
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reads without state changes; errors from dependency views propagate.
    function isSeizable(address asset_, address borrower_) external view override returns (bool) {
        (, , IFLOANv1.Position memory p) = LoanPositions.forCore(_CORE, asset_, borrower_);
        if (p.principalDue == 0) return false;
        // Expiry equality is an intentional protocol deadline.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= p.maturity) return true;
        return positionHealthFactor(asset_, p.collateral, p.principalDue) < _WAD;
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reverts if:
    ///      - The collateral asset is not registered by Burner Loans.
    ///      Reads without state changes; errors from dependency views propagate.
    function getAssetCollateralStatus(
        address asset_
    ) public view override returns (IBurnerLoansCore.AssetCollateralStatus memory) {
        if (!_CORE.isAssetRegistered(asset_))
            revert IBurnerLoansCore.BurnerLoansCore_AssetNotConfigured(asset_);
        return LoanCustody.getAssetCollateralStatus(_depositManager(), asset_, address(_CORE));
    }

    struct Scan {
        address[] borrowers;
        uint256 cursor;
        uint256 debt;
        uint256 collateral;
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reads without state changes; errors from dependency views propagate.
    function getSeizableBorrowers(
        address asset_,
        uint256 start_,
        uint256 count_
    ) external view override returns (address[] memory, uint256, uint256) {
        return getSeizableBorrowersFor(msg.sender, asset_, start_, count_);
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reverts if:
    ///      - The starting offset is outside the current canonical borrower list.
    ///      Reads without state changes; errors from dependency views propagate.
    function getSeizableBorrowersFor(
        address actor_,
        address asset_,
        uint256 start_,
        uint256 count_
    ) public view override returns (address[] memory, uint256, uint256) {
        (Scan memory scan, IBurnerLoansCore.PriceSnapshot memory snapshot) = _scan(
            asset_,
            start_,
            count_,
            type(uint256).max
        );
        return (scan.borrowers, scan.cursor, _scanReward(asset_, actor_, scan, snapshot));
    }

    /// @inheritdoc IBurnerLoansLens
    /// @dev Reverts if:
    ///      - The asset is unregistered.
    ///      - The scan start is invalid.
    ///
    /// @dev These checks precede zero-limit shortcuts. Scan work and selected results are bounded independently;
    ///      scanning stops at the result cap without dropping eligible borrowers from a larger page.
    function getSeizableBorrowersBoundedFor(
        address actor_,
        address asset_,
        uint256 start_,
        uint256 count_,
        uint256 maxResults_
    ) external view override returns (address[] memory, uint256, uint256) {
        (Scan memory scan, IBurnerLoansCore.PriceSnapshot memory snapshot) = _scan(
            asset_,
            start_,
            count_,
            maxResults_
        );
        return (scan.borrowers, scan.cursor, _scanReward(asset_, actor_, scan, snapshot));
    }

    /// @notice Quotes the keeper reward for the selected scan results.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param actor_ Keeper identity used to select protocol-caller rewards.
    /// @param scan_ Bounded borrower scan with cursor and aggregate collateral/principal.
    /// @param snapshot_ Captured operation price/backing values, all in the same PRICE decimal scale.
    /// @return uint256 Keeper reward estimate in output-token units.
    function _scanReward(
        address asset_,
        address actor_,
        Scan memory scan_,
        IBurnerLoansCore.PriceSnapshot memory snapshot_
    ) private view returns (uint256) {
        if (scan_.borrowers.length == 0) return 0;
        // Quote one redemption and one reward for the selected batch, matching Core's aggregate
        // settlement. Per-borrower reward rounding or caps would produce a different result.
        (uint32 market, IBurnerLoansCore.AssetConfig memory cfg, ) = LoanMarket.configuration(
            _CORE,
            asset_
        );
        (, uint256 output) = LoanCustody.previewWithdrawAmount(
            _depositManager(),
            asset_,
            scan_.collateral,
            cfg.withdrawAsShares
        );
        ROLESv1 roles = ROLESv1(
            address(Policy(address(_CORE)).kernel().getModuleForKeycode(toKeycode("ROLES")))
        );
        bool protocolCaller = roles.hasRole(actor_, BURNER_LOANS_SEIZER_ROLE) ||
            roles.hasRole(actor_, HEART_ROLE);
        return
            _risk().keeperReward(
                snapshot_,
                market,
                scan_.debt,
                scan_.collateral,
                output,
                protocolCaller
            );
    }

    /// @notice Builds a bounded list of currently seizable borrowers.
    /// @dev Reads without state changes; errors from dependency views propagate.
    /// @param asset_ Underlying collateral token identifying the market.
    /// @param start_ Initial canonical borrower index.
    /// @param count_ Maximum canonical borrowers examined in the remaining suffix.
    /// @param maxResults_ Maximum eligible borrowers selected before stopping the scan.
    /// @return scan Bounded selected borrowers, canonical cursor and aggregate position amounts.
    /// @return snapshot Captured price/backing pair shared by this scan.
    // Canonical dependency reads are bounded by the clipped borrower suffix.
    // forge-lint: disable-start(calls-loop)
    function _scan(
        address asset_,
        uint256 start_,
        uint256 count_,
        uint256 maxResults_
    ) private view returns (Scan memory scan, IBurnerLoansCore.PriceSnapshot memory snapshot) {
        IFLOANv1 floan = IFLOANv1(_CORE.floan());
        uint32 market = _CORE.marketId(asset_);
        uint256 population = floan.getActiveBorrowerCount(market);
        if (start_ >= population && (population != 0 || start_ != 0))
            revert BurnerLoansLens_InvalidStart(start_, population);
        scan.cursor = start_;
        scan.borrowers = new address[](0);
        if (population == 0 || count_ == 0 || maxResults_ == 0) return (scan, snapshot);
        // Clamp before allocating or adding: even uint256.max requests stay within this suffix.
        uint256 remaining = population - start_;
        if (count_ > remaining) count_ = remaining;
        IBurnerLoansRisk evaluator = _risk();
        snapshot = evaluator.snapshot(asset_);
        // count_ bounds inspected positions, while maxResults_ bounds selected borrowers. Healthy
        // positions still consume scan work and advance the cursor, but do not contribute to the reward.
        address[] memory candidates = new address[](count_ < maxResults_ ? count_ : maxResults_);
        uint256 returned;
        for (uint256 checked; checked < count_ && returned < maxResults_; ++checked) {
            address borrower = floan.getActiveBorrowerAt(market, scan.cursor++);
            IFLOANv1.Position memory p = LoanPositions.getOrEmpty(floan, market, borrower);
            if (!LoanPositions.isSeizable(evaluator, snapshot, market, p)) continue;
            candidates[returned++] = borrower;
            scan.debt += p.principalDue;
            scan.collateral += p.collateral;
        }
        // A zero cursor signals wraparound. Borrower indices can move after debt closes; the task
        // consuming these pages repairs stale offsets and adjusts progress after successful seizures.
        if (scan.cursor == population) scan.cursor = 0;
        scan.borrowers = new address[](returned);
        for (uint256 i; i < returned; ++i) scan.borrowers[i] = candidates[i];
    }

    // forge-lint: disable-end(calls-loop)

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId_) public view override returns (bool) {
        return
            interfaceId_ == type(IVersioned).interfaceId ||
            interfaceId_ == type(IBurnerLoansLens).interfaceId ||
            interfaceId_ == type(IBurnerLoansCoreBound).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (uint8, uint8) {
        return (1, 0);
    }
}
