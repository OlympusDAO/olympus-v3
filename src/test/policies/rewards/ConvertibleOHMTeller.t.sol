// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {Kernel, Actions, toKeycode, Keycode, Policy} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConvertibleOHMTeller} from "src/policies/rewards/convertible/ConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";
import {IConvertibleOHMTeller} from "src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {MaliciousConvertibleOHMToken} from "src/test/mocks/MaliciousConvertibleOHMToken.sol";

contract ConvertibleOHMTellerTestBase is Test {
    // Contracts
    Kernel kernel;
    OlympusTreasury trsry;
    OlympusMinter mintr;
    OlympusRoles roles;

    MockOhm ohm;
    MockERC20 usds;

    ConvertibleOHMTeller teller;

    // Constants
    uint256 internal constant _DEFAULT_MINT_CAP = 1000e9;

    // Test accounts
    address rewardDistributor = makeAddr("rewardDistributor"); // False contract
    address admin = makeAddr("admin");
    address user0 = makeAddr("user0");
    address user1 = makeAddr("user1");

    // Test parameters
    uint256 constant STRIKE_PRICE = 15e18; // 15 USDS per OHM
    uint48 eligibleTimestamp;
    uint48 expiryTimestamp;

    function setUp() public virtual {
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
        // Activate the policy
        kernel.executeAction(Actions.ActivatePolicy, address(teller));

        // Grant the permission to this test contract to call saveRole
        _grantModulePermission(toKeycode("ROLES"), ROLESv1.saveRole.selector);
        // Setup roles
        roles.saveRole(teller.ROLE_TELLER_ADMIN(), admin);
        roles.saveRole(ADMIN_ROLE, address(this));

        // Enable the teller policy with infinite minting cap
        teller.enable(abi.encode(type(uint256).max));

        // Grant the reward distributor role (required for the functions deploy and create)
        roles.saveRole(teller.ROLE_REWARD_DISTRIBUTOR(), rewardDistributor);

        // Fund users with USDS for exercise tests
        usds.mint(user0, 1_000_000e18);
        usds.mint(user1, 1_000_000e18);

        // Prepare test parameters
        uint48 startTimestamp = uint48(vm.getBlockTimestamp());
        // Set the eligible time to 3 months from now (rounded to the nearest day)
        eligibleTimestamp = _roundToDay(startTimestamp + 90 days);
        // Set the expiry time to 6 months from now (rounded to the nearest day)
        expiryTimestamp = _roundToDay(startTimestamp + 180 days);
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

    function _deployConvertibleToken() internal returns (ConvertibleOHMToken token) {
        vm.prank(rewardDistributor);
        token = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    // Deploys a malicious convertible token for testing
    function _deployMaliciousConvertibleToken(
        address creator_,
        uint48 eligible_,
        uint48 expiry_,
        address teller_
    ) internal returns (MaliciousConvertibleOHMToken) {
        return
            new MaliciousConvertibleOHMToken(
                address(usds),
                creator_,
                eligible_,
                expiry_,
                teller_,
                STRIKE_PRICE
            );
    }

    // Calculates the exact exercise cost using the teller
    function _exerciseCost(
        ConvertibleOHMToken token,
        uint256 amount
    ) internal view returns (uint256) {
        (, uint256 cost) = teller.exerciseCost(address(token), amount);
        return cost;
    }

    // Calculates token hash using default parameters (usds, STRIKE_PRICE)
    function _calcTokenHash(
        address creator_,
        uint48 eligible_,
        uint48 expiry_
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    address(usds),
                    creator_,
                    _roundToDay(eligible_),
                    _roundToDay(expiry_),
                    STRIKE_PRICE
                )
            );
    }

    // Calculates an expected USDS cost for convertible tokens based on the strike price
    function _calcExpectedCost(uint256 convertibleTokens) internal pure returns (uint256) {
        // cost = ceil(convertibleTokens * strikePrice / 10^ohm.decimals())
        // Example: cost = 100e9 * 15e18 / 1e9 = 1500e18 USDS
        return (convertibleTokens * STRIKE_PRICE + 1e9 - 1) / 1e9; // Round up
    }

    function _roundToDay(uint48 timestamp) internal pure returns (uint48) {
        return uint48(timestamp / 1 days) * 1 days;
    }
}

