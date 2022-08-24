// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";

import {BondFixedTermCDA} from "test/lib/bonds/BondFixedTermCDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import {ZuniswapV2Factory} from "test/lib/zuniswapv2/ZuniswapV2Factory.sol";
import {ZuniswapV2Pair} from "test/lib/zuniswapv2/ZuniswapV2Pair.sol";
import {ZuniswapV2Library} from "test/lib/zuniswapv2/ZuniswapV2Library.sol";
import {ZuniswapV2Router} from "test/lib/zuniswapv2/ZuniswapV2Router.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE.sol";
import {OlympusRange} from "modules/RANGE.sol";
import {OlympusTreasury} from "modules/TRSRY.sol";
import {OlympusMinter} from "modules/MINTR.sol";
import {OlympusInstructions} from "modules/INSTR.sol";
import {OlympusVotes} from "modules/VOTES.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

library SimIO {
    Vm internal constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    // TODO replace with vm.toString()
    // Some fancy math to convert a uint into a string, courtesy of Provable Things.
    // Updated to work with solc 0.8.0.
    // https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.6.sol
    function _uint2bstr(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return bstr;
    }

    function _loadData(
        string memory script,
        string memory query,
        string memory path
    ) internal returns (bytes memory response) {
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        inputs[2] = string(
            bytes.concat(
                "./src/test/lib/sim/",
                bytes(script),
                " ",
                bytes(query),
                " ",
                bytes(path),
                ""
            )
        );
        bytes memory response = vm.ffi(inputs);
    }

    struct Params {
        uint32 key;
        uint32 maxLiqRatio;
        uint32 reserveFactor;
        uint32 cushionFactor;
        uint32 wallSpread;
        uint32 cushionSpread;
    }

    function loadParams(uint32 seed) external returns (Params[] memory params) {
        string memory script = "loadParams.sh";
        string memory query = string(
            bytes.concat(
                "'[.[] | { key: tonumber(.key | lstrtrim(\"",
                _uint2bstr(uint256(seed)),
                "\")), maxLiqRatio: tonumber(.maxLiqRatio) * 10000, reserveFactor: tonumber(.askFactor) * 10000, cushionFactor: tonumber(.cushionFactor) * 10000, wallSpread: tonumber(.wall) * 10000, cushionSpread: tonumber(.cushion) * 10000 }]'",
                ""
            )
        );
        string memory path = "./src/test/sim/params.json";
        bytes memory res = loadData(query, path);
        params = abi.decode(res, Params[]);
    }

    struct Netflow {
        uint32 key;
        int256 netflow;
    }

    function loadNetflows(uint32 seed) external returns (Netflow[] memory netflows) {
        string memory script = "loadNetflows.sh";
        string memory query = string(
            bytes.concat(
                "'[.[] | { key: tonumber(.key | lstrtrim(\"",
                _uint2bstr(uint256(seed)),
                "\")), netflow: tonumber(.netflow) }]'",
                ""
            )
        );
        string memory path = "./src/test/sim/netflows.json";
        bytes memory res = loadData(query, path);
        netflows = abi.decode(res, Netflow[]);
    }

    // TODO work with R&D to get all the data they need out
    struct Result {
        uint32 epoch;
        bool rebalanced;
        uint256 marketCap;
        uint256 price;
        uint256 reserves;
        uint256 liqRatio;
        uint256 supply;
    }

    function writeResults(
        uint32 seed,
        uint32 key,
        Result[] memory results
    ) external {
        bytes memory data = "[";
        uint256 len = results.length;
        for (uint256 i; i < len; ) {
            if (i > 0) {
                data = bytes.concat(data, ",");
            }
            data = bytes.concat(
                data,
                "{seed: ",
                _uint2bstr(uint256(seed)),
                ", key: ",
                _uint2bstr(uint256(key)),
                ", epoch: ",
                _uint2bstr(uint256(results[i].epoch)),
                ", marketCap: ",
                _uint2bstr(results[i].marketCap),
                ", price: ",
                _uint2bstr(results[i].price),
                ", reserves: ",
                _uint2bstr(results[i].reserves),
                ", liqRatio: ",
                _uint2bstr(results[i].liqRatio),
                ", supply: ",
                _uint2bstr(results[i].supply),
                "}"
            );
            unchecked {
                i++;
            }
        }
        data = bytes.concat(data, "]");
        vm.writeFile("./src/test/sim/results.json", string(data));
    }
}

