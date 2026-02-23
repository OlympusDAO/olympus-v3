// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {Kernel, Actions, toKeycode, Keycode, Policy} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConvertibleOHMTeller} from "src/policies/rewards/convertible/ConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";
import {RewardDistributorConvertible} from "src/policies/rewards/RewardDistributorConvertible.sol";
import {IRewardDistributor} from "src/policies/interfaces/rewards/IRewardDistributor.sol";
import {IRewardDistributorConvertible} from "src/policies/interfaces/rewards/IRewardDistributorConvertible.sol";
import {IConvertibleOHMTeller} from "src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockConvertibleOHMTellerZeroDeploy} from "src/test/mocks/MockConvertibleOHMTellerZeroDeploy.sol";

contract RewardDistributorConvertibleTestBase is Test {
    // Contracts
    Kernel kernel;
    OlympusTreasury trsry;
    OlympusMinter mintr;
    OlympusRoles roles;

    MockOhm ohm;
    MockERC20 usds;

    ConvertibleOHMTeller teller;
    RewardDistributorConvertible distributor;

    // Test accounts
    address admin = makeAddr("admin");
    address user0 = makeAddr("user0");
    address user1 = makeAddr("user1");

    // Test parameters
    uint256 constant STRIKE_PRICE = 15e18; // 15 USDS per OHM
    uint40 startTimestamp; // Midnight UTC (00:00:00)
    uint48 eligibleTimestamp;
    uint48 expiryTimestamp;

    function setUp() public virtual {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp to a reasonable date (roughly Jan 1, 2021) at midnight UTC
        startTimestamp = uint40(vm.getBlockTimestamp());

        // Deploy mock tokens
        ohm = new MockOhm("Olympus", "OHM", 9);
        usds = new MockERC20("USDS", "USDS", 18);

        // Deploy the kernel
        kernel = new Kernel();

        // Deploy the required modules
        trsry = new OlympusTreasury(kernel);
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        // Install the modules
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));

        // Deploy the teller policy
        teller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(teller));

        // Grant permission to this test contract to call increaseMintApproval
        _grantModulePermission(toKeycode("MINTR"), MINTRv1.increaseMintApproval.selector);
        // Grant permission to this test contract to call saveRole
        _grantModulePermission(toKeycode("ROLES"), ROLESv1.saveRole.selector);

        // Approve the teller to mint OHM (infinite approval)
        mintr.increaseMintApproval(address(teller), type(uint256).max);

        // Setup roles for teller
        roles.saveRole(teller.ROLE_TELLER_ADMIN(), admin);

        // Enable the teller policy with infinite minting cap
        roles.saveRole(ADMIN_ROLE, address(this));
        teller.enable(abi.encode(type(uint256).max));

        // Deploy the distributor
        distributor = new RewardDistributorConvertible(
            address(kernel),
            startTimestamp - 1,
            address(teller)
        );
        kernel.executeAction(Actions.ActivatePolicy, address(distributor));

        // Grant the reward distributor role to the distributor policy
        roles.saveRole(teller.ROLE_REWARD_DISTRIBUTOR(), address(distributor));

        // Setup roles for distributor
        roles.saveRole(distributor.ROLE_REWARDS_MANAGER(), admin);

        // Enable the distributor policy
        distributor.enable("");

        // Prepare test parameters for convertible tokens
        // Set the eligible time to 3 months from now (rounded to the nearest day)
        eligibleTimestamp = _roundToDay(uint48(vm.getBlockTimestamp()) + 90 days);
        // Set the expiry time to 6 months from now (rounded to the nearest day)
        expiryTimestamp = _roundToDay(uint48(vm.getBlockTimestamp()) + 180 days);

        // Fund users with USDS for exercise tests
        usds.mint(user0, 1_000_000e18);
        usds.mint(user1, 1_000_000e18);
    }

    function _grantModulePermission(Keycode keycode, bytes4 selector) internal {
        // modulePermissions is at slot 6 in Kernel
        bytes32 slot = keccak256(
            abi.encode(
                selector,
                keccak256(abi.encode(address(this), keccak256(abi.encode(keycode, 6))))
            )
        );
        vm.store(address(kernel), slot, bytes32(uint256(1)));
        // Validate that the hardcoded slot matches the actual storage layout
        require(
            kernel.modulePermissions(keycode, Policy(address(this)), selector),
            "Storage slot mismatch: modulePermissions slot may have changed"
        );
    }

    // Returns the end date of the first epoch
    function _firstEpochEndDate() internal view returns (uint40) {
        return startTimestamp + 1 days - 1;
    }

    // Generates a merkle leaf for reward claims
    function _generateLeaf(
        address user,
        uint256 epochEndDate,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user, epochEndDate, amount))));
    }

    // Generates a proof for a leaf in a 2-leaf tree
    function _generateProof(bytes32 siblingLeaf) internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = siblingLeaf;
        return proof;
    }

    // Generates a merkle root for two leaves
    function _generateRoot(bytes32 leaf1, bytes32 leaf2) internal pure returns (bytes32) {
        if (leaf1 < leaf2) {
            return keccak256(abi.encodePacked(leaf1, leaf2));
        } else {
            return keccak256(abi.encodePacked(leaf2, leaf1));
        }
    }

    // Rounds timestamp to the nearest day
    function _roundToDay(uint48 timestamp) internal pure returns (uint48) {
        return uint48(timestamp / 1 days) * 1 days;
    }

    // Calculates an expected USDS cost for convertible tokens based on the strike price
    function _calcExpectedCost(uint256 convertibleTokens) internal pure returns (uint256) {
        // cost = ceil(convertibleTokens * strikePrice / 10^ohm.decimals())
        // Example: cost = 100e9 * 15e18 / 1e9 = 1500e18 USDS
        return (convertibleTokens * STRIKE_PRICE + 1e9 - 1) / 1e9; // Round up
    }

    // Encodes IRewardDistributorConvertible.EndEpochParams
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
}

