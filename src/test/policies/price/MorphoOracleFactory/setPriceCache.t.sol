// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";

contract MockNonPriceCache {}

contract MorphoOracleFactorySetPriceCacheTest is MorphoOracleFactoryTest {
    function test_whenCallerIsAdmin_setsPriceCache() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache();

        vm.prank(admin);
        factory.setPriceCache(address(cache));

        assertEq(factory.getPriceCache(), address(cache), "Price cache should be updated");
    }

    function test_whenPriceCacheAddressIsZero_reverts() public givenFactoryIsEnabled {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidPriceCache.selector, address(0))
        );
        factory.setPriceCache(address(0));
    }

    function test_whenCallerIsOracleManager_reverts() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache();

        vm.prank(oracleManager);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        factory.setPriceCache(address(cache));
    }

    function testFuzz_whenCallerIsNotAdmin_reverts(address caller_) public givenFactoryIsEnabled {
        vm.assume(caller_ != address(0));
        vm.assume(caller_ != admin);

        MockPriceCache cache = new MockPriceCache();

        vm.prank(caller_);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
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
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
