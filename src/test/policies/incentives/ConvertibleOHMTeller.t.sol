// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

// Interfaces
import {IConvertibleOHMTeller} from "src/policies/incentives/convertible/interfaces/IConvertibleOHMTeller.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";
import {SafeCast} from "@openzeppelin-5.3.0/utils/math/SafeCast.sol";
import {Test, stdError} from "forge-std/Test.sol";

// Contracts
import {ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ConvertibleOHMTeller} from "src/policies/incentives/convertible/ConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/incentives/convertible/ConvertibleOHMToken.sol";
import {Kernel, Actions, toKeycode, Keycode, Policy} from "src/Kernel.sol";
import {MaliciousConvertibleOHMToken} from "src/test/mocks/MaliciousConvertibleOHMToken.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";

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
    uint256 internal constant _DEFAULT_MINT_CAP = 1000e9; // TODO: update this value when it becomes known
    uint256 internal constant _UNLIMITED_CREATOR_CAP = type(uint128).max;

    // Test accounts
    address incentiveDistributor = makeAddr("incentiveDistributor"); // False contract
    address admin = makeAddr("admin");
    address heart = makeAddr("heart");
    address emergency = makeAddr("emergency");
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
        roles.saveRole(ADMIN_ROLE, address(this));
        // Emergency role used by disable() (onlyEmergencyOrAdminRole)
        roles.saveRole(EMERGENCY_ROLE, emergency);
        // Heart role for periodic-task execute() tests
        roles.saveRole(teller.ROLE_HEART(), heart);
        // Distributor role required for deploy and create
        roles.saveRole(teller.ROLE_CONVERTIBLE_DISTRIBUTOR(), incentiveDistributor);

        // Enable the teller policy with a single creator at an effectively unlimited cap
        teller.enable(_enableData(_UNLIMITED_CREATOR_CAP));

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

    /// @dev Encodes enableData with a single creator (incentiveDistributor) at the given cap.
    function _enableData(uint256 cap_) internal view returns (bytes memory) {
        address[] memory creators = new address[](1);
        creators[0] = incentiveDistributor;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap_;
        return abi.encode(creators, caps);
    }

    /// @dev Encodes enableData with the supplied creator and cap arrays.
    function _enableDataMulti(
        address[] memory creators_,
        uint256[] memory caps_
    ) internal pure returns (bytes memory) {
        return abi.encode(creators_, caps_);
    }

    /// @dev Encodes enableData with empty arrays (smallest valid payload).
    function _enableDataEmpty() internal pure returns (bytes memory) {
        return abi.encode(new address[](0), new uint256[](0));
    }

    /// @dev Wraps a single creator address in a memory array for invariant assertions.
    function _singletonCreators(address creator_) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = creator_;
    }

    /// @dev Asserts `MINTR.mintApproval(teller) == sum(creatorOutstanding[c])` across creators.
    function _assertMintApprovalInvariant(address[] memory creators_) internal view {
        uint256 sum;
        for (uint256 i; i < creators_.length; ++i) {
            sum += teller.creatorOutstanding(creators_[i]);
        }
        assertEq(
            mintr.mintApproval(address(teller)),
            sum,
            "MINTR approval should equal sum of creator outstanding"
        );
    }

    /// @dev Warps `block.timestamp` to the token's eligible timestamp.
    ///      Reverts if the target is earlier than the current `block.timestamp`.
    function _warpToEligible(ConvertibleOHMToken token_) internal {
        uint256 target = uint256(token_.eligible());
        require(target >= vm.getBlockTimestamp(), "warp target before current block.timestamp");
        vm.warp(target);
    }

    /// @dev Warps `block.timestamp` past the token's expiry.
    ///      Reverts if the target is earlier than the current `block.timestamp`.
    function _warpPastExpiry(ConvertibleOHMToken token_) internal {
        uint256 target = uint256(token_.expiry()) + 1;
        require(target >= vm.getBlockTimestamp(), "warp target before current block.timestamp");
        vm.warp(target);
    }

    /// @dev Expects a ROLES_RequireRole revert with the given role.
    function _expectRoleRevert(bytes32 role_) internal {
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, role_));
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
        vm.prank(incentiveDistributor);
        token = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    /// @dev Deploys a convertible token by `incentiveDistributor` with custom timestamps.
    function _deployConvertibleTokenAt(
        uint48 eligible_,
        uint48 expiry_
    ) internal returns (ConvertibleOHMToken token) {
        vm.prank(incentiveDistributor);
        token = ConvertibleOHMToken(teller.deploy(address(usds), eligible_, expiry_, STRIKE_PRICE));
    }

    /// @dev Deploys a convertible token by an arbitrary distributor with custom timestamps.
    function _deployConvertibleTokenForDistributor(
        address distributor_,
        uint48 eligible_,
        uint48 expiry_,
        uint256 strikePrice_
    ) internal returns (ConvertibleOHMToken token) {
        vm.prank(distributor_);
        token = ConvertibleOHMToken(teller.deploy(address(usds), eligible_, expiry_, strikePrice_));
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

contract ConvertibleOHMTellerConstructorTests is ConvertibleOHMTellerTestBase {
    function test_constructor_setsStateAndEmitsEvents() external {
        // Expect constructor events
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MinDurationSet(uint48(1 days));
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MinEligibleDelaySet(uint48(1 days));

        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));

        // Verify immutables
        assertEq(newTeller.OHM(), address(ohm), "OHM should be set");
        assertTrue(
            newTeller.TOKEN_IMPLEMENTATION() != address(0),
            "TOKEN_IMPLEMENTATION should be deployed"
        );

        // Verify initial state
        assertEq(newTeller.minDuration(), uint48(1 days), "minDuration should default to 1 day");
        assertEq(
            newTeller.minEligibleDelay(),
            uint48(1 days),
            "minEligibleDelay should default to 1 day"
        );
        assertFalse(newTeller.isEnabled(), "Should not be enabled after construction");
    }

    function test_constructor_revertsIfKernelIsZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(address(0))
            )
        );
        new ConvertibleOHMTeller(address(0), address(ohm));
    }

    function test_constructor_revertsIfOhmIsZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(address(0))
            )
        );
        new ConvertibleOHMTeller(address(kernel), address(0));
    }

    function test_constructor_revertsIfOhmDecimalsNot9() external {
        MockERC20 badOhm = new MockERC20("Bad OHM", "bOHM", 18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(address(badOhm))
            )
        );
        new ConvertibleOHMTeller(address(kernel), address(badOhm));
    }
}

