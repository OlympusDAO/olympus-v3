// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import {Test, console2} from "@forge-std-1.16.2/Test.sol";
import {stdJson} from "@forge-std-1.16.2/StdJson.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {CCIPBurnMintTokenPool} from "src/policies/bridge/CCIPBurnMintTokenPool.sol";
import {CCIPFeeBudgetLib} from "src/scripts/ops/lib/CCIPFeeBudgetLib.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {Pool} from "@chainlink-ccip-1.6.0/ccip/libraries/Pool.sol";
import {RateLimiter} from "@chainlink-ccip-1.6.0/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@chainlink-ccip-1.6.0/ccip/pools/TokenPool.sol";
import {Router} from "@chainlink-ccip-1.6.0/ccip/Router.sol";

// The meter, the base and the four chain suites share this file: the meter exists only to be
// registered as an off-ramp on the forked router and to time the delivery sequence from inside
// one transaction, and each suite differs from the base by its chain name and fork block.
// forge-lint: disable-start(multi-contract-file)

/// @notice Runs the delivery sequence of a CCIP off-ramp against a token pool inside one
///         transaction and returns the gas of each step: the receiver balance before, the
///         `releaseOrMint` call, the receiver balance after. Registered as an off-ramp of the
///         source chain on the forked router, so that the pool accepts its call as it accepts
///         the live off-ramp's.
contract DeliveryMeter {
    function run(
        IERC20 token_,
        CCIPBurnMintTokenPool pool_,
        Pool.ReleaseOrMintInV1 memory input_
    ) external returns (uint256 gasBefore, uint256 gasRelease, uint256 gasAfter) {
        uint256 g0 = gasleft();
        uint256 balanceBefore = token_.balanceOf(input_.receiver);
        uint256 g1 = gasleft();
        Pool.ReleaseOrMintOutV1 memory out = pool_.releaseOrMint(input_);
        uint256 g2 = gasleft();
        uint256 balanceAfter = token_.balanceOf(input_.receiver);
        uint256 g3 = gasleft();
        // The off-ramp requires the receiver balance to grow by exactly the returned amount
        require(
            balanceAfter - balanceBefore == out.destinationAmount,
            "DeliveryMeter: the balance delta is not the returned amount"
        );
        return (g0 - g1, g1 - g2, g2 - g3);
    }
}

