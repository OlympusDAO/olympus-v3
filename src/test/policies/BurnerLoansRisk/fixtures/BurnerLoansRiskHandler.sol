// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansRisk} from "src/policies/burnerloans/BurnerLoansRisk.sol";

/// @dev Exercises a Kernel-active Risk. Unit tests cover deactivation and grace boundaries.
contract BurnerLoansRiskHandler is Test {
    BurnerLoansRisk internal immutable _risk;
    address internal immutable _otherAdmin;
    address public expectedOperator;
    uint48 public expectedAge;
    bool public expectedEnabled = true;

    constructor(BurnerLoansRisk risk_, address otherAdmin_) {
        _risk = risk_;
        _otherAdmin = otherAdmin_;
        expectedAge = risk_.priceCacheMaxAge();
    }

    function selectOperator(address next_) external {
        if (next_ == expectedOperator) return;
        _risk.setConfigOperator(next_);
        expectedOperator = next_;
    }

    function setAgeAsAdmin(uint48 age_) external {
        if (!expectedEnabled) return;
        _risk.setPriceCacheMaxAge(age_);
        expectedAge = age_;
    }

    function setAgeAsOperator(uint48 age_) external {
        if (!expectedEnabled || expectedOperator == address(0)) return;
        vm.prank(expectedOperator);
        _risk.setPriceCacheMaxAge(age_);
        expectedAge = age_;
    }

    function attemptUnauthorizedAge(address caller_, uint48 age_) external {
        if (
            !expectedEnabled ||
            caller_ == address(this) ||
            caller_ == _otherAdmin ||
            caller_ == expectedOperator
        ) return;
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(caller_);
        _risk.setPriceCacheMaxAge(age_);
    }

    function pause() external {
        if (!expectedEnabled) return;
        _risk.disable("");
        expectedEnabled = false;
    }

    function enable() external {
        if (expectedEnabled) return;
        _risk.enable("");
        expectedEnabled = true;
    }
}