contract ConvertibleOHMTellerDeploymentTests is ConvertibleOHMTellerTestBase {
    function test_deploy_createsConvertibleTokenWithCorrectParams() external {
        // The deployment should emit the event
        vm.expectEmit(false, true, true, true);
        emit IConvertibleOHMTeller.ConvertibleTokenCreated(
            address(0), // The address is not yet known
            address(usds),
            rewardDistributor,
            _roundToDay(eligibleTimestamp),
            _roundToDay(expiryTimestamp),
            STRIKE_PRICE
        );
        // Deploy a new token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // Verify
        assertFalse(address(token) == address(0), "The convertible token should be deployed");

        assertEq(token.decimals(), ohm.decimals(), "Decimals should match OHM");
        assertEq(
            token.eligible(),
            _roundToDay(eligibleTimestamp),
            "The eligible timestamp should be rounded to the nearest day"
        );
        assertEq(
            token.expiry(),
            _roundToDay(expiryTimestamp),
            "The expiry timestamp should be rounded to the nearest day"
        );
        assertEq(token.strike(), STRIKE_PRICE, "The strike price should match");
        assertEq(token.teller(), address(teller), "The teller should match the teller contract");
        assertEq(token.quote(), address(usds), "The quote token should match");
        assertEq(
            token.creator(),
            rewardDistributor,
            "The creator should match the reward distributor"
        );
        assertEq(
            keccak256(bytes(token.name())),
            keccak256(abi.encodePacked(bytes32("OHM/USDS 15.00 19700630"))),
            "The name should match"
        );
        assertEq(
            keccak256(bytes(token.symbol())),
            keccak256(abi.encodePacked(bytes32("convOHM-19700630"))),
            "The symbol should match"
        );
        assertEq(
            teller.tokens(_calcTokenHash(rewardDistributor, eligibleTimestamp, expiryTimestamp)),
            address(token),
            "The token should be stored in the mapping"
        );
        assertEq(token.chainId(), block.chainid, "The chainId should match");
    }

    function test_deploy_createsTokenWithZeroEligibleUsingCurrentTimestamp() external {
        // Deploy a token with zero eligible time
        vm.prank(rewardDistributor);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.deploy(
                address(usds),
                0, // Should use the current timestamp rounded to the nearest day
                expiryTimestamp,
                STRIKE_PRICE
            )
        );

        // Verify
        assertEq(
            token.eligible(),
            _roundToDay(uint48(vm.getBlockTimestamp())),
            "The eligible should be the current timestamp rounded to the nearest day"
        );
    }

    function test_deploy_returnsSameTokenForSameParams() external {
        // Deploy a token with same parameters twice
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        ConvertibleOHMToken token2 = _deployConvertibleToken();

        // Verify
        assertEq(
            address(token1),
            address(token2),
            "Should return the same token for same parameters"
        );
    }

    function test_deploy_createsUniqueTokensForDifferentParams_skipOnCoverage() external {
        // Deploy convertible tokens with different params
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        vm.startPrank(rewardDistributor);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE + 1e18)
        );
        ConvertibleOHMToken token3 = ConvertibleOHMToken(
            teller.deploy(
                address(usds),
                eligibleTimestamp + 1 days,
                expiryTimestamp + 1 days,
                STRIKE_PRICE
            )
        );
        vm.stopPrank();

        // Verify
        assertTrue(
            address(token1) != address(token2),
            "Should create a different token for the different strike price"
        );
        assertTrue(
            address(token1) != address(token3),
            "Should create a different token for the different eligible time"
        );
    }

    function test_deploy_createsUniqueTokensForDifferentQuoteTokens_skipOnCoverage() external {
        // 1. Preparation: deploy another quote token
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        // 2. Test
        // Deploy tokens with different quote tokens
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        vm.prank(rewardDistributor);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            teller.deploy(address(usdc), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        // Verify
        assertTrue(
            address(token1) != address(token2),
            "Should create a different token for the different quote token"
        );
        assertEq(token1.quote(), address(usds), "The Token1's quote token should be USDS");
        assertEq(token2.quote(), address(usdc), "The Token2's quote token should be USDC");
    }

    function test_deploy_createsUniqueTokensForDifferentCreators_skipOnCoverage() external {
        // 1. Preparation: create second reward distributor
        address rewardDistributor2 = makeAddr("rewardDistributor2");
        roles.saveRole(teller.ROLE_REWARD_DISTRIBUTOR(), rewardDistributor2);

        // 2. Test: deploy tokens with same params but different creators
        ConvertibleOHMToken token1 = _deployConvertibleToken(); // deployed by rewardDistributor

        vm.prank(rewardDistributor2);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        // 3. Verify: tokens should be different
        assertTrue(
            address(token1) != address(token2),
            "Should create different tokens for different creators"
        );
        assertEq(token1.creator(), rewardDistributor, "Token1 creator should be rewardDistributor");
        assertEq(
            token2.creator(),
            rewardDistributor2,
            "Token2 creator should be rewardDistributor2"
        );

        // Verify hash includes creator
        bytes32 hash1 = teller.getTokenHash(
            address(usds),
            rewardDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );
        bytes32 hash2 = teller.getTokenHash(
            address(usds),
            rewardDistributor2,
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );
        assertTrue(hash1 != hash2, "Hashes should be different for different creators");
    }

    function testFuzz_deploy_existingTokenReturnedForSameRoundedTimestamps_skipOnCoverage(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) external {
        eligibleDiff_ = uint48(bound(eligibleDiff_, 0, uint48(1 days) - 1));
        expiryDiff_ = uint48(bound(expiryDiff_, 0, uint48(1 days) - 1));

        // 1. Preparation: deploy a token
        ConvertibleOHMToken token1 = _deployConvertibleToken();

        // 2. Test: deploy with different timestamps that round to the same day
        vm.prank(rewardDistributor);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            teller.deploy(
                address(usds),
                eligibleTimestamp + eligibleDiff_,
                expiryTimestamp + expiryDiff_,
                STRIKE_PRICE
            )
        );
        assertEq(
            address(token1),
            address(token2),
            "Same token should be returned for rounded timestamps"
        );
    }

    function test_deploy_revertsIfQuoteTokenIsZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(address(0))
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(0), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }

    function test_deploy_revertsIfQuoteTokenDecimalsTooLow() external {
        // Deploy a token with 1 decimal (below minimum of 2)
        MockERC20 lowDecToken = new MockERC20("LOW", "LOW", 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(address(lowDecToken))
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(lowDecToken), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }

    function test_deploy_revertsIfQuoteTokenIsNotContract() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(user0)
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(user0, eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }

    function test_deploy_revertsIfEligibleIsInThePast() external {
        // 1. Preparation: warp to a later time to make sure current day is different from past day
        vm.warp(vm.getBlockTimestamp() + 2 days);

        // 2. Test
        uint48 pastEligible = _roundToDay(uint48(vm.getBlockTimestamp())) - 1 days;
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(pastEligible)
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), pastEligible, expiryTimestamp + 2 days, STRIKE_PRICE);
    }

    function test_deploy_revertsIfExpiryLessThanEligible() external {
        uint48 expiry = eligibleTimestamp - 1 days;
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                2,
                abi.encodePacked(expiry)
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiry, STRIKE_PRICE);
    }

    function test_deploy_revertsIfExpiryEqualsEligible() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                2,
                abi.encodePacked(eligibleTimestamp)
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), eligibleTimestamp, eligibleTimestamp, STRIKE_PRICE);
    }

    function test_deploy_revertsIfDurationLessThanMinDuration() external {
        // 1. Preparation: set min duration to 5 days
        // vm.prank(address(this));
        teller.setMinDuration(uint48(5 days));

        // 2. Test
        uint48 shortExpiry = eligibleTimestamp + 3 days;
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                2,
                abi.encodePacked(shortExpiry)
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), eligibleTimestamp, shortExpiry, STRIKE_PRICE);
    }

    function test_deploy_revertsIfStrikePriceIsZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                3,
                abi.encodePacked(uint256(0))
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, 0);
    }

    function test_deploy_revertsIfStrikePriceOutOfBounds() external {
        // Strike price with price decimals < -9 (for 18 decimal quote token)
        uint256 tooLowStrike = 10 ** (usds.decimals() - 10);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                3,
                abi.encodePacked(tooLowStrike)
            )
        );
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, tooLowStrike);
    }

    function test_deploy_revertsIfNotRewardDistributor() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                teller.ROLE_REWARD_DISTRIBUTOR()
            )
        );
        vm.prank(user0);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }

    function test_deploy_revertsIfPolicyDisabled() external {
        // 1. Preparation: disable the teller policy
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(rewardDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }
}