contract ConvertibleOHMTellerDeploymentTests is ConvertibleOHMTellerTestBase {
    function test_deploy_createsConvertibleTokenWithCorrectParams() external {
        // The deployment should emit the event
        vm.expectEmit(false, true, true, true);
        emit IConvertibleOHMTeller.ConvertibleTokenCreated(
            address(0), // The address is not yet known
            address(usds),
            incentiveDistributor,
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
            incentiveDistributor,
            "The creator should match the incentive distributor"
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
            teller.tokens(_calcTokenHash(incentiveDistributor, eligibleTimestamp, expiryTimestamp)),
            address(token),
            "The token should be stored in the mapping"
        );
        assertEq(token.chainId(), block.chainid, "The chainId should match");
    }

    function test_deploy_createsTokenWithZeroEligibleUsingMinDelay() external {
        // Deploy a token with zero eligible time
        vm.prank(incentiveDistributor);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.deploy(
                address(usds),
                0, // Should compute earliest UTC midnight >= block.timestamp + minEligibleDelay
                expiryTimestamp,
                STRIKE_PRICE
            )
        );

        // Expected: smallest UTC midnight >= block.timestamp + minEligibleDelay
        uint48 minTimestamp = uint48(vm.getBlockTimestamp()) + teller.minEligibleDelay();
        uint48 expectedEligible = _roundToDay(minTimestamp + 1 days - 1);

        // Verify
        assertEq(
            token.eligible(),
            expectedEligible,
            "The eligible should be the earliest UTC midnight satisfying minEligibleDelay"
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

    function test_deploy_createsUniqueTokensForDifferentParams() external {
        // Deploy convertible tokens with different params
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        vm.startPrank(incentiveDistributor);
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

    function test_deploy_createsUniqueTokensForDifferentQuoteTokens() external {
        // 1. Preparation: deploy another quote token
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);

        // 2. Test
        // Deploy tokens with different quote tokens
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
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

    function test_deploy_createsUniqueTokensForDifferentCreators() external {
        // 1. Preparation: create second incentive distributor
        address incentiveDistributor2 = makeAddr("incentiveDistributor2");
        roles.saveRole(teller.ROLE_CONVERTIBLE_DISTRIBUTOR(), incentiveDistributor2);

        // 2. Test: deploy tokens with same params but different creators
        ConvertibleOHMToken token1 = _deployConvertibleToken(); // deployed by incentiveDistributor

        vm.prank(incentiveDistributor2);
        ConvertibleOHMToken token2 = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        // 3. Verify: tokens should be different
        assertTrue(
            address(token1) != address(token2),
            "Should create different tokens for different creators"
        );
        assertEq(
            token1.creator(),
            incentiveDistributor,
            "Token1 creator should be incentiveDistributor"
        );
        assertEq(
            token2.creator(),
            incentiveDistributor2,
            "Token2 creator should be incentiveDistributor2"
        );

        // Verify hash includes creator
        bytes32 hash1 = teller.getTokenHash(
            address(usds),
            incentiveDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );
        bytes32 hash2 = teller.getTokenHash(
            address(usds),
            incentiveDistributor2,
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );
        assertTrue(hash1 != hash2, "Hashes should be different for different creators");
    }

    function testFuzz_deploy_existingTokenReturnedForSameRoundedTimestamps(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) external {
        eligibleDiff_ = uint48(bound(eligibleDiff_, 0, uint48(1 days) - 1));
        expiryDiff_ = uint48(bound(expiryDiff_, 0, uint48(1 days) - 1));

        // 1. Preparation: deploy a token
        ConvertibleOHMToken token1 = _deployConvertibleToken();

        // 2. Test: deploy with different timestamps that round to the same day
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), pastEligible, expiryTimestamp + 2 days, STRIKE_PRICE);
    }

    function test_deploy_zeroEligibleIsNotImmediatelyExercisable() external {
        vm.prank(incentiveDistributor);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.deploy(address(usds), 0, expiryTimestamp, STRIKE_PRICE)
        );

        assertTrue(
            token.eligible() > uint48(vm.getBlockTimestamp()),
            "Token should not be immediately exercisable"
        );
        assertTrue(
            token.eligible() >= uint48(vm.getBlockTimestamp()) + teller.minEligibleDelay(),
            "Token eligible must satisfy minEligibleDelay"
        );
    }

    function test_deploy_revertsIfEligibleWithinMinDelay() external {
        // Warp off midnight so truncated eligible is strictly less than block.timestamp + delay
        vm.warp(vm.getBlockTimestamp() + 12 hours);
        if (vm.getBlockTimestamp() % 1 days == 0) skip(1);

        uint48 tomorrowMidnight = _roundToDay(uint48(vm.getBlockTimestamp()) + 1 days);
        // tomorrowMidnight < block.timestamp + minEligibleDelay because block.timestamp
        // is not aligned to midnight, so the gap after truncation is less than 1 day

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(tomorrowMidnight)
            )
        );
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), tomorrowMidnight, expiryTimestamp, STRIKE_PRICE);
    }

    function testFuzz_deploy_zeroEligibleRespectsMinDelay(uint48 delay_) external {
        delay_ = uint48(bound(delay_, 1 days, 365 days));
        teller.setMinEligibleDelay(delay_);

        uint48 safeExpiry = _roundToDay(uint48(vm.getBlockTimestamp()) + 730 days);

        vm.prank(incentiveDistributor);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.deploy(address(usds), 0, safeExpiry, STRIKE_PRICE)
        );

        // Eligible must be a UTC midnight that satisfies the delay
        uint48 eligible = token.eligible();
        assertEq(eligible, _roundToDay(eligible), "Eligible must be a UTC midnight");
        assertTrue(
            eligible >= uint48(vm.getBlockTimestamp()) + delay_,
            "Eligible must satisfy minEligibleDelay"
        );
        // Must be the smallest such midnight (ceiling rounds up by at most 1 day)
        assertTrue(
            eligible < uint48(vm.getBlockTimestamp()) + delay_ + 1 days,
            "Eligible should be the earliest valid midnight"
        );
    }

    function testFuzz_deploy_explicitEligibleRespectsMinDelay(uint48 delay_) external {
        delay_ = uint48(bound(delay_, 1 days, 365 days));
        teller.setMinEligibleDelay(delay_);

        // Compute the earliest eligible that satisfies the delay
        uint48 minTimestamp = uint48(vm.getBlockTimestamp()) + delay_;
        uint48 eligible = _roundToDay(minTimestamp + 1 days - 1);
        uint48 safeExpiry = eligible + 180 days;

        vm.prank(incentiveDistributor);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.deploy(address(usds), eligible, safeExpiry, STRIKE_PRICE)
        );

        assertEq(token.eligible(), eligible, "Eligible should match the provided value");
    }

    function test_deploy_boundaryEligibleExactlyAtMinDelay() external {
        // Warp to a midnight so block.timestamp + 1 day is also a midnight
        vm.warp(_roundToDay(uint48(vm.getBlockTimestamp()) + 1 days));

        uint48 eligible = uint48(vm.getBlockTimestamp()) + uint48(1 days);
        uint48 expiry = eligible + 180 days;

        // eligible == block.timestamp + minEligibleDelay -> passes
        vm.prank(incentiveDistributor);
        ConvertibleOHMToken token = ConvertibleOHMToken(
            teller.deploy(address(usds), eligible, expiry, STRIKE_PRICE)
        );
        assertEq(token.eligible(), eligible, "Eligible at exact boundary should succeed");
    }

    function test_deploy_boundaryEligibleOneBelowMinDelay() external {
        // Warp to a midnight so arithmetic is clean
        vm.warp(_roundToDay(uint48(vm.getBlockTimestamp()) + 1 days));

        // eligible = block.timestamp + 1 day - 1 second, truncated to block.timestamp
        // block.timestamp < block.timestamp + minEligibleDelay -> reverts
        uint48 eligible = uint48(vm.getBlockTimestamp()) + uint48(1 days) - 1;
        uint48 truncatedEligible = _roundToDay(eligible);
        uint48 expiry = truncatedEligible + 180 days;

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                1,
                abi.encodePacked(truncatedEligible)
            )
        );
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), eligible, expiry, STRIKE_PRICE);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), eligibleTimestamp, shortExpiry, STRIKE_PRICE);
    }

    function test_deploy_revertsIfExpiryTooFarInFuture() external {
        uint48 farExpiry = _roundToDay(uint48(block.timestamp) + 731 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                2,
                abi.encodePacked(farExpiry)
            )
        );
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), eligibleTimestamp, farExpiry, STRIKE_PRICE);
    }

    function test_deploy_revertsIfStrikePriceIsZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                3,
                abi.encodePacked(uint256(0))
            )
        );
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, tooLowStrike);
    }

    function test_deploy_revertsIfQuoteTokenDecimalsTooHigh() external {
        // Quote token with 128 decimals overflows int8 (max 127) in SafeCast
        MockERC20 highDecToken = new MockERC20("HIGH", "HIGH", 128);
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedIntDowncast.selector, 8, int256(128))
        );
        vm.prank(incentiveDistributor);
        teller.deploy(address(highDecToken), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }

    function testFuzz_deploy_revertsIfNotIncentiveDistributor(address addr_) external {
        vm.assume(addr_ != incentiveDistributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                teller.ROLE_CONVERTIBLE_DISTRIBUTOR()
            )
        );
        vm.prank(addr_);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE);
    }

    function test_deploy_revertsIfPolicyDisabled() external {
        // 1. Preparation: disable the teller policy
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
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
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            mintAmount,
            "creatorMinted should track cumulative mints"
        );
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            mintAmount,
            "creatorOutstanding should track live supply"
        );
        assertEq(
            teller.remainingMintApproval(),
            mintAmount,
            "MINTR approval should match outstanding"
        );
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));
    }

    function test_create_mintsToTwoUsers() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        // Create tokens to two users
        uint256 mintAmount1 = 100e9;
        uint256 mintAmount2 = 200e9;
        vm.startPrank(incentiveDistributor);
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
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            mintAmount1 + mintAmount2,
            "creatorMinted should track cumulative mints across users"
        );
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            mintAmount1 + mintAmount2,
            "creatorOutstanding should track live supply across users"
        );
        assertEq(
            teller.remainingMintApproval(),
            mintAmount1 + mintAmount2,
            "MINTR approval should equal sum of mints"
        );
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));
    }

    function test_create_succeedsAtCapBoundary() external {
        // 1. Preparation: deploy a token and lower the cap to 100e9
        ConvertibleOHMToken token = _deployConvertibleToken();
        teller.setCreatorMintCap(incentiveDistributor, 100e9);

        // 2. Test: minting exactly the cap should succeed
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);

        assertEq(
            teller.creatorMinted(incentiveDistributor),
            100e9,
            "creatorMinted should reach the cap exactly"
        );
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            100e9,
            "creatorOutstanding should equal the minted amount"
        );
    }

    function test_create_creatorMintedMonotonic() external {
        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // Step 1: mint 60e9
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 60e9);

        // Step 2: user0 exercises 60e9
        vm.warp(eligibleTimestamp);
        uint256 cost = _exerciseCost(token, 60e9);
        vm.startPrank(user0);
        token.approve(address(teller), 60e9);
        usds.approve(address(teller), cost);
        teller.exercise(address(token), 60e9);
        vm.stopPrank();

        // Step 3: mint 40e9 more
        vm.prank(incentiveDistributor);
        teller.create(address(token), user1, 40e9);

        // creatorMinted is monotonic and tracks cumulative mints, not net
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            100e9,
            "creatorMinted should track cumulative mints across exercises"
        );
        // creatorOutstanding only reflects live convOHM
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            40e9,
            "creatorOutstanding should reflect live (un-exercised) supply"
        );
    }

    function test_create_revertsIfTokenDoesNotExist() external {
        // 1. Preparation: create a malicious token that mimics ConvertibleOHMToken
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            incentiveDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            address(teller)
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(incentiveDistributor, eligibleTimestamp, expiryTimestamp)
            )
        );
        vm.prank(incentiveDistributor);
        teller.create(address(badToken), user0, 100e9);
    }

    function test_create_revertsIfTokenDoesNotMatchStored() external {
        // 1. Preparation: deploy a real token and a malicious one with same params
        _deployConvertibleToken();
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            incentiveDistributor,
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
        vm.prank(incentiveDistributor);
        teller.create(address(badToken), user0, 100e9);
    }

    function test_create_revertsIfNotTokenCreator() external {
        // 1. Preparation: deploy a token by incentiveDistributor
        ConvertibleOHMToken token = _deployConvertibleToken();

        // Create second incentive distributor with the role
        address incentiveDistributor2 = makeAddr("incentiveDistributor2");
        roles.saveRole(teller.ROLE_CONVERTIBLE_DISTRIBUTOR(), incentiveDistributor2);

        // 2. Test: incentiveDistributor2 should not be able to mint tokens created by incentiveDistributor
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_NotTokenCreator.selector,
                incentiveDistributor2,
                incentiveDistributor
            )
        );
        vm.prank(incentiveDistributor2);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
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
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 0);
    }

    function testFuzz_create_revertsIfNotIncentiveDistributor(address addr_) external {
        vm.assume(addr_ != incentiveDistributor);

        // 1. Preparation: deploy a token
        ConvertibleOHMToken token = _deployConvertibleToken();

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                teller.ROLE_CONVERTIBLE_DISTRIBUTOR()
            )
        );
        vm.prank(addr_);
        teller.create(address(token), user0, 100e9);
    }

    function test_create_revertsIfTokenIsEOA() external {
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleOHMTeller.Teller_UnsupportedToken.selector, user0)
        );
        vm.prank(incentiveDistributor);
        teller.create(user0, user0, 100e9);
    }

    function test_create_revertsIfTokenIsNonTokenContract() external {
        // Use the kernel address as a contract that doesn't implement parameters()
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_UnsupportedToken.selector,
                address(kernel)
            )
        );
        vm.prank(incentiveDistributor);
        teller.create(address(kernel), user0, 100e9);
    }

    function test_create_revertsIfPolicyDisabled() external {
        // 1. Preparation: deploy a token, then disable the policy
        ConvertibleOHMToken token = _deployConvertibleToken();
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
    }

    function test_create_revertsIfCapExceeded() external {
        // 1. Preparation: deploy a token and lower the cap below the intended mint
        ConvertibleOHMToken token = _deployConvertibleToken();
        teller.setCreatorMintCap(incentiveDistributor, 100e9);

        // 2. Test: cap == 100e9, attempt to mint 100e9 + 1 should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_CapExceeded.selector,
                incentiveDistributor,
                100e9 + 1,
                100e9
            )
        );
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9 + 1);
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
        vm.prank(incentiveDistributor);
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
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after full exercise"
        );
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            user0InitialBal,
            "creatorMinted should remain monotonic post-exercise"
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
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            user0InitialBal - exerciseAmount,
            "creatorOutstanding should reflect remaining supply"
        );
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            user0InitialBal,
            "creatorMinted should remain unchanged on partial exercise"
        );
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

    function test_exercise_byTwoUsers() external {
        // 1. Preparation: mint convertible tokens to User1, warp to the eligible time
        uint256 user1InitialBal = 200e9;
        vm.prank(incentiveDistributor);
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
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after both exercises"
        );
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            user0InitialBal + user1InitialBal,
            "creatorMinted should equal sum of mints"
        );
    }

    function test_exercise_afterTransfer() external {
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
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after exercise (transfer does not affect creator state)"
        );
    }

    function test_exercise_revertsIfTokenDoesNotExist() external {
        // 1. Preparation: create a malicious token with different params (not deployed)
        uint48 differentEligible = eligibleTimestamp + 30 days;
        uint48 differentExpiry = expiryTimestamp + 30 days;
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            incentiveDistributor,
            differentEligible,
            differentExpiry,
            address(teller)
        );

        // 2. Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(incentiveDistributor, differentEligible, differentExpiry)
            )
        );
        teller.exercise(address(badToken), 100e9);
    }

    function test_exercise_revertsIfTokenDoesNotMatchStored() external {
        // 1. Preparation: deploy a real token and a malicious one with same params
        _deployConvertibleToken();
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            incentiveDistributor,
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
        // 1. Preparation: drain the teller's MINTR approval below the live convOHM supply.
        // Under the new accounting model, approval is kept in lockstep with outstanding,
        // so we must cause divergence by reducing approval directly via MINTR.
        _grantModulePermission(toKeycode("MINTR"), MINTRv1.decreaseMintApproval.selector);
        mintr.decreaseMintApproval(address(teller), 50e9);

        // Warp to the eligible time
        vm.warp(eligibleTimestamp);

        // 2. Test: try to exercise more than the remaining approval allows
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
        vm.prank(incentiveDistributor);
        ConvertibleOHMToken fotConvToken = ConvertibleOHMToken(
            teller.deploy(address(fotToken), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );

        // Mint convertible tokens to user0
        vm.prank(incentiveDistributor);
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

    function test_exercise_revertsIfTokenIsEOA() external {
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleOHMTeller.Teller_UnsupportedToken.selector, user0)
        );
        teller.exercise(user0, 100e9);
    }

    function test_exercise_revertsIfTokenIsNonTokenContract() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_UnsupportedToken.selector,
                address(kernel)
            )
        );
        teller.exercise(address(kernel), 100e9);
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

