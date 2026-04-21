// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {ERC7726OracleFactoryTest} from "./ERC7726OracleFactoryTest.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {ERC7726OracleFactory} from "src/policies/price/ERC7726OracleFactory.sol";

contract ERC7726OracleFactoryGetPriceCacheTest is ERC7726OracleFactoryTest {
    function test_whenFactoryIsDeployed_returnsConfiguredPriceCache() public {
        MockPriceCache cache = new MockPriceCache();
        ERC7726OracleFactory localFactory = ERC7726OracleFactory(
            _deployFactoryWithPriceCache(address(cache))
        );

        assertEq(
            localFactory.getPriceCache(),
            address(cache),
            "Price cache should be set from constructor"
        );
    }

    function test_whenPriceCacheIsUpdated_returnsUpdatedPriceCache() public givenFactoryIsEnabled {
        MockPriceCache cache = new MockPriceCache();

        vm.prank(admin);
        factory.setPriceCache(address(cache));

        assertEq(factory.getPriceCache(), address(cache), "Price cache should be updated");
    }

    function _deployFactoryWithPriceCache(address priceCache_) internal returns (address factory_) {
        bytes memory creationCode = abi.encodePacked(
            type(ERC7726OracleFactory).creationCode,
            abi.encode(kernel, priceCache_)
        );

        assembly {
            factory_ := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        require(factory_ != address(0), "Factory deployment failed");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
