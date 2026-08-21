// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";
import {BURNER_LOANS_ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

import {BurnerLoansConfigTimelockTest} from "./BurnerLoansConfigTimelockTest.sol";

contract BurnerLoansConfigTimelockQueueSetFeeConfigTest is BurnerLoansConfigTimelockTest {
    // queueSetAssetFeeConfig
    // given caller has neither admin nor burner_loans_admin
    //  when queueing a baseFeeBps update
    //   then it reverts before validating the update
    function test_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != burnerLoansAdmin);
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        config.baseFeeBps = 10_001;

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, BURNER_LOANS_ADMIN_ROLE)
        );
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given caller has admin role
    //  when baseFeeBps is selected and valid
    //   then the action is queued and stores the expected sub-action
    function test_givenAdminCaller_whenBaseFeeBpsSelected_queuesAction() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        uint64 nextActionId = configTimelock.nextActionId();
        bytes memory payload = abi.encode(address(usds), config, selection);
        _expectSingleActionQueued(
            nextActionId,
            admin,
            IBurnerLoansConfig.setAssetFeeConfig.selector,
            payload
        );

        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, nextActionId, "action id");
        assertEq(configTimelock.getQueuedActionLength(actionId), 1, "sub-action length");

        (address target, bytes4 selector, bytes memory storedPayload) = configTimelock
            .getQueuedSubAction(actionId, 0);
        assertEq(target, address(burnerLoansConfig), "target");
        assertEq(selector, IBurnerLoansConfig.setAssetFeeConfig.selector, "selector");
        assertEq(storedPayload, payload, "payload");
    }

    // queueSetAssetFeeConfig
    // given caller has burner_loans_admin role
    //  when baseFeeBps is selected and valid
    //   then the action is queued
    function test_givenBurnerLoansAdminCaller_whenBaseFeeBpsSelected_queuesAction() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
        assertEq(configTimelock.nextActionId(), 2, "next action id");
    }

    // queueSetAssetFeeConfig
    // given a fee update is pending for an asset
    //  when a different fee field update is queued for the same asset
    //   then it reverts with the owning action and preserves the key lock
    function test_givenDifferentFeeFieldPendingForSameAsset_revertsWithOwningAction() public {
        (
            IBurnerLoans.AssetFeeConfig memory baseFeeUpdate,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory baseFeeSelection
        ) = _singleFeeUpdate(0);
        vm.prank(burnerLoansAdmin);
        uint64 owner = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            baseFeeUpdate,
            baseFeeSelection
        );
        (bytes32 key, ) = configTimelock.getQueuedConfigState(owner, 0, 0);

        (
            IBurnerLoans.AssetFeeConfig memory kinkUpdate,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory kinkSelection
        ) = _singleFeeUpdate(1);
        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigTimelockBatchQueue.IConfigTimelockBatchQueue_ConfigKeyPending.selector,
                key,
                owner
            )
        );
        configTimelock.queueSetAssetFeeConfig(address(usds), kinkUpdate, kinkSelection);

        assertEq(configTimelock.pendingActionId(key), owner, "first fee action retains key");
        assertEq(configTimelock.nextActionId(), owner + 1, "failed queue does not consume id");
    }

    // queueSetAssetFeeConfig
    // given market originations are disabled
    //  when a fee update is queued and executed
    //   then the existing market can still be configured
    function test_givenOriginationsDisabled_executes() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        config.baseFeeBps = 50;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
        vm.warp(block.timestamp + configTimelock.timelockDelay());
        configTimelock.executeQueuedAction(actionId);

        assertFalse(
            burnerLoansConfig.getAssetConfig(address(usds)).originationsEnabled,
            "originations disabled"
        );
        assertEq(burnerLoansConfig.getAssetFeeConfig(address(usds)).baseFeeBps, 50, "base fee");
    }

    // queueSetAssetFeeConfig
    // given asset is not configured
    //  when queueing a baseFeeBps update
    //   then it reverts
    function test_givenUnconfiguredAsset_reverts() public {
        address unknownAsset = makeAddr("unknownAsset");
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                unknownAsset
            )
        );
        configTimelock.queueSetAssetFeeConfig(unknownAsset, config, selection);
    }

    // queueSetAssetFeeConfig
    // given no fee fields are selected
    //  when queueing the action
    //   then it reverts
    function test_givenEmptySelection_reverts() public {
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetFeeConfig(
            address(usds),
            IBurnerLoans.AssetFeeConfig(0, 0, 0, 0),
            selection
        );
    }

    // queueSetAssetFeeConfig
    // given an unselected fee field is non-zero
    //  when queueing the action
    //   then it reverts for any unselected field
    function test_givenUnselectedNonZeroField_reverts(
        uint8 selectedField_,
        uint8 unselectedField_,
        uint16 value_
    ) public {
        // Select one legitimate field so the update is otherwise valid.
        selectedField_ = uint8(bound(selectedField_, 0, 3));

        // Map the second fuzz input onto a different field to prove every unselected
        // field must be zeroed instead of silently ignored.
        unselectedField_ = uint8(bound(unselectedField_, 0, 2));
        if (unselectedField_ >= selectedField_) unselectedField_++;
        value_ = uint16(bound(value_, 1, type(uint16).max));

        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(selectedField_);
        _setNonZeroFeeField(config, unselectedField_, value_);

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidParam.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given baseFeeBps is greater than 100%
    //  when queueing the action
    //   then it reverts
    function test_givenBaseFeeBpsAboveMax_reverts(uint16 baseFeeBps_) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.baseFeeBps = baseFeeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, baseFeeBps_)
        );
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given kinkBps is zero and postKinkSlopeBps is non-zero
    //  when queueing the action
    //   then it reverts
    function test_givenKinkBpsIsZeroAndPostKinkSlopeBpsIsNonZero_reverts(
        uint16 postKinkSlopeBps_
    ) public {
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 1, 10_000));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.kinkBps = 0;
        config.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given kinkBps is greater than or equal to 100%
    //  when queueing the action
    //   then it reverts
    function test_givenKinkBpsAtOrAboveMax_reverts(uint16 kinkBps_) public {
        kinkBps_ = uint16(bound(kinkBps_, 10_000, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.kinkBps = kinkBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given preKinkSlopeBps is greater than 100%
    //  when queueing the action
    //   then it reverts
    function test_givenPreKinkSlopeBpsAboveMax_reverts(uint16 preKinkSlopeBps_) public {
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.preKinkSlopeBps = preKinkSlopeBps_;
        config.postKinkSlopeBps = preKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, preKinkSlopeBps_)
        );
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given postKinkSlopeBps is greater than 100%
    //  when queueing the action
    //   then it reverts
    function test_givenPostKinkSlopeBpsAboveMax_reverts(uint16 postKinkSlopeBps_) public {
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 10_001, type(uint16).max));
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_InvalidBps.selector, postKinkSlopeBps_)
        );
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given preKinkSlopeBps is greater than postKinkSlopeBps but the full-utilization fee is within the cap
    //  when queueing the action
    //   then it queues the action because Aave-style slopes are segment deltas, not ordered gradients
    function test_givenPreKinkSlopeBpsGreaterThanPostKinkSlopeBps_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        config.preKinkSlopeBps = 900;
        config.postKinkSlopeBps = 100;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            config,
            _selectAllFees()
        );

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given fee rate at full utilization exceeds 100%
    //  when queueing the action
    //   then it reverts
    function test_givenFullUtilizationFeeRateAboveOneWad_reverts(
        uint16 baseFeeBps_,
        uint16 preKinkSlopeBps_,
        uint16 postKinkSlopeBps_
    ) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 1, 10_000));
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 0, 10_000 - baseFeeBps_));
        // Keep each individual component inside its raw bps bound; the invalidity comes only
        // from the Aave-style full-utilization sum exceeding 100%.
        postKinkSlopeBps_ = uint16(
            bound(postKinkSlopeBps_, 10_001 - baseFeeBps_ - preKinkSlopeBps_, 10_000)
        );
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: 5_000,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: postKinkSlopeBps_
        });

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given a single-slope fee curve has baseFeeBps plus preKinkSlopeBps greater than 100%
    //  when queueing the action
    //   then it reverts
    function test_givenBaseFeePlusSingleSlopeAboveOneWad_reverts(
        uint16 baseFeeBps_,
        uint16 preKinkSlopeBps_
    ) public {
        baseFeeBps_ = uint16(bound(baseFeeBps_, 1, 10_000));
        // Keep both components inside their raw bps bounds; the invalidity comes only from
        // the single-slope full-utilization fee exceeding 100%.
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 10_001 - baseFeeBps_, 10_000));
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: baseFeeBps_,
            kinkBps: 0,
            preKinkSlopeBps: preKinkSlopeBps_,
            postKinkSlopeBps: 0
        });

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, _selectAllFees());
    }

    // queueSetAssetFeeConfig
    // given baseFeeBps is inside the valid resulting-config range
    //  when baseFeeBps is selected
    //   then it queues the action for every valid value
    function test_givenBaseFeeBpsInValidRange_queuesAction(uint16 baseFeeBps_) public {
        // Aave-style slope components contribute preKinkSlopeBps + postKinkSlopeBps = 1000 bps at 100%
        // utilization, so base fee can be at most 9,000 bps.
        baseFeeBps_ = uint16(bound(baseFeeBps_, 0, 9_000));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        config.baseFeeBps = baseFeeBps_;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given baseFeeBps is inside the raw bps range but makes full-utilization fee exceed 100%
    //  when baseFeeBps is selected
    //   then it reverts for every invalid resulting-config value
    function test_givenBaseFeeBpsAboveResultingConfigCap_reverts(uint16 baseFeeBps_) public {
        // Default preKinkSlopeBps + postKinkSlopeBps contributes 1,000 bps at 100% utilization, so
        // baseFeeBps of 9,001 through 10,000 is raw-valid but resulting-config invalid.
        baseFeeBps_ = uint16(bound(baseFeeBps_, 9_001, 10_000));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        config.baseFeeBps = baseFeeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given kinkBps is inside the valid non-zero range
    //  when kinkBps is selected
    //   then it queues the action for every valid value
    function test_givenKinkBpsInValidNonZeroRange_queuesAction(uint16 kinkBps_) public {
        kinkBps_ = uint16(bound(kinkBps_, 1, 9_999));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(1);
        config.kinkBps = kinkBps_;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given the current postKinkSlopeBps is non-zero
    //  when kinkBps is set to zero
    //   then it reverts
    function test_givenKinkBpsZeroWithCurrentPostKinkSlopeBps_reverts() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(1);
        config.kinkBps = 0;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given preKinkSlopeBps is inside the valid resulting-config range
    //  when preKinkSlopeBps is selected
    //   then it queues the action for every valid value
    function test_givenPreKinkSlopeBpsInValidRange_queuesAction(uint16 preKinkSlopeBps_) public {
        // Default baseFeeBps + postKinkSlopeBps contributes 925 bps at 100% utilization.
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 0, 9_075));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(2);
        config.preKinkSlopeBps = preKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given preKinkSlopeBps is inside the raw bps range but makes full-utilization fee exceed 100%
    //  when preKinkSlopeBps is selected
    //   then it reverts for every invalid resulting-config value
    function test_givenPreKinkSlopeBpsAboveResultingConfigCap_reverts(
        uint16 preKinkSlopeBps_
    ) public {
        // Default baseFeeBps + postKinkSlopeBps contributes 925 bps at 100% utilization, so
        // preKinkSlopeBps of 9,076 through 10,000 is raw-valid but resulting-config invalid.
        preKinkSlopeBps_ = uint16(bound(preKinkSlopeBps_, 9_076, 10_000));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(2);
        config.preKinkSlopeBps = preKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given postKinkSlopeBps is inside the valid resulting-config range
    //  when postKinkSlopeBps is selected
    //   then it queues the action for every valid value
    function test_givenPostKinkSlopeBpsInValidRange_queuesAction(uint16 postKinkSlopeBps_) public {
        // Default baseFeeBps + preKinkSlopeBps contributes 125 bps at 100% utilization.
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 0, 9_875));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(3);
        config.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given postKinkSlopeBps is inside the raw bps range but makes full-utilization fee exceed 100%
    //  when postKinkSlopeBps is selected
    //   then it reverts for every invalid resulting-config value
    function test_givenPostKinkSlopeBpsAboveResultingConfigCap_reverts(
        uint16 postKinkSlopeBps_
    ) public {
        // Default baseFeeBps + preKinkSlopeBps contributes 125 bps at 100% utilization, so
        // postKinkSlopeBps of 9,876 through 10,000 is raw-valid but resulting-config invalid.
        postKinkSlopeBps_ = uint16(bound(postKinkSlopeBps_, 9_876, 10_000));
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(3);
        config.postKinkSlopeBps = postKinkSlopeBps_;

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given kinkBps and both slopes are zero
    //  when queueing a flat base-fee curve
    //   then it queues the action
    function test_givenKinkBpsAndSlopesAreZero_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 100,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            config,
            _selectAllFees()
        );

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given a kinked fee curve reaches exactly 100% at full utilization
    //  when queueing the action
    //   then it queues the action
    function test_givenBaseFeePlusPreKinkSlopeAtOneWad_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 5_000,
            kinkBps: 5_000,
            preKinkSlopeBps: 5_000,
            postKinkSlopeBps: 0
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            config,
            _selectAllFees()
        );

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given preKinkSlopeBps is zero and postKinkSlopeBps is positive
    //  when a kinked fee curve is queued
    //   then it queues the action
    function test_givenZeroSlope1WithBaseFeeAndSlope2_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 50,
            kinkBps: 8_000,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 500
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            config,
            _selectAllFees()
        );

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given caller has burner_loans_admin role
    //  when kinkBps is selected and valid
    //   then the action is queued
    function test_givenBurnerLoansAdminCaller_whenKinkBpsSelected_queuesAction() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(1);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given caller has burner_loans_admin role
    //  when preKinkSlopeBps is selected and valid
    //   then the action is queued
    function test_givenBurnerLoansAdminCaller_whenPreKinkSlopeBpsSelected_queuesAction() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(2);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given caller has burner_loans_admin role
    //  when postKinkSlopeBps is selected and valid
    //   then the action is queued
    function test_givenBurnerLoansAdminCaller_whenPostKinkSlopeBpsSelected_queuesAction() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(3);

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given zero values are selected for fields that allow zero
    //  when queueing the action
    //   then it queues the action
    function test_givenZeroAllowedFields_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 5_000,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            config,
            _selectAllFees()
        );

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given values are at their valid boundary
    //  when queueing the action
    //   then it queues the action
    function test_givenValidBoundaryValues_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 9_999,
            preKinkSlopeBps: 10_000,
            postKinkSlopeBps: 0
        });

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            config,
            _selectAllFees()
        );

        assertEq(actionId, 1, "action id");
    }

    // queueSetAssetFeeConfig
    // given caller has burner_loans_admin role
    //  when baseFeeBps, kinkBps, preKinkSlopeBps, and postKinkSlopeBps are selected and valid
    //   then one action is queued
    function test_givenBurnerLoansAdminCaller_whenAllFeeFieldsSelected_queuesOneAction() public {
        IBurnerLoans.AssetFeeConfig memory config = _defaultAssetFeeConfig();
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection = _selectAllFees();

        vm.prank(burnerLoansAdmin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, 1, "action id");
        assertEq(configTimelock.nextActionId(), 2, "next action id");
    }

    function _singleFeeUpdate(
        uint8 field_
    )
        internal
        pure
        returns (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        )
    {
        _selectFeeField(selection, field_);
        _setValidFeeField(config, field_);
    }

    function _selectFeeField(
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection_,
        uint8 field_
    ) internal pure {
        if (field_ == 0) {
            selection_.baseFeeBps = true;
        } else if (field_ == 1) {
            selection_.kinkBps = true;
        } else if (field_ == 2) {
            selection_.preKinkSlopeBps = true;
        } else {
            selection_.postKinkSlopeBps = true;
        }
    }

    function _setValidFeeField(
        IBurnerLoans.AssetFeeConfig memory config_,
        uint8 field_
    ) internal pure {
        if (field_ == 0) {
            config_.baseFeeBps = 30;
        } else if (field_ == 1) {
            config_.kinkBps = 7_500;
        } else if (field_ == 2) {
            config_.preKinkSlopeBps = 90;
        } else {
            config_.postKinkSlopeBps = 1_000;
        }
    }

    function _setNonZeroFeeField(
        IBurnerLoans.AssetFeeConfig memory config_,
        uint8 field_,
        uint16 value_
    ) internal pure {
        if (field_ == 0) {
            config_.baseFeeBps = value_;
        } else if (field_ == 1) {
            config_.kinkBps = value_;
        } else if (field_ == 2) {
            config_.preKinkSlopeBps = value_;
        } else {
            config_.postKinkSlopeBps = value_;
        }
    }
}