contract ConvertibleOHMTellerSweepTests is ConvertibleOHMTellerTestBase {
    function test_sweep_noopWhenNoTokens() external {
        // No tokens deployed: sweep should be a no-op and emit nothing.
        uint256 approvalBefore = teller.remainingMintApproval();
        teller.sweepExpiredTokens(10);
        assertEq(teller.activeTokensLength(), 0, "Active tokens length should remain 0");
        assertEq(
            teller.remainingMintApproval(),
            approvalBefore,
            "MINTR approval should not change"
        );
    }

    function test_sweep_noopWhenNoneExpired() external {
        // Deploy and mint, but do not warp.
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);

        uint256 approvalBefore = teller.remainingMintApproval();
        teller.sweepExpiredTokens(10);

        assertEq(teller.activeTokensLength(), 1, "Active tokens length should remain 1");
        assertEq(
            teller.remainingMintApproval(),
            approvalBefore,
            "MINTR approval should not change"
        );
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            100e9,
            "creatorOutstanding should be unchanged"
        );
    }

    function test_sweep_singleExpiredToken() external {
        // Mint, warp past expiry, sweep.
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);

        _warpPastExpiry(token);

        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token), 100e9);
        teller.sweepExpiredTokens(10);

        assertEq(teller.activeTokensLength(), 0, "Active tokens length should be 0 after sweep");
        assertFalse(teller.isActiveToken(address(token)), "Swept token should no longer be active");
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after sweep"
        );
        assertEq(teller.remainingMintApproval(), 0, "MINTR approval should be 0 after sweep");
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            100e9,
            "creatorMinted should be preserved (monotonic)"
        );
    }

    function test_sweep_partialExerciseThenExpire() external {
        // Mint 100e9, exercise 40e9, warp past expiry, sweep.
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);

        vm.warp(eligibleTimestamp);
        uint256 cost = _exerciseCost(token, 40e9);
        vm.startPrank(user0);
        token.approve(address(teller), 40e9);
        usds.approve(address(teller), cost);
        teller.exercise(address(token), 40e9);
        vm.stopPrank();

        _warpPastExpiry(token);

        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token), 60e9);
        teller.sweepExpiredTokens(10);

        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after sweep"
        );
        assertEq(teller.remainingMintApproval(), 0, "MINTR approval should be 0 after sweep");
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            100e9,
            "creatorMinted should remain at 100e9 (monotonic)"
        );
    }

    function test_sweep_multipleCreatorsBatch() external {
        // 1. Preparation: register a second distributor and deploy a token from each
        address distributor2 = makeAddr("distributor2");
        roles.saveRole(teller.ROLE_CONVERTIBLE_DISTRIBUTOR(), distributor2);
        teller.setCreatorMintCap(distributor2, _UNLIMITED_CREATOR_CAP);

        ConvertibleOHMToken token1 = _deployConvertibleToken();
        ConvertibleOHMToken token2 = _deployConvertibleTokenForDistributor(
            distributor2,
            eligibleTimestamp + 1 days,
            expiryTimestamp + 1 days,
            STRIKE_PRICE
        );

        // Mint from both distributors
        vm.prank(incentiveDistributor);
        teller.create(address(token1), user0, 100e9);
        vm.prank(distributor2);
        teller.create(address(token2), user0, 200e9);

        // Warp past the latest expiry so both tokens are expired
        _warpPastExpiry(token2);

        // 2. Test: sweep should fire one event per token
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token2), 200e9);
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token1), 100e9);
        teller.sweepExpiredTokens(10);

        assertEq(teller.activeTokensLength(), 0, "All active tokens should be removed");
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "Distributor1 outstanding should be 0"
        );
        assertEq(
            teller.creatorOutstanding(distributor2),
            0,
            "Distributor2 outstanding should be 0"
        );
        assertEq(
            teller.remainingMintApproval(),
            0,
            "MINTR approval should be 0 after batched sweep"
        );

        address[] memory creators = new address[](2);
        creators[0] = incentiveDistributor;
        creators[1] = distributor2;
        _assertMintApprovalInvariant(creators);
    }

    function test_sweep_zeroMaxIterations() external {
        // Even with an expired token, maxIterations==0 must be a strict no-op.
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
        _warpPastExpiry(token);

        uint256 approvalBefore = teller.remainingMintApproval();
        teller.sweepExpiredTokens(0);

        assertEq(teller.activeTokensLength(), 1, "Active tokens should remain unchanged");
        assertEq(
            teller.remainingMintApproval(),
            approvalBefore,
            "MINTR approval should not change"
        );
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            100e9,
            "creatorOutstanding should not change"
        );
    }

    function test_sweep_partialMaxIterations() external {
        // Three expired tokens. With maxIterations=1 the backward scan removes the last entry.
        ConvertibleOHMToken token1 = _deployConvertibleTokenAt(eligibleTimestamp, expiryTimestamp);
        vm.prank(incentiveDistributor);
        teller.create(address(token1), user0, 10e9);

        ConvertibleOHMToken token2 = _deployConvertibleTokenAt(
            eligibleTimestamp + 1 days,
            expiryTimestamp + 1 days
        );
        vm.prank(incentiveDistributor);
        teller.create(address(token2), user0, 20e9);

        ConvertibleOHMToken token3 = _deployConvertibleTokenAt(
            eligibleTimestamp + 2 days,
            expiryTimestamp + 2 days
        );
        vm.prank(incentiveDistributor);
        teller.create(address(token3), user0, 30e9);

        _warpPastExpiry(token3);

        // Sweep with one iteration removes the last-inserted token (token3, supply 30e9).
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token3), 30e9);
        teller.sweepExpiredTokens(1);

        assertEq(teller.activeTokensLength(), 2, "Two tokens should remain");
        assertFalse(teller.isActiveToken(address(token3)), "token3 should have been swept");
        assertTrue(teller.isActiveToken(address(token1)), "token1 should remain");
        assertTrue(teller.isActiveToken(address(token2)), "token2 should remain");
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            30e9,
            "Outstanding should drop by token3 supply"
        );
    }

    function test_sweep_consecutiveCallsRemoveOneEach() external {
        // Three expired tokens. Two consecutive sweep(1) calls should each remove one token,
        // proving sweep can drain the active set in chunks across multiple invocations.
        ConvertibleOHMToken token1 = _deployConvertibleTokenAt(eligibleTimestamp, expiryTimestamp);
        vm.prank(incentiveDistributor);
        teller.create(address(token1), user0, 10e9);

        ConvertibleOHMToken token2 = _deployConvertibleTokenAt(
            eligibleTimestamp + 1 days,
            expiryTimestamp + 1 days
        );
        vm.prank(incentiveDistributor);
        teller.create(address(token2), user0, 20e9);

        ConvertibleOHMToken token3 = _deployConvertibleTokenAt(
            eligibleTimestamp + 2 days,
            expiryTimestamp + 2 days
        );
        vm.prank(incentiveDistributor);
        teller.create(address(token3), user0, 30e9);

        _warpPastExpiry(token3);

        // First call: backward scan removes the last-inserted token (token3).
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token3), 30e9);
        teller.sweepExpiredTokens(1);

        assertEq(teller.activeTokensLength(), 2, "Two tokens should remain after first sweep");
        assertFalse(teller.isActiveToken(address(token3)), "token3 should be swept");
        assertTrue(teller.isActiveToken(address(token1)), "token1 should remain");
        assertTrue(teller.isActiveToken(address(token2)), "token2 should remain");
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            30e9,
            "Outstanding after first sweep should be token1 + token2 supply (10e9 + 20e9)"
        );
        assertEq(
            teller.remainingMintApproval(),
            30e9,
            "MINTR approval should track outstanding after first sweep"
        );

        // Second call: backward scan now removes the next last-inserted token (token2).
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token2), 20e9);
        teller.sweepExpiredTokens(1);

        assertEq(teller.activeTokensLength(), 1, "One token should remain after second sweep");
        assertFalse(teller.isActiveToken(address(token2)), "token2 should be swept");
        assertTrue(teller.isActiveToken(address(token1)), "token1 should remain");
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            10e9,
            "Outstanding after second sweep should be token1 supply (10e9)"
        );
        assertEq(
            teller.remainingMintApproval(),
            10e9,
            "MINTR approval should track outstanding after second sweep"
        );
    }

    function test_sweep_backwardIterationOrder() external {
        // Three tokens A, B, C. Only B is expired. Sweep removes B, leaves [A, C].
        // We mint very small amounts so the totals are easy to verify.
        ConvertibleOHMToken tokenA = _deployConvertibleTokenAt(
            eligibleTimestamp,
            expiryTimestamp + 30 days
        );
        vm.prank(incentiveDistributor);
        teller.create(address(tokenA), user0, 10e9);

        ConvertibleOHMToken tokenB = _deployConvertibleTokenAt(eligibleTimestamp, expiryTimestamp);
        vm.prank(incentiveDistributor);
        teller.create(address(tokenB), user0, 20e9);

        ConvertibleOHMToken tokenC = _deployConvertibleTokenAt(
            eligibleTimestamp + 1 days,
            expiryTimestamp + 60 days
        );
        vm.prank(incentiveDistributor);
        teller.create(address(tokenC), user0, 30e9);

        // Warp so that only tokenB is expired (between B's expiry and A/C's expiries).
        vm.warp(uint256(tokenB.expiry()) + 1);

        teller.sweepExpiredTokens(10);

        // After swap-and-pop, the slot of B is filled by C and the array shrinks.
        // The plan asserts presence of A and C, not order.
        assertEq(teller.activeTokensLength(), 2, "Two tokens should remain");
        assertTrue(teller.isActiveToken(address(tokenA)), "tokenA should remain");
        assertTrue(teller.isActiveToken(address(tokenC)), "tokenC should remain");
        assertFalse(teller.isActiveToken(address(tokenB)), "tokenB should be swept");
    }

    function test_sweep_idempotence() external {
        // Sweeping twice should leave state unchanged after the first call.
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
        _warpPastExpiry(token);

        teller.sweepExpiredTokens(10);
        assertEq(teller.activeTokensLength(), 0, "Active set should be empty after first sweep");

        // Second call should be a no-op.
        uint256 approvalAfterFirst = teller.remainingMintApproval();
        teller.sweepExpiredTokens(10);
        assertEq(
            teller.activeTokensLength(),
            0,
            "Active set should remain empty after second sweep"
        );
        assertEq(
            teller.remainingMintApproval(),
            approvalAfterFirst,
            "MINTR approval should not change on second sweep"
        );
    }

    function test_sweep_revertsIfPolicyDisabled() external {
        teller.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        teller.sweepExpiredTokens(10);
    }
}