contract ConvertibleOHMTellerMintTests is ConvertibleOHMTellerTestBase {
    function test_create_mintsConvertibleTokens() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        // Create (mint) convertible tokens to User0
        uint256 mintAmount = 100e9; // 100 OHM worth of tokens
        vm.prank(rewardDistributor);
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ConvertibleTokenMinted(address(token), user0, mintAmount);
        teller.create(address(token), user0, mintAmount);

        // Verify
        assertEq(token.balanceOf(user0), mintAmount, "User0 should have minted tokens");
        assertEq(
            token.totalSupply(),
            mintAmount,
            "The total supply should equal the minted amount"
        );
    }

    function test_create_mintsToTwoUsers_skipOnCoverage() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        // Create tokens to two users
        uint256 mintAmount1 = 100e9;
        uint256 mintAmount2 = 200e9;
        vm.startPrank(rewardDistributor);
        teller.create(address(token), user0, mintAmount1);
        teller.create(address(token), user1, mintAmount2);
        vm.stopPrank();

        // Verify
        assertEq(token.balanceOf(user0), mintAmount1, "The User0's balance should match");
        assertEq(token.balanceOf(user1), mintAmount2, "The User1's balance should match");
        assertEq(
            token.totalSupply(),
            mintAmount1 + mintAmount2,
            "The total supply should be the sum of mints"
        );
    }

    function test_create_revertsIfTokenDoesNotExist() external {
        // 1. Preparation: create a malicious token that mimics ConvertibleOHMToken
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            rewardDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            address(teller)
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(rewardDistributor, eligibleTimestamp, expiryTimestamp)
            )
        );
        vm.prank(rewardDistributor);
        teller.create(address(badToken), user0, 100e9);
    }

    function test_create_revertsIfTokenDoesNotMatchStored() external {
        // 1. Preparation: deploy a real token and a malicious one with same params
        _deployConvertibleToken();
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            rewardDistributor,
            _roundToDay(eligibleTimestamp),
            _roundToDay(expiryTimestamp),
            address(user1) // different teller
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_UnsupportedToken.selector,
                address(badToken)
            )
        );
        vm.prank(rewardDistributor);
        teller.create(address(badToken), user0, 100e9);
    }

    function test_create_revertsIfNotTokenCreator() external {
        // 1. Preparation: deploy a token by rewardDistributor
        ConvertibleOHMToken token = _deployConvertibleToken();

        // Create second reward distributor with the role
        address rewardDistributor2 = makeAddr("rewardDistributor2");
        roles.saveRole(teller.ROLE_REWARD_DISTRIBUTOR(), rewardDistributor2);

        // 2. Test: rewardDistributor2 should not be able to mint tokens created by rewardDistributor
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_NotTokenCreator.selector,
                rewardDistributor2,
                rewardDistributor
            )
        );
        vm.prank(rewardDistributor2);
        teller.create(address(token), user0, 100e9);
    }

    function test_create_revertsIfTokenExpired() external {
        // 1. Preparation: deploy a token and warp past expiry
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.warp(expiryTimestamp + 1);

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenExpired.selector,
                _roundToDay(expiryTimestamp)
            )
        );
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, 100e9);
    }

    function test_create_revertsIfToAddressIsZero() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(address(0))
            )
        );
        vm.prank(rewardDistributor);
        teller.create(address(token), address(0), 100e9);
    }

    function test_create_revertsIfAmountIsZero() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                2,
                abi.encodePacked(uint256(0))
            )
        );
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, 0);
    }

    function test_create_revertsIfNotRewardDistributor() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                teller.ROLE_REWARD_DISTRIBUTOR()
            )
        );
        vm.prank(user0);
        teller.create(address(token), user0, 100e9);
    }

    function test_create_revertsIfPolicyDisabled() external {
        // 1. Preparation: deploy a token, then disable the policy
        ConvertibleOHMToken token = _deployConvertibleToken();
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, 100e9);
    }
}

