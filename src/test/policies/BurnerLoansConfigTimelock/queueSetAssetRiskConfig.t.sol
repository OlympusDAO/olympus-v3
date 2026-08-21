// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetAssetRiskConfigTest is BurnerLoansConfigTimelockTest {
    uint16 internal constant MAX_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_FACTOR_BPS = 10_000;
    uint16 internal constant MAX_COLLATERAL_RATIO_BPS = 50_000;
    uint16 internal constant MAX_BACKING_MULTIPLIER_BPS = 50_000;
    uint256 internal constant MAX_KEEPER_REWARD = type(uint128).max;

    // queueSetAssetRiskConfig
    // given caller has neither admin nor burner_loans_admin
    //  when queueing a collateralFactorBps update
    //   then it reverts before validating the update
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();
        update.collateralFactorBps = 0;

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given caller has admin role
    //  when collateralFactorBps is selected and valid
    //   then the action is queued
    function test_givenAdminCaller_whenCollateralFactorBpsSelected_queuesAction() public {
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();

        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetRiskConfig
    // given caller has burner_loans_admin role
    //  when collateralFactorBps is selected and valid
    //   then the action is queued and stores the expected full BurnerLoans setter payload
    function test_givenBurnerLoansAdminCaller_whenCollateralFactorBpsSelected_queuesAction()
        public
    {
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();
        uint64 nextActionId = configTimelock.nextActionId();
        bytes memory payload = abi.encode(address(usds), update, selection);
        _expectSingleActionQueued(
            nextActionId,
            burnerLoansAdmin,
            IBurnerLoansConfig.setAssetRiskConfig.selector,
            payload
        );

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);

        assertEq(actionId, nextActionId, "action id");
        assertEq(configTimelock.getQueuedActionLength(actionId), 1, "sub-action length");

        (address target, bytes4 selector, bytes memory storedPayload) = configTimelock
            .getQueuedSubAction(actionId, 0);
        assertEq(target, address(burnerLoansConfig), "target");
        assertEq(selector, IBurnerLoansConfig.setAssetRiskConfig.selector, "selector");
        assertEq(storedPayload, payload, "payload");
    }

    // queueSetAssetRiskConfig
    // given a risk update is pending for an asset
    //  when a different risk field is queued for the same asset
    //   then it reverts with the shared risk key's owning action
    function test_givenRiskUpdatePendingForAsset_whenDifferentRiskFieldQueued_revertsWithSharedKeyOwner()
        public
    {
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory collateralUpdate,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory collateralSelection
        ) = _collateralFactorUpdate();
        vm.prank(burnerLoansAdmin);
        uint64 owner = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            collateralUpdate,
            collateralSelection
        );
        (bytes32 key, ) = configTimelock.getQueuedConfigState(owner, 0, 0);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory ratioUpdate;
        ratioUpdate.minCollateralRatioBps = 12_000;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory ratioSelection;
        ratioSelection.minCollateralRatioBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                owner
            )
        );
        configTimelock.queueSetAssetRiskConfig(address(usds), ratioUpdate, ratioSelection);

        assertEq(configTimelock.pendingActionId(key), owner, "first risk action retains key");
        assertEq(configTimelock.nextActionId(), owner + 1, "failed queue does not consume id");
    }

    // queueSetAssetRiskConfig
    // given a risk update is pending for an asset
    //  when a fee update is queued for the same asset
    //   then both queues succeed with distinct scoped configuration keys
    function test_givenRiskUpdatePendingForAsset_whenFeeUpdateQueuedForSameAsset_queuesDistinctKeys()
        public
    {
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory riskUpdate,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory riskSelection
        ) = _collateralFactorUpdate();
        vm.prank(burnerLoansAdmin);
        uint64 riskActionId = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            riskUpdate,
            riskSelection
        );

        IBurnerLoans.AssetFeeConfig memory feeUpdate;
        feeUpdate.baseFeeBps = 30;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory feeSelection;
        feeSelection.baseFeeBps = true;
        vm.prank(burnerLoansAdmin);
        uint64 feeActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            feeUpdate,
            feeSelection
        );

        (bytes32 riskKey, ) = configTimelock.getQueuedConfigState(riskActionId, 0, 0);
        (bytes32 feeKey, ) = configTimelock.getQueuedConfigState(feeActionId, 0, 0);
        assertEq(riskActionId, 1, "risk action queued first");
        assertEq(feeActionId, 2, "fee action queued second");
        assertNotEq(riskKey, feeKey, "risk and fee keys are distinct");
        assertEq(configTimelock.pendingActionId(riskKey), riskActionId, "risk key owner");
        assertEq(configTimelock.pendingActionId(feeKey), feeActionId, "fee key owner");
    }

    // queueSetAssetRiskConfig
    // given asset is not configured
    //  when queueing a collateralFactorBps update
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts() public {
        address unknownAsset = makeAddr("unknownAsset");
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unknownAsset
            )
        );
        configTimelock.queueSetAssetRiskConfig(unknownAsset, update, selection);
    }

    // queueSetAssetRiskConfig
    // given market originations are disabled
    //  when a risk update is queued and executed
    //   then the existing market can still be configured
    function test_givenOriginationsDisabled_executes() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);

        IBurnerLoans.AssetConfig memory stored = burnerLoansConfig.getAssetConfig(address(usds));
        assertFalse(stored.originationsEnabled, "originations disabled");
        assertEq(stored.collateralFactorBps, 9_500, "risk update applied");
    }

    // queueSetAssetRiskConfig
    // given no risk fields are selected
    //  when queueing the action
    //   then it reverts
    function test_givenEmptySelection_reverts() public {
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(
            address(usds),
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate({
                collateralFactorBps: 0,
                minCollateralRatioBps: 0,
                backingMultiplierBps: 0,
                keeperRewardBps: 0,
                termLength: 0,
                maxMaturityHorizon: 0,
                maxKeeperReward: 0
            }),
            selection
        );
    }

    // queueSetAssetRiskConfig
    // given an unselected risk field is non-zero
    //  when queueing the action
    //   then it reverts for any unselected field
    function test_givenUnselectedNonZeroField_reverts(
        uint8 selectedField_,
        uint8 unselectedField_,
        uint256 value_
    ) public {
        // Select one legitimate field so the update is otherwise valid.
        selectedField_ = uint8(bound(selectedField_, 0, 6));

        // Map the second fuzz input onto a different field to prove every unselected
        // field must be zeroed instead of silently ignored.
        unselectedField_ = uint8(bound(unselectedField_, 0, 5));
        if (unselectedField_ >= selectedField_) unselectedField_++;
        value_ = bound(value_, 1, type(uint48).max);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        _selectRiskField(selection, selectedField_);
        _setValidRiskField(update, selectedField_);
        _setNonZeroRiskField(update, unselectedField_, value_);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given collateralFactorBps is zero
    //  when queueing the action
    //   then it reverts
    function test_givenCollateralFactorBpsIsZero_reverts() public {
        (
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update,
            IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection
        ) = _collateralFactorUpdate();
        update.collateralFactorBps = 0;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, 0));
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given collateralFactorBps is greater than 100%
    //  when queueing the action
    //   then it reverts
    function test_givenCollateralFactorBpsAboveMax_reverts(uint16 collateralFactorBps_) public {
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 10_001, type(uint16).max));
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.collateralFactorBps = collateralFactorBps_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.collateralFactorBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidBps.selector,
                collateralFactorBps_
            )
        );
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given minCollateralRatioBps is below 100%
    //  when queueing the action
    //   then it reverts
    function test_givenMinCollateralRatioBpsBelowMin_reverts(uint16 minCollateralRatioBps_) public {
        minCollateralRatioBps_ = uint16(bound(minCollateralRatioBps_, 0, 9_999));
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.minCollateralRatioBps = minCollateralRatioBps_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.minCollateralRatioBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given minCollateralRatioBps is above the protocol maximum
    //  when queueing the action
    //   then it reverts
    function test_givenMinCollateralRatioBpsAboveMax_reverts(uint16 minCollateralRatioBps_) public {
        minCollateralRatioBps_ = uint16(
            bound(minCollateralRatioBps_, MAX_COLLATERAL_RATIO_BPS + 1, type(uint16).max)
        );
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.minCollateralRatioBps = minCollateralRatioBps_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.minCollateralRatioBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given backingMultiplierBps is below 100%
    //  when queueing the action
    //   then it reverts
    function test_givenBackingMultiplierBpsBelowMin_reverts(uint16 backingMultiplierBps_) public {
        backingMultiplierBps_ = uint16(bound(backingMultiplierBps_, 0, 9_999));
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.backingMultiplierBps = backingMultiplierBps_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.backingMultiplierBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given backingMultiplierBps is above the protocol maximum
    //  when queueing the action
    //   then it reverts
    function test_givenBackingMultiplierBpsAboveMax_reverts(uint16 backingMultiplierBps_) public {
        backingMultiplierBps_ = uint16(
            bound(backingMultiplierBps_, MAX_BACKING_MULTIPLIER_BPS + 1, type(uint16).max)
        );
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.backingMultiplierBps = backingMultiplierBps_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.backingMultiplierBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given keeperRewardBps is greater than 100%
    //  when queueing the action
    //   then it reverts
    function test_givenKeeperRewardBpsAboveMax_reverts(uint16 keeperRewardBps_) public {
        keeperRewardBps_ = uint16(bound(keeperRewardBps_, 10_001, type(uint16).max));
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.keeperRewardBps = keeperRewardBps_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.keeperRewardBps = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, keeperRewardBps_)
        );
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given maxKeeperReward is above the protocol maximum
    //  when queueing the action
    //   then it reverts
    function test_givenMaxKeeperRewardAboveMax_reverts(uint256 maxKeeperReward_) public {
        maxKeeperReward_ = bound(maxKeeperReward_, MAX_KEEPER_REWARD + 1, type(uint256).max);
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.maxKeeperReward = maxKeeperReward_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.maxKeeperReward = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given protocol-level term and maturity horizon constants
    //  when the bounds are compared
    //   then the max maturity horizon is strictly greater than the max term length
    function test_givenProtocolTermConstants_maxMaturityHorizonExceedsMaxTermLength() public pure {
        assertGt(
            BurnerLoansConstants.MAX_MATURITY_HORIZON,
            BurnerLoansConstants.MAX_TERM_LENGTH,
            "max horizon must exceed max term"
        );
    }

    // queueSetAssetRiskConfig
    // given termLength is zero
    //  when queueing the action
    //   then it reverts
    function test_givenTermLengthIsZero_reverts() public {
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.termLength = 0;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.termLength = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given termLength is above max
    //  when queueing the action
    //   then it reverts
    function test_givenTermLengthAboveMax_reverts(uint48 termLength_) public {
        termLength_ = uint48(
            bound(termLength_, BurnerLoansConstants.MAX_TERM_LENGTH + 1, type(uint48).max)
        );
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.termLength = termLength_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.termLength = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given maxMaturityHorizon is below or equal to termLength
    //  when queueing the action
    //   then it reverts
    function test_givenMaxMaturityHorizonBelowOrEqualToTermLength_reverts(
        uint48 maxMaturityHorizon_
    ) public {
        maxMaturityHorizon_ = uint48(bound(maxMaturityHorizon_, 1, 30 days));
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.maxMaturityHorizon = maxMaturityHorizon_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.maxMaturityHorizon = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given maxMaturityHorizon is above max
    //  when queueing the action
    //   then it reverts
    function test_givenMaxMaturityHorizonAboveMax_reverts(uint48 maxMaturityHorizon_) public {
        maxMaturityHorizon_ = uint48(
            bound(
                maxMaturityHorizon_,
                BurnerLoansConstants.MAX_MATURITY_HORIZON + 1,
                type(uint48).max
            )
        );
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update;
        update.maxMaturityHorizon = maxMaturityHorizon_;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection;
        selection.maxMaturityHorizon = true;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetRiskConfig(address(usds), update, selection);
    }

    // queueSetAssetRiskConfig
    // given risk values are inside the valid combined range
    //  when all fields are selected
    //   then the action is queued for every valid value
    function test_givenRiskConfigInValidRange_queuesAction(
        uint16 collateralFactorBps_,
        uint16 minCollateralRatioBps_,
        uint16 backingMultiplierBps_,
        uint16 keeperRewardBps_,
        uint48 termLength_,
        uint48 maxMaturityHorizon_,
        uint256 maxKeeperReward_
    ) public {
        collateralFactorBps_ = uint16(bound(collateralFactorBps_, 1, MAX_COLLATERAL_FACTOR_BPS));
        minCollateralRatioBps_ = uint16(
            bound(minCollateralRatioBps_, MAX_BPS, MAX_COLLATERAL_RATIO_BPS)
        );
        backingMultiplierBps_ = uint16(
            bound(backingMultiplierBps_, MAX_BPS, MAX_BACKING_MULTIPLIER_BPS)
        );
        keeperRewardBps_ = uint16(bound(keeperRewardBps_, 0, MAX_BPS));
        termLength_ = uint48(bound(termLength_, 1, BurnerLoansConstants.MAX_TERM_LENGTH));
        maxMaturityHorizon_ = uint48(
            bound(maxMaturityHorizon_, termLength_ + 1, BurnerLoansConstants.MAX_MATURITY_HORIZON)
        );
        maxKeeperReward_ = bound(maxKeeperReward_, 0, MAX_KEEPER_REWARD);

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update = IBurnerLoansConfigTimelock
            .AssetRiskConfigUpdate({
                collateralFactorBps: collateralFactorBps_,
                minCollateralRatioBps: minCollateralRatioBps_,
                backingMultiplierBps: backingMultiplierBps_,
                keeperRewardBps: keeperRewardBps_,
                termLength: termLength_,
                maxMaturityHorizon: maxMaturityHorizon_,
                maxKeeperReward: maxKeeperReward_
            });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            update,
            _selectAllRiskFields()
        );

        assertEq(actionId, 1, "action id");
    }

    function _selectRiskField(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory selection_,
        uint8 field_
    ) internal pure {
        if (field_ == 0) {
            selection_.collateralFactorBps = true;
        } else if (field_ == 1) {
            selection_.minCollateralRatioBps = true;
        } else if (field_ == 2) {
            selection_.backingMultiplierBps = true;
        } else if (field_ == 3) {
            selection_.keeperRewardBps = true;
        } else if (field_ == 4) {
            selection_.termLength = true;
        } else if (field_ == 5) {
            selection_.maxMaturityHorizon = true;
        } else {
            selection_.maxKeeperReward = true;
        }
    }

    function _setValidRiskField(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        uint8 field_
    ) internal pure {
        if (field_ == 0) {
            update_.collateralFactorBps = 9_500;
        } else if (field_ == 1) {
            update_.minCollateralRatioBps = 12_000;
        } else if (field_ == 2) {
            update_.backingMultiplierBps = 11_000;
        } else if (field_ == 3) {
            update_.keeperRewardBps = 500;
        } else if (field_ == 4) {
            update_.termLength = 14 days;
        } else if (field_ == 5) {
            update_.maxMaturityHorizon = 120 days;
        } else {
            update_.maxKeeperReward = 500e6;
        }
    }

    function _setNonZeroRiskField(
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory update_,
        uint8 field_,
        uint256 value_
    ) internal pure {
        if (field_ == 0) {
            update_.collateralFactorBps = uint16(bound(value_, 1, type(uint16).max));
        } else if (field_ == 1) {
            update_.minCollateralRatioBps = uint16(bound(value_, 1, type(uint16).max));
        } else if (field_ == 2) {
            update_.backingMultiplierBps = uint16(bound(value_, 1, type(uint16).max));
        } else if (field_ == 3) {
            update_.keeperRewardBps = uint16(bound(value_, 1, type(uint16).max));
        } else if (field_ == 4) {
            update_.termLength = uint48(value_);
        } else if (field_ == 5) {
            update_.maxMaturityHorizon = uint48(value_);
        } else {
            update_.maxKeeperReward = value_;
        }
    }
}
