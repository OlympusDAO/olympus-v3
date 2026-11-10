// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/deposits/IConvertibleDepositAuctioneer.sol";
import {IDepositFacility} from "src/policies/interfaces/deposits/IDepositFacility.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Contracts
import {EmissionManager} from "src/policies/EmissionManager.sol";
import {IHeart} from "src/policies/interfaces/IHeart.sol";
import {ConvertibleDepositRetuningProposal} from "src/proposals/ConvertibleDepositRetuningProposal.sol";
import {ProposalTest} from "./ProposalTest.sol";

contract ConvertibleDepositRetuningProposalTest is ProposalTest {
    uint8 internal constant _TARGET_PERIOD = 3;
    uint8 internal constant _LEGACY_PERIOD = 6;
    uint256 internal constant _MINIMUM_BID = 100e18;
    uint256 internal constant _AUCTION_UPDATE_BEATS = 3;
    IERC20 internal _usds;
    IDepositFacility internal _facility;
    IDepositManager internal _depositManager;
    IConvertibleDepositAuctioneer internal _auctioneer;
    EmissionManager internal _emissionManager;
    uint256 internal _currentPriceBeforeGovernance;

    function setUp() public {
        vm.createSelectFork(
            vm.envOr("RPC_URL", _RPC_ALIAS),
            vm.envOr("FORK_BLOCK", uint256(26_127_004))
        );
        _setupSuite(address(new ConvertibleDepositRetuningProposal()));
        hasBeenSubmitted = false;
        _usds = IERC20(addresses.getAddress("external-tokens-USDS"));
        _facility = IDepositFacility(
            addresses.getAddress("olympus-policy-convertible-deposit-facility-1_0")
        );
        _depositManager = IDepositManager(
            addresses.getAddress("olympus-policy-deposit-manager-1_0")
        );
        _auctioneer = IConvertibleDepositAuctioneer(
            addresses.getAddress("olympus-policy-convertible-deposit-auctioneer-1_0")
        );
        _emissionManager = EmissionManager(
            addresses.getAddress("olympus-policy-emissionmanager-1_2")
        );
        _currentPriceBeforeGovernance = _emissionManager.PRICE().getCurrentPrice();
        assertGt(_currentPriceBeforeGovernance, 0, "Pinned oracle price is nonzero");
        _simulateProposal();
    }

    function test_givenProposalExecuted_parametersConfigured() public view {
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
    }

    function test_givenProposalExecuted_givenNextAuctionUpdate_settingsBecomeActive() public {
        // Frozen fork oracle rounds become stale during governance and time travel.
        // Keep this component check at the actual pre-governance price.
        vm.mockCall(
            address(_emissionManager.PRICE()),
            abi.encodeWithSignature("getCurrentPrice()"),
            abi.encode(_currentPriceBeforeGovernance)
        );
        address heart = addresses.getAddress("olympus-policy-heart-1_7");
        uint256 frequency = IHeart(heart).frequency();
        for (uint256 i = 0; i < _AUCTION_UPDATE_BEATS; ++i) {
            vm.warp(block.timestamp + frequency);
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
    }
}