contract ConvertibleOHMTellerExerciseTests is ConvertibleOHMTellerTestBase {
    ConvertibleOHMToken token;

    uint256 user0InitialBal = 100e9;

    function setUp() public override {
        super.setUp();

        // Deploy the convertible token
        token = _deployConvertibleToken();

        // Mint convertible tokens to User0
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, user0InitialBal);
    }

    function test_exercise_exchangesTokensForOHM() external {
        // 1. Preparation: warp to the eligible time
        vm.warp(eligibleTimestamp);

        // 2. Test
        // Store balances before exercising
        uint256 user0UsdsBalBefore = usds.balanceOf(user0);
        uint256 user0OhmBalBefore = ohm.balanceOf(user0);
        uint256 treasuryUsdsBefore = usds.balanceOf(address(trsry));
        uint256 approvalBefore = teller.remainingMintApproval();

        // Exercise convertible tokens
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        token.approve(address(teller), user0InitialBal);
        usds.approve(address(teller), exerciseCost);
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ConvertibleTokenExercised(
            address(token),
            user0,
            user0InitialBal,
            _calcExpectedCost(user0InitialBal)
        );
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        // Verify
        assertEq(
            ohm.balanceOf(user0),
            user0OhmBalBefore + user0InitialBal,
            "User0 should receive OHM"
        );
        assertEq(
            usds.balanceOf(user0),
            user0UsdsBalBefore - _calcExpectedCost(user0InitialBal),
            "User0 should transfer USDS"
        );
        assertEq(
            usds.balanceOf(address(trsry)) - treasuryUsdsBefore,
            _calcExpectedCost(user0InitialBal),
            "The treasury should receive USDS"
        );

        assertEq(token.balanceOf(user0), 0, "The convertible tokens should be burned");
        assertEq(token.totalSupply(), 0, "The total supply of the convertible token should be 0");
        assertEq(
            teller.remainingMintApproval(),
            approvalBefore - user0InitialBal,
            "The minting approval should decrease by the exercised amount"
        );
    }

    function test_exercise_partially() external {
        // 1. Preparation: warp to the eligible time
        vm.warp(eligibleTimestamp);

        // 2. Test
        // Partially exercise convertible tokens
        uint256 exerciseAmount = (user0InitialBal * 4) / 10;
        uint256 exerciseCost = _exerciseCost(token, exerciseAmount);
        vm.startPrank(user0);
        token.approve(address(teller), exerciseAmount);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), exerciseAmount);
        vm.stopPrank();

        // Verify
        assertEq(
            token.balanceOf(user0),
            user0InitialBal - exerciseAmount,
            "User0 should have remaining convertible tokens"
        );
        assertEq(ohm.balanceOf(user0), exerciseAmount, "User0 should receive partial OHM");
    }

    function test_exercise_nearExpiry() external {
        // 1. Preparation: warp to just before the expiry time
        vm.warp(expiryTimestamp - 1 seconds);

        // 2. Test
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        token.approve(address(teller), user0InitialBal);
        usds.approve(address(teller), exerciseCost);
        // User0 should still be able to exercise even near the expiry time
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        // Verify
        assertEq(ohm.balanceOf(user0), user0InitialBal, "User0 should receive OHM");
    }

    function test_exercise_byTwoUsers_skipOnCoverage() external {
        // 1. Preparation: mint convertible tokens to User1, warp to the eligible time
        uint256 user1InitialBal = 200e9;
        vm.prank(rewardDistributor);
        teller.create(address(token), user1, user1InitialBal);

        vm.warp(eligibleTimestamp);

        // 2. Test
        // Both users exercise
        uint256 user0ExerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        token.approve(address(teller), user0InitialBal);
        usds.approve(address(teller), user0ExerciseCost);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        uint256 user1ExerciseCost = _exerciseCost(token, user1InitialBal);
        vm.startPrank(user1);
        token.approve(address(teller), user1InitialBal);
        usds.approve(address(teller), user1ExerciseCost);
        teller.exercise(address(token), user1InitialBal);
        vm.stopPrank();

        // Verify
        assertEq(ohm.balanceOf(user0), user0InitialBal, "User0 should receive OHM");
        assertEq(ohm.balanceOf(user1), user1InitialBal, "User1 should receive OHM");
        assertEq(token.totalSupply(), 0, "All the convertible tokens should be burned");
    }

    function test_exercise_afterTransfer_skipOnCoverage() external {
        // 1. Preparation: User0 transfers convertible tokens to User1, warp to the eligible time
        uint256 user1Amount = user0InitialBal;
        vm.prank(user0);
        token.transfer(user1, user1Amount);

        vm.warp(eligibleTimestamp);

        // 2. Test
        // User1 exercises
        uint256 exerciseCost = _exerciseCost(token, user1Amount);
        vm.startPrank(user1);
        token.approve(address(teller), user1Amount);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), user1Amount);
        vm.stopPrank();

        // Verify
        assertEq(ohm.balanceOf(user1), user1Amount, "User1 should receive OHM");
        assertEq(token.balanceOf(user1), 0, "The User1's convertible tokens should be burned");
    }

    function test_exercise_revertsIfTokenDoesNotExist() external {
        // 1. Preparation: create a malicious token with different params (not deployed)
        uint48 differentEligible = eligibleTimestamp + 30 days;
        uint48 differentExpiry = expiryTimestamp + 30 days;
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            rewardDistributor,
            differentEligible,
            differentExpiry,
            address(teller)
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(rewardDistributor, differentEligible, differentExpiry)
            )
        );
        teller.exercise(address(badToken), 100e9);
    }

    function test_exercise_revertsIfTokenDoesNotMatchStored() external {
        // 1. Preparation: deploy a real token and a malicious one with same params
        _deployConvertibleToken();
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            rewardDistributor,
            _roundToDay(eligibleTimestamp),
            _roundToDay(expiryTimestamp),
            address(user1) // different teller
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_UnsupportedToken.selector,
                address(badToken)
            )
        );
        teller.exercise(address(badToken), 100e9);
    }

    function test_exercise_revertsIfNotEligible() external {
        // Test: try to exercise before eligible time
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_NotEligible.selector,
                _roundToDay(eligibleTimestamp)
            )
        );
        vm.prank(user0);
        teller.exercise(address(token), 100e9);
    }

    function test_exercise_revertsIfTokenExpired() external {
        // 1. Preparation: warp past expiry
        vm.warp(expiryTimestamp + 1);

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenExpired.selector,
                _roundToDay(expiryTimestamp)
            )
        );
        vm.prank(user0);
        teller.exercise(address(token), 100e9);
    }

    function test_exercise_revertsIfAmountIsZero() external {
        // 1. Preparation: warp to eligible
        vm.warp(eligibleTimestamp);

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(uint256(0))
            )
        );
        vm.prank(user0);
        teller.exercise(address(token), 0);
    }

    function test_exercise_revertsIfInsufficientMintApproval() external {
        // 1. Preparation: reduce the minting cap to less than the exercise amount
        uint256 limitedCap = 50e9; // Only allow 50 OHM to be minted
        teller.setMintCap(limitedCap);
        // Warp to the eligible time
        vm.warp(eligibleTimestamp);

        // 2. Test: try to exercise more than the minting cap allows
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        token.approve(address(teller), user0InitialBal);
        usds.approve(address(teller), exerciseCost);
        vm.expectRevert(MINTRv1.MINTR_NotApproved.selector);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();
    }

    function test_exercise_revertsIfFeeOnTransfer() external {
        // 1. Preparation: deploy a fee-on-transfer token as the quote token
        address feeRecipient = makeAddr("feeRecipient");
        MockERC20FeeOnTransfer fotToken = new MockERC20FeeOnTransfer("FOT", "FOT", feeRecipient);

        // Deploy a convertible token with the fee-on-transfer quote token
        vm.prank(rewardDistributor);
        ConvertibleOHMToken fotConvToken = ConvertibleOHMToken(
            teller.deploy(address(fotToken), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        // Mint convertible tokens to user0
        vm.prank(rewardDistributor);
        teller.create(address(fotConvToken), user0, user0InitialBal);

        // Fund user0 with fee-on-transfer tokens
        fotToken.mint(user0, 1_000_000e18);

        // Warp to eligible time
        vm.warp(eligibleTimestamp);

        // 2. Test: exercise should revert because the treasury receives less than expected
        // quoteAmount = ceil(100e9 * 15e18 / 1e9) = 1500e18
        uint256 quoteAmount = _exerciseCost(fotConvToken, user0InitialBal);
        // fee = 1500e18 * 1000 / 10000 = 150e18
        // Treasury receives 1500e18 - 150e18 = 1350e18
        uint256 fee = (quoteAmount * 1000) / 100e2;
        uint256 actualReceived = quoteAmount - fee;

        vm.startPrank(user0);
        fotConvToken.approve(address(teller), user0InitialBal);
        fotToken.approve(address(teller), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_FeeOnTransfer.selector,
                quoteAmount,
                actualReceived
            )
        );
        teller.exercise(address(fotConvToken), user0InitialBal);
        vm.stopPrank();
    }

    function test_exercise_revertsIfPolicyDisabled() external {
        // 1. Preparation: warp to the eligible time, disable the policy
        vm.warp(eligibleTimestamp);
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(user0);
        teller.exercise(address(token), 100e9);
    }
}

