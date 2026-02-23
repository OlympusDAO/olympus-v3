// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {console2} from "forge-std/console2.sol";

// Contracts
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {ConvertibleOHMTeller} from "src/policies/rewards/convertible/ConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";
import {RewardDistributorConvertible} from "src/policies/rewards/RewardDistributorConvertible.sol";

// Interfaces
import {IRewardDistributorConvertible} from "src/policies/interfaces/rewards/IRewardDistributorConvertible.sol";

// Proposal
import {RewardDistributorProposalConvertible} from "src/proposals/RewardDistributorProposalConvertible.sol";

contract RewardDistributorProposalConvertibleTest is ProposalTest {
    /// @dev Block after contracts are deployed and installed in the Kernel.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 23831097;

    // ========== DEPLOYMENT TOGGLES ==========

    /// @dev Set to true once the ConvertibleOHMTeller and RewardDistributorConvertible
    ///      policies have been deployed on mainnet. When false, setUp() deploys them
    ///      locally and registers them in the address registry before proposal simulation.
    bool public constant IS_POLICIES_DEPLOYED = false;

    // ========== CONTRACTS ==========

    Kernel public kernel;
    ConvertibleOHMTeller public teller;
    RewardDistributorConvertible public distributor;
    RewardDistributorProposalTestWrapper public proposalWrapper;
    IERC20 public ohm;
    IERC20 public usds;
    ROLESv1 public roles;

    // ========== ADDRESSES ==========

    address public distributorMS;
    address public daoMS;

    // ========== TEST PARAMETERS ==========

    uint256 internal constant STRIKE_PRICE = 15e18; // 15 USDS per OHM (18 decimals)
    address internal user0 = makeAddr("user0");

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK + 1);

        // ========== PROPOSAL SETUP ==========

        // Deploy proposal under test
        RewardDistributorProposalConvertible proposal = new RewardDistributorProposalConvertible();
        proposalWrapper = new RewardDistributorProposalTestWrapper();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Initialize test suite and addresses
        _setupSuite(address(proposal));

        // ========== LOAD COMMON ADDRESSES ==========

        kernel = Kernel(addresses.getAddress("olympus-kernel"));
        ohm = IERC20(addresses.getAddress("olympus-legacy-ohm"));
        usds = IERC20(addresses.getAddress("external-tokens-usds"));
        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        daoMS = addresses.getAddress("olympus-multisig-dao");
        distributorMS = addresses.getAddress("olympus-multisig-reward-distributor");

        // ========== CONDITIONAL POLICY DEPLOYMENT ==========

        if (IS_POLICIES_DEPLOYED) {
            teller = ConvertibleOHMTeller(
                addresses.getAddress("olympus-policy-convertible-ohm-teller")
            );
            distributor = RewardDistributorConvertible(
                addresses.getAddress("olympus-policy-reward-distributor-convertible")
            );
            console2.log("Policies already deployed on mainnet");
        } else {
            // Deploy teller
            teller = new ConvertibleOHMTeller(address(kernel), address(ohm));
            vm.label(address(teller), "ConvertibleOHMTeller");

            // Deploy distributor
            // lastEpochEndDate = end of yesterday (23:59:59 UTC)
            uint256 lastEpochEndDate = _roundToDay(uint48(block.timestamp)) - 1;
            distributor = new RewardDistributorConvertible(
                address(kernel),
                lastEpochEndDate,
                address(teller)
            );
            vm.label(address(distributor), "RewardDistributorConvertible");

            // Register in the address registry so the proposal can find them
            // Note: addresses.json has 0x0 placeholders which are treated as non-existent,
            // so we use addAddress (not changeAddress)
            addresses.addAddress(
                "olympus-policy-convertible-ohm-teller",
                address(teller),
                block.chainid
            );
            addresses.addAddress(
                "olympus-policy-reward-distributor-convertible",
                address(distributor),
                block.chainid
            );
            console2.log("Policies deployed locally");
        }

        // Set debug mode
        suite.setDebug(true);

        // Simulate the proposal (activates policies, grants roles, enables)
        _simulateProposal();

        // Deploy wrapper with updated addresses (after simulation)
        proposalWrapper.deploy(addresses, address(this));

        // Re-read addresses in case simulation updated them
        addresses = suite.addresses();

        // ========== VERIFY POST-PROPOSAL STATE ==========

        _verifyPostProposalState();
    }

    // ========== SETUP VERIFICATION ==========

    /// @notice Verifies the critical post-proposal state in setUp, failing fast on misconfiguration
    function _verifyPostProposalState() internal view {
        assertTrue(
            Policy(address(teller)).isActive(),
            "ConvertibleOHMTeller should be active after proposal"
        );
        assertTrue(
            Policy(address(distributor)).isActive(),
            "RewardDistributorConvertible should be active after proposal"
        );
        assertTrue(teller.isEnabled(), "ConvertibleOHMTeller should be enabled after proposal");
        assertTrue(
            distributor.isEnabled(),
            "RewardDistributorConvertible should be enabled after proposal"
        );

        console2.log("");
        console2.log("====== Post-Proposal State Verified ======");
        console2.log("ConvertibleOHMTeller active:", Policy(address(teller)).isActive());
        console2.log(
            "RewardDistributorConvertible active:",
            Policy(address(distributor)).isActive()
        );
        console2.log("Mint approval:", teller.remainingMintApproval());
    }

    // ========== HELPERS ==========

    /// @notice Generates a merkle leaf for reward claims (double-hash)
    function _generateLeaf(
        address user,
        uint256 epochEndDate,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user, epochEndDate, amount))));
    }

    /// @notice Encodes EndEpochParams for the distributor
    function _encodeParams(
        address quoteToken,
        uint48 eligible,
        uint48 expiry,
        uint256 strikePrice
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                IRewardDistributorConvertible.EndEpochParams({
                    quoteToken: quoteToken,
                    eligible: eligible,
                    expiry: expiry,
                    strikePrice: strikePrice
                })
            );
    }

    /// @notice Returns a valid epoch end date (23:59:59 UTC) for the first epoch after the fork
    function _firstEpochEndDate() internal view returns (uint40) {
        return uint40(_roundToDay(uint48(block.timestamp)) + 1 days - 1);
    }

    /// @notice Rounds a timestamp down to 00:00:00 UTC
    function _roundToDay(uint48 timestamp) internal pure returns (uint48) {
        return uint48(timestamp / 1 days) * 1 days;
    }

    /// @notice Calculates exercise cost: ceil(amount * strikePrice / 1e9)
    function _calcExerciseCost(uint256 amount) internal pure returns (uint256) {
        // amount is in OHM decimals (9), strikePrice is in USDS decimals (18)
        // cost = amount * strikePrice / 1e9, rounded up
        return (amount * STRIKE_PRICE + 1e9 - 1) / 1e9;
    }

    // ========================================================================
    // End State Tests
    // ========================================================================

    /// @notice Validates that the proposal leaves the system in the correct end state
    function test_proposalEndState() public view {
        // Verify ConvertibleOHMTeller is active in the Kernel
        assertTrue(Policy(address(teller)).isActive(), "ConvertibleOHMTeller should be active");

        // Verify RewardDistributorConvertible is active in the Kernel
        assertTrue(
            Policy(address(distributor)).isActive(),
            "RewardDistributorConvertible should be active"
        );

        // Verify roles are correctly assigned
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(distributor), bytes32("convertible_distributor")),
            "RewardDistributorConvertible should have convertible_distributor role"
        );
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, bytes32("convertible_admin")),
            "DAO MS should have convertible_admin role"
        );
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(distributorMS, bytes32("rewards_manager")),
            "Distributor MS should have rewards_manager role"
        );

        // Verify policies are enabled
        assertTrue(teller.isEnabled(), "ConvertibleOHMTeller should be enabled");
        assertTrue(distributor.isEnabled(), "RewardDistributorConvertible should be enabled");

        // TODO: specify the specific minting cap value when it becomes known
        // Verify mint cap was set to INITIAL_MINT_CAP (1000 OHM = 1000e9)
        assertEq(teller.remainingMintApproval(), 1000e9, "Mint cap should be 1000 OHM");

        // Cross-references: distributor -> teller
        assertEq(
            address(distributor.TELLER()),
            address(teller),
            "Distributor TELLER should reference the teller"
        );

        // Cross-references: teller -> OHM
        assertEq(teller.OHM(), address(ohm), "Teller OHM should reference the OHM token");

        // Default config: minDuration
        assertEq(
            teller.minDuration(),
            uint48(1 days),
            "Teller minDuration should default to 1 day"
        );

        // Initial state: lastEpochEndDate initialized (not zero)
        assertTrue(
            distributor.lastEpochEndDate() > 0,
            "Distributor lastEpochEndDate should be initialized"
        );
    }

    // ========================================================================
    // Validate Tests
    // ========================================================================

    /// @notice Validates the proposal's own _validate function passes
    function test_validate_passes() public view {
        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Verifies that _validate still passes after a rewards_manager ends an epoch
    /// @dev endEpoch deploys tokens but does not change mint approval, so _validate
    ///      (which checks remainingMintApproval == INITIAL_MINT_CAP) should still pass.
    ///      Analogous to migration cleanup tests that verify _validate holds after state changes.
    function test_validate_passesAfterEndEpoch() public {
        vm.prank(distributorMS);
        distributor.endEpoch(
            _firstEpochEndDate(),
            bytes32(uint256(1)),
            _encodeParams(
                address(usds),
                _roundToDay(uint48(block.timestamp) + 90 days),
                _roundToDay(uint48(block.timestamp) + 180 days),
                STRIKE_PRICE
            )
        );

        proposalWrapper.validate(addresses, address(this));
    }

    /// @notice Verifies that _validate still passes after a user claims convOHM tokens
    /// @dev claim() mints convOHM via teller.create() which does not consume MINTR
    ///      mint approval. _validate's remainingMintApproval check should still pass.
    function test_validate_passesAfterClaim() public {
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9;
        bytes32 leaf = _generateLeaf(user0, epochEndDate, claimAmount);

        vm.prank(distributorMS);
        distributor.endEpoch(
            epochEndDate,
            leaf,
            _encodeParams(
                address(usds),
                _roundToDay(uint48(block.timestamp) + 90 days),
                _roundToDay(uint48(block.timestamp) + 180 days),
                STRIKE_PRICE
            )
        );

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        proposalWrapper.validate(addresses, address(this));
    }

    // ========================================================================
    // Functional Lifecycle Tests
    // ========================================================================

    /// @notice Validates that an epoch can be ended by the rewards_manager
    /// @dev Verifies the rewards_manager role can call endEpoch, which deploys a
    ///      ConvertibleOHMToken with the correct parameters and stores the merkle root.
    function test_endEpoch_succeeds() public {
        uint40 epochEndDate = _firstEpochEndDate();
        bytes32 merkleRoot = bytes32(uint256(1));
        uint48 eligibleTimestamp = _roundToDay(uint48(block.timestamp) + 90 days);
        uint48 expiryTimestamp = _roundToDay(uint48(block.timestamp) + 180 days);

        bytes memory params = _encodeParams(
            address(usds),
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );

        vm.prank(distributorMS);
        address token = distributor.endEpoch(epochEndDate, merkleRoot, params);

        // Verify token was deployed
        assertFalse(token == address(0), "Token should be deployed");

        // Verify merkle root was set
        assertEq(
            distributor.epochMerkleRoots(epochEndDate),
            merkleRoot,
            "Merkle root should be set"
        );

        // Verify convertible token was stored for the epoch
        assertEq(
            address(distributor.epochConvertibleTokens(epochEndDate)),
            token,
            "Token should be stored for epoch"
        );

        // Verify lastEpochEndDate was updated
        assertEq(
            distributor.lastEpochEndDate(),
            epochEndDate,
            "lastEpochEndDate should be updated"
        );

        // Verify token parameters match what was requested
        ConvertibleOHMToken convToken = ConvertibleOHMToken(token);
        assertEq(address(convToken.quote()), address(usds), "Quote token should be USDS");
        assertEq(convToken.strike(), STRIKE_PRICE, "Strike price should match");
        assertEq(convToken.eligible(), eligibleTimestamp, "Eligible timestamp should match");
        assertEq(convToken.expiry(), expiryTimestamp, "Expiry timestamp should match");
    }

    /// @notice Validates that a user can claim convOHM for an epoch
    /// @dev Verifies a user can claim convOHM tokens via merkle proof. Uses a single-leaf
    ///      tree (leaf == root) for simplicity and checks balance + claimed flag.
    function test_claim_succeeds() public {
        // 1. Setup: end epoch with a single-leaf merkle tree for user0
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9; // 100 OHM (9 decimals)
        uint48 eligibleTimestamp = _roundToDay(uint48(block.timestamp) + 90 days);
        uint48 expiryTimestamp = _roundToDay(uint48(block.timestamp) + 180 days);

        // Single-leaf merkle tree: leaf == root
        bytes32 leaf = _generateLeaf(user0, epochEndDate, claimAmount);

        vm.prank(distributorMS);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                leaf,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // 2. User claims with empty proof (single leaf = root)
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        (address[] memory tokens, uint256[] memory mintedAmounts) = distributor.claim(
            epochEndDates,
            amounts,
            proofs
        );

        // 3. Verify
        assertEq(tokens.length, 1, "Should return one token");
        assertEq(tokens[0], address(token), "Token address should match");
        assertEq(mintedAmounts[0], claimAmount, "Minted amount should match");
        assertEq(token.balanceOf(user0), claimAmount, "User should hold convOHM tokens");
        assertTrue(distributor.hasClaimed(user0, epochEndDate), "User should be marked as claimed");
    }

    /// @notice Validates the full lifecycle: endEpoch -> claim convOHM -> exercise to OHM
    /// @dev Full lifecycle test: claim convOHM -> warp to eligible -> exercise via teller.
    ///      Verifies OHM minted to user, convOHM burned, USDS transferred to TRSRY,
    ///      and mint approval decremented by the exercised amount.
    function test_claimAndExercise_succeeds() public {
        // 1. Setup: end epoch
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9; // 100 OHM (9 decimals)
        uint48 eligibleTimestamp = _roundToDay(uint48(block.timestamp) + 90 days);
        uint48 expiryTimestamp = _roundToDay(uint48(block.timestamp) + 180 days);

        bytes32 leaf = _generateLeaf(user0, epochEndDate, claimAmount);

        vm.prank(distributorMS);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                leaf,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // 2. User claims
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);
        assertEq(token.balanceOf(user0), claimAmount, "User should hold convOHM tokens");

        // 3. Warp to eligible timestamp
        vm.warp(eligibleTimestamp);

        // 4. Exercise: convert convOHM to OHM by paying USDS
        // exerciseCost = ceil(100e9 * 15e18 / 1e9) = 1500e18 USDS
        uint256 exerciseCost = _calcExerciseCost(claimAmount);
        deal(address(usds), user0, exerciseCost);

        uint256 ohmBefore = ohm.balanceOf(user0);
        address trsry = address(teller.TRSRY());
        uint256 trsryUsdsBefore = usds.balanceOf(trsry);
        uint256 mintApprovalBefore = teller.remainingMintApproval();

        vm.startPrank(user0);
        token.approve(address(teller), claimAmount);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), claimAmount);
        vm.stopPrank();

        // 5. Verify user received OHM and convOHM was burned
        assertEq(
            ohm.balanceOf(user0) - ohmBefore,
            claimAmount,
            "User should receive OHM equal to claim amount"
        );
        assertEq(token.balanceOf(user0), 0, "convOHM tokens should be burned");

        // 6. Verify USDS was transferred to TRSRY
        assertEq(
            usds.balanceOf(trsry) - trsryUsdsBefore,
            exerciseCost,
            "TRSRY should receive USDS exercise cost"
        );

        // 7. Verify user USDS was fully spent
        assertEq(usds.balanceOf(user0), 0, "User should have no USDS remaining");

        // 8. Verify mint approval decreased by the exercised amount
        assertEq(
            mintApprovalBefore - teller.remainingMintApproval(),
            claimAmount,
            "Mint approval should decrease by exercised amount"
        );
    }
}

/// @notice Test wrapper to expose internal _validate and _deploy functions for testing
contract RewardDistributorProposalTestWrapper is RewardDistributorProposalConvertible {
    function validate(Addresses addresses, address caller) external view {
        _validate(addresses, caller);
    }

    function deploy(Addresses addresses, address deployer) external {
        _deploy(addresses, deployer);
    }
}

/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
