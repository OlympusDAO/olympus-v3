// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IIncentiveDistributorConvertible} from "src/policies/interfaces/incentives/IIncentiveDistributorConvertible.sol";
import {IPeriodicTaskManager} from "src/bases/interfaces/IPeriodicTaskManager.sol";

// Libraries
import {console2} from "forge-std/console2.sol";

// Contracts
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {ConvertibleOHMTeller} from "src/policies/incentives/convertible/ConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/incentives/convertible/ConvertibleOHMToken.sol";
import {IncentiveDistributorConvertible} from "src/policies/incentives/IncentiveDistributorConvertible.sol";
import {IncentiveDistributorProposalConvertible} from "src/proposals/IncentiveDistributorProposalConvertible.sol";
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {ProposalTest} from "./ProposalTest.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";

contract IncentiveDistributorProposalConvertibleTest is ProposalTest {
    /// @dev Block after contracts are deployed and installed in the Kernel.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 24978836;

    // ========== DEPLOYMENT TOGGLES ==========

    /// @dev Set to true once the ConvertibleOHMTeller and IncentiveDistributorConvertible
    ///      policies have been deployed on mainnet. When false, setUp() deploys them
    ///      locally and registers them in the address registry before proposal simulation.
    bool public constant IS_POLICIES_DEPLOYED = false;

    // ========== CONTRACTS ==========

    Kernel public kernel;
    ConvertibleOHMTeller public teller;
    IncentiveDistributorConvertible public distributor;
    IncentiveDistributorProposalTestWrapper public proposalWrapper;
    IERC20 public ohm;
    IERC20 public usds;
    ROLESv1 public roles;

    // ========== ADDRESSES ==========

    address public distributorMS;

    // ========== TEST PARAMETERS ==========

    uint256 internal constant STRIKE_PRICE = 15e18; // 15 USDS per OHM (18 decimals)
    address internal user0 = makeAddr("user0");

    function setUp() public virtual {
        // Mainnet fork at a fixed block prior to proposal execution to ensure deterministic state
        vm.createSelectFork(_RPC_ALIAS, BLOCK + 1);

        // ========== PROPOSAL SETUP ==========

        // Deploy proposal under test
        IncentiveDistributorProposalConvertible proposal = new IncentiveDistributorProposalConvertible();
        proposalWrapper = new IncentiveDistributorProposalTestWrapper();

        // Set to true once the proposal has been submitted on-chain to enforce calldata matching
        hasBeenSubmitted = false;

        // Initialize test suite and addresses
        _setupSuite(address(proposal));

        // ========== LOAD COMMON ADDRESSES ==========

        kernel = Kernel(addresses.getAddress("olympus-kernel"));
        ohm = IERC20(addresses.getAddress("olympus-legacy-ohm"));
        usds = IERC20(addresses.getAddress("external-tokens-usds"));
        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        distributorMS = addresses.getAddress("olympus-multisig-incentive-distributor");

        // ========== CONDITIONAL POLICY DEPLOYMENT ==========

        if (IS_POLICIES_DEPLOYED) {
            teller = ConvertibleOHMTeller(
                addresses.getAddress("olympus-policy-convertible-ohm-teller")
            );
            distributor = IncentiveDistributorConvertible(
                addresses.getAddress("olympus-policy-incentive-distributor-convertible")
            );
            console2.log("Policies already deployed on mainnet");
        } else {
            // Deploy teller
            teller = new ConvertibleOHMTeller(address(kernel), address(ohm));
            vm.label(address(teller), "ConvertibleOHMTeller");

            // Deploy distributor
            // lastEpochEndDate = end of yesterday (23:59:59 UTC)
            uint40 lastEpochEndDate = uint40(_roundToDay(uint48(block.timestamp)) - 1);
            distributor = new IncentiveDistributorConvertible(
                address(kernel),
                lastEpochEndDate,
                address(teller)
            );
            vm.label(address(distributor), "IncentiveDistributorConvertible");

            // Register in the address registry so the proposal can find them
            // Note: addresses.json has 0x0 placeholders which are treated as non-existent,
            // so we use addAddress (not changeAddress)
            addresses.addAddress(
                "olympus-policy-convertible-ohm-teller",
                address(teller),
                block.chainid
            );
            addresses.addAddress(
                "olympus-policy-incentive-distributor-convertible",
                address(distributor),
                block.chainid
            );
            console2.log("Policies deployed locally");

            // Activate policies in the Kernel (normally done by deployment scripts)
            address executor = kernel.executor();
            vm.startPrank(executor);
            kernel.executeAction(Actions.ActivatePolicy, address(teller));
            kernel.executeAction(Actions.ActivatePolicy, address(distributor));
            vm.stopPrank();
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
            "IncentiveDistributorConvertible should be active after proposal"
        );
        assertTrue(teller.isEnabled(), "ConvertibleOHMTeller should be enabled after proposal");
        assertTrue(
            distributor.isEnabled(),
            "IncentiveDistributorConvertible should be enabled after proposal"
        );

        console2.log("");
        console2.log("====== Post-Proposal State Verified ======");
        console2.log("ConvertibleOHMTeller active:", Policy(address(teller)).isActive());
        console2.log(
            "IncentiveDistributorConvertible active:",
            Policy(address(distributor)).isActive()
        );
        console2.log("Mint approval:", teller.remainingMintApproval());
    }

    // ========== HELPERS ==========

    /// @notice Generates a merkle leaf for incentive claims (double-hash)
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
                IIncentiveDistributorConvertible.EndEpochParams({
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

        // Verify IncentiveDistributorConvertible is active in the Kernel
        assertTrue(
            Policy(address(distributor)).isActive(),
            "IncentiveDistributorConvertible should be active"
        );

        // Verify roles are correctly assigned
        address timelock = addresses.getAddress("olympus-timelock");
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(timelock, bytes32("admin")),
            "OCG Timelock should have admin role"
        );
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(distributor), bytes32("convertible_distributor")),
            "IncentiveDistributorConvertible should have convertible_distributor role"
        );
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(distributorMS, bytes32("incentive_manager")),
            "Distributor MS should have incentive_manager role"
        );

        // Verify the teller is registered as a periodic task on the Heart
        IPeriodicTaskManager heart = IPeriodicTaskManager(
            addresses.getAddress("olympus-policy-heart-1_7")
        );
        assertTrue(
            heart.hasPeriodicTask(address(teller)),
            "ConvertibleOHMTeller should be registered as a Heart periodic task"
        );

        // Verify policies are enabled
        assertTrue(teller.isEnabled(), "ConvertibleOHMTeller should be enabled");
        assertTrue(distributor.isEnabled(), "IncentiveDistributorConvertible should be enabled");

        // TODO: specify the specific cap value when it becomes known
        // Verify creator mint cap was set to 1000 OHM and no mints have happened yet.
        assertEq(
            teller.remainingMintApproval(),
            0,
            "MINTR approval should be 0 at enable (no mints yet)"
        );
        assertEq(
            teller.creatorMintCap(address(distributor)),
            1000e9,
            "Distributor creator cap should be 1000 OHM"
        );
        assertEq(teller.creatorMinted(address(distributor)), 0, "creatorMinted should start at 0");
        assertEq(
            teller.creatorOutstanding(address(distributor)),
            0,
            "creatorOutstanding should start at 0"
        );

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

    /// @notice Verifies that _validate still passes after a incentive_manager ends an epoch
    /// @dev endEpoch deploys tokens but does not change mint approval, so _validate
    ///      (which checks remainingMintApproval == INITIAL_MINT_CAP) should still pass.
    ///      Analogous to migration cleanup tests that verify _validate holds after state changes.
    function test_validate_passesAfterEndEpoch() public {
        uint40 epochEndDate = _firstEpochEndDate();
        vm.warp(uint256(epochEndDate) + 1);
        vm.prank(distributorMS);
        distributor.endEpoch(
            epochEndDate,
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

    /// @notice Verifies that _validate still passes after a user claims convOHM tokens.
    /// @dev claim() mints convOHM via teller.create(), which raises remainingMintApproval and
    ///      bumps creatorMinted/creatorOutstanding.
    function test_validate_passesAfterClaim() public {
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9;
        bytes32 leaf = _generateLeaf(user0, epochEndDate, claimAmount);

        vm.warp(uint256(epochEndDate) + 1);
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

        // Verify post-claim teller state
        assertEq(
            teller.remainingMintApproval(),
            claimAmount,
            "MINTR approval should equal the claimed amount post-claim"
        );
        assertEq(
            teller.creatorOutstanding(address(distributor)),
            claimAmount,
            "creatorOutstanding should equal the claimed amount post-claim"
        );
        assertEq(
            teller.creatorMinted(address(distributor)),
            claimAmount,
            "creatorMinted should equal the claimed amount post-claim"
        );

        proposalWrapper.validate(addresses, address(this));
    }

    // ========================================================================
    // Functional Lifecycle Tests
    // ========================================================================

    /// @notice Validates that an epoch can be ended by the incentive_manager
    /// @dev Verifies the incentive_manager role can call endEpoch, which deploys a
    ///      ConvertibleOHMToken with the correct parameters and stores the merkle root.
    function test_endEpoch_succeeds() public {
        uint40 epochEndDate = _firstEpochEndDate();
        bytes32 merkleRoot = bytes32(uint256(1));

        // Warp past epoch end so endEpoch() passes the timestamp check
        vm.warp(uint256(epochEndDate) + 1);

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

        // Deployed token should be tracked in the teller's active set
        assertTrue(teller.isActiveToken(token), "Deployed token should be in teller active set");
    }

    /// @notice Validates that a user can claim convOHM for an epoch
    /// @dev Verifies a user can claim convOHM tokens via merkle proof. Uses a single-leaf
    ///      tree (leaf == root) for simplicity and checks balance + claimed flag.
    function test_claim_succeeds() public {
        // 1. Setup: end epoch with a single-leaf merkle tree for user0
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9; // 100 OHM (9 decimals)

        // Warp past epoch end so endEpoch() passes the timestamp check
        vm.warp(uint256(epochEndDate) + 1);

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
        assertEq(
            teller.creatorMinted(address(distributor)),
            claimAmount,
            "creatorMinted should track the claimed amount"
        );
        assertEq(
            teller.remainingMintApproval(),
            claimAmount,
            "MINTR approval should equal the claimed amount"
        );
    }

    /// @notice Validates the full lifecycle: endEpoch -> claim convOHM -> exercise to OHM
    /// @dev Full lifecycle test: claim convOHM -> warp to eligible -> exercise via teller.
    ///      Verifies OHM minted to user, convOHM burned, USDS transferred to TRSRY,
    ///      and mint approval decremented by the exercised amount.
    function test_claimAndExercise_succeeds() public {
        // 1. Setup: end epoch
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9; // 100 OHM (9 decimals)

        // Warp past epoch end so endEpoch() passes the timestamp check
        vm.warp(uint256(epochEndDate) + 1);

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

        // 9. Verify creator state: outstanding back to 0, minted preserved
        assertEq(
            teller.creatorOutstanding(address(distributor)),
            0,
            "creatorOutstanding should be 0 after exercise"
        );
        assertEq(
            teller.creatorMinted(address(distributor)),
            claimAmount,
            "creatorMinted should remain at the claimed amount"
        );
    }
}

/// @notice Test wrapper to expose internal _validate and _deploy functions for testing
contract IncentiveDistributorProposalTestWrapper is IncentiveDistributorProposalConvertible {
    function validate(Addresses addresses, address caller) external view {
        _validate(addresses, caller);
    }

    function deploy(Addresses addresses, address deployer) external {
        _deploy(addresses, deployer);
    }
}

/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
