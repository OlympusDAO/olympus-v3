// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import {Test} from "@forge-std-1.16.2/Test.sol";

import {CCIPFeeBudgetLibHarness} from "src/test/scripts/ops/lib/mocks/CCIPFeeBudgetLibHarness.sol";

/// @notice Runs the fee budget reader against the live fee contracts of the three ramp
///         generations that serve mainnet today, at pinned blocks: `OnRamp 2.0.0` toward
///         Arbitrum, `OnRamp 1.6.0` toward Base and `EVM2EVMOnRamp 1.5.0` toward Berachain, each
///         quoting through the source chain's live contracts. No OHM entry exists on any of them
///         at the pinned block, so every read returns the 90000 chain default and names the
///         contracts it came from. Run with `pnpm test:fork`; the Alchemy key comes from `.env`.
contract CCIPFeeBudgetLibForkTests_readOhmDestGasOverhead is Test {
    /// @notice A mainnet block of 2026-09-04, after the Arbitrum and Optimism lanes moved to
    ///         2.0.0 and while Base stays on 1.6.0 and Berachain on 1.5.0.
    uint256 internal constant MAINNET_FORK_BLOCK = 25903191;

    /// @notice The live default of every EVM destination of the mainnet fee quoter and of the
    ///         1.5 on-ramps at the pinned block.
    uint32 internal constant LIVE_CHAIN_DEFAULT = 90_000;

    CCIPFeeBudgetLibHarness internal harness;
    string internal env;

    function setUp() public {
        vm.createSelectFork("mainnet", MAINNET_FORK_BLOCK);
        harness = new CCIPFeeBudgetLibHarness();
        vm.label(address(harness), "CCIPFeeBudgetLibHarness");
        env = vm.readFile("./src/scripts/env.json");
    }

    // given the live mainnet to Arbitrum lane, an OnRamp 2.0.0 quoting through FeeQuoter 2.0.0
    //   [X] it reads the chain default from the fee quoter and names both contracts
    function test_givenLiveOnRamp20Lane() public view {
        (uint32 overhead, bool isTokenEntry, string memory source) = harness
            .readOhmDestGasOverhead(env, "mainnet", "arbitrum");

        assertEq(overhead, LIVE_CHAIN_DEFAULT, "overhead should be the live chain default");
        assertFalse(isTokenEntry, "no OHM entry exists on the lane at the pinned block");
        assertEq(source, "chain default, FeeQuoter 2.0.0 via OnRamp 2.0.0 (no OHM entry)", "source");
    }

    // given the live mainnet to Base lane, an OnRamp 1.6.0 quoting through the same FeeQuoter 2.0.0
    //   [X] it reads the chain default from the fee quoter and names both contracts
    function test_givenLiveOnRamp16Lane() public view {
        (uint32 overhead, bool isTokenEntry, string memory source) = harness
            .readOhmDestGasOverhead(env, "mainnet", "base");

        assertEq(overhead, LIVE_CHAIN_DEFAULT, "overhead should be the live chain default");
        assertFalse(isTokenEntry, "no OHM entry exists on the lane at the pinned block");
        assertEq(source, "chain default, FeeQuoter 2.0.0 via OnRamp 1.6.0 (no OHM entry)", "source");
    }

    // given the live mainnet to Berachain lane, a dedicated EVM2EVMOnRamp 1.5.0
    //   [X] it reads the lane default from the on-ramp and names it
    function test_givenLiveLegacyLane() public view {
        (uint32 overhead, bool isTokenEntry, string memory source) = harness
            .readOhmDestGasOverhead(env, "mainnet", "berachain");

        assertEq(overhead, LIVE_CHAIN_DEFAULT, "overhead should be the live lane default");
        assertFalse(isTokenEntry, "no OHM entry exists on the lane at the pinned block");
        assertEq(source, "chain default, EVM2EVMOnRamp 1.5.0 (no OHM entry)", "source");
    }

    // given the live lanes without an OHM entry
    //   [X] requireOhmFeeBudget reverts naming the lane and the chain default
    function test_givenLiveLanes_requireOhmFeeBudget_reverts() public {
        vm.expectRevert(
            bytes(
                "CCIPFeeBudgetLib: the OHM delivery gas budget of the lane mainnet -> arbitrum has no enabled OHM token entry (the applicable value is the chain default 90000; chain default, FeeQuoter 2.0.0 via OnRamp 2.0.0 (no OHM entry)); request an enabled OHM fee entry of at least 175000 from Chainlink before opening the route"
            )
        );
        harness.requireOhmFeeBudget(env, "mainnet", "arbitrum");
    }
}