contract ConvertibleOHMTellerAdminTests is ConvertibleOHMTellerTestBase {
    function test_setMinDuration_updatesMinDuration() external {
        uint48 newDuration = 7 days;
        // vm.prank(address(this));
        teller.setMinDuration(newDuration);
        assertEq(teller.minDuration(), newDuration, "The minimum duration should be updated");
    }

    function testFuzz_setMinDuration_skipOnCoverage(uint48 duration_) external {
        duration_ = uint48(bound(duration_, 1 days, type(uint48).max));

        // vm.prank(address(this));
        teller.setMinDuration(duration_);
        assertEq(teller.minDuration(), duration_, "The minimum duration should be updated");
    }

    function test_setMinDuration_revertsIfDurationLessThanOneDay() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(uint48(1 days - 1))
            )
        );
        // vm.prank(address(this));
        teller.setMinDuration(uint48(1 days - 1));
    }

    function test_setMinDuration_revertsIfNotAdmin() external {
        vm.expectRevert();
        vm.prank(user0);
        teller.setMinDuration(7 days);
    }

    function test_setMinDuration_revertsIfPolicyDisabled() external {
        // 1. Preparation: disable the policy
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        // vm.prank(address(this));
        teller.setMinDuration(7 days);
    }

    function test_setMintCap_increasesMintApproval() external {
        // 1. Preparation: reduce the minting cap to 0 first
        teller.setMintCap(0);
        assertEq(teller.remainingMintApproval(), 0, "The initial approval should be 0");

        // 2. Test: increase the minting cap
        uint256 mintCap = _DEFAULT_MINT_CAP;
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MintCapUpdated(mintCap);
        teller.setMintCap(mintCap);

        // Verify
        assertEq(
            teller.remainingMintApproval(),
            mintCap,
            "The approval should match the minting cap"
        );
    }

    function test_setMintCap_decreasesMintApproval() external {
        // 1. Preparation: set an initial minting cap
        uint256 initialCap = _DEFAULT_MINT_CAP;
        teller.setMintCap(initialCap);
        assertEq(teller.remainingMintApproval(), initialCap, "The initial cap should be set");

        // 2. Test: decrease the minting cap
        uint256 newCap = 500e9;
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MintCapUpdated(newCap);
        teller.setMintCap(newCap);

        // Verify
        assertEq(teller.remainingMintApproval(), newCap, "The approval should be decreased");
    }

    function test_setMintCap_notChangeWhenSameValue() external {
        // 1. Preparation: set an initial minting cap
        uint256 cap = _DEFAULT_MINT_CAP;
        teller.setMintCap(cap);

        // 2. Test: set the same minting cap again (should emit the event, but not change the approval)
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MintCapUpdated(cap);
        teller.setMintCap(cap);

        // Verify
        assertEq(teller.remainingMintApproval(), cap, "The approval should remain unchanged");
    }

    function test_setMintCap_emitsActualPostApproval() external {
        // 1. Preparation: set an initial cap and exercise some tokens to reduce the approval
        uint256 initialCap = _DEFAULT_MINT_CAP;
        teller.setMintCap(initialCap);

        // Deploy a convertible token and mint some to user0
        ConvertibleOHMToken token = _deployConvertibleToken();
        uint256 mintAmount = 100e9;
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, mintAmount);

        // Exercise tokens to consume some mint approval (mintOhm reduces mintApproval)
        vm.warp(eligibleTimestamp);
        uint256 cost = _exerciseCost(token, mintAmount);
        vm.startPrank(user0);
        token.approve(address(teller), mintAmount);
        usds.approve(address(teller), cost);
        teller.exercise(address(token), mintAmount);
        vm.stopPrank();

        // Now the MINTR approval is reduced by `mintAmount`
        // currentApproval = initialCap - mintAmount = 900e9
        uint256 approvalAfterExercise = teller.remainingMintApproval();
        assertEq(approvalAfterExercise, initialCap - mintAmount, "Approval should be reduced");

        // 2. Test: set a new cap and verify the event emits the actual post-approval from MINTR
        uint256 newCap = 2000e9;
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MintCapUpdated(newCap);
        teller.setMintCap(newCap);

        // Verify the actual approval matches
        assertEq(teller.remainingMintApproval(), newCap, "Post-approval should match new cap");
    }

    function test_setMintCap_revertsIfNotAdminOrTellerAdmin() external {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(user0);
        teller.setMintCap(_DEFAULT_MINT_CAP);
    }

    function test_setMintCap_succeeds_givenTellerAdminRole() external {
        // `admin` has ROLE_TELLER_ADMIN (setUp line 67), but NOT ADMIN_ROLE
        uint256 mintCap = 500e9;
        vm.prank(admin);
        teller.setMintCap(mintCap);

        // Verify
        assertEq(
            teller.remainingMintApproval(),
            mintCap,
            "The teller admin should be able to set the mint cap"
        );
    }

    function test_setMintCap_succeeds_givenAdminRole() external {
        // `address(this)` has ADMIN_ROLE (setUp line 68), but NOT ROLE_TELLER_ADMIN
        uint256 mintCap = 750e9;
        teller.setMintCap(mintCap);

        // Verify
        assertEq(
            teller.remainingMintApproval(),
            mintCap,
            "The admin should be able to set the mint cap"
        );
    }

    function test_setMintCap_revertsIfPolicyDisabled() external {
        // 1. Preparation: disable the policy
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        teller.setMintCap(_DEFAULT_MINT_CAP);
    }

    function test_enable_withInitialMintCap() external {
        // 1. Preparation: deploy a fresh teller (not enabled yet)
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));
        // Verify the initial approval is 0
        assertEq(newTeller.remainingMintApproval(), 0, "The initial approval should be 0");

        // 2. Test: enable with the initial minting cap
        uint256 initialCap = _DEFAULT_MINT_CAP;
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MintCapUpdated(initialCap);
        newTeller.enable(abi.encode(initialCap));

        // Verify
        assertEq(
            newTeller.remainingMintApproval(),
            initialCap,
            "The approval should match the initial cap"
        );
    }

    function test_enable_revertsIfNoMintCap() external {
        // 1. Preparation: deploy a fresh teller
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        // 2. Test: enable without an initial minting cap (empty data) should revert
        bytes memory emptyData = "";
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                emptyData
            )
        );
        newTeller.enable("");
    }

    function test_enable_revertsIfInvalidDataLength() external {
        // 1. Preparation: deploy a fresh teller
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        // 2. Test: enable with incorrect data length should revert
        bytes memory badData = abi.encodePacked(uint128(_DEFAULT_MINT_CAP));
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleOHMTeller.Teller_InvalidParams.selector, 0, badData)
        );
        newTeller.enable(badData);
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        teller.enable(abi.encode(uint256(_DEFAULT_MINT_CAP)));
    }

    function test_enable_revertsIfNotAdmin() external {
        // 1. Preparation: deploy a fresh teller
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        // 2. Test
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(user0);
        newTeller.enable(abi.encode(uint256(_DEFAULT_MINT_CAP)));
    }

    function test_disable_disablesPolicy() external {
        // The teller is enabled in the setUp
        assertTrue(teller.isEnabled(), "The teller should be enabled");

        // Test
        teller.disable("");

        // Verify
        assertFalse(teller.isEnabled(), "The teller should be disabled");
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        // 1. Preparation: disable the teller
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        teller.disable("");
    }

    function test_disable_revertsIfNotAdmin() external {
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(user0);
        teller.disable("");
    }
}