contract ConvertibleOHMTellerExecuteTests is ConvertibleOHMTellerTestBase {
    function test_execute_noopWhenDisabled() external {
        // Deploy a token while enabled, then disable.
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
        _warpPastExpiry(token);
        teller.disable("");

        // Heart calling execute() while disabled returns early with no state change.
        uint256 lengthBefore = teller.activeTokensLength();
        uint256 approvalBefore = teller.remainingMintApproval();
        vm.prank(heart);
        teller.execute();
        assertEq(
            teller.activeTokensLength(),
            lengthBefore,
            "Active tokens length should not change while disabled"
        );
        assertEq(
            teller.remainingMintApproval(),
            approvalBefore,
            "MINTR approval should not change while disabled"
        );
    }

    function test_execute_sweepsExpiredTokensFromHeart() external {
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
        _warpPastExpiry(token);

        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.ActiveTokenSwept(address(token), 100e9);
        vm.prank(heart);
        teller.execute();

        assertEq(teller.activeTokensLength(), 0, "Active tokens should be empty after heart sweep");
        assertEq(teller.remainingMintApproval(), 0, "MINTR approval should be 0 after heart sweep");
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after heart sweep"
        );
    }

    // Note: SweepExpiredTokensFailed cannot be triggered through the current callable surface:
    //   - MINTR.decreaseMintApproval floors at zero rather than underflowing.
    //   - creatorOutstanding stays in lockstep with token supply across create / exercise.
    //   - The active set is populated only by clones of the immutable TOKEN_IMPLEMENTATION,
    //     so token.expiry() / totalSupply() / creator() are simple immutable-arg or storage
    //     reads that never revert, and there is no way to inject a malicious token.
    //   - The sweep makes no callbacks into untrusted code, so re-entrancy cannot be used to
    //     drive an inner revert either.
    // The try/catch and event are retained as a defensive guard against future logic changes
    // that could introduce a revert in the sweep path.

    function test_execute_respectsHeartSweepLimit() external {
        // Deploy 51 expired tokens and verify execute() sweeps HEART_SWEEP_LIMIT==50 each call.
        uint256 totalTokens = teller.HEART_SWEEP_LIMIT() + 1;
        for (uint256 i = 0; i < totalTokens; ++i) {
            uint48 eligible = eligibleTimestamp + uint48(i) * uint48(1 days);
            uint48 expiry = expiryTimestamp + uint48(i) * uint48(1 days);
            ConvertibleOHMToken token = _deployConvertibleTokenAt(eligible, expiry);
            vm.prank(incentiveDistributor);
            teller.create(address(token), user0, 1e9);
        }
        assertEq(
            teller.activeTokensLength(),
            totalTokens,
            "All tokens should be in the active set"
        );

        // Warp past the last expiry so all tokens are expired.
        uint48 lastExpiry = expiryTimestamp + uint48(totalTokens - 1) * uint48(1 days);
        vm.warp(uint256(lastExpiry) + 1);

        // First execute() sweeps exactly HEART_SWEEP_LIMIT tokens.
        vm.prank(heart);
        teller.execute();
        assertEq(
            teller.activeTokensLength(),
            1,
            "Exactly one token should remain after first execute"
        );

        // Second execute() clears the remaining token.
        vm.prank(heart);
        teller.execute();
        assertEq(teller.activeTokensLength(), 0, "All tokens should be swept after second execute");
    }

    function testFuzz_execute_revertsIfNotHeart(address addr_) external {
        vm.assume(addr_ != heart);
        _expectRoleRevert(teller.ROLE_HEART());
        vm.prank(addr_);
        teller.execute();
    }
}

