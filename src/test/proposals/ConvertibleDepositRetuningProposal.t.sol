// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

// Libraries
import {SafeCast} from "@openzeppelin-4.8.0/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {console2} from "forge-std/console2.sol";

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositRedemptionVault} from "src/policies/interfaces/deposits/IDepositRedemptionVault.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Contracts
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {ConvertibleDepositRetuningProposal} from "src/proposals/ConvertibleDepositRetuningProposal.sol";
import {ProposalTest} from "./ProposalTest.sol";

interface IReceiptSupply {
    function totalSupply(uint256 tokenId) external view returns (uint256);
}

contract ConvertibleDepositRetuningProposalTest is ProposalTest {
    uint8 internal constant _TARGET_PERIOD = 3;
    uint8 internal constant _LEGACY_PERIOD = 6;
    uint256 internal constant _FIXTURE_RECEIPTS = 300e18;
    uint256 internal constant _DEPOSIT_AMOUNT = 100e18;
    uint256 internal constant _MINIMUM_BID = 100e18;
    uint256 internal constant _ROUNDING_TOLERANCE = 5;
    uint256 internal constant _AUCTION_UPDATE_BEATS = 3;
    IERC20 internal _usds;
    IDepositFacility internal _facility;
    IDepositManager internal _depositManager;
    IDepositRedemptionVault internal _vault;
    IReceiptTokenManager internal _receipts;
    IConvertibleDepositAuctioneer internal _auctioneer;
    EmissionManager internal _emissionManager;
    uint256 internal _receiptId;
    uint256 internal _supplyBefore;
    uint256 internal _currentPriceBeforeGovernance;
    address internal _user;
    uint16 internal _redemptionId;
    IDepositRedemptionVault.UserRedemption internal _redemptionBefore;

    function setUp() public virtual {
        // Fixed mainnet fixture; RPC_URL can point to an archive provider without changing repo config.
        uint256 forkId = vm.createSelectFork(
            vm.envOr("RPC_URL", _RPC_ALIAS),
            vm.envOr("FORK_BLOCK", uint256(26_127_004))
        );
        assertEq(vm.activeFork(), forkId, "Pinned fork selected");
        console2.log("Fork block", block.number);
        _setupSuite(address(new ConvertibleDepositRetuningProposal()));
        hasBeenSubmitted = false;
        _usds = IERC20(addresses.getAddress("external-tokens-USDS"));
        _facility = IDepositFacility(
            addresses.getAddress("olympus-policy-convertible-deposit-facility-1_0")
        );
        _depositManager = IDepositManager(
            addresses.getAddress("olympus-policy-deposit-manager-1_0")
        );
        _vault = IDepositRedemptionVault(
            addresses.getAddress("olympus-policy-deposit-redemption-vault-1_0")
        );
        _receipts = _depositManager.getReceiptTokenManager();
        _auctioneer = IConvertibleDepositAuctioneer(
            addresses.getAddress("olympus-policy-convertible-deposit-auctioneer-1_0")
        );
        _emissionManager = EmissionManager(
            addresses.getAddress("olympus-policy-emissionmanager-1_2")
        );
        _currentPriceBeforeGovernance = _emissionManager.PRICE().getCurrentPrice();
        assertGt(_currentPriceBeforeGovernance, 0, "Pinned oracle price is nonzero");
        _receiptId = _depositManager.getReceiptTokenId(_usds, _TARGET_PERIOD, address(_facility));
        _supplyBefore = IReceiptSupply(address(_receipts)).totalSupply(_receiptId);

        // Move existing receipts on the fork only; no minting or balance storage overrides.
        address holder = 0xF3DCaeb909d3D17318C0908A1eC0Ca31321E1672;
        _user = makeAddr("redemption-regression-user");
        assertGe(
            _receipts.balanceOf(holder, _receiptId),
            _FIXTURE_RECEIPTS,
            "Fixture holder lacks receipts"
        );
        vm.prank(holder);
        assertTrue(
            _receipts.transfer(_user, _receiptId, _FIXTURE_RECEIPTS),
            "Fixture transfer succeeded"
        );
        vm.startPrank(_user);
        assertTrue(
            _receipts.approve(address(_vault), _receiptId, _DEPOSIT_AMOUNT),
            "Redemption approval succeeded"
        );
        _redemptionId = _vault.startRedemption(
            _usds,
            _TARGET_PERIOD,
            _DEPOSIT_AMOUNT,
            address(_facility)
        );
        vm.stopPrank();
        _redemptionBefore = _vault.getUserRedemption(_user, _redemptionId);
        assertEq(
            _facility.getAssetPeriodReclaimRate(_usds, _TARGET_PERIOD),
            9750,
            "Fixture reclaim rate changed"
        );
        _simulateProposal();
    }

    function test_givenProposalExecuted_parametersAndReceiptsPreserved() public view {
        assertEq(
            _facility.getAssetPeriodReclaimRate(_usds, _TARGET_PERIOD),
            9000,
            "3-month reclaim target"
        );
        assertEq(
            _facility.getAssetPeriodReclaimRate(_usds, _LEGACY_PERIOD),
            9900,
            "6-month reclaim unchanged"
        );
        (, bool threeMonthPending) = _auctioneer.isDepositPeriodEnabled(_TARGET_PERIOD);
        (, bool sixMonthPending) = _auctioneer.isDepositPeriodEnabled(_LEGACY_PERIOD);
        assertTrue(threeMonthPending, "3-month period queued");
        assertFalse(sixMonthPending, "6-month period queued off");
        assertEq(_auctioneer.getMinimumBid(), _MINIMUM_BID, "Minimum bid target");
        assertEq(_auctioneer.getTickStep(), 10010, "0.10% tick increment");
        assertEq(_emissionManager.tickSize(), 10_000e9, "Standard tick target");
        assertEq(_emissionManager.minPriceScalar(), 1.1e18, "Price scalar unchanged");
        assertEq(_emissionManager.minimumPremium(), 0.5e18, "Minimum premium unchanged");
        assertEq(_auctioneer.getTickSizeBase(), 2e18, "Tick-size base unchanged");
        assertEq(
            IAssetManager(address(_depositManager)).getAssetConfiguration(_usds).depositCap,
            60_000_000e18,
            "Deposit cap unchanged"
        );
        assertEq(
            IReceiptSupply(address(_receipts)).totalSupply(_receiptId),
            _supplyBefore,
            "Existing supply unchanged"
        );
    }

    function test_givenExistingRedemption_finishesWithoutReclaimDiscount() public {
        IDepositRedemptionVault.UserRedemption memory afterProposal = _vault.getUserRedemption(
            _user,
            _redemptionId
        );
        assertEq(
            abi.encode(afterProposal),
            abi.encode(_redemptionBefore),
            "Existing redemption record unchanged"
        );
        vm.warp(afterProposal.redeemableAt);
        uint256 balanceBefore = _usds.balanceOf(_user);
        vm.prank(_user);
        uint256 paid = _vault.finishRedemption(_redemptionId);
        assertApproxEqAbs(
            paid,
            _DEPOSIT_AMOUNT,
            _ROUNDING_TOLERANCE,
            "Full principal, not 90% reclaim"
        );
        assertEq(_usds.balanceOf(_user) - balanceBefore, paid, "Actual redemption transfer");
        assertEq(_vault.getUserRedemption(_user, _redemptionId).amount, 0, "Redemption consumed");
    }

    function test_givenExistingReceipts_reclaimUsesNewRate() public {
        _assertReclaim();
    }

    function test_givenCancelledRedemption_reclaimUsesNewRate() public {
        vm.prank(_user);
        _vault.cancelRedemption(_redemptionId, _DEPOSIT_AMOUNT);
        assertEq(_vault.getUserRedemption(_user, _redemptionId).amount, 0, "Redemption cancelled");
        assertEq(_receipts.balanceOf(_user, _receiptId), _FIXTURE_RECEIPTS, "Receipts returned");
        _assertReclaim();
    }

    function _assertReclaim() internal {
        uint256 preview = _facility.previewReclaim(_usds, _TARGET_PERIOD, _DEPOSIT_AMOUNT);
        assertEq(preview, 90e18, "New reclaim rate is 90%");
        uint256 balanceBefore = _usds.balanceOf(_user);
        vm.startPrank(_user);
        assertTrue(
            _receipts.approve(address(_depositManager), _receiptId, _DEPOSIT_AMOUNT),
            "Reclaim approval succeeded"
        );
        uint256 paid = _facility.reclaim(_usds, _TARGET_PERIOD, _DEPOSIT_AMOUNT);
        vm.stopPrank();
        assertApproxEqAbs(
            paid,
            preview,
            _ROUNDING_TOLERANCE,
            "Reclaim matches preview within vault rounding"
        );
        assertEq(_usds.balanceOf(_user) - balanceBefore, paid, "Actual reclaim transfer");
    }

    function test_givenNextAuctionUpdate_deferredSettingsBecomeActive() public {
        // EmissionManager updates the auction every third authorized Heart call.
        // This exercises that component boundary, not the entire Heart keeper transaction.
        // Governance time travel does not publish new external oracle rounds.
        // Isolate activation from that frozen-feed artifact using the price read
        // from the actual PRICE module before governance. Only this component test
        // uses the fixture; the governance and holder-impact tests remain unmocked.
        vm.mockCall(
            address(_emissionManager.PRICE()),
            abi.encodeWithSignature("getCurrentPrice()"),
            abi.encode(_currentPriceBeforeGovernance)
        );
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        for (uint256 i = 0; i < _AUCTION_UPDATE_BEATS; ++i) {
            vm.prank(heart);
            _emissionManager.execute();
        }
        assertEq(_emissionManager.baseEmissionRate(), 1_000_000, "0.10% base rate active");
        (, uint48 daysLeft, ) = _emissionManager.rateChange();
        assertEq(daysLeft, 0, "Scheduled rate change consumed");
        (bool threeMonthActive, ) = _auctioneer.isDepositPeriodEnabled(_TARGET_PERIOD);
        (bool sixMonthActive, ) = _auctioneer.isDepositPeriodEnabled(_LEGACY_PERIOD);
        assertTrue(threeMonthActive, "3-month auction active");
        assertFalse(sixMonthActive, "6-month auction inactive");
        (, , uint256 expectedTarget) = _emissionManager.getNextEmission();
        uint256 expectedTick = _emissionManager.getSizeFor(expectedTarget);
        IConvertibleDepositAuctioneer.AuctionParameters memory params = _auctioneer
            .getAuctionParameters();
        assertEq(params.tickSize, expectedTick, "Auction tick updated");
        assertEq(params.target, expectedTick == 0 ? 0 : expectedTarget, "Auction target updated");
    }
}

