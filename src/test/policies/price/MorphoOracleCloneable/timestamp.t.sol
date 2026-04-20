// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {MorphoOracleCloneableTest} from "./MorphoOracleCloneableTest.sol";

contract MorphoOracleCloneableTimestampTest is MorphoOracleCloneableTest {
    function test_givenConsistentTimestamps_returnsTimestamp() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, , uint48 expectedTimestamp, ) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );

        uint48 actualTimestamp = oracle.timestamp();
        assertEq(actualTimestamp, expectedTimestamp, "Timestamp should match cached timestamp");
    }

    function test_givenOnlyCollateralUsdCacheChanges_returnsCachedPairTimestamp() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, , uint48 expectedTimestamp, ) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );
        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(collateralToken), priceModule.unitOfAccount());

        assertEq(
            oracle.timestamp(),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenOnlyLoanUsdCacheChanges_returnsCachedPairTimestamp() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, , uint48 expectedTimestamp, ) = priceModule.getCachedPrice(
            address(collateralToken),
            address(loanToken)
        );
        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(loanToken), priceModule.unitOfAccount());

        assertEq(
            oracle.timestamp(),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenConsistentTimestamps_gasSnapshot() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));

        vm.startSnapshotGas("MorphoOracleCloneable.timestamp");
        oracle.timestamp();
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenLoanTokenRemovedFromPRICE_reverts() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        priceModule.removeAsset(address(loanToken));

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, address(loanToken))
        );
        oracle.timestamp();
    }

    function test_givenCollateralTokenRemovedFromPRICE_reverts() public {
        priceModule.cachePrice(address(collateralToken), address(loanToken));
        priceModule.removeAsset(address(collateralToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPRICEv2.PRICE_AssetNotApproved.selector,
                address(collateralToken)
            )
        );
        oracle.timestamp();
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
