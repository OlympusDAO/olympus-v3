// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {stdError} from "@forge-std-1.16.2/StdError.sol";
import {LoanMath} from "src/policies/burnerloans/libraries/LoanMath.sol";

// Contracts
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskKeeperRewardTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-KEEPER-REWARD-L01.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(_prices(), _MARKET, 0, 1000, 1000, false),
            10,
            "one percent reward"
        );
    }

    // Scenarios: BLRISK-KEEPER-REWARD-L02.
    function test_givenDisabled_whenCalled_reverts(address caller_) public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.keeperReward(_prices(), _MARKET, 0, 1000, 1000, false);
    }

    // Scenarios: BLRISK-KEEPER-REWARD-L03.
    function test_givenInactive_whenCalled_reverts(address caller_) public givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.keeperReward(_prices(), _MARKET, 0, 1000, 1000, false);
    }

    // Scenarios: BLRISK-KEEPER-REWARD-L04.
    function test_givenInactiveAndDisabled_whenCalled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.keeperReward(_prices(), _MARKET, 0, 1000, 1000, false);
    }

    // Scenarios: BLRISK-KEEPER-REWARD-L01.
    function test_givenReEnabled_whenCalled(address caller_) public givenReEnabled {
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(_prices(), _MARKET, 0, 1000, 1000, false),
            10,
            "one percent reward"
        );
    }

    function _reward(uint256 output_) private view returns (uint256) {
        return
            _risk.keeperReward(
                IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e12),
                _MARKET,
                1e9,
                output_,
                output_,
                false
            );
    }

    function _setReward(bool shares_, uint16 bps_, uint128 cap_) private {
        _data.withdrawAsShares = shares_;
        _data.keeperRewardBps = bps_;
        _data.maxKeeperReward = cap_;
        _mockMarket();
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N01.
    function test_whenBelowPercentBoundary() public {
        _setReward(false, 100, 100);
        // floor(999*100/10000), capped at 100 and at max(999-1,0) backing surplus.
        uint256 reward = _reward(999);
        assertEq(reward, 9, "independent underlying reward");
        assertEq(999 - reward, 990, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N08.
    function test_whenAtPercentBoundary() public {
        _setReward(false, 100, 100);
        // floor(1000*100/10000), capped at 100 and at max(1000-1,0) backing surplus.
        uint256 reward = _reward(1000);
        assertEq(reward, 10, "independent underlying reward");
        assertEq(1000 - reward, 990, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N09.
    function test_whenAbovePercentBoundary() public {
        _setReward(false, 100, 100);
        // floor(1001*100/10000), capped at 100 and at max(1001-1,0) backing surplus.
        uint256 reward = _reward(1001);
        assertEq(reward, 10, "independent underlying reward");
        assertEq(1001 - reward, 991, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N10.
    function test_whenCapBelowPercent() public {
        _setReward(false, 100, 9);
        // floor(1000*100/10000), capped at 9 and at max(1000-1,0) backing surplus.
        uint256 reward = _reward(1000);
        assertEq(reward, 9, "independent underlying reward");
        assertEq(1000 - reward, 991, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N11.
    function test_whenCapEqualsPercent() public {
        _setReward(false, 100, 10);
        // floor(1000*100/10000), capped at 10 and at max(1000-1,0) backing surplus.
        uint256 reward = _reward(1000);
        assertEq(reward, 10, "independent underlying reward");
        assertEq(1000 - reward, 990, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N12.
    function test_whenCapAbovePercent() public {
        _setReward(false, 100, 11);
        // floor(1000*100/10000), capped at 11 and at max(1000-1,0) backing surplus.
        uint256 reward = _reward(1000);
        assertEq(reward, 10, "independent underlying reward");
        assertEq(1000 - reward, 990, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N02.
    function test_whenBelowBacking() public {
        _setReward(false, 10000, 100);
        // floor(0*10000/10000), capped at 100 and at max(0-1,0) backing surplus.
        uint256 reward = _reward(0);
        assertEq(reward, 0, "independent underlying reward");
        assertEq(0 - reward, 0, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N13.
    function test_whenAtBacking() public {
        _setReward(false, 10000, 100);
        // floor(1*10000/10000), capped at 100 and at max(1-1,0) backing surplus.
        uint256 reward = _reward(1);
        assertEq(reward, 0, "independent underlying reward");
        assertEq(1 - reward, 1, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N14.
    function test_whenAboveBacking() public {
        _setReward(false, 10000, 100);
        // floor(2*10000/10000), capped at 100 and at max(2-1,0) backing surplus.
        uint256 reward = _reward(2);
        assertEq(reward, 1, "independent underlying reward");
        assertEq(2 - reward, 1, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N04.
    function test_whenFractionalUnderlyingReward() public {
        _setReward(false, 100, 100);
        // floor(99*100/10000), capped at 100 and at max(99-1,0) backing surplus.
        uint256 reward = _reward(99);
        assertEq(reward, 0, "independent underlying reward");
        assertEq(99 - reward, 99, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N06.
    function test_whenRewardLeavesBackingRemainder() public {
        _setReward(false, 9999, 100);
        // floor(2*9999/10000), capped at 100 and at max(2-1,0) backing surplus.
        uint256 reward = _reward(2);
        assertEq(reward, 1, "independent underlying reward");
        assertEq(2 - reward, 1, "remaining settlement allocation");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N15.
    function test_whenSharesBelowUnity() public {
        _setReward(true, 100, 100);
        // 100 underlying * 1%=1; shares=floor(50*1/100)=0.
        uint256 reward = _risk.keeperReward(_prices(), _MARKET, 0, 100, 50, false);
        assertEq(reward, 0, "independent share reward");
        assertEq(50 - reward, 50, "remaining output shares");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N16.
    function test_whenSharesAtUnity() public {
        _setReward(true, 100, 100);
        // 100 underlying * 1%=1; shares=floor(100*1/100)=1.
        uint256 reward = _risk.keeperReward(_prices(), _MARKET, 0, 100, 100, false);
        assertEq(reward, 1, "independent share reward");
        assertEq(100 - reward, 99, "remaining output shares");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N17.
    function test_whenSharesAboveUnity() public {
        _setReward(true, 100, 100);
        // 100 underlying * 1%=1; shares=floor(200*1/100)=2.
        uint256 reward = _risk.keeperReward(_prices(), _MARKET, 0, 100, 200, false);
        assertEq(reward, 2, "independent share reward");
        assertEq(200 - reward, 198, "remaining output shares");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N05.
    function test_whenFractionalShareReward() public {
        _setReward(true, 100, 100);
        // 100 underlying * 1%=1; shares=floor(1*1/100)=0.
        uint256 reward = _risk.keeperReward(_prices(), _MARKET, 0, 100, 1, false);
        assertEq(reward, 0, "independent share reward");
        assertEq(1 - reward, 1, "remaining output shares");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N07.
    function test_whenZeroShareOutput() public {
        _setReward(true, 100, 100);
        // 100 underlying * 1%=1; shares=floor(0*1/100)=0.
        uint256 reward = _risk.keeperReward(_prices(), _MARKET, 0, 100, 0, false);
        assertEq(reward, 0, "independent share reward");
        assertEq(0 - reward, 0, "remaining output shares");
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P01.
    function test_whenShareConversionUsesAnyRepresentableOutput(
        address caller_,
        uint256 output_
    ) public {
        _setReward(true, 100, 100);
        // One underlying reward out of 100; output/100 is exact independent integer division.
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(_prices(), _MARKET, 0, 100, output_, false),
            output_ / 100,
            "share conversion floors"
        );
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P01.
    function test_whenShareOutputMaximum() public {
        _setReward(true, 100, 100);
        assertEq(
            _risk.keeperReward(_prices(), _MARKET, 0, 100, type(uint256).max, false),
            type(uint256).max / 100,
            "full precision share conversion"
        );
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P02.
    function test_whenShareCollateralIsZero(address caller_, uint256 output_) public {
        _setReward(true, 100, 100);
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(_prices(), _MARKET, 1e9, 0, output_, false),
            0,
            "zero collateral avoids division"
        );
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P02.
    function test_whenZeroCollateralOutputEndpoints() public {
        _setReward(true, 100, 100);
        assertEq(_risk.keeperReward(_prices(), _MARKET, 1e9, 0, 0, false), 0, "zero output");
        assertEq(
            _risk.keeperReward(_prices(), _MARKET, 1e9, 0, type(uint256).max, false),
            0,
            "max output"
        );
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P03.
    function test_givenProtocolCaller_whenRewardQuoted(address caller_) public {
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(
                IBurnerLoansCore.PriceSnapshot(0, 0, type(uint256).max),
                _MARKET,
                type(uint256).max,
                type(uint256).max,
                type(uint256).max,
                true
            ),
            0,
            "early reward bypasses price arithmetic"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, type(uint32).max)
        );
        vm.prank(caller_);
        _risk.keeperReward(_prices(), type(uint32).max, 0, 0, 0, true);
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P04.
    function test_givenZeroBps_whenRewardQuoted(address caller_) public {
        _setReward(false, 0, 100);
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(
                IBurnerLoansCore.PriceSnapshot(0, 0, type(uint256).max),
                _MARKET,
                type(uint256).max,
                type(uint256).max,
                type(uint256).max,
                false
            ),
            0,
            "early reward bypasses price arithmetic"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, type(uint32).max)
        );
        vm.prank(caller_);
        _risk.keeperReward(_prices(), type(uint32).max, 0, 0, 0, false);
    }

    // Scenarios: BLRISK-KEEPER-REWARD-P05.
    function test_givenZeroCap_whenRewardQuoted(address caller_) public {
        _setReward(false, 100, 0);
        vm.prank(caller_);
        assertEq(
            _risk.keeperReward(
                IBurnerLoansCore.PriceSnapshot(0, 0, type(uint256).max),
                _MARKET,
                type(uint256).max,
                type(uint256).max,
                type(uint256).max,
                false
            ),
            0,
            "early reward bypasses price arithmetic"
        );
        vm.expectRevert(
            abi.encodeWithSelector(IFLOANv1.FLOAN_InvalidMarket.selector, type(uint32).max)
        );
        vm.prank(caller_);
        _risk.keeperReward(_prices(), type(uint32).max, 0, 0, 0, false);
    }

    // Scenarios: BLRISK-KEEPER-REWARD-N03.
    function test_whenRequiredBackingOverflows_reverts(address caller_) public {
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller_);
        _risk.keeperReward(
            IBurnerLoansCore.PriceSnapshot(1e18, 1e18, type(uint256).max),
            _MARKET,
            type(uint256).max,
            100,
            100,
            false
        );
    }
}
