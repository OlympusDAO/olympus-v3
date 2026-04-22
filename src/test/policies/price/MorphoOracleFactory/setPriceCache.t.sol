// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

contract MockNonPriceCache {}

contract MorphoOracleFactorySetPriceCacheTest is MorphoOracleFactoryTest {
    function test_whenCallerIsAdmin_setsPriceCache() public givenFactoryIsEnabled {
        MockPriceCache cache = _newCache();

        vm.expectEmit(true, false, false, false);
        emit IOracleFactory.PriceCacheSet(address(cache));

        vm.prank(admin);
        factory.setPriceCache(address(cache));

        assertEq(factory.getPriceCache(), address(cache), "Price cache should be updated");
    }

    function test_whenPriceCacheAddressIsZero_reverts() public givenFactoryIsEnabled {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidPriceCache.selector,
                address(0)
            )
        );
        factory.setPriceCache(address(0));
    }

    function test_whenCallerIsOracleManager_reverts() public givenFactoryIsEnabled {
        MockPriceCache cache = _newCache();

        vm.prank(oracleManager);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        factory.setPriceCache(address(cache));
    }

    function testFuzz_whenCallerIsNotAdmin_reverts(address caller_) public givenFactoryIsEnabled {
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != admin);

        MockPriceCache cache = _newCache();

        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        factory.setPriceCache(address(cache));
    }

    function test_whenPriceCacheDoesNotImplementIPriceCache_reverts() public givenFactoryIsEnabled {
        MockNonPriceCache nonPriceCache = new MockNonPriceCache();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidPriceCache.selector,
                address(nonPriceCache)
            )
        );
        factory.setPriceCache(address(nonPriceCache));
    }

    function test_whenPriceCacheUsesDifferentKernel_reverts() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache(makeAddr("DIFFERENT_KERNEL"));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleFactory.OracleFactory_InvalidPriceCache.selector,
                address(cache)
            )
        );
        factory.setPriceCache(address(cache));
    }

    function _newCache() internal returns (MockPriceCache cache_) {
        cache_ = new MockPriceCache(address(kernel));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