contract ConvertibleOHMTellerViewerTests is ConvertibleOHMTellerTestBase {
    function test_exerciseCost_returnsCorrectValues() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        uint256 amount = 100e9;
        (address quoteToken, uint256 cost) = teller.exerciseCost(address(token), amount);

        // Verify
        assertEq(address(quoteToken), address(usds), "Quote token should be USDS");
        assertEq(cost, _calcExpectedCost(amount), "Cost should match expected");
    }

    function testFuzz_exerciseCost_skipOnCoverage(uint256 amount_) external {
        // Avoid overflow: amount * STRIKE_PRICE should not overflow
        amount_ = bound(amount_, 1, type(uint256).max / STRIKE_PRICE);

        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        (address quoteToken, uint256 cost) = teller.exerciseCost(address(token), amount_);

        // Verify
        assertEq(address(quoteToken), address(usds), "The quote token should be USDS");
        assertEq(cost, _calcExpectedCost(amount_), "The cost should match the expected one");
    }

    function test_exerciseCost_revertsIfTokenDoesNotExist() external {
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            rewardDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            address(teller)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(rewardDistributor, eligibleTimestamp, expiryTimestamp)
            )
        );
        teller.exerciseCost(address(badToken), 100e9);
    }

    function test_exerciseCost_revertsIfTokenDoesNotMatchStored() external {
        // 1. Preparation: deploy a real token and a malicious one
        _deployConvertibleToken();
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            rewardDistributor,
            _roundToDay(eligibleTimestamp),
            _roundToDay(expiryTimestamp),
            address(user1)
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_UnsupportedToken.selector,
                address(badToken)
            )
        );
        teller.exerciseCost(address(badToken), 100e9);
    }

    function test_exerciseCost_revertsIfAmountIsZero() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(uint256(0))
            )
        );
        teller.exerciseCost(address(token), 0);
    }

    function test_getToken_returnsCorrectToken() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken expectedToken = _deployConvertibleToken();

        // 2. Test
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.getToken(
                address(usds),
                rewardDistributor,
                eligibleTimestamp,
                expiryTimestamp,
                STRIKE_PRICE
            )
        );
        assertEq(address(token), address(expectedToken), "Should return the deployed token");
    }

    function testFuzz_getToken_roundedTimestamps_skipOnCoverage(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) external {
        eligibleDiff_ = uint48(bound(eligibleDiff_, 0, uint48(1 days) - 1));
        expiryDiff_ = uint48(bound(expiryDiff_, 0, uint48(1 days) - 1));

        // 1. Preparation: deploy a token
        ConvertibleOHMToken expectedToken = _deployConvertibleToken();

        // 2. Test: get with different timestamps that round to the same day
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.getToken(
                address(usds),
                rewardDistributor,
                eligibleTimestamp + eligibleDiff_,
                expiryTimestamp + expiryDiff_,
                STRIKE_PRICE
            )
        );
        assertEq(
            address(token),
            address(expectedToken),
            "Should return same token for rounded timestamps"
        );
    }

    function test_getToken_revertsIfTokenDoesNotExist() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(rewardDistributor, eligibleTimestamp, expiryTimestamp)
            )
        );
        teller.getToken(
            address(usds),
            rewardDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );
    }

    function test_getTokenHash_returnsCorrectHash() external view {
        assertEq(
            teller.getTokenHash(
                address(usds),
                rewardDistributor,
                eligibleTimestamp,
                expiryTimestamp,
                STRIKE_PRICE
            ),
            _calcTokenHash(rewardDistributor, eligibleTimestamp, expiryTimestamp),
            "The hash should match the expected one"
        );
    }

    function testFuzz_getTokenHash_roundedTimestamps_skipOnCoverage(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) external view {
        eligibleDiff_ = uint48(bound(eligibleDiff_, 0, uint48(1 days) - 1));
        expiryDiff_ = uint48(bound(expiryDiff_, 0, uint48(1 days) - 1));

        assertEq(
            teller.getTokenHash(
                address(usds),
                rewardDistributor,
                eligibleTimestamp + eligibleDiff_,
                expiryTimestamp + expiryDiff_,
                STRIKE_PRICE
            ),
            _calcTokenHash(rewardDistributor, eligibleTimestamp, expiryTimestamp),
            "The hash should match for the rounded timestamps"
        );
    }

    function test_remainingMintApproval_returnsCorrectValue() external {
        // 1. Preparation: set a specific minting cap
        uint256 mintCap = _DEFAULT_MINT_CAP;
        teller.setMintCap(mintCap);

        // 2. Test
        assertEq(teller.remainingMintApproval(), mintCap, "Should return a correct value");
    }
}

