// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// forge-lint: disable-start(literal-instead-of-constant)

// Libraries
import {Vm} from "forge-std/Vm.sol";

// Interfaces
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

// Contracts
import {BurnerLoansTest} from "./BurnerLoansTest.sol";

// Test inputs prove numeric casts fit; fixture casts intentionally select fixed-width values.
// Scenario-specific contracts and fixtures have no cross-file consumers.
// forge-lint: disable-start(unsafe-typecast,multi-contract-file)

contract BurnerLoansYieldRoutingAbiHarness {
    function roundTrip(
        IBurnerLoans.AssetYieldRouting calldata routing_
    ) external pure returns (IBurnerLoans.AssetYieldRouting memory routing) {
        return routing_;
    }
}

contract BurnerLoansYieldRoutingAbiTest is BurnerLoansTest {
    bytes32 internal constant _YIELD_ASSET_ROUTING_SET_TOPIC =
        keccak256("YieldAssetRoutingSet(address,(uint16,(address,uint16)[]))");
    bytes32 internal constant _YIELD_CLAIMED_TOPIC =
        keccak256("YieldClaimed(address,uint256,(address,uint256)[])");

    BurnerLoansYieldRoutingAbiHarness internal _harness;

    function setUp() public override {
        super.setUp();
        _harness = new BurnerLoansYieldRoutingAbiHarness();
    }

    function test_whenRouteHasZeroDirectAllocations_eventRoundTripsNestedRoute() public {
        _assertRouteEventRoundTrip(_createRouting(4_000, 0));
    }

    function test_whenRouteHasOneDirectAllocation_eventRoundTripsNestedRoute() public {
        _assertRouteEventRoundTrip(_createRouting(2_000, 1));
    }

    function test_whenRouteHasFiveDirectAllocations_eventRoundTripsNestedRoute() public {
        _assertRouteEventRoundTrip(_createRouting(1_000, 5));
    }

    function test_whenRouteHasFiveDirectAllocations_externalCallerRoundTripsNestedRoute() public {
        IBurnerLoans.AssetYieldRouting memory expected = _createRouting(1_000, 5);

        IBurnerLoans.AssetYieldRouting memory actual = _harness.roundTrip(expected);

        _assertRoutingEq(actual, expected);
    }

    function test_whenClaimHasMultipleResults_eventRoundTripsTreasuryLast() public {
        address asset = makeAddr("asset");
        IBurnerLoans.YieldDistribution[]
            memory distributions = new IBurnerLoans.YieldDistribution[](7);
        for (uint256 i; i < distributions.length - 1; ++i) {
            distributions[i] = IBurnerLoans.YieldDistribution({
                recipient: address(uint160(i + 1)),
                amount: 1_000
            });
        }
        distributions[6] = IBurnerLoans.YieldDistribution({
            recipient: address(trsry),
            amount: 4_000
        });

        vm.recordLogs();
        emit IBurnerLoans.YieldClaimed(asset, 10_000, distributions);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "claim event count");
        assertEq(entries[0].topics.length, 2, "claim event topic count");
        assertEq(entries[0].topics[0], _YIELD_CLAIMED_TOPIC, "claim event signature");
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(asset))), "claim event asset");

        (uint256 claimed, IBurnerLoans.YieldDistribution[] memory decodedDistributions) = abi
            .decode(entries[0].data, (uint256, IBurnerLoans.YieldDistribution[]));
        assertEq(claimed, 10_000, "claimed amount");
        assertEq(decodedDistributions.length, distributions.length, "distribution count");
        for (uint256 i; i < distributions.length; ++i) {
            _assertDistributionEq(decodedDistributions[i], distributions[i], "distribution");
        }
    }

    function _assertRouteEventRoundTrip(IBurnerLoans.AssetYieldRouting memory expected) internal {
        address asset = makeAddr("asset");

        vm.recordLogs();
        emit IBurnerLoans.YieldAssetRoutingSet(asset, expected);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1, "route event count");
        assertEq(entries[0].topics.length, 2, "route event topic count");
        assertEq(entries[0].topics[0], _YIELD_ASSET_ROUTING_SET_TOPIC, "route event signature");
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(asset))), "route event asset");

        IBurnerLoans.AssetYieldRouting memory actual = abi.decode(
            entries[0].data,
            (IBurnerLoans.AssetYieldRouting)
        );
        _assertRoutingEq(actual, expected);
    }

    function _createRouting(
        uint16 repurchaseRecipientBps_,
        uint256 directAllocationCount_
    ) internal pure returns (IBurnerLoans.AssetYieldRouting memory routing) {
        routing.repurchaseRecipientBps = repurchaseRecipientBps_;
        routing.directAllocations = new IBurnerLoans.DirectYieldAllocation[](
            directAllocationCount_
        );
        for (uint256 i; i < directAllocationCount_; ++i) {
            routing.directAllocations[i] = IBurnerLoans.DirectYieldAllocation({
                recipient: address(uint160(i + 1)),
                bps: 1_000
            });
        }
    }

    function _assertRoutingEq(
        IBurnerLoans.AssetYieldRouting memory actual_,
        IBurnerLoans.AssetYieldRouting memory expected_
    ) internal pure {
        assertEq(
            actual_.repurchaseRecipientBps,
            expected_.repurchaseRecipientBps,
            "repurchase recipient bps"
        );
        assertEq(
            actual_.directAllocations.length,
            expected_.directAllocations.length,
            "direct allocation count"
        );
        for (uint256 i; i < expected_.directAllocations.length; ++i) {
            assertEq(
                actual_.directAllocations[i].recipient,
                expected_.directAllocations[i].recipient,
                "direct allocation recipient"
            );
            assertEq(
                actual_.directAllocations[i].bps,
                expected_.directAllocations[i].bps,
                "direct allocation bps"
            );
        }
    }

    function _assertDistributionEq(
        IBurnerLoans.YieldDistribution memory actual_,
        IBurnerLoans.YieldDistribution memory expected_,
        string memory message_
    ) internal pure {
        assertEq(actual_.recipient, expected_.recipient, string.concat(message_, " recipient"));
        assertEq(actual_.amount, expected_.amount, string.concat(message_, " amount"));
    }
}

// forge-lint: disable-end(unsafe-typecast,multi-contract-file)

// forge-lint: disable-end(literal-instead-of-constant)
