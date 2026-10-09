// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {StdInvariant} from "@forge-std-1.16.2/StdInvariant.sol";

// Contracts
import {BurnerLoansTest} from "./BurnerLoansTest.sol";
import {BurnerLoansRescueInvariantHandler} from "./handlers/BurnerLoansRescueInvariantHandler.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

/// forge-config: default.invariant.fail-on-revert = true
contract BurnerLoansRescueInvariantTest is StdInvariant, BurnerLoansTest {
    BurnerLoansRescueInvariantHandler internal _handler;

    function setUp() public override {
        super.setUp();
        MockRevertingTransferToken asset = new MockRevertingTransferToken(18);
        _handler = new BurnerLoansRescueInvariantHandler(
            burnerLoans,
            burnerLoansConfig,
            asset,
            admin,
            address(trsry)
        );
        targetContract(address(_handler));
    }

    function invariant_pendingBucketsStaySolventAndConserved() public view {
        _handler.assertAccounting();
    }
}