contract ConvertibleOHMTellerClonedTokenBasicTests is ConvertibleOHMTellerTestBase {
    ConvertibleOHMToken token;

    uint256 user0InitialBal = 100e9;

    function setUp() public override {
        super.setUp();

        // Deploy the convertible token
        token = _deployConvertibleToken();

        // Mint convertible tokens to User0
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, user0InitialBal);
    }

    function test_transfer() external {
        // User0 transfers to User1
        uint256 value = (user0InitialBal * 4) / 10;
        vm.prank(user0);
        bool success = token.transfer(user1, value);

        // Verify
        assertTrue(success, "The transfer should be successful");
        assertEq(token.balanceOf(user0), user0InitialBal - value, "User0 should transfer tokens");
        assertEq(token.balanceOf(user1), value, "User1 should receive tokens");
    }

    function test_approve() external {
        // User0 approves User1
        uint256 value = user0InitialBal / 2;
        vm.prank(user0);
        bool success = token.approve(user1, value);

        // Verify
        assertTrue(success, "The approval should be successful");
        assertEq(token.allowance(user0, user1), value, "The allowance should be set");
    }

    function test_transferFrom() external {
        // 1. Preparation: User0 approves User1
        uint256 approvedValue = user0InitialBal / 2;
        vm.prank(user0);
        token.approve(user1, approvedValue);

        // 2. Test
        // User1 transfers from User0
        uint256 value = approvedValue / 2;
        vm.prank(user1);
        bool success = token.transferFrom(user0, user1, value);

        // Verify
        assertTrue(success, "The transfer should be successful");
        assertEq(
            token.balanceOf(user0),
            user0InitialBal - value,
            "User0 should transfer convertible tokens"
        );
        assertEq(token.balanceOf(user1), value, "User1 should receive convertible tokens");
        assertEq(
            token.allowance(user0, user1),
            approvedValue - value,
            "The allowance should be reduced"
        );
    }

    function test_parameters() external view {
        (
            address quoteToken,
            address creator_,
            uint48 eligible_,
            uint48 expiry_,
            uint256 strike_
        ) = token.parameters();

        assertEq(quoteToken, address(usds), "Quote token should be USDS");
        assertEq(creator_, rewardDistributor, "Creator should be reward distributor");
        assertEq(eligible_, _roundToDay(eligibleTimestamp), "Eligible should match");
        assertEq(expiry_, _roundToDay(expiryTimestamp), "Expiry should match");
        assertEq(strike_, STRIKE_PRICE, "Strike price should match");
    }

    function test_quote() external view {
        assertEq(token.quote(), address(usds), "Quote token should be USDS");
    }

    function test_eligible() external view {
        assertEq(
            token.eligible(),
            _roundToDay(eligibleTimestamp),
            "Eligible timestamp should match"
        );
    }

    function test_expiry() external view {
        assertEq(token.expiry(), _roundToDay(expiryTimestamp), "Expiry timestamp should match");
    }

    function test_teller() external view {
        assertEq(token.teller(), address(teller), "Teller should match");
    }

    function test_creator() external view {
        assertEq(token.creator(), rewardDistributor, "Creator should be reward distributor");
    }

    function test_strike() external view {
        assertEq(token.strike(), STRIKE_PRICE, "Strike price should match");
    }

    function test_mintFor_updatesTotalSupplyAndBalance() external {
        // Mint additional tokens to User1
        uint256 mintAmount = 50e9;
        uint256 totalSupplyBefore = token.totalSupply();

        vm.prank(rewardDistributor);
        teller.create(address(token), user1, mintAmount);

        // Verify
        assertEq(token.balanceOf(user1), mintAmount, "User1 should receive minted tokens");
        assertEq(
            token.totalSupply(),
            totalSupplyBefore + mintAmount,
            "Total supply should increase by minted amount"
        );
    }

    function test_mintFor_revertsIfNotTeller() external {
        vm.expectRevert(ConvertibleOHMToken.ConvertibleOHMToken_OnlyTeller.selector);
        vm.prank(user0);
        token.mintFor(user0, 100e9);
    }

    function test_burnFrom_revertsIfNotTeller() external {
        vm.expectRevert(ConvertibleOHMToken.ConvertibleOHMToken_OnlyTeller.selector);
        vm.prank(user0);
        token.burnFrom(user0, user0InitialBal);
    }

    function test_burnFrom_revertsIfInsufficientAllowance() external {
        // 1. Preparation: User0 approves less than the burn amount
        uint256 approvedAmount = user0InitialBal / 2;
        vm.prank(user0);
        token.approve(address(teller), approvedAmount);

        // 2. Test: teller tries to burn more than approved (via exercise)
        vm.warp(eligibleTimestamp);
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        usds.approve(address(teller), exerciseCost);
        vm.expectRevert(stdError.arithmeticError);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();
    }

    function test_burnFrom_revertsIfNoAllowance() external {
        // 1. Preparation: warp to eligible, no token approval given
        vm.warp(eligibleTimestamp);

        // 2. Test: exercise without approving the teller for convertible tokens
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        usds.approve(address(teller), exerciseCost);
        vm.expectRevert(stdError.arithmeticError);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();
    }

    function test_burnFrom_succeedsWithExactAllowance() external {
        // 1. Preparation: User0 approves exact amount
        vm.warp(eligibleTimestamp);
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);

        // 2. Test
        vm.startPrank(user0);
        token.approve(address(teller), user0InitialBal);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        // Verify: allowance should be fully consumed
        assertEq(
            token.allowance(user0, address(teller)),
            0,
            "Allowance should be zero after exact burn"
        );
        assertEq(token.balanceOf(user0), 0, "All tokens should be burned");
    }

    function test_burnFrom_succeedsWithMaxAllowance() external {
        // 1. Preparation: User0 approves max (infinite approval)
        vm.warp(eligibleTimestamp);
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);

        // 2. Test
        vm.startPrank(user0);
        token.approve(address(teller), type(uint256).max);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        // Verify: max allowance should not be decremented
        assertEq(
            token.allowance(user0, address(teller)),
            type(uint256).max,
            "Max allowance should not be decremented"
        );
        assertEq(token.balanceOf(user0), 0, "All tokens should be burned");
    }
}

