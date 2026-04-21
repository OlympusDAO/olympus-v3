// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";

contract ERC7726OracleFactoryGetPriceCacheTest is ERC7726OracleFactoryTest {
    function test_whenPriceCacheIsNotConfigured_returnsZeroAddress() public view {
        assertEq(factory.getPriceCache(), address(0), "Default price cache should be unset");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
