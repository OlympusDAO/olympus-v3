// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskValidateRiskConfigTest is BurnerLoansRiskTest {
    function _validConfig() private pure returns (IBurnerLoansRisk.AssetRiskConfigInput memory) {
        return IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e6);
    }

    function _accept(IBurnerLoansRisk.AssetRiskConfigInput memory cfg_, address caller_) private {
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L01.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        _risk.validateRiskConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L02.
    function test_givenDisabled_whenCalled(address caller_) public givenDisabled {
        vm.prank(caller_);
        _risk.validateRiskConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L03.
    function test_givenInactive_whenCalled(address caller_) public givenInactive {
        vm.prank(caller_);
        _risk.validateRiskConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L04.
    function test_givenInactiveAndDisabled_whenCalled(
        address caller_
    ) public givenDisabled givenInactive {
        vm.prank(caller_);
        _risk.validateRiskConfig(_validConfig());
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L05, BLRISK-VALIDATE-RISK-I01.
    function test_givenOperational_whenLtvIsZero_reverts(address caller_) public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxLtvBps = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 0)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L06, BLRISK-VALIDATE-RISK-I01.
    function test_givenDisabled_whenLtvIsZero_reverts(address caller_) public givenDisabled {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxLtvBps = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 0)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L07, BLRISK-VALIDATE-RISK-I01.
    function test_givenInactive_whenLtvIsZero_reverts(address caller_) public givenInactive {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxLtvBps = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 0)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-L08, BLRISK-VALIDATE-RISK-I01.
    function test_givenInactiveAndDisabled_whenLtvIsZero_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxLtvBps = 0;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, 0)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    function _rejectExcessLtv(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxLtvBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, value_)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I02.
    function test_whenExcessLtv_reverts(uint16 value_, address caller_) public {
        _rejectExcessLtv(uint16(bound(value_, 10001, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I02.
    function test_whenExcessLtvBoundaries_reverts(address caller_) public {
        _rejectExcessLtv(10001, caller_);
        _rejectExcessLtv(65535, caller_);
    }

    function _rejectLowBacking(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.backingMultiplierBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I03.
    function test_whenLowBacking_reverts(uint16 value_, address caller_) public {
        _rejectLowBacking(uint16(bound(value_, 0, 9999)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I03.
    function test_whenLowBackingBoundaries_reverts(address caller_) public {
        _rejectLowBacking(0, caller_);
        _rejectLowBacking(1, caller_);
        _rejectLowBacking(9999, caller_);
    }

    function _rejectExcessBacking(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.backingMultiplierBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I04.
    function test_whenExcessBacking_reverts(uint16 value_, address caller_) public {
        _rejectExcessBacking(uint16(bound(value_, 50001, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I04.
    function test_whenExcessBackingBoundaries_reverts(address caller_) public {
        _rejectExcessBacking(50001, caller_);
        _rejectExcessBacking(65535, caller_);
    }

    function _rejectExcessRewardBps(uint16 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.keeperRewardBps = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansRisk.BurnerLoans_InvalidBps.selector, value_)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I05.
    function test_whenExcessRewardBps_reverts(uint16 value_, address caller_) public {
        _rejectExcessRewardBps(uint16(bound(value_, 10001, type(uint16).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I05.
    function test_whenExcessRewardBpsBoundaries_reverts(address caller_) public {
        _rejectExcessRewardBps(10001, caller_);
        _rejectExcessRewardBps(65535, caller_);
    }

    function _rejectZeroTerm(uint48 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.termLength = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I06.
    function test_whenZeroTerm_reverts(uint48 value_, address caller_) public {
        _rejectZeroTerm(uint48(bound(value_, 0, 0)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I06.
    function test_whenZeroTermBoundaries_reverts(address caller_) public {
        _rejectZeroTerm(0, caller_);
    }

    function _rejectExcessTerm(uint48 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.termLength = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I07.
    function test_whenExcessTerm_reverts(uint48 value_, address caller_) public {
        _rejectExcessTerm(uint48(bound(value_, 31536001, type(uint48).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I07.
    function test_whenExcessTermBoundaries_reverts(address caller_) public {
        _rejectExcessTerm(31536001, caller_);
        _rejectExcessTerm(281474976710655, caller_);
    }

    function _rejectZeroHorizon(uint48 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxMaturityHorizon = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I08.
    function test_whenZeroHorizon_reverts(uint48 value_, address caller_) public {
        _rejectZeroHorizon(uint48(bound(value_, 0, 0)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I08.
    function test_whenZeroHorizonBoundaries_reverts(address caller_) public {
        _rejectZeroHorizon(0, caller_);
    }

    function _rejectExcessHorizon(uint48 value_, address caller_) private {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.maxMaturityHorizon = value_;
        vm.expectRevert(
            abi.encodeWithSelector(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector)
        );
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I11.
    function test_whenExcessHorizon_reverts(uint48 value_, address caller_) public {
        _rejectExcessHorizon(uint48(bound(value_, 31622401, type(uint48).max)), caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I11.
    function test_whenExcessHorizonBoundaries_reverts(address caller_) public {
        _rejectExcessHorizon(31622401, caller_);
        _rejectExcessHorizon(281474976710655, caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I09.
    function test_whenShortHorizon_reverts(uint48 term_, uint48 horizon_, address caller_) public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.termLength = uint48(bound(term_, 2, 365 days));
        cfg.maxMaturityHorizon = uint48(bound(horizon_, 1, cfg.termLength - 1));
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I10.
    function test_whenEqualHorizon_reverts(uint48 term_, address caller_) public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.termLength = uint48(bound(term_, 1, 365 days));
        cfg.maxMaturityHorizon = cfg.termLength;
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        vm.prank(caller_);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-I09, BLRISK-VALIDATE-RISK-I10.
    function test_whenHorizonBoundaries_reverts() public {
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg = _validConfig();
        cfg.termLength = 365 days;
        cfg.maxMaturityHorizon = 1;
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        _risk.validateRiskConfig(cfg);
        cfg.maxMaturityHorizon = 365 days - 1;
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        _risk.validateRiskConfig(cfg);
        cfg.maxMaturityHorizon = 365 days;
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        _risk.validateRiskConfig(cfg);
        cfg.termLength = 1;
        cfg.maxMaturityHorizon = 1;
        vm.expectRevert(IBurnerLoansErrors.BurnerLoans_InvalidParam.selector);
        _risk.validateRiskConfig(cfg);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-P01.
    function test_whenConfigIsValid(
        IBurnerLoansRisk.AssetRiskConfigInput memory cfg_,
        address caller_
    ) public {
        cfg_.maxLtvBps = uint16(bound(cfg_.maxLtvBps, 1, 10000));
        cfg_.backingMultiplierBps = uint16(bound(cfg_.backingMultiplierBps, 10000, 50000));
        cfg_.keeperRewardBps = uint16(bound(cfg_.keeperRewardBps, 0, 10000));
        cfg_.termLength = uint48(bound(cfg_.termLength, 1, 365 days));
        cfg_.maxMaturityHorizon = uint48(
            bound(cfg_.maxMaturityHorizon, cfg_.termLength + 1, 366 days)
        );
        _accept(cfg_, caller_);
    }

    // Scenarios: BLRISK-VALIDATE-RISK-P01, BLRISK-VALIDATE-RISK-P02.
    function test_whenValidEndpoints(address caller_) public {
        _accept(IBurnerLoansRisk.AssetRiskConfigInput(1, 10000, 0, 1, 2, 0), caller_);
        _accept(
            IBurnerLoansRisk.AssetRiskConfigInput(
                10000,
                50000,
                10000,
                365 days,
                366 days,
                type(uint128).max
            ),
            caller_
        );
    }
}