contract ConvertibleOHMTellerIntegrationTests is ConvertibleOHMTellerTestBase {
    function test_deployAndCreateAndExercise_skipOnCoverage() external {
        // Deploy the convertible token
        ConvertibleOHMToken token = _deployConvertibleToken();
        assertFalse(
            address(token) == address(0),
            "The deployed convertible token should not be the zero address"
        );

        // Create (mint) convertible tokens to User0
        uint256 mintAmount = 500e9;
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, mintAmount);
        assertEq(token.balanceOf(user0), mintAmount, "User0 should receive convertible tokens");

        // Wait until the eligible time
        vm.warp(eligibleTimestamp);

        // Store the balance before exercising
        uint256 user0UsdsBalBefore = usds.balanceOf(user0);

        // Exercise
        uint256 exerciseCost = _exerciseCost(token, mintAmount);
        vm.startPrank(user0);
        token.approve(address(teller), mintAmount);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), mintAmount);
        vm.stopPrank();

        // Verify
        assertEq(ohm.balanceOf(user0), mintAmount, "User0 should receive OHM");
        assertEq(
            usds.balanceOf(user0),
            user0UsdsBalBefore - _calcExpectedCost(mintAmount),
            "User0 should transfer USDS"
        );
        assertEq(token.balanceOf(user0), 0, "All the convertible tokens should be burned");
    }

    function test_multipleDeploysAndExercises_skipOnCoverage() external {
        // Deploy two different tokens
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        vm.startPrank(rewardDistributor);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2)
        );

        // Mint convertible tokens to User0
        uint256 amount1 = 100e9;
        uint256 amount2 = 100e9;
        teller.create(address(token1), user0, amount1);
        teller.create(address(token2), user0, amount2);
        vm.stopPrank();

        // Warp to the eligible time
        vm.warp(eligibleTimestamp);

        // Exercise both convertible tokens
        uint256 exerciseCost1 = _exerciseCost(token1, amount1);
        vm.startPrank(user0);
        token1.approve(address(teller), amount1);
        usds.approve(address(teller), exerciseCost1);
        teller.exercise(address(token1), amount1);
        token2.approve(address(teller), amount2);
        uint256 exerciseCost2 = _exerciseCost(token2, amount2);
        usds.approve(address(teller), exerciseCost2);
        teller.exercise(address(token2), amount2);
        vm.stopPrank();

        // Verify
        assertEq(
            ohm.balanceOf(user0),
            amount1 + amount2,
            "User0 should receive the total OHM amount"
        );
    }
}
