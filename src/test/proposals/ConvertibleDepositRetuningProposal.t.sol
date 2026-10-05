// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
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
        vm.createSelectFork(
            vm.envOr("RPC_URL", _RPC_ALIAS),
            vm.envOr("FORK_BLOCK", uint256(26_127_004))
        );
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
        _receiptId = _depositManager.getReceiptTokenId(_usds, 3, address(_facility));
        _supplyBefore = IReceiptSupply(address(_receipts)).totalSupply(_receiptId);

        // Move existing receipts on the fork only; no minting or balance storage overrides.
        address holder = address(bytes20(hex"f3dcaeb909d3d17318c0908a1ec0ca31321e1672"));
        _user = makeAddr("redemption-regression-user");
        assertGe(_receipts.balanceOf(holder, _receiptId), 300e18, "Fixture holder lacks receipts");
        vm.prank(holder);
        _receipts.transfer(_user, _receiptId, 300e18);
        vm.startPrank(_user);
        _receipts.approve(address(_vault), _receiptId, 100e18);
        _redemptionId = _vault.startRedemption(_usds, 3, 100e18, address(_facility));
        vm.stopPrank();
        _redemptionBefore = _vault.getUserRedemption(_user, _redemptionId);
        assertEq(
            _facility.getAssetPeriodReclaimRate(_usds, 3),
            9750,
            "Fixture reclaim rate changed"
        );
        _simulateProposal();
    }

    function test_givenProposalExecuted_parametersAndReceiptsPreserved() public view {
        assertEq(_facility.getAssetPeriodReclaimRate(_usds, 3), 9000, "3-month reclaim target");
        assertEq(_facility.getAssetPeriodReclaimRate(_usds, 6), 9900, "6-month reclaim unchanged");
        (, bool threeMonthPending) = _auctioneer.isDepositPeriodEnabled(3);
        (, bool sixMonthPending) = _auctioneer.isDepositPeriodEnabled(6);
        assertTrue(threeMonthPending, "3-month period queued");
        assertFalse(sixMonthPending, "6-month period queued off");
        assertEq(_auctioneer.getMinimumBid(), 100e18, "Minimum bid target");
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
        assertApproxEqAbs(paid, 100e18, 5, "Full principal, not 90% reclaim");
        assertEq(_usds.balanceOf(_user) - balanceBefore, paid, "Actual redemption transfer");
        assertEq(_vault.getUserRedemption(_user, _redemptionId).amount, 0, "Redemption consumed");
    }

    function test_givenExistingReceipts_reclaimUsesNewRate() public {
        _assertReclaim();
    }

    function test_givenCancelledRedemption_reclaimUsesNewRate() public {
        vm.prank(_user);
        _vault.cancelRedemption(_redemptionId, 100e18);
        assertEq(_vault.getUserRedemption(_user, _redemptionId).amount, 0, "Redemption cancelled");
        assertEq(_receipts.balanceOf(_user, _receiptId), 300e18, "Receipts returned");
        _assertReclaim();
    }

    function _assertReclaim() internal {
        uint256 preview = _facility.previewReclaim(_usds, 3, 100e18);
        assertEq(preview, 90e18, "New reclaim rate is 90%");
        uint256 balanceBefore = _usds.balanceOf(_user);
        vm.startPrank(_user);
        _receipts.approve(address(_depositManager), _receiptId, 100e18);
        uint256 paid = _facility.reclaim(_usds, 3, 100e18);
        vm.stopPrank();
        assertApproxEqAbs(paid, preview, 5, "Reclaim matches preview within vault rounding");
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
        for (uint256 i; i < 3; ++i) {
            vm.prank(heart);
            _emissionManager.execute();
        }
        assertEq(_emissionManager.baseEmissionRate(), 1_000_000, "0.10% base rate active");
        (, uint48 daysLeft, ) = _emissionManager.rateChange();
        assertEq(daysLeft, 0, "Scheduled rate change consumed");
        (bool threeMonthActive, ) = _auctioneer.isDepositPeriodEnabled(3);
        (bool sixMonthActive, ) = _auctioneer.isDepositPeriodEnabled(6);
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