contract ConvertibleOHMTellerAdminTests is ConvertibleOHMTellerTestBase {
    function test_setMinDuration_updatesMinDuration() external {
        uint48 newDuration = 7 days;
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MinDurationSet(newDuration);
        teller.setMinDuration(newDuration);
        assertEq(teller.minDuration(), newDuration, "The minimum duration should be updated");
    }

    function testFuzz_setMinDuration(uint48 duration_) external {
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

    function testFuzz_setMinDuration_revertsIfNotAdmin(address addr_) external {
        vm.assume(addr_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(addr_);
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

    // ========== setMinEligibleDelay ========== //

    function test_setMinEligibleDelay_setsDelay() external {
        teller.setMinEligibleDelay(2 days);
        assertEq(teller.minEligibleDelay(), 2 days, "Min eligible delay should be 2 days");
    }

    function test_setMinEligibleDelay_emitsEvent() external {
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.MinEligibleDelaySet(uint48(2 days));
        teller.setMinEligibleDelay(2 days);
    }

    function test_setMinEligibleDelay_revertsIfLessThanOneDay() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(uint48(12 hours))
            )
        );
        teller.setMinEligibleDelay(12 hours);
    }

    function testFuzz_setMinEligibleDelay_revertsIfNotAdmin(address addr_) external {
        vm.assume(addr_ != address(this));
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
        vm.prank(addr_);
        teller.setMinEligibleDelay(2 days);
    }

    function test_setMinEligibleDelay_revertsIfPolicyDisabled() external {
        teller.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        teller.setMinEligibleDelay(2 days);
    }

    // ========== setCreatorMintCap ========== //

    function test_setCreatorMintCap_setsCapAndEmits() external {
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.CreatorMintCapSet(incentiveDistributor, 500e9);
        teller.setCreatorMintCap(incentiveDistributor, 500e9);
        assertEq(
            teller.creatorMintCap(incentiveDistributor),
            500e9,
            "Creator mint cap should be updated"
        );
    }

    function testFuzz_setCreatorMintCap(uint256 cap_) external {
        cap_ = bound(cap_, 0, type(uint128).max);
        teller.setCreatorMintCap(incentiveDistributor, cap_);
        assertEq(
            teller.creatorMintCap(incentiveDistributor),
            cap_,
            "Creator mint cap should match fuzzed value"
        );
    }

    function test_setCreatorMintCap_freezesNewMintsAtCurrentMinted() external {
        // Mint 100e9 then set the cap exactly at minted
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
        teller.setCreatorMintCap(incentiveDistributor, 100e9);

        // Any further mint must revert (cap exceeded by 1)
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_CapExceeded.selector,
                incentiveDistributor,
                100e9 + 1,
                100e9
            )
        );
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 1);
    }

    function test_setCreatorMintCap_raisingCapUnfreezes() external {
        // Freeze first by minting and lowering cap
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);
        teller.setCreatorMintCap(incentiveDistributor, 100e9);

        // Raise cap and verify a new mint succeeds
        teller.setCreatorMintCap(incentiveDistributor, 200e9);
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 50e9);
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            150e9,
            "creatorMinted should grow by the new mint amount"
        );
    }

    function test_setCreatorMintCap_revertsIfBelowMinted() external {
        // Mint 100e9 so creatorMinted == 100e9
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, 100e9);

        // Attempting cap=50e9 below the current minted should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_CapBelowMinted.selector,
                incentiveDistributor,
                100e9,
                50e9
            )
        );
        teller.setCreatorMintCap(incentiveDistributor, 50e9);
    }

    function test_setCreatorMintCap_revertsIfZeroAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(address(0))
            )
        );
        teller.setCreatorMintCap(address(0), 500e9);
    }

    function testFuzz_setCreatorMintCap_revertsIfNotAdmin(address addr_) external {
        vm.assume(addr_ != address(this));
        _expectRoleRevert(ADMIN_ROLE);
        vm.prank(addr_);
        teller.setCreatorMintCap(incentiveDistributor, 500e9);
    }

    function test_setCreatorMintCap_revertsIfPolicyDisabled() external {
        teller.disable("");
        vm.expectRevert(IEnabler.NotEnabled.selector);
        teller.setCreatorMintCap(incentiveDistributor, 500e9);
    }

    // ========== enable ========== //

    function test_enable_emptyArraysAccepted() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        vm.expectEmit(true, true, false, true);
        emit IEnabler.Enabled();
        newTeller.enable(_enableDataEmpty());

        assertTrue(newTeller.isEnabled(), "New teller should be enabled");
        assertEq(
            newTeller.creatorMintCap(incentiveDistributor),
            0,
            "No creator caps should have been set"
        );
        assertEq(newTeller.remainingMintApproval(), 0, "MINTR approval should be 0 at enable time");
    }

    function test_enable_singleCreatorSetsCapAndEmits() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.CreatorMintCapSet(incentiveDistributor, _DEFAULT_MINT_CAP);
        vm.expectEmit(true, true, false, true);
        emit IEnabler.Enabled();
        newTeller.enable(_enableData(_DEFAULT_MINT_CAP));

        assertEq(
            newTeller.creatorMintCap(incentiveDistributor),
            _DEFAULT_MINT_CAP,
            "Creator cap should be stored"
        );
        assertEq(newTeller.remainingMintApproval(), 0, "MINTR approval should be 0 at enable time");
    }

    function test_enable_twoCreatorsSetsBothCaps() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));
        address distributor2 = makeAddr("distributor2");

        address[] memory creators = new address[](2);
        creators[0] = incentiveDistributor;
        creators[1] = distributor2;
        uint256[] memory caps = new uint256[](2);
        caps[0] = 500e9;
        caps[1] = 1000e9;

        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.CreatorMintCapSet(creators[0], caps[0]);
        vm.expectEmit(true, true, false, true);
        emit IConvertibleOHMTeller.CreatorMintCapSet(creators[1], caps[1]);
        vm.expectEmit(true, true, false, true);
        emit IEnabler.Enabled();
        newTeller.enable(_enableDataMulti(creators, caps));

        assertEq(
            newTeller.creatorMintCap(creators[0]),
            caps[0],
            "First creator cap should be stored"
        );
        assertEq(
            newTeller.creatorMintCap(creators[1]),
            caps[1],
            "Second creator cap should be stored"
        );
    }

    function testFuzz_enable_singleCreatorCap(uint256 cap_) external {
        cap_ = bound(cap_, 0, type(uint128).max);
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        newTeller.enable(_enableData(cap_));
        assertEq(
            newTeller.creatorMintCap(incentiveDistributor),
            cap_,
            "Creator cap should match fuzzed value"
        );
    }

    function test_enable_revertsIfArrayLengthMismatch() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        address[] memory creators = new address[](2);
        creators[0] = incentiveDistributor;
        creators[1] = makeAddr("distributor2");
        uint256[] memory caps = new uint256[](1);
        caps[0] = 500e9;

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(creators.length, caps.length)
            )
        );
        newTeller.enable(_enableDataMulti(creators, caps));
    }

    function test_enable_revertsIfDataTooShort() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        bytes memory shortData = abi.encodePacked(uint256(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                shortData
            )
        );
        newTeller.enable(shortData);
    }

    function test_enable_revertsIfEmptyBytes() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        bytes memory emptyData = "";
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                emptyData
            )
        );
        newTeller.enable(emptyData);
    }

    function test_enable_revertsIfZeroCreatorAddress() external {
        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        address[] memory creators = new address[](1);
        creators[0] = address(0);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100e9;

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_InvalidParams.selector,
                0,
                abi.encodePacked(address(0))
            )
        );
        newTeller.enable(_enableDataMulti(creators, caps));
    }

    function test_enable_revertsIfAlreadyEnabled() external {
        vm.expectRevert(IEnabler.NotDisabled.selector);
        teller.enable(_enableDataEmpty());
    }

    function testFuzz_enable_revertsIfNotAdmin(address addr_) external {
        vm.assume(addr_ != address(this));

        ConvertibleOHMTeller newTeller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        kernel.executeAction(Actions.ActivatePolicy, address(newTeller));

        _expectRoleRevert(ADMIN_ROLE);
        vm.prank(addr_);
        newTeller.enable(_enableDataEmpty());
    }

    function test_disable_adminCanDisable() external {
        // The teller is enabled in the setUp
        assertTrue(teller.isEnabled(), "The teller should be enabled");

        // Test
        vm.expectEmit(true, true, false, true);
        emit IEnabler.Disabled();
        // vm.prank(address(this)); // admin
        teller.disable("");

        // Verify
        assertFalse(teller.isEnabled(), "The teller should be disabled");
    }

    function test_disable_emergencyCanDisable() external {
        assertTrue(teller.isEnabled(), "The teller should be enabled");

        vm.expectEmit(true, true, false, true);
        emit IEnabler.Disabled();
        vm.prank(emergency);
        teller.disable("");

        assertFalse(
            teller.isEnabled(),
            "The teller should be disabled by the emergency role holder"
        );
    }

    function test_disable_revertsIfAlreadyDisabled() external {
        // 1. Preparation: disable the teller
        teller.disable("");

        // 2. Test
        vm.expectRevert(IEnabler.NotEnabled.selector);
        teller.disable("");
    }

    function testFuzz_disable_revertsIfNotAdminOrEmergency(address addr_) external {
        vm.assume(addr_ != address(this)); // admin
        vm.assume(addr_ != emergency);
        vm.expectRevert(IPolicyAdmin.NotAuthorised.selector);
        vm.prank(addr_);
        teller.disable("");
    }
}

