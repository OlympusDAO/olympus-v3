// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {MockPrice} from "src/test/mocks/MockPrice.v2.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskValidatePriceSupportTest is BurnerLoansRiskTest {
    // Scenarios: BLRISK-VALIDATE-PRICE-I03.
    function test_givenPriceCodeAbsent_whenValidated_reverts(address caller_) public {
        vm.etch(address(_price), hex"");
        // The external interface read has no contract/ABI response; match its exact empty data.
        vm.expectRevert(bytes(""));
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-L01.
    function test_givenOperational_whenCalled(address caller_) public {
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-L02.
    function test_givenDisabled_whenCalled_reverts(address caller_) public givenDisabled {
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-L03.
    function test_givenInactive_whenCalled_reverts(address caller_) public givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-L04.
    function test_givenInactiveAndDisabled_whenCalled_reverts(
        address caller_
    ) public givenDisabled givenInactive {
        _expectInactive();
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-L01.
    function test_givenReEnabled_whenCalled(address caller_) public givenReEnabled {
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-I01.
    function test_whenRequiredInterfaceMissing_reverts(address caller_) public {
        vm.mockCall(
            address(_price),
            abi.encodeCall(IERC165.supportsInterface, (type(IPRICEv2).interfaceId)),
            abi.encode(false)
        );
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-I02.
    function test_whenAssetUnapproved_reverts(address caller_) public {
        _price.removeAsset(address(_asset));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-P01, BLRISK-VALIDATE-PRICE-I03.
    function test_whenPriceApprovalExists(address asset_, address caller_) public {
        // Risk consumes PRICE approval; it adds no token-code or market admission requirement.
        _price.setPrice(asset_, 1e18);
        vm.prank(caller_);
        _risk.validatePriceSupport(asset_);
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-I03.
    function test_whenZeroAndEoaApproved(address caller_) public {
        _price.setPrice(address(0), 1e18);
        _price.setPrice(address(0xBEEF), 1e18);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(0));
        vm.prank(caller_);
        _risk.validatePriceSupport(address(0xBEEF));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-I03.
    function test_givenInterfaceReadReverts_whenValidated_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_price),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(DependencyReadFailed.selector);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-I03.
    function test_givenApprovalReadReverts_whenValidated_reverts(address caller_) public {
        vm.mockCallRevert(
            address(_price),
            abi.encodeWithSelector(IPRICEv2.isAssetApproved.selector),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(DependencyReadFailed.selector);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }

    // Scenarios: BLRISK-VALIDATE-PRICE-I03.
    function test_givenPriceReplacement_whenValidated(address caller_) public {
        _risk.validatePriceSupport(address(_asset));
        MockPrice replacement = new MockPrice(_kernel, 18, 8 hours);
        _kernel.executeAction(Actions.UpgradeModule, address(replacement));
        vm.expectRevert(IBurnerLoansRisk.BurnerLoans_InvalidPrice.selector);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
        replacement.setPrice(address(_asset), 1e18);
        vm.prank(caller_);
        _risk.validatePriceSupport(address(_asset));
    }
}