/// @notice Builder-only regressions: mocked getter responses model drift at one pinned block.
/// @dev Uses the public build entry point; never executes the synthetic actions on the fork.
contract ConvertibleDepositRetuningBuilderTest is Test {
    uint8 internal constant _TARGET_PERIOD = 3;
    uint8 internal constant _LEGACY_PERIOD = 6;
    uint8 internal constant _LAST_CONTROL = 3;
    uint256 internal constant _TARGET_BASE_RATE = 1_000_000;
    uint256 internal constant _RATE_CHANGE = 100_000;
    Addresses internal _addresses;
    ConvertibleDepositRetuningProposal internal _proposal;
    address internal _manager;
    address internal _auctioneer;
    address internal _facility;
    address internal _deposits;
    IERC20 internal _usds;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.envOr("RPC_URL", string("mainnet")), 26_127_004);
        assertEq(vm.activeFork(), forkId, "Pinned fork selected");
        _addresses = new Addresses("./src/proposals/addresses.json");
        _proposal = new ConvertibleDepositRetuningProposal();
        _manager = _addresses.getAddress("olympus-policy-emissionmanager-1_2");
        _auctioneer = _addresses.getAddress("olympus-policy-convertible-deposit-auctioneer-1_0");
        _facility = _addresses.getAddress("olympus-policy-convertible-deposit-facility-1_0");
        _deposits = _addresses.getAddress("olympus-policy-deposit-manager-1_0");
        _usds = IERC20(_addresses.getAddress("external-tokens-USDS"));
    }

    function _build() internal {
        _proposal.run(_addresses, address(this), false, true, false, false, false, false);
    }

    function _mockPeriodState(uint8 period, bool current, bool pending) internal {
        vm.mockCall(
            _auctioneer,
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.isDepositPeriodEnabled.selector,
                period
            ),
            abi.encode(current, pending)
        );
    }

    function _mockPeriodInterface() internal {
        vm.mockCall(
            _auctioneer,
            abi.encodeWithSelector(IConvertibleDepositAuctioneer.isDepositPeriodEnabled.selector),
            abi.encode(false, false)
        );
        // The proposal must work with the existing interface, without the raw queue getter.
        vm.mockCallRevert(
            _auctioneer,
            abi.encodeWithSignature("getPendingDepositPeriodChanges()"),
            abi.encodeWithSelector(
                ConvertibleDepositRetuningProposal.ValidationFailed.selector,
                "Raw queue getter unavailable"
            )
        );
    }

    function _selector(bytes memory callData) internal pure returns (bytes4) {
        assertGe(callData.length, 4, "Action calldata includes a selector");
        // Deliberately extract the four-byte selector, excluding encoded arguments.
        return bytes4(callData);
    }

    function _assertPeriodActions(uint8 period, bool enableTarget, bool disablePeriod) internal {
        _build();
        (address[] memory targets, uint256[] memory values, bytes[] memory data) = _proposal
            .getProposalActions();
        uint256 enables = 0;
        uint256 disables = 0;
        for (uint256 i = 0; i < targets.length; ++i) {
            if (targets[i] != _auctioneer) continue;
            if (_selector(data[i]) == IConvertibleDepositAuctioneer.enableDepositPeriod.selector) {
                ++enables;
                assertEq(values[i], 0, "Period enable sends no ETH");
                assertEq(
                    data[i],
                    abi.encodeWithSelector(
                        IConvertibleDepositAuctioneer.enableDepositPeriod.selector,
                        _TARGET_PERIOD
                    ),
                    "Only enable target period"
                );
            }
            if (_selector(data[i]) == IConvertibleDepositAuctioneer.disableDepositPeriod.selector) {
                ++disables;
                assertEq(values[i], 0, "Period disable sends no ETH");
                assertEq(
                    data[i],
                    abi.encodeWithSelector(
                        IConvertibleDepositAuctioneer.disableDepositPeriod.selector,
                        period
                    ),
                    "Exact non-target period disable"
                );
            }
        }
        assertEq(enables, enableTarget ? 1 : 0, "Target enable count");
        assertEq(disables, disablePeriod ? 1 : 0, "Non-target disable count");
    }

    function test_givenTargetPeriodState(bool current, bool pending) public {
        _mockPeriodInterface();
        _mockPeriodState(_TARGET_PERIOD, current, pending);
        _assertPeriodActions(_LEGACY_PERIOD, !pending, false);
    }

    function test_givenNonTargetPeriodState(uint8 period, bool current, bool pending) public {
        vm.assume(period != _TARGET_PERIOD);
        _mockPeriodInterface();
        _mockPeriodState(_TARGET_PERIOD, false, true);
        _mockPeriodState(period, current, pending);
        _assertPeriodActions(period, false, pending);
    }

    function test_givenPendingOnlyPeriod_whenZero() public {
        _mockPeriodInterface();
        _mockPeriodState(0, false, true);
        _assertPeriodActions(0, true, true);
    }

    function test_givenPendingOnlyPeriod_whenOne() public {
        _mockPeriodInterface();
        _mockPeriodState(1, false, true);
        _assertPeriodActions(1, true, true);
    }

    function test_givenPendingOnlyPeriod_whenMaximum() public {
        _mockPeriodInterface();
        _mockPeriodState(type(uint8).max, false, true);
        _assertPeriodActions(type(uint8).max, true, true);
    }

    function test_whenUnchangedControlDrifts_reverts(uint8 control, uint256 value) public {
        control = SafeCast.toUint8(bound(control, 0, _LAST_CONTROL));
        uint256 expected = control == 0 ? 1.1e18 : control == 1 ? 0.5e18 : control == 2
            ? 2e18
            : 60_000_000e18;
        vm.assume(value != expected);
        string memory reason;
        if (control == _LAST_CONTROL) {
            IAssetManager.AssetConfiguration memory config = IAssetManager(_deposits)
                .getAssetConfiguration(_usds);
            config.depositCap = value;
            vm.mockCall(
                _deposits,
                abi.encodeWithSelector(IAssetManager.getAssetConfiguration.selector, _usds),
                abi.encode(config)
            );
            reason = "USDS deposit cap changed";
        } else {
            address target = control == 2 ? _auctioneer : _manager;
            bytes memory getter = control == 0
                ? abi.encodeWithSignature("minPriceScalar()")
                : control == 1
                ? abi.encodeWithSignature("minimumPremium()")
                : abi.encodeWithSelector(IConvertibleDepositAuctioneer.getTickSizeBase.selector);
            vm.mockCall(target, getter, abi.encode(value));
            reason = control == 0 ? "Minimum price scalar changed" : control == 1
                ? "Minimum premium changed"
                : "Tick-size base changed";
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                ConvertibleDepositRetuningProposal.ValidationFailed.selector,
                reason
            )
        );
        _build();
    }

    function test_whenLegacyReclaimDrifts_reverts(uint16 value) public {
        vm.assume(value != 9900);
        vm.mockCall(
            _facility,
            abi.encodeWithSelector(
                IDepositFacility.getAssetPeriodReclaimRate.selector,
                _usds,
                _LEGACY_PERIOD
            ),
            abi.encode(value)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ConvertibleDepositRetuningProposal.ValidationFailed.selector,
                "6-month reclaim rate changed"
            )
        );
        _build();
    }

    function _rate(uint256 current, uint256 change, uint48 remaining, bool addition) internal {
        vm.mockCall(_manager, abi.encodeWithSignature("baseEmissionRate()"), abi.encode(current));
        vm.mockCall(
            _manager,
            abi.encodeWithSignature("rateChange()"),
            abi.encode(change, remaining, addition)
        );
    }

    function _assertRateAction(
        bool expected,
        uint256 change,
        uint48 duration,
        bool addition
    ) internal {
        _build();
        (address[] memory targets, uint256[] memory values, bytes[] memory data) = _proposal
            .getProposalActions();
        uint256 count = 0;
        for (uint256 i = 0; i < targets.length; ++i) {
            if (
                targets[i] == _manager &&
                _selector(data[i]) == EmissionManager.changeBaseRate.selector
            ) {
                ++count;
                assertEq(values[i], 0, "Rate action sends no ETH");
                assertEq(
                    data[i],
                    abi.encodeWithSelector(
                        EmissionManager.changeBaseRate.selector,
                        change,
                        duration,
                        addition
                    ),
                    "Exact rate action"
                );
            }
        }
        assertEq(count, expected ? 1 : 0, "Rate action count");
    }

    function test_givenTargetRate_whenNoPendingChange() public {
        _rate(_TARGET_BASE_RATE, 0, 0, false);
        _assertRateAction(false, 0, 0, false);
    }

    function test_givenTargetRate_whenPendingChange() public {
        _rate(_TARGET_BASE_RATE, 10, 2, true);
        _assertRateAction(true, 0, 0, false);
    }

    function test_givenMatchingPendingChange(bool addition) public {
        _rate(
            addition ? (_TARGET_BASE_RATE - _RATE_CHANGE) : (_TARGET_BASE_RATE + _RATE_CHANGE),
            _RATE_CHANGE,
            1,
            addition
        );
        _assertRateAction(false, 0, 0, false);
    }

    function test_whenCurrentRateDiffers(uint256 current) public {
        vm.assume(current != _TARGET_BASE_RATE);
        _rate(current, 0, 0, false);
        bool addition = current < _TARGET_BASE_RATE;
        _assertRateAction(
            true,
            addition ? _TARGET_BASE_RATE - current : current - _TARGET_BASE_RATE,
            1,
            addition
        );
    }

    function test_whenCurrentRateIsMaximum() public {
        _rate(type(uint256).max, 0, 0, false);
        _assertRateAction(true, type(uint256).max - _TARGET_BASE_RATE, 1, false);
    }

    function test_givenConflictingPendingChange(uint8 mismatch) public {
        mismatch = SafeCast.toUint8(bound(mismatch, 0, 2));
        _rate(
            (_TARGET_BASE_RATE + _RATE_CHANGE),
            mismatch == 0 ? 1 : _RATE_CHANGE,
            mismatch == 1 ? 2 : 1,
            mismatch == 2
        );
        _assertRateAction(true, _RATE_CHANGE, 1, false);
    }
}