contract ConvertibleOHMTellerViewerTests is ConvertibleOHMTellerTestBase {
    function test_supportsInterface_validatesAllInterfaces() external view {
        ERC165Helper.validateSupportsInterface(address(teller));

        assertTrue(teller.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
        assertTrue(
            teller.supportsInterface(type(IConvertibleOHMTeller).interfaceId),
            "Should support IConvertibleOHMTeller"
        );
        assertTrue(
            teller.supportsInterface(type(IPeriodicTask).interfaceId),
            "Should support IPeriodicTask"
        );
        assertTrue(
            teller.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
        assertTrue(teller.supportsInterface(type(IEnabler).interfaceId), "Should support IEnabler");
        assertFalse(
            teller.supportsInterface(type(IERC20OZ).interfaceId),
            "Should not support IERC20"
        );
    }

    function test_VERSION_returnsExpectedTuple() external view {
        (uint8 major, uint8 minor) = teller.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }

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

    function testFuzz_exerciseCost(uint256 amount_) external {
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
            incentiveDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            address(teller)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_TokenDoesNotExist.selector,
                _calcTokenHash(incentiveDistributor, eligibleTimestamp, expiryTimestamp)
            )
        );
        teller.exerciseCost(address(badToken), 100e9);
    }

    function test_exerciseCost_revertsIfTokenDoesNotMatchStored() external {
        // 1. Preparation: deploy a real token and a malicious one
        _deployConvertibleToken();
        MaliciousConvertibleOHMToken badToken = _deployMaliciousConvertibleToken(
            incentiveDistributor,
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

    function test_exerciseCost_revertsIfTokenIsEOA() external {
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleOHMTeller.Teller_UnsupportedToken.selector, user0)
        );
        teller.exerciseCost(user0, 100e9);
    }

    function test_exerciseCost_revertsIfTokenIsNonTokenContract() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleOHMTeller.Teller_UnsupportedToken.selector,
                address(kernel)
            )
        );
        teller.exerciseCost(address(kernel), 100e9);
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
                incentiveDistributor,
                eligibleTimestamp,
                expiryTimestamp,
                STRIKE_PRICE
            )
        );
        assertEq(address(token), address(expectedToken), "Should return the deployed token");
    }

    function testFuzz_getToken_roundedTimestamps(
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
                incentiveDistributor,
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
                _calcTokenHash(incentiveDistributor, eligibleTimestamp, expiryTimestamp)
            )
        );
        teller.getToken(
            address(usds),
            incentiveDistributor,
            eligibleTimestamp,
            expiryTimestamp,
            STRIKE_PRICE
        );
    }

    function test_getTokenHash_returnsCorrectHash() external view {
        assertEq(
            teller.getTokenHash(
                address(usds),
                incentiveDistributor,
                eligibleTimestamp,
                expiryTimestamp,
                STRIKE_PRICE
            ),
            _calcTokenHash(incentiveDistributor, eligibleTimestamp, expiryTimestamp),
            "The hash should match the expected one"
        );
    }

    function testFuzz_getTokenHash_roundedTimestamps(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) external view {
        eligibleDiff_ = uint48(bound(eligibleDiff_, 0, uint48(1 days) - 1));
        expiryDiff_ = uint48(bound(expiryDiff_, 0, uint48(1 days) - 1));

        assertEq(
            teller.getTokenHash(
                address(usds),
                incentiveDistributor,
                eligibleTimestamp + eligibleDiff_,
                expiryTimestamp + expiryDiff_,
                STRIKE_PRICE
            ),
            _calcTokenHash(incentiveDistributor, eligibleTimestamp, expiryTimestamp),
            "The hash should match for the rounded timestamps"
        );
    }

    function test_activeTokens_initiallyEmpty() external view {
        assertEq(teller.activeTokens().length, 0, "activeTokens() should be empty initially");
    }

    function test_activeTokens_afterSingleDeploy() external {
        ConvertibleOHMToken token = _deployConvertibleToken();

        address[] memory all = teller.activeTokens();
        assertEq(all.length, 1, "activeTokens() should have one entry");
        assertEq(all[0], address(token), "activeTokens()[0] should be the deployed token");
    }

    function test_activeTokens_afterTwoDeploys() external {
        ConvertibleOHMToken tokenA = _deployConvertibleToken();
        // Deploy a second token with a different strike price to get a distinct address
        vm.prank(incentiveDistributor);
        ConvertibleOHMToken tokenB = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2)
        );

        address[] memory all = teller.activeTokens();
        assertEq(all.length, 2, "activeTokens() should have two entries");
        assertEq(all[0], address(tokenA), "First entry should be tokenA");
        assertEq(all[1], address(tokenB), "Second entry should be tokenB");
    }

    function test_activeTokenAt_returnsTokenAtIndex() external {
        ConvertibleOHMToken tokenA = _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        ConvertibleOHMToken tokenB = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2)
        );

        assertEq(teller.activeTokenAt(0), address(tokenA), "activeTokenAt(0) should be tokenA");
        assertEq(teller.activeTokenAt(1), address(tokenB), "activeTokenAt(1) should be tokenB");
    }

    function test_activeTokenAt_revertsWhenLengthZero() external {
        // No tokens deployed: any index access should revert with EVM panic 0x32.
        vm.expectRevert(stdError.indexOOBError);
        teller.activeTokenAt(0);
    }

    function test_activeTokenAt_revertsWhenIndexOutOfBounds() external {
        // Deploy two tokens so length == 2; valid indices are 0 and 1.
        _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2);

        // Accessing index == length should revert with EVM panic 0x32.
        vm.expectRevert(stdError.indexOOBError);
        teller.activeTokenAt(2);
    }

    function test_activeTokensLength_initiallyZero() external view {
        assertEq(teller.activeTokensLength(), 0, "activeTokensLength() should be 0 initially");
    }

    function test_activeTokensLength_afterSingleDeploy() external {
        _deployConvertibleToken();
        assertEq(teller.activeTokensLength(), 1, "activeTokensLength() should be 1");
    }

    function test_activeTokensLength_afterTwoDeploys() external {
        _deployConvertibleToken();
        vm.prank(incentiveDistributor);
        teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE * 2);
        assertEq(teller.activeTokensLength(), 2, "activeTokensLength() should be 2");
    }

    function test_isActiveToken_trueAfterDeploy() external {
        ConvertibleOHMToken token = _deployConvertibleToken();
        assertTrue(
            teller.isActiveToken(address(token)),
            "isActiveToken should be true for the deployed token"
        );
    }

    function test_isActiveToken_falseForZeroAddress() external view {
        assertFalse(
            teller.isActiveToken(address(0)),
            "isActiveToken should be false for the zero address"
        );
    }

    function testFuzz_isActiveToken_falseForUnknownAddress(address addr_) external {
        ConvertibleOHMToken token = _deployConvertibleToken();
        vm.assume(addr_ != address(token));

        assertFalse(
            teller.isActiveToken(addr_),
            "isActiveToken should be false for any address that is not the deployed token"
        );
    }

    function test_remainingMintApproval_tracksOutstanding() external {
        // Initially approval is 0 (no convOHM minted)
        assertEq(teller.remainingMintApproval(), 0, "Initial approval should be 0");
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));

        // Mint convOHM and verify approval increases by the same amount
        ConvertibleOHMToken token = _deployConvertibleToken();
        uint256 mintAmount = 100e9;
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, mintAmount);
        assertEq(
            teller.remainingMintApproval(),
            mintAmount,
            "Approval should equal outstanding after mint"
        );
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));

        // Exercise part of the convOHM and verify approval decreases by the exercised amount
        vm.warp(eligibleTimestamp);
        uint256 exerciseAmount = 40e9;
        uint256 cost = _exerciseCost(token, exerciseAmount);
        vm.startPrank(user0);
        token.approve(address(teller), exerciseAmount);
        usds.approve(address(teller), cost);
        teller.exercise(address(token), exerciseAmount);
        vm.stopPrank();

        assertEq(
            teller.remainingMintApproval(),
            mintAmount - exerciseAmount,
            "Approval should decrease by the exercised amount"
        );
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));
    }
}

