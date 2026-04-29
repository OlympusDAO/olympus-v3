// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ChainlinkOracleFactoryTest} from "./ChainlinkOracleFactoryTest.sol";
import {IOracleFactory} from "src/policies/interfaces/price/IOracleFactory.sol";

contract ChainlinkOracleFactoryCachePriceTest is ChainlinkOracleFactoryTest {
    function test_whenCachePriceCalledByNonOracle_reverts() public givenFactoryIsEnabled {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleFactory.OracleFactory_InvalidOracle.selector, admin)
        );

        vm.prank(admin);
        factory.cachePrice(address(baseToken), address(quoteToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
