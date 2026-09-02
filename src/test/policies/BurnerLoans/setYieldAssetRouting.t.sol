// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Libraries
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {BurnerLoansYieldRoutingTestBase} from "./fixtures/BurnerLoansYieldRoutingTestBase.sol";

contract BurnerLoansSetYieldAssetRoutingTest is BurnerLoansYieldRoutingTestBase {
    function test_whenValidRouteValidated_callerIsArbitrary(address caller_) public {
        _addDefaultUsdsAsset();

        vm.prank(caller_);
        burnerLoans.validateYieldAssetRouting(address(usds), _treasuryOnlyRouting());
    }

    function test_givenBurnerLoansDisabled_whenRouteValidated_reverts() public {
        _addDefaultUsdsAsset();
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.validateYieldAssetRouting(address(usds), _treasuryOnlyRouting());
    }

    function test_givenNewAsset_defaultsToImplicitTreasuryOnlyRoute() public {
        _addDefaultUsdsAsset();

        IBurnerLoans.AssetYieldRouting memory routing = burnerLoans.getYieldAssetRouting(
            address(usds)
        );
        assertEq(routing.repurchaseRecipientBps, 0, "default repurchase bps");
        assertEq(routing.directAllocations.length, 0, "default direct count");
    }

    function test_whenCallerIsNotConfigurator_reverts(address caller_) public {
        _addDefaultUsdsAsset();
        vm.assume(caller_ != address(burnerLoansConfig));

        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_OnlyConfigurator.selector, caller_)
        );
        vm.prank(caller_);
        burnerLoans.setYieldAssetRouting(address(usds), _treasuryOnlyRouting());
    }

    function test_givenBurnerLoansDisabled_reverts() public {
        _addDefaultUsdsAsset();
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        _setYieldAssetRouting(address(usds), _treasuryOnlyRouting());
    }

    function test_whenAssetIsUnregistered_reverts(address asset_) public {
        vm.assume(asset_ != address(usds));
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoans.BurnerLoans_AssetNotConfigured.selector, asset_)
        );
        _setYieldAssetRouting(asset_, _treasuryOnlyRouting());
    }

    function test_givenRepurchaseRecipientUnset_whenRepurchaseBpsNonZero_reverts(
        uint16 repurchaseBps_
    ) public {
        _addDefaultUsdsAsset();
        repurchaseBps_ = uint16(bound(repurchaseBps_, 1, BurnerLoansConstants.MAX_BPS));

        vm.expectRevert(IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotConfigured.selector);
        _setYieldAssetRouting(address(usds), _repurchaseRouting(repurchaseBps_));
    }

    function test_givenDirectCustodyAsset_whenRepurchaseBpsNonZero_reverts() public {
        _addDefaultUsdsAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        yieldRecipient.setRevertGetVaultConfig(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientVaultRequired.selector,
                address(usds)
            )
        );
        _setYieldAssetRouting(address(usds), _repurchaseRouting(1));
    }

    function test_givenRepurchaseRecipientInvalid_whenRepurchaseBpsZero_allowsRepair() public {
        (MockERC20 asset, ) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        _setYieldAssetRouting(address(asset), _repurchaseRouting(1));
        yieldRecipient.setEnabled(false);

        _setYieldAssetRouting(address(asset), _treasuryOnlyRouting());

        assertEq(
            burnerLoans.getYieldAssetRouting(address(asset)).repurchaseRecipientBps,
            0,
            "cleared repurchase bps"
        );
    }

    function test_whenDirectAllocationCountExceedsFive_succeeds() public {
        _addDefaultUsdsAsset();
        address[] memory recipients = new address[](6);
        uint16[] memory bps = new uint16[](6);
        for (uint256 i; i < 6; ++i) {
            recipients[i] = makeAddr(string.concat("recipient", vm.toString(i)));
            bps[i] = 1;
        }

        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));

        assertEq(
            burnerLoans.getYieldAssetRouting(address(usds)).directAllocations.length,
            6,
            "direct count"
        );
    }

    function test_whenNonTreasuryTotalIsBelowMaximum_succeeds(
        uint16 repurchaseBps_,
        uint16 directBps_
    ) public {
        (MockERC20 asset, ) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        repurchaseBps_ = uint16(bound(repurchaseBps_, 0, BurnerLoansConstants.MAX_BPS));
        directBps_ = uint16(bound(directBps_, 0, BurnerLoansConstants.MAX_BPS - repurchaseBps_));
        address recipient = makeAddr("recipient");
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.repurchaseRecipientBps = repurchaseBps_;
        if (directBps_ != 0) {
            routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](1);
            routing.directAllocations[0] = IBurnerLoans.DirectYieldAllocation({
                recipient: recipient,
                bps: directBps_
            });
        } else {
            routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](0);
        }

        _setYieldAssetRouting(address(asset), routing);

        IBurnerLoans.AssetYieldRouting memory stored = burnerLoans.getYieldAssetRouting(
            address(asset)
        );
        assertEq(stored.repurchaseRecipientBps, repurchaseBps_, "repurchase bps");
        assertEq(stored.directAllocations.length, directBps_ == 0 ? 0 : 1, "direct count");
    }

    function test_whenNonTreasuryTotalExceedsMaximum_reverts(
        uint16 repurchaseBps_,
        uint16 directBps_
    ) public {
        _addDefaultUsdsAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        repurchaseBps_ = uint16(bound(repurchaseBps_, 0, BurnerLoansConstants.MAX_BPS));
        directBps_ = uint16(
            bound(directBps_, BurnerLoansConstants.MAX_BPS - repurchaseBps_ + 1, type(uint16).max)
        );
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](1);
        routing.directAllocations[0] = IBurnerLoans.DirectYieldAllocation({
            recipient: makeAddr("recipient"),
            bps: directBps_
        });
        routing.repurchaseRecipientBps = repurchaseBps_;
        uint256 totalBps = uint256(repurchaseBps_) + directBps_;

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidAssetYieldRoutingTotal.selector,
                totalBps
            )
        );
        _setYieldAssetRouting(address(usds), routing);
    }

    function test_whenRepurchaseBpsIsMaximumRepresentableValue_revertsWithoutPanic() public {
        _addDefaultUsdsAsset();
        IBurnerLoans.AssetYieldRouting memory routing = _treasuryOnlyRouting();
        routing.repurchaseRecipientBps = type(uint16).max;

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidAssetYieldRoutingTotal.selector,
                type(uint16).max
            )
        );
        _setYieldAssetRouting(address(usds), routing);
    }

    function test_whenRepurchaseAndDirectBpsAreMaximumRepresentableValues_revertsWithoutPanic()
        public
    {
        _addDefaultUsdsAsset();
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](1);
        routing.directAllocations[0] = IBurnerLoans.DirectYieldAllocation({
            recipient: makeAddr("recipient"),
            bps: type(uint16).max
        });
        routing.repurchaseRecipientBps = type(uint16).max;

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidAssetYieldRoutingTotal.selector,
                uint256(type(uint16).max) * 2
            )
        );
        _setYieldAssetRouting(address(usds), routing);
    }

    function test_whenOneOfMultipleDirectRecipientsIsZero_reverts(uint8 zeroIndex_) public {
        _addDefaultUsdsAsset();
        zeroIndex_ = uint8(bound(zeroIndex_, 0, 2));
        address[] memory recipients = new address[](3);
        uint16[] memory bps = new uint16[](3);
        for (uint256 i; i < recipients.length; ++i) {
            recipients[i] = makeAddr(string.concat("recipient", vm.toString(i)));
            bps[i] = 1;
        }
        recipients[zeroIndex_] = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient.selector,
                address(0)
            )
        );
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
    }

    function test_whenOneOfMultipleDirectBpsIsZero_reverts(uint8 zeroIndex_) public {
        _addDefaultUsdsAsset();
        zeroIndex_ = uint8(bound(zeroIndex_, 0, 2));
        IBurnerLoans.AssetYieldRouting memory routing;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](3);
        for (uint256 i; i < routing.directAllocations.length; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: makeAddr(string.concat("recipient", vm.toString(i))),
                bps: i == zeroIndex_ ? 0 : 1
            });
        }
        address zeroBpsRecipient = routing.directAllocations[zeroIndex_].recipient;

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDirectYieldAllocationBps.selector,
                zeroBpsRecipient
            )
        );
        _setYieldAssetRouting(address(usds), routing);
    }

    function test_whenDirectRecipientIsDuplicated_reverts() public {
        _addDefaultUsdsAsset();
        address recipient = makeAddr("recipient");
        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = recipient;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 5_000;
        bps[1] = 5_000;

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_DuplicateDirectYieldRecipient.selector,
                recipient
            )
        );
        _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
    }

    function test_whenDirectRecipientIsReserved_reverts() public {
        _addDefaultUsdsAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        address[3] memory reserved = [
            address(burnerLoans),
            address(trsry),
            address(yieldRecipient)
        ];
        for (uint256 i; i < reserved.length; ++i) {
            address[] memory recipients = new address[](1);
            recipients[0] = reserved[i];
            uint16[] memory bps = new uint16[](1);
            bps[0] = 1;

            vm.expectRevert(
                abi.encodeWithSelector(
                    IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient.selector,
                    reserved[i]
                )
            );
            _setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
        }
    }

    function test_givenExistingRoute_whenReplacementSet_removesOldAllocations() public {
        _addDefaultUsdsAsset();
        address[] memory firstRecipients = new address[](2);
        firstRecipients[0] = makeAddr("first");
        firstRecipients[1] = makeAddr("second");
        uint16[] memory firstBps = new uint16[](2);
        firstBps[0] = 1_000;
        firstBps[1] = 2_000;
        _setYieldAssetRouting(address(usds), _directRouting(firstRecipients, firstBps));

        address[] memory replacementRecipients = new address[](1);
        replacementRecipients[0] = makeAddr("replacement");
        uint16[] memory replacementBps = new uint16[](1);
        replacementBps[0] = 3_000;
        _setYieldAssetRouting(address(usds), _directRouting(replacementRecipients, replacementBps));

        IBurnerLoans.AssetYieldRouting memory stored = burnerLoans.getYieldAssetRouting(
            address(usds)
        );
        assertEq(stored.directAllocations.length, 1, "replacement direct count");
        assertEq(
            stored.directAllocations[0].recipient,
            replacementRecipients[0],
            "replacement recipient"
        );
    }

    function test_givenSameValidRoute_revalidatesThenEmitsNoEvent() public {
        (MockERC20 asset, ) = _addYieldAsset();
        _setYieldRepurchaseRecipient(address(yieldRecipient));
        IBurnerLoans.AssetYieldRouting memory routing = _repurchaseRouting(5_000);
        _setYieldAssetRouting(address(asset), routing);

        vm.recordLogs();
        _setYieldAssetRouting(address(asset), routing);
        assertEq(vm.getRecordedLogs().length, 0, "no-op event count");

        yieldRecipient.setEnabled(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotEnabled.selector,
                address(yieldRecipient)
            )
        );
        _setYieldAssetRouting(address(asset), routing);
    }
}
