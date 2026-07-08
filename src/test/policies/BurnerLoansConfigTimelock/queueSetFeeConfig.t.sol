// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfigTimelock} from "src/policies/interfaces/IBurnerLoansConfigTimelock.sol";
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
            IBurnerLoans.setAssetFeeConfig.selector,
            payload
        );

        vm.prank(admin);
        uint64 actionId = configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);

        assertEq(actionId, nextActionId, "action id");
        assertEq(configTimelock.getQueuedActionLength(actionId), 1, "sub-action length");

        (address target, bytes4 selector, bytes memory storedPayload) = configTimelock
            .getQueuedSubAction(actionId, 0);
        assertEq(target, address(burnerLoans), "target");
        assertEq(selector, IBurnerLoans.setAssetFeeConfig.selector, "selector");
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
    // given timelock policy is disabled
    //  when queueing a baseFeeBps update
    //   then it reverts
    function test_givenTimelockDisabled_reverts() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        vm.prank(emergency);
        configTimelock.disable("");

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
    }

    // queueSetAssetFeeConfig
    // given BurnerLoans configurator has been rotated away from the config timelock
    //  when queueing a baseFeeBps update
    //   then it reverts immediately
    function test_givenConfiguratorRotated_reverts() public {
        (
            IBurnerLoans.AssetFeeConfig memory config,
            IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory selection
        ) = _singleFeeUpdate(0);
        vm.prank(admin);
        burnerLoans.setConfigurator(makeAddr("newConfigurator"));

        vm.prank(burnerLoansAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_UnauthorizedConfigurator.selector,
                address(configTimelock)
            )
        );
        configTimelock.queueSetAssetFeeConfig(address(usds), config, selection);
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
    // given kinkBps is zero while the projected postKinkSlopeBps remains non-zero
    //  when only kinkBps is selected
    //   then it reverts because zero-kink curves must have postKinkSlopeBps equal to zero
    function test_givenKinkBpsZeroWithProjectedPostKinkSlopeBps_reverts() public {
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
    // given kinkBps and postKinkSlopeBps are both zero
    //  when queueing a single-slope fee curve
    //   then it queues the action
    function test_givenKinkBpsAndPostKinkSlopeBpsAreZero_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
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
    // given a single-slope fee curve reaches exactly 100% at full utilization
    //  when queueing the action
    //   then it queues the action
    function test_givenBaseFeePlusSingleSlopeAtOneWad_queuesAction() public {
        IBurnerLoans.AssetFeeConfig memory config = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 5_000,
            kinkBps: 0,
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
    // given an earlier queued fee action changes the resulting curve domain
    //  when a later fee action is queued
    //   then the later action validates against the projected fee config
    function test_givenEarlierQueuedFeeActionChangesDomain_laterActionUsesProjectedState() public {
        // The first action converts the default kinked curve into a single-slope curve.
        // Without projecting that queued state, the second action would be checked against
        // live default values and fail because baseFeeBps + preKinkSlopeBps + postKinkSlopeBps would exceed 100%.
        IBurnerLoans.AssetFeeConfig memory singleSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory singleSlopeSelection;
        singleSlopeSelection.baseFeeBps = true;
        singleSlopeSelection.kinkBps = true;
        singleSlopeSelection.postKinkSlopeBps = true;

        IBurnerLoans.AssetFeeConfig memory maxSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 10_000,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory maxSlopeSelection;
        maxSlopeSelection.preKinkSlopeBps = true;

        vm.startPrank(burnerLoansAdmin);
        uint64 firstActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            singleSlope,
            singleSlopeSelection
        );
        uint64 secondActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            maxSlope,
            maxSlopeSelection
        );
        vm.stopPrank();

        assertEq(firstActionId, 1, "first action id");
        assertEq(secondActionId, 2, "second action id");
    }

    // queueSetAssetFeeConfig
    // given an earlier queued fee action removes the kink
    //  when a later action tries to set postKinkSlopeBps
    //   then validation uses the projected single-slope state and reverts
    function test_givenEarlierQueuedFeeActionRemovesKink_laterSlope2UpdateRevertsAgainstProjectedState()
        public
    {
        // The second action would be valid against the live default kinked curve because
        // `postKinkSlopeBps == preKinkSlopeBps == 100`. It is invalid only after projecting the first
        // queued action, because a zero-kink curve requires `postKinkSlopeBps == 0`.
        IBurnerLoans.AssetFeeConfig memory singleSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory singleSlopeSelection;
        singleSlopeSelection.kinkBps = true;
        singleSlopeSelection.postKinkSlopeBps = true;

        IBurnerLoans.AssetFeeConfig memory invalidSlope2;
        invalidSlope2.postKinkSlopeBps = 100;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory invalidSlope2Selection;
        invalidSlope2Selection.postKinkSlopeBps = true;

        vm.startPrank(burnerLoansAdmin);
        uint64 firstActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            singleSlope,
            singleSlopeSelection
        );
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), invalidSlope2, invalidSlope2Selection);
        vm.stopPrank();

        assertEq(firstActionId, 1, "first action id");
    }

    // queueSetAssetFeeConfig
    // given an unrelated risk action is queued between two dependent fee actions
    //  when the later preKinkSlopeBps update is queued
    //   then validation ignores risk state and uses the projected fee config
    function test_givenRiskActionBetweenFeeActions_laterFeeActionUsesProjectedFeeState() public {
        // The first action converts the curve to zero-kink single-slope mode. The risk action
        // in the middle should not reset that fee projection. The final 10,000 bps preKinkSlope update
        // is valid only against the projected single-slope state with zero base and postKinkSlope.
        IBurnerLoans.AssetFeeConfig memory singleSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory singleSlopeSelection;
        singleSlopeSelection.baseFeeBps = true;
        singleSlopeSelection.kinkBps = true;
        singleSlopeSelection.postKinkSlopeBps = true;

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory riskUpdate;
        riskUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory riskSelection;
        riskSelection.collateralFactorBps = true;

        IBurnerLoans.AssetFeeConfig memory maxSlope;
        maxSlope.preKinkSlopeBps = 10_000;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory maxSlopeSelection;
        maxSlopeSelection.preKinkSlopeBps = true;

        vm.startPrank(burnerLoansAdmin);
        uint64 singleSlopeActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            singleSlope,
            singleSlopeSelection
        );
        uint64 riskActionId = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            riskUpdate,
            riskSelection
        );
        uint64 maxSlopeActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            maxSlope,
            maxSlopeSelection
        );
        vm.stopPrank();

        assertEq(singleSlopeActionId, 1, "single slope action id");
        assertEq(riskActionId, 2, "risk action id");
        assertEq(maxSlopeActionId, 3, "max slope action id");
    }

    // queueSetAssetFeeConfig
    // given the latest queued fee projection is cancelled but an earlier fee action remains pending
    //  when a later preKinkSlopeBps update is queued and executed after the earlier pending action
    //   then validation falls back to the pending projected fee config, not the cancelled config
    function test_givenLatestFeeProjectionCancelled_laterFeeActionUsesEarlierPendingProjection()
        public
    {
        // Action 1 converts the curve to zero-kink single-slope mode. The final 10,000 bps
        // pre-kink slope is valid only against that projected state. Action 2 exists only to
        // become the latest cached fee projection and then be cancelled.
        IBurnerLoans.AssetFeeConfig memory singleSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory singleSlopeSelection;
        singleSlopeSelection.baseFeeBps = true;
        singleSlopeSelection.kinkBps = true;
        singleSlopeSelection.postKinkSlopeBps = true;

        IBurnerLoans.AssetFeeConfig memory cancelledUpdate;
        cancelledUpdate.baseFeeBps = 1;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory cancelledSelection;
        cancelledSelection.baseFeeBps = true;

        IBurnerLoans.AssetFeeConfig memory maxSlope;
        maxSlope.preKinkSlopeBps = 10_000;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory maxSlopeSelection;
        maxSlopeSelection.preKinkSlopeBps = true;

        vm.startPrank(burnerLoansAdmin);
        uint64 singleSlopeActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            singleSlope,
            singleSlopeSelection
        );
        uint64 cancelledActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            cancelledUpdate,
            cancelledSelection
        );
        vm.stopPrank();

        vm.prank(emergency);
        configTimelock.cancelQueuedAction(cancelledActionId);

        vm.prank(burnerLoansAdmin);
        uint64 maxSlopeActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            maxSlope,
            maxSlopeSelection
        );

        assertEq(singleSlopeActionId, 1, "single slope action id");
        assertEq(cancelledActionId, 2, "cancelled action id");
        assertEq(maxSlopeActionId, 3, "max slope action id");

        vm.warp(block.timestamp + configTimelock.timelockDelay());

        // Executing action 1 then action 3 proves action 3's expected pre-state is exactly
        // action 1's post-state. If cancellation left action 2's base-fee projection in the
        // chain, action 3 would expect baseFeeBps = 1 and revert here.
        configTimelock.executeQueuedAction(singleSlopeActionId);
        configTimelock.executeQueuedAction(maxSlopeActionId);

        IBurnerLoans.AssetFeeConfig memory config = burnerLoans.getAssetFeeConfig(address(usds));
        assertEq(config.baseFeeBps, 0, "cancelled base fee not applied");
        assertEq(config.kinkBps, 0, "kink");
        assertEq(config.preKinkSlopeBps, 10_000, "pre-kink slope");
        assertEq(config.postKinkSlopeBps, 0, "post-kink slope");
    }

    // queueSetAssetFeeConfig
    // given an unrelated risk action is queued after a fee action removes the kink
    //  when a later postKinkSlopeBps update is queued
    //   then validation ignores risk state and reverts against the projected fee config
    function test_givenRiskActionBetweenFeeActions_laterInvalidFeeActionRevertsAgainstProjectedState()
        public
    {
        // The later postKinkSlope update would be valid against the live default kinked curve. It is
        // invalid only because the earlier queued fee action projected the curve into zero-kink
        // mode, where postKinkSlopeBps must stay zero.
        IBurnerLoans.AssetFeeConfig memory singleSlope = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 0,
            postKinkSlopeBps: 0
        });
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory singleSlopeSelection;
        singleSlopeSelection.kinkBps = true;
        singleSlopeSelection.postKinkSlopeBps = true;

        IBurnerLoansConfigTimelock.AssetRiskConfigUpdate memory riskUpdate;
        riskUpdate.collateralFactorBps = 9_500;
        IBurnerLoansConfigTimelock.AssetRiskConfigUpdateSelection memory riskSelection;
        riskSelection.collateralFactorBps = true;

        IBurnerLoans.AssetFeeConfig memory invalidSlope2;
        invalidSlope2.postKinkSlopeBps = 100;
        IBurnerLoansConfigTimelock.FeeConfigUpdateSelection memory invalidSlope2Selection;
        invalidSlope2Selection.postKinkSlopeBps = true;

        vm.startPrank(burnerLoansAdmin);
        uint64 singleSlopeActionId = configTimelock.queueSetAssetFeeConfig(
            address(usds),
            singleSlope,
            singleSlopeSelection
        );
        uint64 riskActionId = configTimelock.queueSetAssetRiskConfig(
            address(usds),
            riskUpdate,
            riskSelection
        );
        vm.expectRevert(IBurnerLoans.BurnerLoans_InvalidFeeConfig.selector);
        configTimelock.queueSetAssetFeeConfig(address(usds), invalidSlope2, invalidSlope2Selection);
        vm.stopPrank();

        assertEq(singleSlopeActionId, 1, "single slope action id");
        assertEq(riskActionId, 2, "risk action id");
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