/// @notice Meters the cold cost of the OHM delivery sequence on an EVM burn/mint chain against
///         the live token and module stack of that chain: a fresh `CCIPBurnMintTokenPool`
///         activated in the live Kernel, minting the live OHM through the live MINTR, with the
///         mainnet route configured at the `env.json` limits. The sequence the off-ramp runs,
///         `balanceOf`, `releaseOrMint` (two MINTR calls inside) and `balanceOf`, is timed from
///         inside one transaction by a meter registered as an off-ramp of the mainnet lane on the
///         forked router. Every test call is its own transaction (`isolate = true`), so every
///         account and slot the sequence touches is cold, as on a live delivery. The addresses
///         and the route limits are read from `env.json`; a suite per chain pins the fork block.
/// @dev    The budget the sequence must fit is the OHM `destGasOverhead` of the lane,
///         `CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD`, which Chainlink writes on the fee
///         quoter of the source chain. On a 1.5 or 1.6 lane the off-ramp caps the sequence at
///         that budget; on a 2.0.0 lane the budget is summed into the gas the executor supplies.
abstract contract CCIPBurnMintTokenPoolDeliveryGasForkTestBase is Test {
    using stdJson for string;

    /// @notice The delivered amount, 1 OHM in base units (9 decimals); the rescaling from the
    ///         mainnet pool is the identity, since both tokens carry 9 decimals.
    uint256 internal constant AMOUNT = 1e9;

    // ========== STATE ========== //

    string internal env;
    string internal chain;

    address internal kernel;
    address internal rolesAdmin;
    address internal daoMS;
    address internal ohm;
    address internal rmnProxy;
    address internal router;
    uint64 internal mainnetSelector;
    address internal mainnetPool;
    address internal mainnetOHM;

    CCIPBurnMintTokenPool internal pool;
    DeliveryMeter internal meter;
    address internal admin;
    address internal receiver;

    // ========== SUITE PARAMETERS ========== //

    /// @notice The `env.json` chain name of the burn/mint chain.
    function _chainName() internal pure virtual returns (string memory);

    /// @notice The fork block of the burn/mint chain.
    function _forkBlock() internal pure virtual returns (uint256);

    // ========== SETUP ========== //

    function setUp() public {
        chain = _chainName();
        // The call selects the fork; its id is not needed afterwards
        // forge-lint: disable-next-line(unused-return)
        vm.createSelectFork(chain, _forkBlock());

        // The path is a literal: the tracked env.json and nothing else is read
        // forge-lint: disable-next-line(unsafe-cheatcode)
        env = vm.readFile("./src/scripts/env.json");
        kernel = _envAddress(chain, "olympus.Kernel");
        rolesAdmin = _envAddress(chain, "olympus.policies.RolesAdmin");
        daoMS = _envAddress(chain, "olympus.multisig.dao");
        ohm = _envAddress(chain, "olympus.legacy.OHM");
        rmnProxy = _envAddress(chain, "external.ccip.RMN");
        router = _envAddress(chain, "external.ccip.Router");
        mainnetSelector = SafeCast.encodeUInt64(_envUint("mainnet", "external.ccip.ChainSelector"));
        mainnetPool = _envAddress("mainnet", "olympus.periphery.CCIPLockReleaseTokenPool");
        mainnetOHM = _envAddress("mainnet", "olympus.legacy.OHM");

        vm.label(kernel, "Kernel");
        vm.label(rolesAdmin, "RolesAdmin");
        vm.label(daoMS, "DAO MS");
        vm.label(ohm, "OHM");
        vm.label(rmnProxy, "RMNProxy");
        vm.label(router, "Router");

        admin = makeAddr("admin");
        receiver = makeAddr("receiver");

        // The pool as the rollout deploys it, against the live Kernel, OHM, RMN proxy and router
        pool = new CCIPBurnMintTokenPool(kernel, ohm, rmnProxy, router);
        vm.label(address(pool), "CCIPBurnMintTokenPool");

        // Activation grants the MINTR permissions; the executor is the local DAO MS
        vm.prank(daoMS);
        Kernel(kernel).executeAction(Actions.ActivatePolicy, address(pool));

        // The admin role enables the policy; the roles admin is the local DAO MS
        vm.prank(daoMS);
        RolesAdmin(rolesAdmin).grantRole("admin", admin);
        vm.prank(admin);
        pool.enable("");

        // The mainnet route at the env.json limits, with the live mainnet pool and OHM as the
        // remote side
        string memory routeKey = string.concat(
            ".current.",
            chain,
            ".olympus.config.CCIP.routes.mainnet."
        );
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(mainnetPool);
        TokenPool.ChainUpdate[] memory updates = new TokenPool.ChainUpdate[](1);
        updates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: mainnetSelector,
            remotePoolAddresses: remotePools,
            remoteTokenAddress: abi.encode(mainnetOHM),
            outboundRateLimiterConfig: _rateLimit(string.concat(routeKey, "outboundRateLimit")),
            inboundRateLimiterConfig: _rateLimit(string.concat(routeKey, "inboundRateLimit"))
        });
        pool.applyChainUpdates(new uint64[](0), updates);

        // The meter is registered as an off-ramp of the mainnet lane, beside the live ramps
        meter = new DeliveryMeter();
        vm.label(address(meter), "DeliveryMeter");
        Router.OffRamp[] memory offRampAdds = new Router.OffRamp[](1);
        offRampAdds[0] = Router.OffRamp({
            sourceChainSelector: mainnetSelector,
            offRamp: address(meter)
        });
        vm.prank(Router(router).owner());
        Router(router).applyRampUpdates(
            new Router.OnRamp[](0),
            new Router.OffRamp[](0),
            offRampAdds
        );
    }

    // ========== HELPERS ========== //

    function _envAddress(string memory chain_, string memory key_) internal view returns (address) {
        return env.readAddress(string.concat(".current.", chain_, ".", key_));
    }

    function _envUint(string memory chain_, string memory key_) internal view returns (uint256) {
        return env.readUint(string.concat(".current.", chain_, ".", key_));
    }

    /// @notice Reads a rate limiter configuration of `env.json` (capacity and rate in OHM base
    ///         units, the limiter enabled).
    function _rateLimit(string memory key_) internal view returns (RateLimiter.Config memory) {
        return
            RateLimiter.Config({
                isEnabled: env.readBool(string.concat(key_, ".isEnabled")),
                capacity: SafeCast.encodeUInt128(env.readUint(string.concat(key_, ".capacity"))),
                rate: SafeCast.encodeUInt128(env.readUint(string.concat(key_, ".rate")))
            });
    }

    /// @notice The delivery input as the mainnet lock/release pool produces it for the given
    ///         receiver: the mainnet pool as the source pool, nine decimals as the source pool
    ///         data.
    function _input(address receiver_) internal view returns (Pool.ReleaseOrMintInV1 memory) {
        return
            Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(receiver_),
                remoteChainSelector: mainnetSelector,
                receiver: receiver_,
                amount: AMOUNT,
                localToken: ohm,
                sourcePoolAddress: abi.encode(mainnetPool),
                sourcePoolData: abi.encode(uint8(9)),
                offchainTokenData: ""
            });
    }

    /// @notice Runs the metered sequence in one transaction and logs the breakdown.
    function _meter(string memory label_) internal returns (uint256 total) {
        (uint256 gasBefore, uint256 gasRelease, uint256 gasAfter) = meter.run(
            IERC20(ohm),
            pool,
            _input(receiver)
        );
        total = gasBefore + gasRelease + gasAfter;
        console2.log(string.concat(chain, ": ", label_));
        console2.log("  balanceOf before:", gasBefore);
        console2.log("  releaseOrMint:   ", gasRelease);
        console2.log("  balanceOf after: ", gasAfter);
        console2.log("  sequence total:  ", total);
        console2.log("  budget:          ", uint256(CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD));
    }

    /// @notice The first off-ramp of the mainnet lane registered on the live router.
    function _liveOffRamp() internal view returns (address) {
        Router.OffRamp[] memory offRamps = Router(router).getOffRamps();
        for (uint256 i = 0; i < offRamps.length; ++i) {
            if (
                offRamps[i].sourceChainSelector == mainnetSelector &&
                offRamps[i].offRamp != address(meter)
            ) return offRamps[i].offRamp;
        }
        revert("No live off-ramp of the mainnet lane on the router");
    }

    // ========== TESTS ========== //

    // given the receiver holds no OHM (the operating case: the periphery forwards what it
    //     receives, so its balance slot is zero at the next delivery)
    //   [X] the cold sequence exceeds the 90000 chain default
    //   [X] the cold sequence fits the lane budget the rollout requires
    function test_coldDelivery_givenZeroReceiverBalance_fitsBudget() public {
        assertEq(IERC20(ohm).balanceOf(receiver), 0, "The receiver should start with no OHM");

        uint256 total = _meter("cold delivery, receiver balance zero");

        assertEq(IERC20(ohm).balanceOf(receiver), AMOUNT, "The receiver should hold 1 OHM");
        assertGt(total, 90_000, "The sequence should exceed the 90000 chain default");
        assertLe(
            total,
            CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
            "The sequence should fit the lane budget"
        );
    }

    // given the receiver already holds OHM
    //   [X] the cold sequence fits the lane budget the rollout requires
    function test_coldDelivery_givenNonZeroReceiverBalance_fitsBudget() public {
        // A first delivery, in its own transaction, leaves the balance slot non-zero; its gas is
        // not read
        // forge-lint: disable-next-line(unused-return)
        meter.run(IERC20(ohm), pool, _input(receiver));
        assertEq(IERC20(ohm).balanceOf(receiver), AMOUNT, "The receiver should hold 1 OHM");

        uint256 total = _meter("cold delivery, receiver balance non-zero");

        assertEq(IERC20(ohm).balanceOf(receiver), 2 * AMOUNT, "The receiver should hold 2 OHM");
        assertLe(
            total,
            CCIPFeeBudgetLib.OHM_MIN_DEST_GAS_OVERHEAD,
            "The sequence should fit the lane budget"
        );
    }

    // given the caller is a live off-ramp of the mainnet lane
    //   [X] the pool mints to the receiver
    function test_releaseOrMint_givenLiveOffRamp_mints() public {
        address offRamp = _liveOffRamp();
        vm.label(offRamp, "live off-ramp");

        vm.prank(offRamp);
        Pool.ReleaseOrMintOutV1 memory out = pool.releaseOrMint(_input(receiver));

        assertEq(out.destinationAmount, AMOUNT, "The returned amount should be 1 OHM");
        assertEq(IERC20(ohm).balanceOf(receiver), AMOUNT, "The receiver should hold 1 OHM");
    }
}