contract RewardDistributorConvertibleConstructorTests is RewardDistributorConvertibleTestBase {
    function test_constructor_initializesCorrectly() external view {
        assertEq(distributor.EPOCH_START_DATE(), startTimestamp, "EPOCH_START_DATE should match");
        assertEq(address(distributor.TELLER()), address(teller), "TELLER should match");
    }

    function test_constructor_rejectsZeroTeller() external {
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidAddress.selector);
        new RewardDistributorConvertible(address(kernel), startTimestamp - 1, address(0));
    }

    function test_constructor_rejectsZeroStartTimestamp() external {
        vm.expectRevert(IRewardDistributor.RewardDistributor_EpochIsZero.selector);
        new RewardDistributorConvertible(address(kernel), 0, address(teller));
    }

    function test_constructor_rejectsEpochNotEndOfDay() external {
        uint256 notEndOfDay = startTimestamp; // Midnight is not end-of-day (23:59:59)
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidEpochTimestamp.selector);
        new RewardDistributorConvertible(address(kernel), notEndOfDay, address(teller));
    }
}

contract RewardDistributorConvertibleEndEpochTests is RewardDistributorConvertibleTestBase {
    function test_endEpoch_deploysConvertibleTokenAndSetsMerkleRoot() external {
        uint40 epochEndDate = _firstEpochEndDate();
        bytes32 merkleRoot = bytes32(uint256(1));
        bytes memory params = _encodeParams(
            address(usds),
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );

        vm.prank(admin);
        // Use checkTopic2=false because token address is not known before deploy
        vm.expectEmit(true, false, false, true);
        emit IRewardDistributor.EpochEnded(
            epochEndDate,
            address(0), // Address not checked (checkTopic2=false)
            params
        );
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(epochEndDate, merkleRoot, params)
        );

        // Verify state
        assertFalse(address(token) == address(0), "Token should be deployed");
        assertEq(
            distributor.epochMerkleRoots(epochEndDate),
            merkleRoot,
            "Merkle root should be set"
        );
        assertEq(
            address(distributor.epochConvertibleTokens(epochEndDate)),
            address(token),
            "Token should be stored for epoch"
        );
        assertEq(
            distributor.lastEpochEndDate(),
            epochEndDate,
            "lastEpochEndDate should be updated"
        );

        // Verify token parameters
        assertEq(address(token.quote()), address(usds), "Quote token should match");
        assertEq(token.strike(), STRIKE_PRICE, "Strike price should match");
    }

    function test_endEpoch_zeroRewardsMerkleRootSucceeds() external {
        uint40 epochEndDate = _firstEpochEndDate();
        bytes32 leaf = _generateLeaf(user0, epochEndDate, 0);

        vm.prank(admin);
        distributor.endEpoch(
            epochEndDate,
            leaf,
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        assertEq(distributor.epochMerkleRoots(epochEndDate), leaf, "Root should be set");
        assertEq(
            distributor.lastEpochEndDate(),
            epochEndDate,
            "lastEpochEndDate should be updated"
        );
    }

    function testFuzz_endEpoch_anyValidEpoch(uint8 n) external {
        n = uint8(bound(n, 1, 100));

        uint40 epochEndDate = startTimestamp + uint40(n) * 1 days - 1;
        bytes32 merkleRoot = bytes32(uint256(n));

        vm.prank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                merkleRoot,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        assertEq(
            distributor.epochMerkleRoots(epochEndDate),
            merkleRoot,
            "Merkle root should be set"
        );
        assertEq(distributor.lastEpochEndDate(), epochEndDate, "lastEpochEndDate should match");
        assertFalse(address(token) == address(0), "Token should be deployed");
    }

    function test_endEpoch_multipleEpochsSequential_skipOnCoverage() external {
        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 1 days;
        uint40 epoch3EndDate = epoch2EndDate + 1 days;

        bytes32 root1 = bytes32(uint256(1));
        bytes32 root2 = bytes32(uint256(2));
        bytes32 root3 = bytes32(uint256(3));

        vm.startPrank(admin);

        // End epoch 1
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                root1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );
        assertEq(distributor.epochMerkleRoots(epoch1EndDate), root1, "Root1 should be set");
        assertEq(
            distributor.lastEpochEndDate(),
            epoch1EndDate,
            "lastEpochEndDate should be epoch1"
        );

        // End epoch 2
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                root2,
                _encodeParams(
                    address(usds),
                    eligibleTimestamp,
                    expiryTimestamp,
                    STRIKE_PRICE + 1e18
                )
            )
        );
        assertEq(distributor.epochMerkleRoots(epoch2EndDate), root2, "Root2 should be set");
        assertEq(
            distributor.lastEpochEndDate(),
            epoch2EndDate,
            "lastEpochEndDate should be epoch2"
        );

        // End epoch 3
        ConvertibleOHMToken token3 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch3EndDate,
                root3,
                _encodeParams(
                    address(usds),
                    eligibleTimestamp,
                    expiryTimestamp,
                    STRIKE_PRICE + 2e18
                )
            )
        );
        assertEq(distributor.epochMerkleRoots(epoch3EndDate), root3, "Root3 should be set");
        assertEq(
            distributor.lastEpochEndDate(),
            epoch3EndDate,
            "lastEpochEndDate should be epoch3"
        );

        vm.stopPrank();

        // Verify all tokens are different due to different strike prices
        assertTrue(address(token1) != address(token2), "Token1 should differ from token2");
        assertTrue(address(token2) != address(token3), "Token2 should differ from token3");
    }

    function test_endEpoch_differentTokensPerEpoch_skipOnCoverage() external {
        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 1 days;

        bytes32 root1 = _generateLeaf(user0, epoch1EndDate, 100e9);
        bytes32 root2 = _generateLeaf(user0, epoch2EndDate, 200e9);

        // End epochs with different strike prices
        vm.startPrank(admin);
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                root1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                root2,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2)
            )
        );
        vm.stopPrank();

        // Verify
        assertTrue(
            address(token1) != address(token2),
            "Should create different tokens with different params"
        );
        assertEq(address(distributor.epochConvertibleTokens(epoch1EndDate)), address(token1));
        assertEq(address(distributor.epochConvertibleTokens(epoch2EndDate)), address(token2));
    }

    function testFuzz_endEpoch_revertsIfUnauthorized(address caller) external {
        vm.assume(caller != admin);

        uint40 epochEndDate = _firstEpochEndDate();

        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                distributor.ROLE_REWARDS_MANAGER()
            )
        );
        vm.prank(caller);
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    function testFuzz_endEpoch_revertsIfTooEarly(uint40 secondEpochEndDate) external {
        uint40 firstEpochEndDate = _firstEpochEndDate();

        secondEpochEndDate = uint40(
            bound(secondEpochEndDate, 1, uint40(firstEpochEndDate + 1 days - 1 seconds))
        );
        // Align to end of day (23:59:59 UTC)
        secondEpochEndDate = uint40((secondEpochEndDate / 1 days) * 1 days + 1 days - 1);
        vm.assume(secondEpochEndDate != firstEpochEndDate);

        vm.startPrank(admin);
        distributor.endEpoch(
            firstEpochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        vm.expectRevert(IRewardDistributor.RewardDistributor_EpochTooEarly.selector);
        distributor.endEpoch(
            secondEpochEndDate,
            bytes32(uint256(2)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        vm.stopPrank();
    }

    function test_endEpoch_revertsIfNotEndOfDay() external {
        uint40 epochEndDate = startTimestamp + 12 hours; // Not at end of day

        vm.prank(admin);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidEpochTimestamp.selector);
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    function test_endEpoch_revertsIfAlreadySet() external {
        uint40 epochEndDate = _firstEpochEndDate();

        vm.startPrank(admin);
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_EpochAlreadySet.selector,
                epochEndDate
            )
        );
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(2)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        vm.stopPrank();
    }

    function test_endEpoch_revertsIfEpochBeforeFirstValidEpoch() external {
        uint40 epochEndDate = startTimestamp - 1; // 23:59:59 UTC of day before

        vm.prank(admin);
        vm.expectRevert(IRewardDistributor.RewardDistributor_EpochTooEarly.selector);
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    function test_endEpoch_revertsIfExpiryBeforeEpochEnd() external {
        uint40 epochEndDate = _firstEpochEndDate();
        // Set expiry to same day as epoch end (should fail validation)
        uint48 invalidExpiry = uint48(epochEndDate);

        vm.prank(admin);
        vm.expectRevert(IRewardDistributorConvertible.RewardDistributor_InvalidToken.selector);
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, invalidExpiry, STRIKE_PRICE)
        );
    }

    function test_endEpoch_revertsIfParamsTooShort() external {
        uint40 epochEndDate = _firstEpochEndDate();

        // 96 bytes instead of 128 (missing strikePrice)
        bytes memory shortParams = abi.encode(address(usds), eligibleTimestamp, expiryTimestamp);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributorConvertible.RewardDistributor_InvalidParamsLength.selector,
                128,
                shortParams.length
            )
        );
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)), shortParams);
    }

    function test_endEpoch_revertsIfParamsTooLong() external {
        uint40 epochEndDate = _firstEpochEndDate();

        // 160 bytes instead of 128 (extra uint256)
        bytes memory longParams = abi.encode(
            address(usds),
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE,
            uint256(42)
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributorConvertible.RewardDistributor_InvalidParamsLength.selector,
                128,
                longParams.length
            )
        );
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)), longParams);
    }

    function test_endEpoch_revertsIfParamsEmpty() external {
        uint40 epochEndDate = _firstEpochEndDate();

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributorConvertible.RewardDistributor_InvalidParamsLength.selector,
                128,
                0
            )
        );
        distributor.endEpoch(epochEndDate, bytes32(uint256(1)), "");
    }

    function test_endEpoch_revertsIfZeroMerkleRoot() external {
        uint40 epochEndDate = _firstEpochEndDate();

        vm.prank(admin);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidMerkleRoot.selector);
        distributor.endEpoch(
            epochEndDate,
            bytes32(0),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    function test_endEpoch_revertsIfTellerReturnsZeroAddress() external {
        // Deploy a separate distributor backed by a mock teller that returns address(0)
        MockConvertibleOHMTellerZeroDeploy mockTeller = new MockConvertibleOHMTellerZeroDeploy();
        RewardDistributorConvertible mockDistributor = new RewardDistributorConvertible(
            address(kernel),
            startTimestamp - 1,
            address(mockTeller)
        );
        kernel.executeAction(Actions.ActivatePolicy, address(mockDistributor));
        // admin already has ROLE_REWARDS_MANAGER from setUp
        mockDistributor.enable("");

        uint40 epochEndDate = _firstEpochEndDate();
        bytes memory params = _encodeParams(
            address(usds),
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );

        vm.prank(admin);
        vm.expectRevert(IRewardDistributorConvertible.RewardDistributor_InvalidToken.selector);
        mockDistributor.endEpoch(epochEndDate, bytes32(uint256(1)), params);
    }

    function test_endEpoch_revertsIfDisabled() external {
        // Disable the distributor
        distributor.disable("");

        uint40 epochEndDate = _firstEpochEndDate();

        vm.prank(admin);
        vm.expectRevert();
        distributor.endEpoch(
            epochEndDate,
            bytes32(uint256(1)),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }
}

contract RewardDistributorConvertibleClaimTests is RewardDistributorConvertibleTestBase {
    uint40 epochEndDate;
    ConvertibleOHMToken token;

    function setUp() public override {
        super.setUp();

        epochEndDate = _firstEpochEndDate();
    }

    // Helper to setup an epoch with a single user's reward leaf
    function _setupEpochWithLeaf(
        address user,
        uint256 amount
    ) internal returns (ConvertibleOHMToken) {
        bytes32 leaf = _generateLeaf(user, epochEndDate, amount);

        vm.prank(admin);
        return
            ConvertibleOHMToken(
                distributor.endEpoch(
                    epochEndDate,
                    leaf,
                    _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
                )
            );
    }

    function test_claim_mintsConvertibleTokens() external {
        // 1. Preparation: setup epoch with User0's reward
        uint256 amount = 100e9; // 100 OHM worth
        token = _setupEpochWithLeaf(user0, amount);

        // 2. Test: prepare claim data and claim
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectEmit(true, true, true, true);
        emit IRewardDistributorConvertible.ConvertibleTokensClaimed(
            user0,
            address(token),
            amount,
            epochEndDate
        );
        (address[] memory tokens, uint256[] memory mintedAmounts) = distributor.claim(
            epochEndDates,
            amounts,
            proofs
        );

        // Verify
        assertEq(tokens.length, 1, "Should return one token");
        assertEq(address(tokens[0]), address(token), "Token should match");
        assertEq(mintedAmounts[0], amount, "Minted amount should match");
        assertEq(token.balanceOf(user0), amount, "User0 should have tokens");
        assertTrue(
            distributor.hasClaimed(user0, epochEndDate),
            "User0 should be marked as claimed"
        );
    }

    function test_claim_twoEpochs() external {
        // 1. Preparation: setup two epochs with different strike prices
        uint256 amount1 = 100e9;
        uint256 amount2 = 200e9;

        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 7 days;

        bytes32 leaf1 = _generateLeaf(user0, epoch1EndDate, amount1);
        vm.prank(admin);
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                leaf1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        bytes32 leaf2 = _generateLeaf(user0, epoch2EndDate, amount2);
        vm.prank(admin);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                leaf2,
                _encodeParams(
                    address(usds),
                    eligibleTimestamp,
                    expiryTimestamp,
                    STRIKE_PRICE + 5e18
                ) // Different strike = different token
            )
        );

        // 2. Test: claim both epochs
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epoch1EndDate;
        epochEndDates[1] = epoch2EndDate;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        vm.prank(user0);
        (address[] memory tokens, uint256[] memory mintedAmounts) = distributor.claim(
            epochEndDates,
            amounts,
            proofs
        );

        // Verify
        assertEq(tokens.length, 2, "Should return two tokens");
        assertEq(address(tokens[0]), address(token1), "First token should match");
        assertEq(address(tokens[1]), address(token2), "Second token should match");
        assertEq(mintedAmounts[0], amount1, "First minted amount should match");
        assertEq(mintedAmounts[1], amount2, "Second minted amount should match");
        assertEq(token1.balanceOf(user0), amount1, "User0 should have token1");
        assertEq(token2.balanceOf(user0), amount2, "User0 should have token2");
        assertTrue(distributor.hasClaimed(user0, epoch1EndDate), "User0 claimed epoch1");
        assertTrue(distributor.hasClaimed(user0, epoch2EndDate), "User0 claimed epoch2");
    }

    function test_claim_skipsMintIfZeroAmount() external {
        // 1. Preparation: setup two epochs - one with zero amount, one with non-zero
        uint256 zeroAmount = 0;
        uint256 normalAmount = 100e9;

        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 7 days;

        bytes32 leaf1 = _generateLeaf(user0, epoch1EndDate, zeroAmount);
        vm.prank(admin);
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                leaf1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        bytes32 leaf2 = _generateLeaf(user0, epoch2EndDate, normalAmount);
        vm.prank(admin);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                leaf2,
                _encodeParams(
                    address(usds),
                    eligibleTimestamp,
                    expiryTimestamp,
                    STRIKE_PRICE + 1e18
                ) // Different strike price to create a different token
            )
        );

        // 2. Test: claim both epochs in one call
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epoch1EndDate;
        epochEndDates[1] = epoch2EndDate;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = zeroAmount;
        amounts[1] = normalAmount;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        vm.prank(user0);
        (address[] memory tokens, uint256[] memory mintedAmounts) = distributor.claim(
            epochEndDates,
            amounts,
            proofs
        );

        // Verify
        assertEq(tokens.length, 2, "Should return two tokens");
        assertEq(address(tokens[0]), address(token1), "First token should match");
        assertEq(address(tokens[1]), address(token2), "Second token should match");
        assertEq(mintedAmounts[0], 0, "First minted amount should be zero");
        assertEq(mintedAmounts[1], normalAmount, "Second minted amount should match");
        assertEq(token1.balanceOf(user0), 0, "User0 should have no tokens from epoch 1");
        assertEq(token2.balanceOf(user0), normalAmount, "User0 should have tokens from epoch 2");
        assertTrue(
            distributor.hasClaimed(user0, epoch1EndDate),
            "User0 should be marked as claimed for epoch 1"
        );
        assertTrue(
            distributor.hasClaimed(user0, epoch2EndDate),
            "User0 should be marked as claimed for epoch 2"
        );
    }

    function test_claim_withMerkleProof_skipOnCoverage() external {
        uint256 user0Amount = 100e9;
        uint256 user1Amount = 200e9;

        bytes32 user0Leaf = _generateLeaf(user0, epochEndDate, user0Amount);
        bytes32 user1Leaf = _generateLeaf(user1, epochEndDate, user1Amount);
        bytes32 merkleRoot = _generateRoot(user0Leaf, user1Leaf);

        vm.prank(admin);
        token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                merkleRoot,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // User0 claims with User1's leaf as proof
        {
            uint256[] memory epochEndDates = new uint256[](1);
            epochEndDates[0] = epochEndDate;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = user0Amount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = _generateProof(user1Leaf);

            vm.prank(user0);
            distributor.claim(epochEndDates, amounts, proofs);
        }

        // User1 claims with User0's leaf as proof
        {
            uint256[] memory epochEndDates = new uint256[](1);
            epochEndDates[0] = epochEndDate;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = user1Amount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = _generateProof(user0Leaf);

            vm.prank(user1);
            distributor.claim(epochEndDates, amounts, proofs);
        }

        // Verify results.
        assertEq(token.balanceOf(user0), user0Amount, "User0 should have tokens");
        assertEq(token.balanceOf(user1), user1Amount, "User1 should have tokens");
    }

    function test_claim_differentTokensPerEpoch_skipOnCoverage() external {
        // 1. Preparation: set up epochs with different token parameters
        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 1 days;

        uint256 amount1 = 100e9;
        uint256 amount2 = 150e9;

        bytes32 root1 = _generateLeaf(user0, epoch1EndDate, amount1);
        bytes32 root2 = _generateLeaf(user0, epoch2EndDate, amount2);

        vm.startPrank(admin);
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                root1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                root2,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2) // Different strike
            )
        );
        vm.stopPrank();

        // 2. Test
        // Prepare claim data
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epoch1EndDate;
        epochEndDates[1] = epoch2EndDate;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        // Claim both epochs
        vm.prank(user0);
        (address[] memory tokens, ) = distributor.claim(epochEndDates, amounts, proofs);

        // Verify
        assertEq(address(tokens[0]), address(token1), "First token should match");
        assertEq(address(tokens[1]), address(token2), "Second token should match");
        assertEq(token1.balanceOf(user0), amount1, "User0 should have token1");
        assertEq(token2.balanceOf(user0), amount2, "User0 should have token2");
    }

    function testFuzz_claim_variousAmounts_skipOnCoverage(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000_000e9);

        // Setup epoch with fuzzed amount
        bytes32 leaf = _generateLeaf(user0, epochEndDate, amount);
        vm.prank(admin);
        token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                leaf,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // Claim
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        (address[] memory tokens, uint256[] memory mintedAmounts) = distributor.claim(
            epochEndDates,
            amounts,
            proofs
        );

        // Verify
        assertEq(tokens.length, 1, "Should return one token");
        assertEq(address(tokens[0]), address(token), "Token should match");
        assertEq(mintedAmounts[0], amount, "Minted amount should match");
        assertEq(token.balanceOf(user0), amount, "User0 should have tokens");
        assertTrue(distributor.hasClaimed(user0, epochEndDate), "User0 should be marked claimed");
    }

    function testFuzz_claim_multipleEpochs_skipOnCoverage(
        uint256 amount1,
        uint256 amount2
    ) external {
        amount1 = bound(amount1, 1, 1_000_000_000e9);
        amount2 = bound(amount2, 1, 1_000_000_000e9);

        uint40 epoch1EndDate = epochEndDate;
        uint40 epoch2EndDate = epoch1EndDate + 7 days;

        // Setup epochs with different strike prices to get different tokens
        bytes32 leaf1 = _generateLeaf(user0, epoch1EndDate, amount1);
        vm.prank(admin);
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                leaf1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        bytes32 leaf2 = _generateLeaf(user0, epoch2EndDate, amount2);
        vm.prank(admin);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                leaf2,
                _encodeParams(
                    address(usds),
                    eligibleTimestamp,
                    expiryTimestamp,
                    STRIKE_PRICE + 1e18
                ) // Different strike = different token
            )
        );

        // Claim both epochs
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epoch1EndDate;
        epochEndDates[1] = epoch2EndDate;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        vm.prank(user0);
        (address[] memory tokens, uint256[] memory mintedAmounts) = distributor.claim(
            epochEndDates,
            amounts,
            proofs
        );

        // Verify
        assertEq(tokens.length, 2, "Should return two tokens");
        assertEq(address(tokens[0]), address(token1), "First token should match");
        assertEq(address(tokens[1]), address(token2), "Second token should match");
        assertEq(mintedAmounts[0], amount1, "First minted amount should match");
        assertEq(mintedAmounts[1], amount2, "Second minted amount should match");
        assertEq(token1.balanceOf(user0), amount1, "User0 should have token1");
        assertEq(token2.balanceOf(user0), amount2, "User0 should have token2");
        assertTrue(distributor.hasClaimed(user0, epoch1EndDate), "User0 claimed epoch1");
        assertTrue(distributor.hasClaimed(user0, epoch2EndDate), "User0 claimed epoch2");
    }

    function test_claim_revertsIfDisabled() external {
        // 1. Preparation: setup epoch while enabled, then disable
        uint256 amount = 100e9;
        bytes32 leaf = _generateLeaf(user0, epochEndDate, amount);
        vm.prank(admin);
        distributor.endEpoch(
            epochEndDate,
            leaf,
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        distributor.disable("");

        // 2. Test: try to claim
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert();
        distributor.claim(epochEndDates, amounts, proofs);
    }

    function test_claim_revertsIfNoEpochsSpecified() external {
        // 1. Preparation: setup epoch
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        // 2. Test: try to claim with empty epoch array
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert(IRewardDistributor.RewardDistributor_NoEpochsSpecified.selector);
        distributor.claim(new uint256[](0), amounts, proofs);
    }

    function test_claim_revertsIfAmountArrayLengthMismatch() external {
        // 1. Preparation: setup epoch
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        // 2. Test: try to claim with mismatched array lengths
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert(IRewardDistributor.RewardDistributor_ArrayLengthMismatch.selector);
        distributor.claim(epochEndDates, new uint256[](0), proofs);
    }

    function test_claim_revertsIfProofArrayLengthMismatch() external {
        // 1. Preparation: setup epoch
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        // 2. Test: try to claim with mismatched array lengths
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(user0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_ArrayLengthMismatch.selector,
                epochEndDate
            )
        );
        distributor.claim(epochEndDates, amounts, new bytes32[][](0));
    }

    function test_claim_revertsIfAlreadyClaimed() external {
        // 1. Preparation: setup epoch and claim once
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.startPrank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        // 2. Test: second claim should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_AlreadyClaimed.selector,
                epochEndDate
            )
        );
        distributor.claim(epochEndDates, amounts, proofs);
        vm.stopPrank();
    }

    function test_claim_revertsIfAlreadyClaimedInBatch_skipOnCoverage() external {
        // 1. Preparation: setup three epochs
        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 7 days;
        uint40 epoch3EndDate = epoch2EndDate + 7 days;

        vm.startPrank(admin);
        distributor.endEpoch(
            epoch1EndDate,
            _generateLeaf(user0, epoch1EndDate, 100e9),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        distributor.endEpoch(
            epoch2EndDate,
            _generateLeaf(user0, epoch2EndDate, 200e9),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        distributor.endEpoch(
            epoch3EndDate,
            _generateLeaf(user0, epoch3EndDate, 300e9),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        vm.stopPrank();

        // Claim epoch 2 first
        {
            uint256[] memory epochEndDates1 = new uint256[](1);
            epochEndDates1[0] = epoch2EndDate;
            uint256[] memory amounts1 = new uint256[](1);
            amounts1[0] = 200e9;
            bytes32[][] memory proofs1 = new bytes32[][](1);
            proofs1[0] = new bytes32[](0);

            vm.prank(user0);
            distributor.claim(epochEndDates1, amounts1, proofs1);
        }

        // 2. Test: try to claim all three - should revert on epoch 2
        {
            uint256[] memory epochEndDates = new uint256[](3);
            epochEndDates[0] = epoch1EndDate;
            epochEndDates[1] = epoch2EndDate; // Already claimed
            epochEndDates[2] = epoch3EndDate;
            uint256[] memory amounts = new uint256[](3);
            amounts[0] = 100e9;
            amounts[1] = 200e9;
            amounts[2] = 300e9;
            bytes32[][] memory proofs = new bytes32[][](3);
            proofs[0] = new bytes32[](0);
            proofs[1] = new bytes32[](0);
            proofs[2] = new bytes32[](0);

            vm.prank(user0);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRewardDistributor.RewardDistributor_AlreadyClaimed.selector,
                    epoch2EndDate
                )
            );
            distributor.claim(epochEndDates, amounts, proofs);
        }
    }

    function test_claim_revertsIfDuplicateEpochInSameCall() external {
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        // Prepare claim data with duplicate epoch
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epochEndDate;
        epochEndDates[1] = epochEndDate; // Duplicate
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardDistributor.RewardDistributor_AlreadyClaimed.selector,
                epochEndDate
            )
        );
        distributor.claim(epochEndDates, amounts, proofs);

        // Verify nothing was claimed
        assertEq(token.balanceOf(user0), 0, "User0 should have no tokens");
        assertFalse(
            distributor.hasClaimed(user0, epochEndDate),
            "User0 should not be marked claimed"
        );
    }

    function test_claim_revertsIfInvalidProof() external {
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount + 1; // Wrong amount
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidProof.selector);
        distributor.claim(epochEndDates, amounts, proofs);
    }

    function test_claim_revertsIfUsingAnotherUsersProof() external {
        uint256 amount = 100e9;
        token = _setupEpochWithLeaf(user0, amount);

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // User1 tries to claim using User0's proof
        vm.prank(user1);
        vm.expectRevert(IRewardDistributor.RewardDistributor_InvalidProof.selector);
        distributor.claim(epochEndDates, amounts, proofs);

        // Verify User1 received nothing
        assertEq(token.balanceOf(user1), 0, "User1 should have no tokens");
        assertFalse(
            distributor.hasClaimed(user1, epochEndDate),
            "User1 should not be marked claimed"
        );

        // Verify User0 can still claim
        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);
        assertEq(token.balanceOf(user0), amount, "User0 should have tokens");
    }

    function test_claim_revertsIfZeroRewards() external {
        uint256 amount = 0; // Zero rewards
        token = _setupEpochWithLeaf(user0, amount);

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert(IRewardDistributor.RewardDistributor_NothingToClaim.selector);
        distributor.claim(epochEndDates, amounts, proofs);
    }

    function test_claim_revertsIfInvalidTokenWhenEpochNotSetup() external {
        // Don't setup epoch - no convertible token deployed
        // In RewardDistributorConvertible, the InvalidToken check happens before RewardDistributor_MerkleRootNotSet
        // because it first looks up epochConvertibleTokens[epochEndDate]

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e9;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        vm.expectRevert(IRewardDistributorConvertible.RewardDistributor_InvalidToken.selector);
        distributor.claim(epochEndDates, amounts, proofs);
    }
}