contract ConvertibleOHMTellerIntegrationTests is ConvertibleOHMTellerTestBase {
    function test_integration_deployAndCreateAndExercise() external {
        // Deploy the convertible token
        ConvertibleOHMToken token = _deployConvertibleToken();
        assertFalse(
            address(token) == address(0),
            "The deployed convertible token should not be the zero address"
        );

        // Create (mint) convertible tokens to User0
        uint256 mintAmount = 500e9;
        vm.prank(incentiveDistributor);
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
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after full exercise"
        );
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            mintAmount,
            "creatorMinted should remain at the cumulative mint"
        );
        assertEq(teller.remainingMintApproval(), 0, "MINTR approval should be 0 after exercise");
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));
    }

    function test_integration_multipleDeploysAndExercises() external {
        // Deploy two different tokens
        ConvertibleOHMToken token1 = _deployConvertibleToken();
        vm.startPrank(incentiveDistributor);
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
        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after both exercises"
        );
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            amount1 + amount2,
            "creatorMinted should equal sum of mints"
        );
        assertEq(teller.remainingMintApproval(), 0, "MINTR approval should be 0 after exercises");
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));
    }
}

contract ConvertibleOHMTellerInvariantTests is ConvertibleOHMTellerTestBase {
    function test_invariant_mintApprovalEqualsSumOfOutstandings() external {
        // Walk through the lifecycle, asserting the mint-approval invariant after each step
        ConvertibleOHMToken token = _deployConvertibleToken();

        // Step 1: enable -> approval == 0
        assertEq(
            teller.remainingMintApproval(),
            0,
            "MINTR approval should be 0 after enable (no mints)"
        );
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));
        assertLe(
            teller.creatorOutstanding(incentiveDistributor),
            teller.creatorMinted(incentiveDistributor),
            "creatorOutstanding <= creatorMinted"
        );
        assertLe(
            teller.creatorMinted(incentiveDistributor),
            teller.creatorMintCap(incentiveDistributor),
            "creatorMinted <= creatorMintCap"
        );

        // Step 2: mint to user0
        uint256 mintUser0 = 100e9;
        vm.prank(incentiveDistributor);
        teller.create(address(token), user0, mintUser0);
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));

        // Step 3: mint to user1
        uint256 mintUser1 = 50e9;
        vm.prank(incentiveDistributor);
        teller.create(address(token), user1, mintUser1);
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));

        // Step 4: user0 partially exercises
        vm.warp(eligibleTimestamp);
        uint256 exerciseAmount = 40e9;
        uint256 cost = _exerciseCost(token, exerciseAmount);
        vm.startPrank(user0);
        token.approve(address(teller), exerciseAmount);
        usds.approve(address(teller), cost);
        teller.exercise(address(token), exerciseAmount);
        vm.stopPrank();
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));

        // Step 5: warp past expiry and sweep
        _warpPastExpiry(token);
        teller.sweepExpiredTokens(10);
        _assertMintApprovalInvariant(_singletonCreators(incentiveDistributor));

        assertEq(
            teller.creatorOutstanding(incentiveDistributor),
            0,
            "creatorOutstanding should be 0 after sweep"
        );
        assertEq(
            teller.creatorMinted(incentiveDistributor),
            mintUser0 + mintUser1,
            "creatorMinted should remain the cumulative total"
        );
        assertLe(
            teller.creatorOutstanding(incentiveDistributor),
            teller.creatorMinted(incentiveDistributor),
            "creatorOutstanding <= creatorMinted"
        );
        assertLe(
            teller.creatorMinted(incentiveDistributor),
            teller.creatorMintCap(incentiveDistributor),
            "creatorMinted <= creatorMintCap"
        );
    }
}
