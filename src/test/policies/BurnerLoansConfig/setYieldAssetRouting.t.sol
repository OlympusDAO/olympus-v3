// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Interfaces
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";

// Libraries
import {Vm} from "forge-std/Vm.sol";

// Contracts
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {BurnerLoansYieldRoutingTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansYieldRoutingTestBase.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// Test loops call assertions, cheatcodes, or fixtures over bounded collections.
// forge-lint: disable-start(unsafe-typecast,calls-loop)

contract BurnerLoansConfigSetYieldAssetRoutingTest is BurnerLoansYieldRoutingTestBase {
    MockERC4626 internal usdsVault;

    function setUp() public override {
        super.setUp();
        usdsVault = _addDefaultUsdsVaultAsset();
    }

    modifier givenDefaultConfigOperator() {
        _setDefaultConfigOperator();
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenDisabled() {
        vm.prank(admin);
        burnerLoansConfig.disable("");
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenReEnabled() {
        vm.startPrank(admin);
        burnerLoansConfig.disable("");
        burnerLoansConfig.reEnable();
        vm.stopPrank();
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenRepurchaseRecipientConfigured() {
        _configureYieldRepurchaseRecipientAsset(address(usds), address(usdsVault));
        vm.prank(admin);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));
        _;
    }

    // Retained to express the test precondition with the suite's given* structure.
    // forge-lint: disable-next-line(modifier-used-only-once)
    modifier givenYieldRepurchaseRecipient() {
        vm.prank(admin);
        burnerLoansConfig.setYieldRepurchaseRecipient(address(yieldRecipient));
        _;
    }

    function test_givenUnauthorizedCaller_reverts(
        address caller_
    ) public givenDefaultConfigOperator {
        vm.assume(caller_ != admin);
        vm.assume(caller_ != address(configTimelock));

        vm.prank(caller_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansConfig.BurnerLoansConfig_UnauthorizedConfigOperator.selector,
                caller_
            )
        );
        burnerLoansConfig.setYieldAssetRouting(address(usds), _treasuryOnlyRouting());
    }

    function test_givenDisabled_reverts() public givenDisabled {
        vm.prank(admin);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoansConfig.setYieldAssetRouting(address(usds), _treasuryOnlyRouting());
    }

    function test_givenReEnabled_givenAdmin_forwardsEmptyRouteWithoutDuplicateEvent()
        public
        givenReEnabled
        givenRepurchaseRecipientConfigured
    {
        IBurnerLoans.AssetYieldRouting memory expected = _repurchaseRouting(2_500);

        vm.recordLogs();
        vm.prank(admin);
        burnerLoansConfig.setYieldAssetRouting(address(usds), expected);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "configuration event count");
        assertEq(entries[0].emitter, address(burnerLoans), "configuration event emitter");
        _assertRouting(burnerLoans.getYieldAssetRouting(address(usds)), expected);
    }

    function test_givenAdmin_forwardsOneDirectAllocationInOrder() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient");
        uint16[] memory bps = new uint16[](1);
        bps[0] = 4_000;
        IBurnerLoans.AssetYieldRouting memory expected = _directRouting(recipients, bps);

        vm.recordLogs();
        vm.prank(admin);
        burnerLoansConfig.setYieldAssetRouting(address(usds), expected);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "configuration event count");
        assertEq(entries[0].emitter, address(burnerLoans), "configuration event emitter");
        _assertRouting(burnerLoans.getYieldAssetRouting(address(usds)), expected);
    }

    function test_givenConfigOperator_forwardsMoreThanFiveDirectAllocationsInOrder()
        public
        givenDefaultConfigOperator
    {
        address[] memory recipients = new address[](10);
        uint16[] memory bps = new uint16[](10);
        for (uint256 i; i < recipients.length; ++i) {
            recipients[i] = makeAddr(string.concat("recipient", vm.toString(i)));
            bps[i] = uint16((i + 1) * 100);
        }
        IBurnerLoans.AssetYieldRouting memory expected = _directRouting(recipients, bps);

        vm.prank(address(configTimelock));
        burnerLoansConfig.setYieldAssetRouting(address(usds), expected);

        _assertRouting(burnerLoans.getYieldAssetRouting(address(usds)), expected);
    }

    function test_givenNonTreasuryTotalExceedsMaximum_propagatesFacilityCustomError() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient");
        uint16[] memory bps = new uint16[](1);
        bps[0] = 10_001;
        IBurnerLoans.AssetYieldRouting memory routing = _directRouting(recipients, bps);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidAssetYieldRoutingTotal.selector,
                10_001
            )
        );
        burnerLoansConfig.setYieldAssetRouting(address(usds), routing);
    }

    function test_givenDirectRecipientCollidesWithTreasury_propagatesFacilityCustomError() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(trsry);
        uint16[] memory bps = new uint16[](1);
        bps[0] = 1;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDirectYieldRecipient.selector,
                address(trsry)
            )
        );
        burnerLoansConfig.setYieldAssetRouting(address(usds), _directRouting(recipients, bps));
    }

    function test_givenRepurchaseRecipientMissing_propagatesFacilityCustomError() public {
        vm.prank(admin);
        vm.expectRevert(IBurnerLoans.BurnerLoans_YieldRepurchaseRecipientNotConfigured.selector);
        burnerLoansConfig.setYieldAssetRouting(address(usds), _repurchaseRouting(1));
    }

    function test_givenRepurchaseVaultRouteInvalid_propagatesRecipientCustomError()
        public
        givenYieldRepurchaseRecipient
    {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldRepurchaseRecipient.YieldRepurchaseRecipient_VaultNotRegistered.selector,
                address(usdsVault)
            )
        );
        burnerLoansConfig.setYieldAssetRouting(address(usds), _repurchaseRouting(1));
    }

    function _assertRouting(
        IBurnerLoans.AssetYieldRouting memory actual_,
        IBurnerLoans.AssetYieldRouting memory expected_
    ) internal pure {
        assertEq(
            actual_.repurchaseRecipientBps,
            expected_.repurchaseRecipientBps,
            "repurchase recipient bps"
        );
        assertEq(
            actual_.directAllocations.length,
            expected_.directAllocations.length,
            "direct allocation count"
        );
        for (uint256 i; i < expected_.directAllocations.length; ++i) {
            assertEq(
                actual_.directAllocations[i].recipient,
                expected_.directAllocations[i].recipient,
                "direct recipient"
            );
            assertEq(
                actual_.directAllocations[i].bps,
                expected_.directAllocations[i].bps,
                "direct recipient bps"
            );
        }
    }
}

// forge-lint: disable-end(unsafe-typecast,calls-loop)

// forge-lint: disable-end(literal-instead-of-constant)
