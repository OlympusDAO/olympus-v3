// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskValidateFeeConfigTest is BurnerLoansRiskTest {
    function _validConfig() private pure returns (IBurnerLoansRisk.AssetFeeConfig memory) {
        return IBurnerLoansRisk.AssetFeeConfig(25, 8000, 100, 900);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L01.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        _risk.validateFeeConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L02.
    function test_givenDisabled_whenCalled(address caller_) public givenDisabled {
        vm.prank(caller_);
        _risk.validateFeeConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L03.
    function test_givenInactive_whenCalled(address caller_) public givenInactive {
        vm.prank(caller_);
        _risk.validateFeeConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L04.
    function test_givenInactiveAndDisabled_whenCalled(
        address caller_
    ) public givenDisabled givenInactive {
        vm.prank(caller_);
        _risk.validateFeeConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L05.
    function test_givenOperational_whenBaseExceedsBps_reverts(address caller_) public {
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 10001)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig(10001, 0, 0, 0));
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L06.
    function test_givenDisabled_whenBaseExceedsBps_reverts(address caller_) public givenDisabled {
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 10001)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig(10001, 0, 0, 0));
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L07.
    function test_givenInactive_whenBaseExceedsBps_reverts(address caller_) public givenInactive {
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 10001)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig(10001, 0, 0, 0));
    }

    // Scenarios: BLRISK-VALIDATE-FEE-L08.
    function test_givenInactiveAndDisabled_whenBaseExceedsBps_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 10001)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig(10001, 0, 0, 0));
    }

    function _rejectbaseFeeBps(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _validConfig();
        cfg.baseFeeBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, value_)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I01.
    function test_whenbaseFeeBpsExceedsLimit_reverts(uint16 value_, address caller_) public {
        _rejectbaseFeeBps(uint16(bound(value_, 10001, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I01.
    function test_whenbaseFeeBpsBoundaries_reverts(address caller_) public {
        _rejectbaseFeeBps(10001, caller_);
        _rejectbaseFeeBps(type(uint16).max, caller_);
    }

    function _rejectpreKinkSlopeBps(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _validConfig();
        cfg.preKinkSlopeBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, value_)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I02.
    function test_whenpreKinkSlopeBpsExceedsLimit_reverts(uint16 value_, address caller_) public {
        _rejectpreKinkSlopeBps(uint16(bound(value_, 10001, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I02.
    function test_whenpreKinkSlopeBpsBoundaries_reverts(address caller_) public {
        _rejectpreKinkSlopeBps(10001, caller_);
        _rejectpreKinkSlopeBps(type(uint16).max, caller_);
    }

    function _rejectpostKinkSlopeBps(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _validConfig();
        cfg.postKinkSlopeBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, value_)
        );
        vm.prank(caller_);
        _risk.validateFeeConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I03.
    function test_whenpostKinkSlopeBpsExceedsLimit_reverts(uint16 value_, address caller_) public {
        _rejectpostKinkSlopeBps(uint16(bound(value_, 10001, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I03.
    function test_whenpostKinkSlopeBpsBoundaries_reverts(address caller_) public {
        _rejectpostKinkSlopeBps(10001, caller_);
        _rejectpostKinkSlopeBps(type(uint16).max, caller_);
    }

    function _rejectkinkBps(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetFeeConfig memory cfg = _validConfig();
        cfg.kinkBps = value_;
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector);
        vm.prank(caller_);
        _risk.validateFeeConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I04.
    function test_whenkinkBpsExceedsLimit_reverts(uint16 value_, address caller_) public {
        _rejectkinkBps(uint16(bound(value_, 10000, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I04.
    function test_whenkinkBpsBoundaries_reverts(address caller_) public {
        _rejectkinkBps(10000, caller_);
        _rejectkinkBps(type(uint16).max, caller_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I05.
    function test_whenZeroKinkAndPreSlope_reverts(uint16 value_, address caller_) public {
        uint16 value = uint16(bound(value_, 1, 10000));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector);
        vm.prank(caller_);
        _risk.validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig(0, 0, value, 0));
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I06.
    function test_whenZeroKinkAndPostSlope_reverts(uint16 value_, address caller_) public {
        uint16 value = uint16(bound(value_, 1, 10000));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector);
        vm.prank(caller_);
        _risk.validateFeeConfig(IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, value));
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I07.
    function test_whenFeeTotalExceedsBps_reverts(
        IBurnerLoansRisk.AssetFeeConfig memory cfg_,
        address caller_
    ) public {
        cfg_.baseFeeBps = uint16(bound(cfg_.baseFeeBps, 0, 10000));
        cfg_.preKinkSlopeBps = uint16(bound(cfg_.preKinkSlopeBps, 0, 10000));
        cfg_.postKinkSlopeBps = uint16(bound(cfg_.postKinkSlopeBps, 0, 10000));
        cfg_.kinkBps = uint16(bound(cfg_.kinkBps, 1, 9999));
        vm.assume(uint256(cfg_.baseFeeBps) + cfg_.preKinkSlopeBps + cfg_.postKinkSlopeBps > 10000);
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector);
        vm.prank(caller_);
        _risk.validateFeeConfig(cfg_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-I05, BLRISK-VALIDATE-FEE-I06, BLRISK-VALIDATE-FEE-I07.
    function test_whenInvalidCurveBoundaries_reverts(address caller_) public {
        IBurnerLoansRisk.AssetFeeConfig[8] memory seeds = [
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 1, 0),
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 10000, 0),
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 1),
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 10000),
            IBurnerLoansRisk.AssetFeeConfig(5000, 1, 5001, 0),
            IBurnerLoansRisk.AssetFeeConfig(5000, 9999, 0, 5001),
            IBurnerLoansRisk.AssetFeeConfig(10000, 1, 1, 0),
            IBurnerLoansRisk.AssetFeeConfig(10000, 9999, 10000, 10000)
        ];
        for (uint256 i; i < seeds.length; ++i) {
            vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidFeeConfig.selector);
            vm.prank(caller_);
            _risk.validateFeeConfig(seeds[i]);
        }
    }

    // Scenarios: BLRISK-VALIDATE-FEE-P01.
    function test_whenConfigIsValid(
        IBurnerLoansRisk.AssetFeeConfig memory cfg_,
        address caller_
    ) public {
        cfg_.baseFeeBps = uint16(bound(cfg_.baseFeeBps, 0, 10000));
        cfg_.preKinkSlopeBps = uint16(bound(cfg_.preKinkSlopeBps, 0, 10000));
        cfg_.postKinkSlopeBps = uint16(bound(cfg_.postKinkSlopeBps, 0, 10000));
        cfg_.kinkBps = uint16(bound(cfg_.kinkBps, 0, 9999));
        vm.assume(uint256(cfg_.baseFeeBps) + cfg_.preKinkSlopeBps + cfg_.postKinkSlopeBps <= 10000);
        vm.assume(cfg_.kinkBps != 0 || (cfg_.preKinkSlopeBps == 0 && cfg_.postKinkSlopeBps == 0));
        vm.prank(caller_);
        _risk.validateFeeConfig(cfg_);
    }

    // Scenarios: BLRISK-VALIDATE-FEE-P01, BLRISK-VALIDATE-FEE-P02.
    function test_whenValidEndpoints(address caller_) public {
        IBurnerLoansRisk.AssetFeeConfig[7] memory seeds = [
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0),
            IBurnerLoansRisk.AssetFeeConfig(10000, 0, 0, 0),
            IBurnerLoansRisk.AssetFeeConfig(0, 1, 10000, 0),
            IBurnerLoansRisk.AssetFeeConfig(0, 9999, 0, 10000),
            IBurnerLoansRisk.AssetFeeConfig(2500, 1, 5000, 2500),
            IBurnerLoansRisk.AssetFeeConfig(1, 1, 1, 1),
            IBurnerLoansRisk.AssetFeeConfig(0, 9999, 0, 0)
        ];
        for (uint256 i; i < seeds.length; ++i) {
            vm.prank(caller_);
            _risk.validateFeeConfig(seeds[i]);
        }
    }
}