abstract contract RangeSim is Test {
    using ZuniswapV2Library for ZuniswapV2Pair;
    using FullMath for uint256;

    /* ========== RANGE SYSTEM CONTRACTS ========== */

    Kernel public kernel;
    OlympusPrice public price;
    OlympusRange public range;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    Operator public operator;
    BondCallback public bondCallback;
    Heart public heart;

    mapping(uint32 => SimIO.Params) internal params; // map of sim keys to sim params
    mapping(uint32 => mapping(uint32 => int256)) internal netflows; // map of sim keys to epochs to netflows

    /* ========== EXTERNAL CONTRACTS  ========== */

    UserFactory public userCreator;
    address internal market;
    address internal guardian;
    address internal policy;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermCDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;
    ZuniswapV2Factory internal lpFactory;
    ZuniswapV2Pair internal pool;
    ZuniswapV2Router internal router;

    /* ========== SETUP ========== */

    /// @dev Determines which data is pulled from the input files and allows writing results to compare against the same seed.
    function SEED() internal pure virtual returns (uint32);

    // TODO change these to immutable variables configurd in a constructor from the vm.env variables
    /// @dev Number of sims to perform with the seed. It should match the number of keys.
    function KEYS() internal pure virtual returns (uint32);

    /// @dev Number of epochs to run each simulation for.
    function EPOCHS() internal pure virtual returns (uint32);

    /// @dev Duration of an epoch in seconds (real-time)
    function EPOCH_DURATION() internal pure virtual returns (uint32);

    /// @dev Number of epochs between rebalancing the liquidity pool
    function REBALANCE_FREQUENCY() internal pure virtual returns (uint32);

    function setUp() public {
        // Deploy dependencies and setup users for simulation

        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)
        userCreator = new UserFactory();
        {
            // Deploy bond system
            address[] memory users = userCreator.create(5);
            alice = users[0];
            bob = users[1];
            guardian = users[2];
            policy = users[3];
            heart = users[4];
            auth = new RolesAuthority(guardian, SolmateAuthority(address(0)));

            // Deploy the bond system
            aggregator = new BondAggregator(guardian, auth);
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            auctioneer = new BondFixedTermCDA(teller, aggregator, guardian, auth);

            // Register auctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            // Deploy mock tokens
            ohm = new MockOhm("Olympus", "OHM", 9);
            reserve = new MockERC20("Reserve", "RSV", 18);
        }

        {
            // Deploy ZuniswapV2 and Liquidity Pool
            lpFactory = new ZuniswapV2Factory();
            router = new ZuniswapV2Router(address(lpFactory));

            address poolAddress = lpFactory.createPair(address(reserve), address(ohm));
            pool = ZuniswapV2Pair(poolAddress);

            // TODO add liquidity to the pool based on the initialization variables
        }

        {
            // Load sim data
            SimIO.Params[] memory paramArray = SimIO.loadParams(SEED());
            uint256 paramLen = paramArray.length;
            for (uint256 i; i < paramLen; ) {
                params[paramArray[i].key] = paramArray[i];
                unchecked {
                    i++;
                }
            }

            // Load netflows data
            SimIO.Netflow[] memory netflowArray = SimIO.loadNetflows(SEED());
            uint256 netflowLen = netflowArray.length;
            for (uint256 j; j < netflowLen; ) {
                netflows[netflowArray[j].key][netflowArray[j].epoch] = netflowArray[j].netflow;
                unchecked {
                    j++;
                }
            }
        }
    }

    // struct PriceParams {
    //     uint48 frequency;
    //     uint48 duration;
    //     uint256 startPrice; // TODO: Need to determine what units to provide in
    // }

    // struct OperatorParams {
    //     uint32 cushionFactor;
    //     uint32 cushionDuration;
    //     uint32 cushionDebtBuffer;
    //     uint32 cushionDepositInterval;
    //     uint32 reserveFactor;
    //     uint32 regenWait;
    //     uint32 regenThreshold;
    //     uint32 regenObserve;
    // }

    // struct ReserveParams {
    //     uint256 startReserves; // total start reserves
    //     uint32 reservesInLiquidity; // percent with 2 decimals, i.e. 100 = 1%.
    // }

    // struct RangeParams {
    //     OperatorParams operatorParams;
    //     PriceParams priceParams;
    //     ReserveParams reserveParams;
    // }

    function rangeSetup(uint32 key) public {
        // Deploy the range system with the simulation parameters

        // Get the simulation parameters
        SimIO.Params memory _params = params[key];

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules (some mocks)
            price = new MockPrice(kernel, uint48(8 hours));
            range = new OlympusRange(
                kernel,
                [ERC20(ohm), ERC20(reserve)],
                [uint256(100), uint256(1000), uint256(2000)]
            );
            treasury = new OlympusTreasury(kernel);
            minter = new OlympusMinter(kernel, address(ohm));

            /// Configure mocks
            price.setMovingAverage(100 * 1e18);
            price.setLastPrice(100 * 1e18);
            price.setDecimals(18);
        }

        {
            /// Deploy bond callback
            callback = new BondCallback(kernel, IBondAggregator(address(aggregator)), ohm);

            /// Deploy operator
            operator = new Operator(
                kernel,
                IBondAuctioneer(address(auctioneer)),
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
                ]
            );

            /// Registor operator to create bond markets with a callback
            vm.prank(guardian);
            auctioneer.setCallbackAuthStatus(address(operator), true);
        }

        {
            /// Initialize system and kernel

            /// Install modules
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.InstallModule, address(range));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(minter));

            /// Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(callback));
        }
        {
            /// Configure access control

            /// Operator roles
            kernel.grantRole(toRole("operator_operate"), address(heart));
            kernel.grantRole(toRole("operator_operate"), guardian);
            kernel.grantRole(toRole("operator_reporter"), address(callback));
            kernel.grantRole(toRole("operator_policy"), policy);
            kernel.grantRole(toRole("operator_admin"), guardian);

            /// Bond callback roles
            kernel.grantRole(toRole("callback_whitelist"), address(operator));
            kernel.grantRole(toRole("callback_whitelist"), guardian);
            kernel.grantRole(toRole("callback_admin"), guardian);
        }

        /// Set operator on the callback
        vm.prank(guardian);
        callback.setOperator(operator);

        // Mint tokens to users and treasury for testing
        // TODO move to setup function and mint only to treasury and market account
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
    }

    /* ========== SIMULATION HELPER FUNCTIONS ========== */
    /// @notice Returns the rebase percent per epoch based on supply as a percentage with 4 decimals. i.e. 10000 = 1%.
    /// @dev Values are based on the minimum value for each tier as defined in OIP-18.
    function getRebasePercent() internal view returns (uint256) {
        // Implement the current reward rate framework based on supply
        uint256 supply = ohm.totalSupply();
        if (supply < 1_000_000 * 1e9) {
            return 3058;
        } else if (supply < 10_000_000 * 1e9) {
            return 1587;
        } else if (supply < 100_000_000 * 1e9) {
            return 1183;
        } else if (supply < 1_000_000_000 * 1e9) {
            return 458;
        } else if (supply < 10_000_000_000 * 1e9) {
            return 148;
        } else if (supply < 100_000_000_000 * 1e9) {
            return 39;
        } else if (supply < 1_000_000_000_000 * 1e9) {
            return 19;
        } else {
            return 9;
        }
    }

    /// @dev Simulating rebases by minting OHM to the market account (at 80% rate) and the liquidity pool
    function rebase() internal {
        perc = getRebasePercent();

        // Mint OHM to the market account
        vm.startPrank(address(minter));
        ohm.mint(market, (((ohm.balanceOf(market) * 8) / 10) * perc) / 1e6);

        // Mint OHM to the liquidity pool and sync the balances
        uint256 poolBalance = ohm.balanceOf(address(pool));

        ohm.mint(pool, (poolBalance * perc) / 1e6);
        vm.stopPrank();

        // Sync the pool balance
        pool.sync();
    }

    /// @notice Creates a convenient abstraction on the balancer interface for single swaps between OHM and Reserve
    /// @param sender Account to send the swap from and receive the amount out
    /// @param reserveIn Whether the reserve token is being sent in (true) or received from (false) the swap
    /// @param amount Amount of reserves to get in or out (based on reserveIn)
    /// @dev Ensure tokens are approved on the balancer vault already to avoid allowance errors
    function swap(
        address sender,
        bool reserveIn,
        uint256 amount
    ) internal {
        if (reserveIn) {
            // Swap exact amount of reserves in for amount of OHM we can receive
            // Create path to swap
            address[] calldata path = new address[](2);
            path[0] = address(reserve);
            path[1] = address(ohm);

            /// Get amount out for the reserves to swap
            uint256 minAmountOut = pool.getAmountsOut(address(factory), amount, path);

            // Execute swap
            vm.prank(market);
            router.swapExactTokensForTokens(amount, minAmountOut, path, sender);
        } else {
            // Swap amount of ohm for exact amount of reserves out
            // Create path to swap
            address[] calldata path = new address[](2);
            path[0] = address(ohm);
            path[1] = address(reserve);

            uint256 maxAmountIn = pool.getAmountsIn(address(factory), amount, path);

            // Execute swap
            vm.prank(market);
            router.swapTokensForExactTokens(amount, maxAmountIn, path, sender);
        }
    }

    /// @notice Returns the price of the token implied by the liquidity pool
    function poolPrice() public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves(
            factory,
            address(reserve),
            address(ohm)
        );
        return reserve0.mulDiv(1e18 * 1e9, reserve1 * 1e18);
    }

    /// @notice Returns the amount of token in to swap on the liquidity pool to move the price to a target value
    /// @dev based on the UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade() function: https://github.com/Uniswap/v2-periphery/blob/0335e8f7e1bd1e8d8329fd300aea2ef2f36dd19f/contracts/libraries/UniswapV2LiquidityMathLibrary.sol#L17
    function amountToTargetPrice(ERC20 tokenIn, uint256 targetPrice)
        internal
        view
        returns (uint256 amountIn)
    {
        (uint256 reserve0, uint256 reserve1) = pool.getReserves(
            factory,
            address(reserve),
            address(ohm)
        );
        uint256 currentPrice = reserve0.mulDiv(1e18 * 1e9, reserve1 * 1e18);
        uint256 invariant = reserve0 * reserve1;

        uint256 rightSide;
        if (tokenIn == reserve) {
            rightSide = (reserve0 * 1000) / 997;
        } else {
            rightSide = (reserve1 * 1000) / 997;
            currentPrice = 1e36 / currentPrice;
            targetPrice = 1e36 / targetPrice;
        }

        uint256 leftSide = Math.sqrt((invariant * 1000).mulDiv(currentPrice, targetPrice * 997));

        amountIn = leftSide - rightSide;
    }

    function rebalanceLiquidity(uint32 key) internal {
        // Get current liquidity ratio
        uint256 reservesInTreasury = reserve.balanceOf(address(treasury));
        uint256 reservesInLiquidity = reserve.balanceOf(pool);
        uint256 reservesInTotal = reservesInTreasury + reservesInLiquidity;

        uint32 liquidityRatio = uint32((reservesInLiquidity * 1e4) / reservesInTotal);

        // Get the target ratio
        uint32 targetRatio = uint32(params[key].maxLiquidityRatio);

        // Compare ratios and calculate swap amount
        // If ratio is too low, sell reserves into the liquidity pool
        // If ratio is too high, buy reserves from the liquidity pool
        // Currently just doing one big atomic swap

        if (liquidityRatio < targetRatio) {
            // Sell reserves into the liquidity pool
            uint256 amountIn = (reservesInTotal * targetRatio) / 1e4 - reservesInLiquidity;
            swap(address(treasury), true, amountIn);
        } else if (liquidityRatio > targetRatio) {
            // Buy reserves from the liquidity pool
            uint256 amountOut = reservesInLiquidity - (reservesInTotal * targetRatio) / 1e4;
            swap(address(treasury), false, amountOut);
        }
    }

    function marketAction(uint32 key, uint32 epoch) {
        // Get the net flow for the key and epoch combination
        int256 netflow = netflows[key][epoch];

        if (netflow == 0) return; // If netflow is 0, no action is needed

        // Positive flows mean reserves are flowing in, negative flows mean reserves are flowing out
        bool reserveIn = netflow > 0;
        uint256 flow = reserveIn ? uint256(netflow) : uint256(-1 * netflow);

        // Handle branching scenarios

        // If reserves are flowing in (market is buying OHM)
        if (reserveIn) {
            uint256 wallPrice = range.wall(true);
            uint256 cushionPrice = range.cushion(true);

            while (flow > 0) {
                // Check if the RBS side is active, if not, swap all flow into the liquidity pool
                if (range.active(true)) {
                    // Check price against the upper wall and cushion
                    uint256 currentPrice = price.getCurrentPrice();
                    uint256 oracleScale = 10**(price.decimals());

                    // If the market price is above the wall price, swap at the wall up to its capacity
                    if (currentPrice >= wallPrice) {
                        uint256 capacity = range.capacity(true); // Capacity is in OHM units
                        uint256 capacityInReserve = capacity.mulDiv(
                            wallPrice * 1e18,
                            oracleScale * 1e9
                        ); // Convert capacity to reserves to compare with flow
                        if (flow > capacityInReserve) {
                            // If flow is greater than capacity, swap the capacity at the wall
                            uint256 minAmountOut = operator.getAmountOut(
                                reserve,
                                capacityInReserve
                            );
                            vm.prank(market);
                            operator.swap(reserve, capacityInReserve, minAmountOut);
                            flow -= capacity;
                        } else {
                            // If flow is less than capacity, swap the flow at the wall
                            uint256 minAmountOut = operator.getAmountOut(reserve, flow);
                            vm.prank(market);
                            operator.swap(reserve, flow, minAmountOut);
                            flow = 0;
                        }
                    } else if (currentPrice >= cushionPrice) {
                        // Bond against the cushion until it's not a good deal
                        // We assume there is a cushion here since these actions are taking place right after an epoch update
                        uint256 id = range.market(true);
                        uint256 bondScale = aggregator.marketScale(id);
                        uint256 oracleScale = 10**(price.decimals());
                        while (
                            currentPrice >=
                            aggregator.marketPrice(id).mulDiv(oracleScale, bondScale)
                        ) {
                            uint256 maxBond = aggregator.maxAmountAccepted(id, address(treasury));
                            if (maxBond > flow) {
                                uint256 minAmountOut = aggregator.payoutFor(
                                    id,
                                    flow,
                                    address(treasury)
                                );
                                vm.prank(market);
                                teller.purchase(market, address(treasury), id, flow, minAmountOut);
                                flow = 0;
                                break;
                            } else {
                                uint256 minAmountOut = aggregator.payoutFor(
                                    id,
                                    maxBond,
                                    address(treasury)
                                );
                                vm.prank(market);
                                aggregator.bond(id, address(treasury), maxBond);
                                flow -= maxBond;
                            }
                        }

                        // If there is some flow remaining, swap it in the liquidity pool up to the wall price
                        if (flow > 0) {
                            // Get amount that can swapped in the liquidity pool to push price to wall price
                            uint256 maxSwap = amountToTargetPrice(reserve, wallPrice);
                            if (flow > maxSwap) {
                                // Swap the max amount in the liquidity pool
                                swap(market, true, maxSwap);
                                flow -= maxSwap;
                            } else {
                                // Swap the flow in the liquidity pool
                                swap(market, true, flow);
                                flow = 0;
                            }
                        }
                    } else {
                        // If the market price is below the cushion price, swap into the liquidity pool up to the cushion price
                        // Get amount that can swapped in the liquidity pool to push price to wall price
                        uint256 maxSwap = amountToTargetPrice(reserve, cushionPrice);
                        if (flow > maxSwap) {
                            // Swap the max amount in the liquidity pool
                            swap(market, true, maxSwap);
                            flow -= maxSwap;
                        } else {
                            // Swap the flow in the liquidity pool
                            swap(market, true, flow);
                            flow = 0;
                        }
                    }
                } else {
                    // If the RBS side is not active, swap all flow into the liquidity pool
                    swap(market, true, flow);
                    flow = 0;
                }
            }
        } else {
            // If reserves are flowing out (market is selling OHM)
            uint256 wallPrice = range.wall(false);
            uint256 cushionPrice = range.cushion(false);

            while (flow > 0) {
                // Check if the RBS side is active, if not, swap all flow into the liquidity pool
                if (range.active(false)) {
                    // Check price against the upper wall and cushion
                    uint256 currentPrice = price.getCurrentPrice();
                    uint256 oracleScale = 10**(price.decimals());

                    // If the market price is below the wall price, swap at the wall up to its capacity
                    if (currentPrice <= wallPrice) {
                        uint256 capacity = range.capacity(false); // Lower side capacity is in reserves
                        if (flow > capacity) {
                            // If flow is greater than capacity, swap the capacity at the wall
                            uint256 amountIn = capacity.mulDiv(oracleScale * 1e9, wallPrice * 1e18); // Convert to OHM units
                            uint256 minAmountOut = operator.getAmountOut(ohm, amountIn);
                            vm.prank(market);
                            operator.swap(ohm, amountIn, minAmountOut);
                            flow -= capacity;
                        } else {
                            // If flow is less than capacity, swap the flow at the wall
                            uint256 amountIn = flow.mulDiv(oracleScale * 1e9, wallPrice * 1e18); // Convert to OHM units
                            uint256 minAmountOut = operator.getAmountOut(ohm, amountIn);
                            vm.prank(market);
                            operator.swap(ohm, amountIn, minAmountOut);
                            flow = 0;
                        }
                    } else if (currentPrice <= cushionPrice) {
                        // Bond against the cushion until it's not a good deal
                        // We assume there is a cushion here since these actions are taking place right after an epoch update
                        uint256 id = range.market(false);
                        uint256 bondScale = aggregator.marketScale(id);
                        while (
                            currentPrice >=
                            10**(price.decimals() * 2) /
                                aggregator.marketPrice(id).mulDiv(oracleScale, bondScale)
                        ) {
                            (, , , , , uint256 maxPayout) = auctioneer.getMarketInfoForPurchase(id); // in reserve units
                            if (maxPayout > flow) {
                                uint256 amountIn = flow.mulDiv(bondPrice, bondScale); // convert to OHM units
                                uint256 minAmountOut = aggregator.payoutFor(
                                    id,
                                    flow,
                                    address(treasury)
                                );
                                vm.prank(market);
                                teller.purchase(
                                    market,
                                    address(treasury),
                                    id,
                                    amountIn,
                                    minAmountOut
                                );
                                flow = 0;
                                break;
                            } else {
                                uint256 amountIn = maxPayout.mulDiv(bondPrice, bondScale); // convert to OHM units
                                uint256 minAmountOut = aggregator.payoutFor(
                                    id,
                                    amountIn,
                                    address(treasury)
                                );
                                vm.prank(market);
                                aggregator.bond(id, address(treasury), amountIn);
                                flow -= maxPayout;
                            }
                        }

                        // If there is some flow remaining, swap it in the liquidity pool up to the wall price
                        if (flow > 0) {
                            // Get amount that can swapped in the liquidity pool to push price to wall price
                            uint256 maxSwap = amountToTargetPrice(ohm, wallPrice);
                            if (flow > maxSwap) {
                                // Swap the max amount in the liquidity pool
                                swap(market, false, maxSwap);
                                flow -= maxSwap;
                            } else {
                                // Swap the flow in the liquidity pool
                                swap(market, false, flow);
                                flow = 0;
                            }
                        }
                    } else {
                        // If the market price is below the cushion price, swap into the liquidity pool up to the cushion price
                        // Get amount that can swapped in the liquidity pool to push price to wall price
                        uint256 maxSwap = amountToTargetPrice(ohm, cushionPrice);
                        if (flow > maxSwap) {
                            // Swap the max amount in the liquidity pool
                            swap(market, false, maxSwap);
                            flow -= maxSwap;
                        } else {
                            // Swap the flow in the liquidity pool
                            swap(market, false, flow);
                            flow = 0;
                        }
                    }
                } else {
                    // If the RBS side is not active, swap all flow into the liquidity pool
                    swap(market, false, flow);
                    flow = 0;
                }
            }
        }
    }

    function getResult(uint32 epoch, bool rebalanced)
        internal
        view
        returns (SimIO.Result memory result)
    {
        // Retrieve data from the contracts on current status
        uint256 supply = ohm.totalSupply();
        uint256 lastPrice = price.getLastPrice();
        uint256 marketCap = (supply * lastPrice) / 1e9;
        uint256 reservesInTreasury = reserve.balanceOf(address(treasury));
        uint256 reservesInLiquidity = reserve.balanceOf(address(pool));
        uint256 reservesInTotal = reservesInTreasury + reservesInLiquidity;
        uint256 liquidityRatio = uint256((reservesInLiquidity * 1e4) / reservesInTotal);

        // Create result struct
        SimIO.Result result = SimIO.Result(
            epoch,
            rebalanced,
            marketCap,
            lastPrice,
            reservesInTotal,
            liquidityRatio,
            supply
        );
    }

    /* ========== SIMULATION LOGIC ========== */
    function simulate(uint32 key) internal {
        // Deploy a RBS clone for the key
        rangeSetup(key);

        // Initialize variables for tracking status
        uint32 lastRebalance;
        uint32 epochs = EPOCHS();
        uint32 duration = EPOCH_DURATION();
        SimIO.Result result;
        SimIO.Result[] memory results = new SimIO.Result[](epochs);

        // Run simulation
        for (uint32 e; e < epochs; ) {
            // 0. Warp time forward
            vm.warp(block.timestamp + duration);

            // 1. Perform rebase
            rebase();

            // 2. Update price and moving average data from LP pool
            updatePrice();

            // 3. RBS Operations triggered
            heart.beat();

            // 4. Implement market actions for net flows
            marketAction(key, e);

            // 5. Rebalance liquidity if enough epochs have passed
            // 6. Get results for output
            if (e > lastRebalance + REBALANCE_FREQUENCY()) {
                rebalanceLiquidity(key);
                lastRebalance = e;
                result = getResult(e, true);
            } else {
                result = getResult(e, false);
            }

            // 7. Store results for output
            results[e] = result;

            unchecked {
                e++;
            }
        }

        // Write results to output file
        SimIO.writeResults(SEED(), key, results);
    }
}
