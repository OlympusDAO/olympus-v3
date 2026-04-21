// SPDX-License-Identifier: Unlicense
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
pragma solidity >=0.8.15;

import {Actions} from "src/Kernel.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {ERC7726OracleFactory} from "src/policies/price/ERC7726OracleFactory.sol";
import {IERC7726Oracle} from "src/policies/interfaces/price/IERC7726Oracle.sol";
import {ERC7726OracleTest} from "./ERC7726OracleTest.sol";

contract ERC7726OracleTimestampTest is ERC7726OracleTest {
    function test_givenConsistentTimestamps_returnsTimestamp() public {
        ERC7726OracleFactory cloneFactory = new ERC7726OracleFactory(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(cloneFactory));

        vm.prank(admin);
        cloneFactory.enable("");

        vm.prank(admin);
        address cloneOracle = cloneFactory.createOracle(1 hours, bytes(""));

        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, uint48 expectedTimestamp) = priceModule.getPriceIn(
            address(collateralToken),
            address(loanToken),
            IPRICEv2.Variant.LAST
        );

        uint48 actualTimestamp = IERC7726Oracle(cloneOracle).timestamp(
            address(collateralToken),
            address(loanToken)
        );
        assertEq(actualTimestamp, expectedTimestamp, "Timestamp should match cached timestamp");
    }

    function test_givenConsistentTimestamps_gasSnapshot() public {
        ERC7726OracleFactory cloneFactory = new ERC7726OracleFactory(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(cloneFactory));

        vm.prank(admin);
        cloneFactory.enable("");

        vm.prank(admin);
        address cloneOracle = cloneFactory.createOracle(1 hours, bytes(""));

        priceModule.cachePrice(address(collateralToken), address(loanToken));

        vm.startSnapshotGas("ERC7726OracleCloneable.timestamp");
        IERC7726Oracle(cloneOracle).timestamp(address(collateralToken), address(loanToken));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenOnlyBaseUsdCacheChanges_returnsCachedPairTimestamp() public {
        ERC7726OracleFactory cloneFactory = new ERC7726OracleFactory(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(cloneFactory));

        vm.prank(admin);
        cloneFactory.enable("");

        vm.prank(admin);
        address cloneOracle = cloneFactory.createOracle(1 hours, bytes(""));

        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, uint48 expectedTimestamp) = priceModule.getPriceIn(
            address(collateralToken),
            address(loanToken),
            IPRICEv2.Variant.LAST
        );
        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(collateralToken), priceModule.unitOfAccount());

        assertEq(
            IERC7726Oracle(cloneOracle).timestamp(address(collateralToken), address(loanToken)),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenOnlyQuoteUsdCacheChanges_returnsCachedPairTimestamp() public {
        ERC7726OracleFactory cloneFactory = new ERC7726OracleFactory(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(cloneFactory));

        vm.prank(admin);
        cloneFactory.enable("");

        vm.prank(admin);
        address cloneOracle = cloneFactory.createOracle(1 hours, bytes(""));

        priceModule.cachePrice(address(collateralToken), address(loanToken));
        (, uint48 expectedTimestamp) = priceModule.getPriceIn(
            address(collateralToken),
            address(loanToken),
            IPRICEv2.Variant.LAST
        );
        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(loanToken), priceModule.unitOfAccount());

        assertEq(
            IERC7726Oracle(cloneOracle).timestamp(address(collateralToken), address(loanToken)),
            expectedTimestamp,
            "Timestamp should remain the cached pair timestamp"
        );
    }

    function test_givenBaseAssetIsNotApproved_reverts() public {
        address unapprovedBase = makeAddr("UNAPPROVED_BASE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedBase)
        );
        oracle.timestamp(unapprovedBase, address(loanToken));
    }

    function test_givenQuoteAssetIsNotApproved_reverts() public {
        address unapprovedQuote = makeAddr("UNAPPROVED_QUOTE");

        vm.expectRevert(
            abi.encodeWithSelector(IPRICEv2.PRICE_AssetNotApproved.selector, unapprovedQuote)
        );
        oracle.timestamp(address(collateralToken), unapprovedQuote);
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