contract RewardDistributorConvertiblePreviewClaimTests is RewardDistributorConvertibleTestBase {
    function test_previewClaim_returnsCorrectValues() external {
        uint256 amount = 100e9;
        uint40 epochEndDate = _firstEpochEndDate();

        bytes32 leaf = _generateLeaf(user0, epochEndDate, amount);
        vm.prank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                leaf,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // Preview before claiming
        (address[] memory tokens, uint256[] memory claimableAmounts) = distributor.previewClaim(
            user0,
            epochEndDates,
            amounts,
            proofs
        );

        assertEq(tokens.length, 1, "Should return one token");
        assertEq(address(tokens[0]), address(token), "Token should match");
        assertEq(claimableAmounts[0], amount, "Claimable amount should match");
    }

    function test_previewClaim_returnsZeroAfterClaiming() external {
        uint256 amount = 100e9;
        uint40 epochEndDate = _firstEpochEndDate();

        bytes32 leaf = _generateLeaf(user0, epochEndDate, amount);
        vm.prank(admin);
        distributor.endEpoch(
            epochEndDate,
            leaf,
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        // Claim first
        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        // Preview after claiming
        (address[] memory tokens, uint256[] memory claimableAmounts) = distributor.previewClaim(
            user0,
            epochEndDates,
            amounts,
            proofs
        );

        assertEq(claimableAmounts[0], 0, "Claimable amount should be 0 after claiming");
        // Token is still returned but amount is 0
        assertFalse(address(tokens[0]) == address(0), "Token address should still be returned");
    }

    function test_previewClaim_returnsZeroForInvalidProof() external {
        uint256 amount = 100e9;
        uint40 epochEndDate = _firstEpochEndDate();

        bytes32 leaf = _generateLeaf(user0, epochEndDate, amount);
        vm.prank(admin);
        distributor.endEpoch(
            epochEndDate,
            leaf,
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount + 1; // Wrong amount
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        (, uint256[] memory claimableAmounts) = distributor.previewClaim(
            user0,
            epochEndDates,
            amounts,
            proofs
        );

        assertEq(claimableAmounts[0], 0, "Claimable amount should be 0 for invalid proof");
    }

    function test_previewClaim_returnsZeroForMerkleRootNotSet() external view {
        uint40 epochEndDate = _firstEpochEndDate();

        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e9;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        (address[] memory tokens, uint256[] memory claimableAmounts) = distributor.previewClaim(
            user0,
            epochEndDates,
            amounts,
            proofs
        );

        assertEq(claimableAmounts[0], 0, "Claimable amount should be 0 when root not set");
        assertEq(address(tokens[0]), address(0), "Token should be zero address when not set");
    }

    function test_previewClaim_returnsEmptyArraysForInvalidInput() external view {
        uint256[] memory epochEndDates = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        bytes32[][] memory proofs = new bytes32[][](0);

        (address[] memory tokens, uint256[] memory claimableAmounts) = distributor.previewClaim(
            user0,
            epochEndDates,
            amounts,
            proofs
        );

        assertEq(tokens.length, 0, "Should return empty tokens array");
        assertEq(claimableAmounts.length, 0, "Should return empty amounts array");
    }
}

contract RewardDistributorConvertibleIntegrationTests is RewardDistributorConvertibleTestBase {
    function test_claimAndExercise_skipOnCoverage() external {
        uint256 amount = 100e9;
        uint40 epochEndDate = _firstEpochEndDate();

        // Setup epoch
        bytes32 leaf = _generateLeaf(user0, epochEndDate, amount);
        vm.prank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                leaf,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // Claim
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        assertEq(token.balanceOf(user0), amount, "User0 should have convertible tokens");

        // Warp to eligible time
        vm.warp(eligibleTimestamp);

        // Exercise
        uint256 exerciseCost = _calcExpectedCost(amount);
        vm.startPrank(user0);
        token.approve(address(teller), amount);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), amount);
        vm.stopPrank();

        // Verify
        assertEq(ohm.balanceOf(user0), amount, "User0 should receive OHM");
        assertEq(token.balanceOf(user0), 0, "Convertible tokens should be burned");
    }

    function test_multipleEpochsClaimAndExercise_skipOnCoverage() external {
        uint256 amount1 = 100e9;
        uint256 amount2 = 200e9;

        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 7 days;

        // Setup epoch 1
        bytes32 leaf1 = _generateLeaf(user0, epoch1EndDate, amount1);
        vm.prank(admin);
        ConvertibleOHMToken token1 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                leaf1,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // Setup epoch 2 (same token params = same token)
        bytes32 leaf2 = _generateLeaf(user0, epoch2EndDate, amount2);
        vm.prank(admin);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch2EndDate,
                leaf2,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // Both epochs use the same token params, so they return the same token
        assertEq(address(token1), address(token2), "Same params should return same token");

        // Claim both epochs
        uint256[] memory epochEndDates = new uint256[](2);
        epochEndDates[0] = epoch1EndDate;
        epochEndDates[1] = epoch2EndDate;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);

        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        uint256 totalAmount = amount1 + amount2;
        assertEq(
            token1.balanceOf(user0),
            totalAmount,
            "User0 should have total convertible tokens"
        );

        // Warp to eligible time
        vm.warp(eligibleTimestamp);

        // Exercise all
        uint256 exerciseCost = _calcExpectedCost(totalAmount);
        vm.startPrank(user0);
        token1.approve(address(teller), totalAmount);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token1), totalAmount);
        vm.stopPrank();

        // Verify
        assertEq(ohm.balanceOf(user0), totalAmount, "User0 should receive total OHM");
        assertEq(token1.balanceOf(user0), 0, "All convertible tokens should be burned");
    }

    function test_twoUsersClaimSameEpoch_skipOnCoverage() external {
        uint256 user0Amount = 100e9;
        uint256 user1Amount = 200e9;
        uint40 epochEndDate = _firstEpochEndDate();

        // Create a merkle tree with both users
        bytes32 user0Leaf = _generateLeaf(user0, epochEndDate, user0Amount);
        bytes32 user1Leaf = _generateLeaf(user1, epochEndDate, user1Amount);

        // Sort leaves for merkle tree (smaller first)
        bytes32 root;
        bytes32 leftLeaf;
        bytes32 rightLeaf;
        if (uint256(user0Leaf) < uint256(user1Leaf)) {
            leftLeaf = user0Leaf;
            rightLeaf = user1Leaf;
        } else {
            leftLeaf = user1Leaf;
            rightLeaf = user0Leaf;
        }
        root = keccak256(abi.encodePacked(leftLeaf, rightLeaf));

        vm.prank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                root,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // User0 claims
        {
            uint256[] memory epochEndDates = new uint256[](1);
            epochEndDates[0] = epochEndDate;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = user0Amount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](1);
            proofs[0][0] = user1Leaf;

            vm.prank(user0);
            distributor.claim(epochEndDates, amounts, proofs);
        }

        // User1 claims
        {
            uint256[] memory epochEndDates = new uint256[](1);
            epochEndDates[0] = epochEndDate;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = user1Amount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](1);
            proofs[0][0] = user0Leaf;

            vm.prank(user1);
            distributor.claim(epochEndDates, amounts, proofs);
        }

        // Verify
        assertEq(token.balanceOf(user0), user0Amount, "User0 should have her tokens");
        assertEq(token.balanceOf(user1), user1Amount, "User1 should have his tokens");
        assertTrue(distributor.hasClaimed(user0, epochEndDate), "User0 should be marked claimed");
        assertTrue(distributor.hasClaimed(user1, epochEndDate), "User1 should be marked claimed");
    }

    function test_multipleUsersClaimAndExercise_skipOnCoverage() external {
        // 1. Preparation: set up epoch with two users
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 user0Amount = 100e9;
        uint256 user1Amount = 200e9;
        // Generate merkle tree
        bytes32 user0Leaf = _generateLeaf(user0, epochEndDate, user0Amount);
        bytes32 user1Leaf = _generateLeaf(user1, epochEndDate, user1Amount);
        bytes32 merkleRoot = _generateRoot(user0Leaf, user1Leaf);

        // End epoch
        vm.prank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                merkleRoot,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // User0 claims
        {
            uint256[] memory epochEndDates = new uint256[](1);
            epochEndDates[0] = epochEndDate;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = user0Amount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = _generateProof(user1Leaf);

            vm.prank(user0);
            distributor.claim(epochEndDates, amounts, proofs);
        }

        // User1 claims
        {
            uint256[] memory epochEndDates = new uint256[](1);
            epochEndDates[0] = epochEndDate;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = user1Amount;
            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = _generateProof(user0Leaf);

            vm.prank(user1);
            distributor.claim(epochEndDates, amounts, proofs);
        }

        // Both users exercise after eligible
        vm.warp(eligibleTimestamp);

        uint256 user0Cost = _calcExpectedCost(user0Amount);
        vm.startPrank(user0);
        token.approve(address(teller), user0Amount);
        usds.approve(address(teller), user0Cost);
        teller.exercise(address(token), user0Amount);
        vm.stopPrank();

        uint256 user1Cost = _calcExpectedCost(user1Amount);
        vm.startPrank(user1);
        token.approve(address(teller), user1Amount);
        usds.approve(address(teller), user1Cost);
        teller.exercise(address(token), user1Amount);
        vm.stopPrank();

        // Verify final state
        assertEq(ohm.balanceOf(user0), user0Amount, "User0 should have OHM");
        assertEq(ohm.balanceOf(user1), user1Amount, "User1 should have OHM");
    }

    function test_claimAcrossMultipleEpochsThenExercise_skipOnCoverage() external {
        // Set up multiple epochs
        uint40 epoch1EndDate = _firstEpochEndDate();
        uint40 epoch2EndDate = epoch1EndDate + 7 days; // Weekly epochs
        uint40 epoch3EndDate = epoch2EndDate + 7 days;

        uint256 amount1 = 100e9;
        uint256 amount2 = 150e9;
        uint256 amount3 = 200e9;

        // Set up merkle roots for each epoch (same token params = same token)
        vm.startPrank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epoch1EndDate,
                _generateLeaf(user0, epoch1EndDate, amount1),
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );
        distributor.endEpoch(
            epoch2EndDate,
            _generateLeaf(user0, epoch2EndDate, amount2),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        distributor.endEpoch(
            epoch3EndDate,
            _generateLeaf(user0, epoch3EndDate, amount3),
            _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
        vm.stopPrank();

        // Claim all epochs in one transaction
        uint256[] memory epochEndDates = new uint256[](3);
        epochEndDates[0] = epoch1EndDate;
        epochEndDates[1] = epoch2EndDate;
        epochEndDates[2] = epoch3EndDate;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;
        bytes32[][] memory proofs = new bytes32[][](3);
        proofs[0] = new bytes32[](0);
        proofs[1] = new bytes32[](0);
        proofs[2] = new bytes32[](0);

        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        uint256 totalTokens = amount1 + amount2 + amount3;
        assertEq(token.balanceOf(user0), totalTokens, "User0 should have all tokens");

        // Exercise all at once
        vm.warp(eligibleTimestamp);

        uint256 totalCost = _calcExpectedCost(totalTokens);
        vm.startPrank(user0);
        token.approve(address(teller), totalTokens);
        usds.approve(address(teller), totalCost);
        teller.exercise(address(token), totalTokens);
        vm.stopPrank();

        // Verify final state
        assertEq(ohm.balanceOf(user0), totalTokens, "User0 should receive all OHM");
    }

    function test_claimAndPartiallyExercise_skipOnCoverage() external {
        // Set up epoch and claim tokens
        uint40 epochEndDate = _firstEpochEndDate();
        uint256 claimAmount = 100e9;
        uint256 exerciseAmount = 40e9;

        bytes32 merkleRoot = _generateLeaf(user0, epochEndDate, claimAmount);
        vm.prank(admin);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            distributor.endEpoch(
                epochEndDate,
                merkleRoot,
                _encodeParams(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
            )
        );

        // Claim
        uint256[] memory epochEndDates = new uint256[](1);
        epochEndDates[0] = epochEndDate;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = claimAmount;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.prank(user0);
        distributor.claim(epochEndDates, amounts, proofs);

        // Exercise partially
        vm.warp(eligibleTimestamp);

        uint256 partialCost = _calcExpectedCost(exerciseAmount);
        vm.startPrank(user0);
        token.approve(address(teller), exerciseAmount);
        usds.approve(address(teller), partialCost);
        teller.exercise(address(token), exerciseAmount);
        vm.stopPrank();
        // Verify partial state
        assertEq(ohm.balanceOf(user0), exerciseAmount, "User0 should have partial OHM");
        assertEq(
            token.balanceOf(user0),
            claimAmount - exerciseAmount,
            "User0 should have remaining tokens"
        );

        // Exercise remaining
        uint256 remainingCost = _calcExpectedCost(claimAmount - exerciseAmount);
        vm.startPrank(user0);
        token.approve(address(teller), claimAmount - exerciseAmount);
        usds.approve(address(teller), remainingCost);
        teller.exercise(address(token), claimAmount - exerciseAmount);
        vm.stopPrank();

        // Verify final state
        assertEq(ohm.balanceOf(user0), claimAmount, "User0 should have all OHM");
        assertEq(token.balanceOf(user0), 0, "User0 should have no tokens");
    }
}
