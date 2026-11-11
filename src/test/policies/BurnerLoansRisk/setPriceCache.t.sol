// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IPriceCache} from "src/interfaces/IPriceCache.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansErrors} from "src/policies/interfaces/burnerloans/IBurnerLoansErrors.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {PolicyDependency} from "src/libraries/PolicyDependency.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {BurnerLoansRiskTest} from "src/test/policies/BurnerLoansRisk/fixtures/BurnerLoansRiskTest.sol";

contract BurnerLoansRiskSetPriceCacheTest is BurnerLoansRiskTest {
    function _select(address candidate_) private {
        vm.expectEmit(true, false, false, true, address(_risk));
        emit IBurnerLoansRisk.PriceCacheSet(candidate_);
        _risk.setPriceCache(candidate_);
        assertEq(_risk.priceCache(), candidate_, "exact replacement");
    }

    function _reject(address candidate_) private {
        _reject(
            candidate_,
            abi.encodeWithSelector(
                IBurnerLoansRisk.BurnerLoans_InvalidPriceCache.selector,
                candidate_
            )
        );
    }

    function _reject(address candidate_, bytes memory reason_) private {
        address previous = _risk.priceCache();
        vm.expectRevert(reason_);
        _risk.setPriceCache(candidate_);
        assertEq(_risk.priceCache(), previous, "failed setter preserves binding");
    }

    // Scenarios: BLRISK-PRICE-CACHE-L01.
    function test_givenEnabled_whenDependencyChanges(address caller_) public givenAdmin(caller_) {
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-L02.
    function test_givenDisabled_whenDependencyChanges(
        address caller_
    ) public givenDisabled givenAdmin(caller_) {
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-L03.
    function test_givenInactive_whenDependencyChanges_reverts(
        address caller_
    ) public givenInactive givenAdmin(caller_) {
        _expectInactive();
        _risk.setPriceCache(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-L04.
    function test_givenInactiveAndDisabled_whenDependencyChanges_reverts(
        address caller_
    ) public givenDisabled givenInactive givenAdmin(caller_) {
        _expectInactive();
        _risk.setPriceCache(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-A01.
    function test_whenUnauthorizedCaller_reverts(address caller_) public givenOperator {
        vm.assume(caller_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(caller_);
        _risk.setPriceCache(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-I02.
    function test_whenMissingCacheInterface_reverts(address caller_) public givenAdmin(caller_) {
        _cache.setInterfaceSupport(type(IPriceCache).interfaceId, false);
        _reject(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-I03.
    function test_whenMissingEnabler_reverts(address caller_) public givenAdmin(caller_) {
        _cache.setInterfaceSupport(type(IEnabler).interfaceId, false);
        _reject(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P10.
    function test_givenVersionGetterReverts_whenSelected(
        address caller_
    ) public givenAdmin(caller_) {
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("VERSION()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-I05.
    function test_whenMissingVersionInterface_reverts(address caller_) public givenAdmin(caller_) {
        _cache.setInterfaceSupport(type(IVersioned).interfaceId, false);
        _reject(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-I06.
    function test_whenRevertingERC165_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _reject(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-I07.
    function test_whenMalformedERC165_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_cache),
            abi.encodeWithSelector(IERC165.supportsInterface.selector),
            hex"01"
        );
        _reject(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P03.
    function test_whenRevertingKernel_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCallRevert(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        _reject(
            address(_cache),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_cache)
            )
        );
    }

    // Scenarios: BLRISK-PRICE-CACHE-P03.
    function test_whenMalformedKernel_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCall(address(_cache), abi.encodeWithSignature("kernel()"), hex"01");
        _reject(
            address(_cache),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_cache)
            )
        );
    }

    // Scenarios: BLRISK-PRICE-CACHE-P03.
    function test_whenNoncanonicalKernel_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(type(uint256).max)
        );
        _reject(
            address(_cache),
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_InvalidDependency.selector,
                address(_cache)
            )
        );
    }

    // Scenarios: BLRISK-PRICE-CACHE-I04.
    function test_whenEoa_reverts(address caller_) public givenAdmin(caller_) {
        _reject(address(0xBEEF));
    }

    // Scenarios: BLRISK-PRICE-CACHE-I01.
    function test_whenCleared(address caller_) public givenCache givenAdmin(caller_) {
        _select(address(0));
    }

    // Scenarios: BLRISK-PRICE-CACHE-D01.
    function test_whenKernelMismatches_reverts(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_cache),
            abi.encodeWithSignature("kernel()"),
            abi.encode(address(0xBAD))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                PolicyDependency.PolicyDependency_KernelMismatch.selector,
                address(_cache),
                address(_kernel),
                address(0xBAD)
            )
        );
        _risk.setPriceCache(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P04.
    function test_givenCache11_whenSelected(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P05.
    function test_givenCache10_whenSelected(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(true)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P06.
    function test_givenCache01_whenSelected(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(true));
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P07.
    function test_givenCache00_whenSelected(address caller_) public givenAdmin(caller_) {
        vm.mockCall(
            address(_kernel),
            abi.encodeWithSelector(Kernel.isPolicyActive.selector, address(_cache)),
            abi.encode(false)
        );
        vm.mockCall(address(_cache), abi.encodeWithSignature("isEnabled()"), abi.encode(false));
        _select(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P08.
    function test_givenCache_whenUnchanged_reverts(
        address caller_
    ) public givenCache givenAdmin(caller_) {
        vm.mockCallRevert(
            address(_cache),
            bytes(""),
            abi.encodeWithSelector(DependencyReadFailed.selector)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                address(_cache)
            )
        );
        _risk.setPriceCache(address(_cache));
    }

    // Scenarios: BLRISK-PRICE-CACHE-P09.
    function test_givenNoCache_whenUnchanged_reverts(address caller_) public givenAdmin(caller_) {
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoansErrors.BurnerLoans_UnchangedAddress.selector,
                address(0)
            )
        );
        _risk.setPriceCache(address(0));
    }
}
