// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity ^0.8.24;

// Contracts
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {YieldRepurchaseFacilityV2Proposal} from "src/proposals/YieldRepurchaseFacilityV2Proposal.sol";

/// @notice Exposes the lifecycle hooks of the proposal and reads the tracked `env.json`
///         unchanged: the proposal as it is before its submission.
contract YieldRepurchaseFacilityV2ProposalHarness is YieldRepurchaseFacilityV2Proposal {
    /// @notice The desired-state string the proposal reads, for the assertions of the rig.
    function readEnv() external view returns (string memory env) {
        return _readEnv();
    }

    function deploy(Addresses addresses_, address deployer_) external {
        _deploy(addresses_, deployer_);
    }

    /// @notice Reads the state before the actions, the way `run` does between the deployment
    ///         hook and the build.
    function afterDeploy(Addresses addresses_, address deployer_) external {
        _afterDeploy(addresses_, deployer_);
    }

    function build(Addresses addresses_) external {
        _build(addresses_);
    }

    /// @notice Runs the built actions through the governor, the way `run` does after the build.
    function simulate(Addresses addresses_) external {
        _run(addresses_, address(0));
    }

    function validate(Addresses addresses_, address caller_) external view {
        _validate(addresses_, caller_);
    }
}

/// @notice The proposal after its submission: it reads the desired state from the snapshot of
///         `env.json` taken when the proposal was submitted, so that the suites pinned at the
///         submission block do not follow later changes of the tracked file.
/// @dev The snapshot holds the keys that `YieldRepurchaseFacilityV2ConfigLib` and
///      `BackingOracleConfigLib` read for mainnet, and nothing else.
contract YieldRepurchaseFacilityV2ProposalSnapshotHarness is
    YieldRepurchaseFacilityV2ProposalHarness
{
    string public constant ENV_SNAPSHOT_PATH =
        "./src/scripts/proposals/snapshots/YieldRepurchaseFacilityV2Proposal.env.json";

    /// @inheritdoc YieldRepurchaseFacilityV2Proposal
    function _readEnv() internal view override returns (string memory env) {
        // The path is the constant above: the snapshot and nothing else is read
        // forge-lint: disable-next-line(unsafe-cheatcode)
        return vm.readFile(ENV_SNAPSHOT_PATH);
    }
}

/// @notice The proposal against a desired state supplied by the test, for the gates of the
///         build that compare the activator with `env.json`.
contract YieldRepurchaseFacilityV2ProposalFixtureHarness is
    YieldRepurchaseFacilityV2ProposalHarness
{
    string internal _fixtureEnv;

    constructor(string memory env_) {
        _fixtureEnv = env_;
    }

    /// @inheritdoc YieldRepurchaseFacilityV2Proposal
    function _readEnv() internal view override returns (string memory env) {
        return _fixtureEnv;
    }
}
