// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IMorphoOracle} from "src/policies/interfaces/price/IMorphoOracle.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableTimestampTest is MorphoOracleCloneableTest {
    function test_givenConsistentTimestamps_returnsTimestamp() public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));
        (, uint48 expectedTimestamp) = priceModule.getPrice(
            address(collateralToken),
            IPRICEv2.Variant.LAST
        );

        uint48 actualTimestamp = oracle.timestamp();
        assertEq(actualTimestamp, expectedTimestamp, "Timestamp should match cached timestamp");
    }

    function test_givenInconsistentTimestamps_reverts() public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));
        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(collateralToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMorphoOracle.MorphoOracle_InconsistentTimestamps.selector,
                uint48(block.timestamp),
                uint48(block.timestamp - 1)
            )
        );
        oracle.timestamp();
    }

    function test_givenConsistentTimestamps_gasSnapshot() public {
        priceModule.storeObservation(address(collateralToken));
        priceModule.storeObservation(address(loanToken));

        vm.startSnapshotGas("MorphoOracleCloneable.timestamp");
        oracle.timestamp();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
