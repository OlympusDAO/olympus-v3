// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Proposal test-suite imports
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestSuite} from "proposal-sim/test/TestSuite.t.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {BytesLib} from "src/test/libraries/BytesLib.sol";
import {Strings} from "@openzeppelin-4.8.0/utils/Strings.sol";

/// @notice Creates a sandboxed environment from a mainnet fork, to simulate the proposal.
/// @dev    Update the `setUp` function to deploy your proposal and set the submission
///         flag to `true` once the proposal has been submitted on-chain.
/// Note: this will fail if the OCGPermissions script has not been run yet.
abstract contract ProposalTest is Test {
    string public constant ADDRESSES_PATH = "./src/proposals/addresses.json";
    TestSuite public suite;
    Addresses public addresses;

    // Wether the proposal has been submitted or not.
    // If true, the framework will check that calldatas match.
    bool public hasBeenSubmitted;

    string internal constant _RPC_ALIAS = "mainnet";

    /// @notice This function simulates a proposal suite which has already been setup via `_setupSuite()` or `_setupSuites()`.
    /// @dev    This function assumes the following:
    ///         - A mainnet fork has been created using `vm.createSelectFork` with a block number prior to the proposal deployment.
    ///         - If the proposal has been submitted on-chain, the `hasBeenSubmitted` flag has been set to `true`.
    ///         - The proposal contract has been deployed within the test contract and passed as an argument.
    function _simulateProposal() internal virtual {
        /// @notice This section is used to simulate the proposal on the mainnet fork.
        if (address(suite) == address(0)) {
            // solhint-disable gas-custom-errors
            revert("_setupSuites() should be called prior to simulating");
        }

        vm.recordLogs();

        // Execute proposals
        suite.testProposals();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Proposals execution may change addresses, so we need to update the addresses object.
        addresses = suite.addresses();

        if (entries.length != 0) {
            _logRoleEvents(entries, addresses);
        }

        // Check if simulated calldatas match the ones from mainnet.
        if (hasBeenSubmitted) {
            address governor = addresses.getAddress("olympus-governor");
            bool[] memory matches = suite.checkProposalCalldatas(governor);
            for (uint256 i; i < matches.length; i++) {
                assertTrue(matches[i], "Calldata should match");
            }
        } else {
            console2.log("\n\n------- Calldata check (simulation vs mainnet) -------\n");
            console2.log("Proposal has NOT been submitted on-chain yet.\n");
        }
    }

    function _setupSuite(address proposal_) internal {
        address[] memory proposals_ = new address[](1);
        proposals_[0] = proposal_;
        _setupSuites(proposals_);
    }

    function _setupSuites(address[] memory proposals_) internal {
        // Deploy TestSuite contract
        suite = new TestSuite(ADDRESSES_PATH, proposals_);

        // Set addresses object
        addresses = suite.addresses();

        // Set debug mode
        suite.setDebug(true);
    }

    /// @dev Dummy test to ensure `setUp` is executed and the proposal simulated.
    function testProposal_simulate() public pure {
        assertTrue(true, "Proposal should be simulated");
    }

    /// @notice Prints human-readable role change events emitted during proposal execution.
    /// @dev    Ignores logs that do not match `RoleGranted` or `RoleRevoked`. Handles both cases where
    ///         the role bytes32 decodes to an ASCII string and where no address name is known (falls
    ///         back to the raw hex string).
    /// @param logs_ The logs recorded during the proposal execution.
    /// @param addresses_ The addresses registry, used to resolve names for relevant addresses.
    function _logRoleEvents(
        Vm.Log[] memory logs_,
        Addresses addresses_
    ) internal view {
        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 roleGrantedSig = keccak256("RoleGranted(bytes32,address)");
        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 roleRevokedSig = keccak256("RoleRevoked(bytes32,address)");

        for (uint256 i; i < logs_.length; i++) {
            Vm.Log memory entry = logs_[i];

            if (entry.topics.length < 3) continue;

            bytes32 signature = entry.topics[0];

            if (signature != roleGrantedSig && signature != roleRevokedSig) {
                continue;
            }

            bytes32 role = entry.topics[1];
            address account = address(uint160(uint256(entry.topics[2])));

            string memory roleLabel = BytesLib.bytes32ToString(role);
            string memory accountDescriptor = _formatAccountDescriptor(
                addresses_,
                account
            );

            if (signature == roleGrantedSig) {
                console2.log(
                    string.concat(
                        "+ Role '",
                        roleLabel,
                        "' granted to ",
                        accountDescriptor
                    )
                );
            } else {
                console2.log(
                    string.concat(
                        "- Role '",
                        roleLabel,
                        "' revoked from ",
                        accountDescriptor
                    )
                );
            }
        }
    }

    /// @notice Builds a display string for an address combining its name (if available) with the hex value.
    /// @dev    Returns only the hex string when the address is unknown in the registry and no VM label is set.
    /// @param addresses_ The addresses registry to query for known addresses.
    /// @param account_ The address being formatted.
    /// @return string A human-readable descriptor, e.g. `olympus-governor (0x...)` or just `0x...`.
    function _formatAccountDescriptor(
        Addresses addresses_,
        address account_
    ) internal view returns (string memory) {
        string memory name = _lookupAddressName(addresses_, account_);

        if (bytes(name).length == 0) {
            return Strings.toHexString(account_);
        }

        return string.concat(name, " (", Strings.toHexString(account_), ")");
    }

    /// @notice Attempts to resolve the human-readable name for an address.
    /// @dev    Searches recorded and changed addresses scoped to the current chain id, falls back to
    ///         any forge-std VM label, and returns an empty string if no label is known.
    /// @param addresses_ The addresses registry containing recorded and changed entries.
    /// @param account_ The address to look up.
    /// @return string The resolved name or an empty string when no name is found.
    function _lookupAddressName(
        Addresses addresses_,
        address account_
    ) internal view returns (string memory) {
        if (address(addresses_) != address(0)) {
            try addresses_.getRecordedAddresses() returns (
                string[] memory names,
                uint256[] memory chainIds,
                address[] memory recordedAddresses
            ) {
                uint256 thisChainId = block.chainid;
                for (uint256 i; i < recordedAddresses.length; i++) {
                    if (
                        recordedAddresses[i] == account_ &&
                        chainIds[i] == thisChainId
                    ) {
                        return names[i];
                    }
                }
            } catch {}

            try addresses_.getChangedAddresses() returns (
                string[] memory changedNames,
                uint256[] memory chainIds,
                address[] memory /* oldAddresses */,
                address[] memory newAddresses
            ) {
                uint256 thisChainId = block.chainid;
                for (uint256 i; i < newAddresses.length; i++) {
                    if (
                        newAddresses[i] == account_ &&
                        chainIds[i] == thisChainId
                    ) {
                        return changedNames[i];
                    }
                }
            } catch {}
        }

        string memory label = vm.getLabel(account_);
        if (bytes(label).length != 0) {
            return label;
        }

        return "";
    }
}