/// @notice Arbitrum at a block of 2026-10-16.
contract CCIPBurnMintTokenPoolDeliveryGasForkTest_Arbitrum is
    CCIPBurnMintTokenPoolDeliveryGasForkTestBase
{
    function _chainName() internal pure override returns (string memory) {
        return "arbitrum";
    }

    function _forkBlock() internal pure override returns (uint256) {
        return 515_345_692;
    }
}

/// @notice Optimism at a block of 2026-10-16.
contract CCIPBurnMintTokenPoolDeliveryGasForkTest_Optimism is
    CCIPBurnMintTokenPoolDeliveryGasForkTestBase
{
    function _chainName() internal pure override returns (string memory) {
        return "optimism";
    }

    function _forkBlock() internal pure override returns (uint256) {
        return 158_273_784;
    }
}

/// @notice Base at a block of 2026-10-16.
contract CCIPBurnMintTokenPoolDeliveryGasForkTest_Base is
    CCIPBurnMintTokenPoolDeliveryGasForkTestBase
{
    function _chainName() internal pure override returns (string memory) {
        return "base";
    }

    function _forkBlock() internal pure override returns (uint256) {
        return 52_678_499;
    }
}

/// @notice Berachain at a block of 2026-10-16.
contract CCIPBurnMintTokenPoolDeliveryGasForkTest_Berachain is
    CCIPBurnMintTokenPoolDeliveryGasForkTestBase
{
    function _chainName() internal pure override returns (string memory) {
        return "berachain";
    }

    function _forkBlock() internal pure override returns (uint256) {
        return 27_565_814;
    }
}

// forge-lint: disable-end(multi-contract-file)
