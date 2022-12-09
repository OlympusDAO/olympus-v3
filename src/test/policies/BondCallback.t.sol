// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {IBondSDA as LibIBondSDA} from "test/lib/bonds/interfaces/IBondSDA.sol";
import {RolesAuthority, Authority as SolmateAuthority} from "solmate/auth/authorities/RolesAuthority.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockPrice} from "test/mocks/MockPrice.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {FullMath} from "libraries/FullMath.sol";

import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter, OHM} from "modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {Operator} from "policies/Operator.sol";
import {BondCallback} from "policies/BondCallback.sol";

import "src/Kernel.sol";

contract MockOhm is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burnFrom(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}

// solhint-disable-next-line max-states-count
contract BondCallbackTest is Test {
    using FullMath for uint256;

    UserFactory public userCreator;
    address internal alice;
    address internal bob;
    address internal guardian;
    address internal policy;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;
    MockERC20 internal other;

    Kernel internal kernel;
    MockPrice internal price;
    OlympusRange internal range;
    OlympusTreasury internal treasury;
    OlympusMinter internal minter;
    OlympusRoles internal roles;

    Operator internal operator;
    BondCallback internal callback;
    RolesAdmin internal rolesAdmin;

    // Bond market ids to reference
    uint256 internal regBond;
    uint256 internal invBond;
    uint256 internal internalBond;
    uint256 internal externalBond;
    uint256 internal nonWhitelistedBond;

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(4);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));

            /// Deploy the bond system
            aggregator = new BondAggregator(guardian, auth);
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);

            /// Register auctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            /// Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
            other = new MockERC20("Other", "OTH", 18);
        }

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            price = new MockPrice(kernel, uint48(8 hours), 10 * 1e18);
            range = new OlympusRange(
                kernel,
                ERC20(ohm),
                ERC20(reserve),
                uint256(100),
                uint256(1000),
                uint256(2000)
            );
            treasury = new OlympusTreasury(kernel);
            minter = new OlympusMinter(kernel, address(ohm));
            roles = new OlympusRoles(kernel);

            /// Configure mocks
            price.setMovingAverage(100 * 1e18);
            price.setLastPrice(100 * 1e18);
            price.setDecimals(18);
            price.setLastTime(uint48(block.timestamp));
        }

        {
            /// Deploy roles admin
            rolesAdmin = new RolesAdmin(kernel);

            /// Deploy bond callback
            callback = new BondCallback(kernel, IBondAggregator(address(aggregator)), ohm);

            /// Deploy operator
            operator = new Operator(
                kernel,
                IBondSDA(address(auctioneer)),
                callback,
                [ERC20(ohm), ERC20(reserve)],
                [
                    uint32(2000), // cushionFactor
                    uint32(5 days), // duration
                    uint32(100_000), // debtBuffer
                    uint32(1 hours), // depositInterval
                    uint32(1000), // reserveFactor
                    uint32(1 hours), // regenWait
                    uint32(5), // regenThreshold
                    uint32(7) // regenObserve
                    // uint32(8 hours) // observationFrequency
                ]
            );

            /// Registor operator to create bond markets with a callback
            vm.prank(guardian);
            auctioneer.setCallbackAuthStatus(address(operator), true);

            /// Register this contract to create bond markets with a callback
            vm.prank(guardian);
            auctioneer.setCallbackAuthStatus(address(this), true);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.InstallModule, address(range));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(roles));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(callback));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            /// Configure access control

            /// Operator roles
            rolesAdmin.grantRole("operator_operate", guardian);
            rolesAdmin.grantRole("operator_reporter", address(callback));
            rolesAdmin.grantRole("operator_policy", policy);
            rolesAdmin.grantRole("operator_admin", guardian);

            /// Bond callback roles
            rolesAdmin.grantRole("callback_whitelist", address(operator));
            rolesAdmin.grantRole("callback_whitelist", policy);
            rolesAdmin.grantRole("callback_admin", guardian);
        }

        /// Set operator on the callback
        vm.prank(guardian);
        callback.setOperator(operator);

        /// Initialize the operator
        vm.prank(guardian);
        operator.initialize();

        // Mint tokens to users and treasury for testing
        uint256 testOhm = 1_000_000 * 1e9;
        uint256 testReserve = 1_000_000 * 1e18;

        ohm.mint(alice, testOhm * 20);
        reserve.mint(alice, testReserve * 20);

        reserve.mint(address(treasury), testReserve * 100);

        // Approve the operator and bond teller for the tokens to swap
        vm.prank(alice);
        ohm.approve(address(operator), testOhm * 20);
        vm.prank(alice);
        reserve.approve(address(operator), testReserve * 20);

        vm.prank(alice);
        ohm.approve(address(teller), testOhm * 20);
        vm.prank(alice);
        reserve.approve(address(teller), testReserve * 20);

        // Create five markets in the bond system
        // 0. Regular OHM bond (Reserve -> OHM)
        regBond = createMarket(reserve, ohm, 0, 1, 3);
        // 1. Inverse bond (OHM -> Reserve)
        invBond = createMarket(ohm, reserve, 1, 0, 3);
        // 2. Internal bond (OHM -> OHM)
        internalBond = createMarket(ohm, ohm, 1, 0, 8);
        // 3. Non-OHM bond (WETH -> Reserve)
        externalBond = createMarket(reserve, reserve, 0, -1, 8);
        // 4. Regular OHM bond that will not be whitelisted
        nonWhitelistedBond = createMarket(reserve, ohm, 0, 1, 3);

        // Whitelist all markets except the last one
        vm.prank(policy);
        callback.whitelist(address(teller), regBond);

        vm.prank(policy);
        callback.whitelist(address(teller), invBond);

        vm.prank(policy);
        callback.whitelist(address(teller), internalBond);

        vm.prank(policy);
        callback.whitelist(address(teller), externalBond);
    }

    // =========  HELPER FUNCTIONS ========= //
    function createMarket(
        ERC20 quoteToken,
        ERC20 payoutToken,
        int8 _quotePriceDecimals,
        int8 _payoutPriceDecimals,
        uint256 priceSignificand
    ) internal returns (uint256 id_) {
        uint8 _payoutDecimals = payoutToken.decimals();
        uint8 _quoteDecimals = quoteToken.decimals();

        uint256 capacity = 100_000 * 10**uint8(int8(_payoutDecimals) - _payoutPriceDecimals);

        int8 scaleAdjustment = int8(_payoutDecimals) -
            int8(_quoteDecimals) -
            (_payoutPriceDecimals - _quotePriceDecimals) /
            2;

        uint256 initialPrice = priceSignificand *
            10 **
                (
                    uint8(
                        int8(36 + _quoteDecimals - _payoutDecimals) +
                            scaleAdjustment +
                            _payoutPriceDecimals -
                            _quotePriceDecimals
                    )
                );

        uint256 minimumPrice = (priceSignificand / 2) *
            10 **
                (
                    uint8(
                        int8(36 + _quoteDecimals - _payoutDecimals) +
                            scaleAdjustment +
                            _payoutPriceDecimals -
                            _quotePriceDecimals
                    )
                );

        LibIBondSDA.MarketParams memory params = LibIBondSDA.MarketParams(
            payoutToken, // ERC20 payoutToken
            quoteToken, // ERC20 quoteToken
            address(callback), // address callbackAddr
            false, // bool capacityInQuote
            capacity, // uint256 capacity
            initialPrice, // uint256 initialPrice
            minimumPrice, // uint256 minimumPrice
            uint32(50_000), // uint32 debtBuffer
            uint48(0), // uint48 vesting (timestamp or duration)
            uint48(block.timestamp + 7 days), // uint48 conclusion (timestamp)
            uint32(24 hours), // uint32 depositInterval (duration)
            scaleAdjustment // int8 scaleAdjustment
        );

        return auctioneer.createMarket(abi.encode(params));
    }

    // =========  CALLBACK TESTS ========= //

    /// DONE
    /// [X] Callback correctly handles payouts for the 4 market cases
    /// [X] Only whitelisted markets can callback

    function testCorrectness_callback() public {
        /// Ensure the callback handles payouts for the 4 market cases correctly

        /// Case 1: Regular Bond (Reserve -> OHM)
        /// OHM is minted for payout
        /// Reserve is stored in callback until batched to treasury

        /// Store start balances of teller and callback
        uint256 startBalTeller = ohm.balanceOf(address(teller));
        uint256 startBalCallback = reserve.balanceOf(address(callback));

        /// Mint tokens to the callback to simulate a purchase
        reserve.mint(address(callback), 300);

        /// Call the callback function from the teller
        vm.prank(address(teller));
        callback.callback(regBond, 300, 10);

        /// Expect the balances of the teller and callback to be updated
        assertEq(ohm.balanceOf(address(teller)), startBalTeller + 10);
        assertEq(reserve.balanceOf(address(callback)), startBalCallback + 300);

        /// Case 2: Inverse Bond (OHM -> Reserve)
        /// Reserve is withdrawn from the treasury to pay out teller
        /// OHM received is held in the callback until batched to treasury

        /// Store start balances of teller and callback
        startBalTeller = reserve.balanceOf(address(teller));
        startBalCallback = ohm.balanceOf(address(callback));

        /// Mint tokens to the callback to simulate a purchase
        ohm.mint(address(callback), 10);

        /// Call the callback function from the teller
        vm.prank(address(teller));
        callback.callback(invBond, 10, 300);

        /// Expect the balances of the teller and callback to be updated
        /// Callback should be the same as the start amount since the OHM is burned
        assertEq(reserve.balanceOf(address(teller)), startBalTeller + 300);
        assertEq(ohm.balanceOf(address(callback)), startBalCallback);

        /// Case 3: Internal Bond (OHM -> OHM)
        /// OHM is received by the callback and the difference
        /// in the quote token and payout is minted to the callback to pay the teller

        /// Store start balances of teller and callback
        startBalTeller = ohm.balanceOf(address(teller));
        startBalCallback = ohm.balanceOf(address(callback));

        /// Mint tokens to the callback to simulate a purchase
        ohm.mint(address(callback), 100);

        /// Call the callback function from the teller
        vm.prank(address(teller));
        callback.callback(internalBond, 100, 150);

        /// Expect the balances of the teller and callback to be updated
        assertEq(ohm.balanceOf(address(teller)), startBalTeller + 150);
        assertEq(ohm.balanceOf(address(callback)), startBalCallback);

        /// Case 4: Non-OHM Bond (Reserve -> Reserve)
        /// Should fail with Callback_MarketNotSupported(id)

        /// Mint tokens to the callback to simulate a purchase
        reserve.mint(address(callback), 100);

        /// Call the callback function from the teller, expect to revert
        bytes memory err = abi.encodeWithSignature(
            "Callback_MarketNotSupported(uint256)",
            externalBond
        );
        vm.prank(address(teller));
        vm.expectRevert(err);
        callback.callback(externalBond, 100, 150);
    }

    function testCorrectness_callbackMustReceiveTokens() public {
        /// Ensure that the callback function has received at least the correct number of tokens as being claimed

        /// Case 1: Zero tokens sent in
        bytes memory err = abi.encodeWithSignature("Callback_TokensNotReceived()");
        vm.prank(address(teller));
        vm.expectRevert(err);
        callback.callback(regBond, 10, 10);

        /// Case 2: Fewer than claimed tokens sent in
        reserve.mint(address(callback), 5);

        vm.prank(address(teller));
        vm.expectRevert(err);
        callback.callback(regBond, 10, 10);

        /// Case 3: Exact number of tokens claimed, should work
        vm.prank(address(teller));
        callback.callback(regBond, 5, 5);

        (uint256 quote, uint256 payout) = callback.amountsForMarket(regBond);

        assertEq(quote, 5);
        assertEq(payout, 5);

        /// Case 4: More tokens sent than claimed, should work
        /// Will allow a subsequent caller to pay less than they should
        /// This realistically shouldn't happen since the callback function is whitelisted
        reserve.mint(address(callback), 20);

        vm.prank(address(teller));
        callback.callback(regBond, 10, 10);

        (quote, payout) = callback.amountsForMarket(regBond);

        assertEq(quote, 15);
        assertEq(payout, 15);
    }

    function testCorrectness_OnlyWhitelistedMarketsCanCallback() public {
        // Mint tokens to callback to simulate deposit from teller
        reserve.mint(address(callback), 10);

        // Get balance of OHM in teller to start
        uint256 oldTellerBal = ohm.balanceOf(address(teller));

        // Attempt callback from teller for non-whitelisted bond, expect to fail
        bytes memory err = abi.encodeWithSignature(
            "Callback_MarketNotSupported(uint256)",
            nonWhitelistedBond
        );
        vm.prank(address(teller));
        vm.expectRevert(err);
        callback.callback(nonWhitelistedBond, 10, 10);

        // Check teller balance of OHM is still the same
        uint256 newTellerBal = ohm.balanceOf(address(teller));
        assertEq(newTellerBal, oldTellerBal);

        // Attempt callback from teller on whitelisted market, expect to succeed
        vm.prank(address(teller));
        callback.callback(regBond, 10, 10);

        // Check teller balance is updated
        newTellerBal = ohm.balanceOf(address(teller));
        assertEq(newTellerBal, oldTellerBal + 10);

        // Change the market to not be whitelisted and expect revert
        vm.prank(policy);
        callback.blacklist(address(teller), regBond);

        err = abi.encodeWithSignature("Callback_MarketNotSupported(uint256)", regBond);
        vm.prank(address(teller));
        vm.expectRevert(err);
        callback.callback(regBond, 10, 10);
    }

    // =========  ADMIN TESTS ========= //

    /// DONE
    /// [X] whitelist
    /// [X] blacklist
    /// [X] setOperator
    /// [X] batchToTreasury

    function testCorrectness_whitelist() public {
        // Create two new markets to test whitelist functionality
        uint256 wlOne = createMarket(reserve, ohm, 0, 1, 3);
        uint256 wlTwo = createMarket(reserve, ohm, 0, 1, 3);

        // Attempt to whitelist a market as a non-approved address, expect revert
        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("callback_whitelist")
        );
        vm.prank(alice);
        vm.expectRevert(err);
        callback.whitelist(address(teller), wlOne);

        // Whitelist the first bond market from the policy address
        vm.prank(policy);
        callback.whitelist(address(teller), wlOne);

        // Check whitelist is applied
        assert(callback.approvedMarkets(address(teller), wlOne));

        // Whitelist the second bond market from the operator address
        vm.prank(address(operator));
        callback.whitelist(address(teller), wlTwo);

        // Check whitelist is applied
        assert(callback.approvedMarkets(address(teller), wlTwo));
    }

    function testCorrectness_blacklist() public {
        // Create two new markets to test whitelist functionality
        uint256 wlOne = createMarket(reserve, ohm, 0, 1, 3);

        // Whitelist the bond market from the policy address
        vm.prank(policy);
        callback.whitelist(address(teller), wlOne);

        // Check whitelist is applied
        assert(callback.approvedMarkets(address(teller), wlOne));

        // Remove the market from the whitelist
        vm.prank(policy);
        callback.blacklist(address(teller), wlOne);

        // Check whitelist is applied
        assert(!callback.approvedMarkets(address(teller), wlOne));
    }

    function testCorrectness_setOperator() public {
        /// Attempt to set operator contract to zero address and expect revert
        bytes memory err = abi.encodeWithSignature("Callback_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(guardian);
        callback.setOperator(Operator(address(0)));

        /// Update the operator as guardian
        vm.prank(guardian);
        callback.setOperator(Operator(alice));

        /// Check that the operator contract has been set
        assertEq(address(callback.operator()), alice);
    }

    function testCorrectness_batchToTreasury() public {
        /// Create an extra market with the other token as the quote token
        uint256 otherBond = createMarket(other, ohm, 2, 1, 5);

        /// Whitelist new market on the callback
        vm.prank(policy);
        callback.whitelist(address(teller), otherBond);

        /// Store the initial balances of the treasury
        uint256[2] memory startBalances = [
            reserve.balanceOf(address(treasury)),
            other.balanceOf(address(treasury))
        ];

        /// Send other tokens and reserve tokens to callback to mimic bond purchase
        reserve.mint(address(callback), 30);
        other.mint(address(callback), 10);

        /// Call the callback function from the teller to payout the purchases
        vm.prank(address(teller));
        callback.callback(regBond, 30, 1);

        vm.prank(address(teller));
        callback.callback(otherBond, 10, 200);

        /// Check the balance of the callback and ensure it's updated
        assertEq(reserve.balanceOf(address(callback)), 30);
        assertEq(other.balanceOf(address(callback)), 10);

        /// Call batch to treasury with each token separately
        ERC20[] memory tokens = new ERC20[](1);
        tokens[0] = reserve;

        /// Try to call batch to treasury as non-policy, expect revert
        {
            bytes memory err = abi.encodeWithSelector(
                ROLESv1.ROLES_RequireRole.selector,
                bytes32("callback_admin")
            );
            vm.prank(alice);
            vm.expectRevert(err);
            callback.batchToTreasury(tokens);
        }

        /// Call batch to treasury as guardian
        vm.prank(guardian);
        callback.batchToTreasury(tokens);

        /// Expect the reserve balance of the callback and treasury to be updated
        assertEq(reserve.balanceOf(address(callback)), 0);
        assertEq(reserve.balanceOf(address(treasury)), startBalances[0] + 30);

        /// Test batch to treasury with the other token
        tokens[0] = other;

        /// Call batch to treasury as guardian
        vm.prank(guardian);
        callback.batchToTreasury(tokens);

        /// Expect the other balance of the callback and treasury to be updated
        assertEq(other.balanceOf(address(callback)), 0);
        assertEq(other.balanceOf(address(treasury)), startBalances[1] + 10);

        /// Try with both tokens at once now

        /// Store updated treasury balances
        startBalances = [reserve.balanceOf(address(treasury)), other.balanceOf(address(treasury))];

        /// Send other tokens and reserve tokens to callback to mimic bond purchase
        reserve.mint(address(callback), 30);
        other.mint(address(callback), 10);

        /// Call the callback function from the teller to payout the purchases
        vm.prank(address(teller));
        callback.callback(regBond, 30, 1);

        vm.prank(address(teller));
        callback.callback(otherBond, 10, 200);

        /// Check that the callback balances are updated again
        assertEq(reserve.balanceOf(address(callback)), 30);
        assertEq(other.balanceOf(address(callback)), 10);

        /// Call batch to treasury with both tokens
        tokens = new ERC20[](2);
        tokens[0] = reserve;
        tokens[1] = other;

        vm.prank(guardian);
        callback.batchToTreasury(tokens);

        /// Expect the reserve balance of the callback and treasury to be updated
        assertEq(reserve.balanceOf(address(callback)), 0);
        assertEq(reserve.balanceOf(address(treasury)), startBalances[0] + 30);

        /// Expect the other balance of the callback and treasury to be updated
        assertEq(other.balanceOf(address(callback)), 0);
        assertEq(other.balanceOf(address(treasury)), startBalances[1] + 10);
    }

    // =========  VIEW TESTS ========= //

    /// DONE
    /// [X] amountsForMarket

    function testCorrectness_amountsForMarket() public {
        // Mint tokens to callback to simulate deposit from teller
        reserve.mint(address(callback), 10);

        // Check that the amounts for market doesn't reflect tokens transferred in tokens
        (uint256 oldQuoteAmount, uint256 oldPayoutAmount) = callback.amountsForMarket(regBond);
        assertEq(oldQuoteAmount, 0);
        assertEq(oldPayoutAmount, 0);

        // Attempt callback from teller after whitelist, expect to succeed
        vm.prank(address(teller));
        callback.callback(regBond, 10, 10);

        // Check amounts are updated after callback
        (uint256 newQuoteAmount, uint256 newPayoutAmount) = callback.amountsForMarket(regBond);
        assertEq(newQuoteAmount, 10);
        assertEq(newPayoutAmount, 10);
    }
}
