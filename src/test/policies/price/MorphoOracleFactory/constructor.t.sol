// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity ^0.8.15;

import {Kernel} from "src/Kernel.sol";
import {MorphoOracleFactory} from "src/policies/price/MorphoOracleFactory.sol";
import {MockPriceCache} from "src/test/mocks/MockPriceCache.sol";
import {MorphoOracleFactoryTest} from "./MorphoOracleFactoryTest.sol";

contract MorphoOracleFactoryConstructorTest is MorphoOracleFactoryTest {
    // ========== TESTS ========== //

    // [X] it deploys implementation
    // [X] it sets creation enabled to true
    // [X] it sets factory disabled by default

    function test_whenFactoryIsDeployed_initializesDefaults() public {
        Kernel newKernel = new Kernel();
        MockPriceCache newPriceCache = new MockPriceCache(address(newKernel));
        MorphoOracleFactory newFactory = new MorphoOracleFactory(newKernel, address(newPriceCache));

        assertNotEq(
            address(newFactory.ORACLE_IMPLEMENTATION()),
            address(0),
            "Implementation should be deployed"
        );
        assertTrue(newFactory.isCreationEnabled(), "Creation should be enabled by default");
        assertFalse(newFactory.isEnabled(), "Factory should be disabled by default");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
