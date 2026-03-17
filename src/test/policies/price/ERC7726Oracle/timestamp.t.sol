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

        priceModule.cachePrice(address(collateralToken));
        priceModule.cachePrice(address(loanToken));
        (, uint48 expectedTimestamp) = priceModule.getPrice(
            address(collateralToken),
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

        priceModule.cachePrice(address(collateralToken));
        priceModule.cachePrice(address(loanToken));

        vm.startSnapshotGas("ERC7726OracleCloneable.timestamp");
        IERC7726Oracle(cloneOracle).timestamp(address(collateralToken), address(loanToken));
        uint256 gasUsed = vm.stopSnapshotGas();
        assertGt(gasUsed, 0, "Gas snapshot should be non-zero");
    }

    function test_givenInconsistentTimestamps_reverts() public {
        ERC7726OracleFactory cloneFactory = new ERC7726OracleFactory(kernel);
        kernel.executeAction(Actions.ActivatePolicy, address(cloneFactory));

        vm.prank(admin);
        cloneFactory.enable("");

        vm.prank(admin);
        address cloneOracle = cloneFactory.createOracle(1 hours, bytes(""));

        priceModule.cachePrice(address(collateralToken));
        priceModule.cachePrice(address(loanToken));
        vm.warp(block.timestamp + 1);
        priceModule.cachePrice(address(collateralToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7726Oracle.ERC7726Oracle_InconsistentTimestamps.selector,
                uint48(block.timestamp),
                uint48(block.timestamp - 1)
            )
        );
        IERC7726Oracle(cloneOracle).timestamp(address(collateralToken), address(loanToken));
    }
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
