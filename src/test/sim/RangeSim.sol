// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {BondFixedTermSDA} from "test/lib/bonds/BondFixedTermSDA.sol";
import {BondAggregator} from "test/lib/bonds/BondAggregator.sol";
import {BondFixedTermTeller} from "test/lib/bonds/BondFixedTermTeller.sol";
import {RolesAuthority, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import {IBondSDA} from "interfaces/IBondSDA.sol";
import {IBondAggregator} from "interfaces/IBondAggregator.sol";

import {ZuniswapV2Factory} from "test/lib/zuniswapv2/ZuniswapV2Factory.sol";
import {ZuniswapV2Pair} from "test/lib/zuniswapv2/ZuniswapV2Pair.sol";
import {ZuniswapV2Library} from "test/lib/zuniswapv2/ZuniswapV2Library.sol";
import {ZuniswapV2Router} from "test/lib/zuniswapv2/ZuniswapV2Router.sol";
import {MathLibrary} from "test/lib/zuniswapv2/libraries/Math.sol";

import "src/Kernel.sol";
import {OlympusPrice} from "modules/PRICE/OlympusPrice.sol";
import {OlympusRange} from "modules/RANGE/OlympusRange.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusInstructions} from "modules/INSTR/OlympusInstructions.sol";
import {OlympusVotes} from "modules/VOTES/OlympusVotes.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";

import {Operator} from "policies/Operator.sol";
import {OlympusHeart} from "policies/Heart.sol";
import {BondCallback} from "policies/BondCallback.sol";
import {OlympusPriceConfig} from "policies/PriceConfig.sol";
import {MockPriceFeed} from "test/mocks/MockPriceFeed.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";
import {FullMath} from "libraries/FullMath.sol";

library SimIO {
    Vm internal constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    function _loadData(
        string memory script,
        uint32 seed,
        string memory path
    ) internal returns (bytes memory response) {
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        inputs[2] = string(
            bytes.concat(
                "./src/test/sim/shell/",
                bytes(script),
                " ",
                bytes(vm.toString(uint256(seed))),
                " ",
                bytes(path),
                ""
            )
        );
        response = vm.ffi(inputs);
    }

    struct Params {
        uint32 key;
        uint32 maxLiqRatio;
        uint32 reserveFactor;
        uint32 cushionFactor;
        uint32 wallSpread;
        uint32 cushionSpread;
        bool dynamicRR;
    }

    function loadParams(uint32 seed) external returns (Params[] memory params) {
        string memory script = "loadParams.sh";
        string memory path = "./src/test/sim/in/params.json";
        bytes memory res = _loadData(script, seed, path);
        params = abi.decode(res, (Params[]));
    }

    struct Netflow {
        uint32 key;
        uint32 epoch;
        int256 netflow;
    }

    function loadNetflows(uint32 seed) external returns (Netflow[] memory netflows) {
        string memory script = "loadNetflows.sh";
        string memory path = "./src/test/sim/in/netflows.json";
        bytes memory res = _loadData(script, seed, path);
        netflows = abi.decode(res, (Netflow[]));
    }

    struct Result {
        uint32 epoch;
        bool rebalanced;
        uint256 marketCap;
        uint256 price;
        uint256 reserves;
        uint256 liqRatio;
        uint256 supply;
        uint256 lowCapacity;
        uint256 highCapacity;
        uint256 lowWall;
        uint256 highWall;
        uint256 lowCushion;
        uint256 highCushion;
    }

    function writeResults(
        uint32 seed,
        uint32 key,
        Result[] memory results
    ) external {
        string memory path = string(
            bytes.concat(
                "./src/test/sim/out/results-",
                bytes(vm.toString(uint256(seed))),
                "-",
                bytes(vm.toString(uint256(key))),
                ".json",
                ""
            )
        );
        vm.writeLine(path, "[");
        bytes memory data;
        uint256 len = results.length;
        for (uint256 i; i < len; ) {
            data = "";
            data = bytes.concat(
                data,
                '{"seed": ',
                bytes(vm.toString(uint256(seed))),
                ', "key": ',
                bytes(vm.toString(uint256(key))),
                ', "epoch": ',
                bytes(vm.toString(uint256(results[i].epoch))),
                ', "marketCap": ',
                bytes(vm.toString(results[i].marketCap)),
                ', "price": ',
                bytes(vm.toString(results[i].price)),
                ', "reserves": ',
                bytes(vm.toString(results[i].reserves)),
                ', "liqRatio": ',
                bytes(vm.toString(results[i].liqRatio))
            );
            data = bytes.concat(
                data,
                ', "supply": ',
                bytes(vm.toString(results[i].supply)),
                ', "lowCapacity": ',
                bytes(vm.toString(results[i].lowCapacity)),
                ', "highCapacity": ',
                bytes(vm.toString(results[i].highCapacity)),
                ', "lowWall": ',
                bytes(vm.toString(results[i].lowWall)),
                ', "highWall": ',
                bytes(vm.toString(results[i].highWall)),
                ', "lowCushion": ',
                bytes(vm.toString(results[i].lowCushion)),
                ', "highCushion": ',
                bytes(vm.toString(results[i].highCushion)),
                "}"
            );
            if (i < len - 1) {
                data = bytes.concat(data, ",");
            }
            vm.writeLine(path, string(data));
            unchecked {
                i++;
            }
        }

        vm.writeLine(path, "]");
    }
}

abstract contract RangeSim is Test {
    using FullMath for uint256;

    // =========  RANGE SYSTEM CONTRACTS ========= //

    Kernel public kernel;
    OlympusPrice public price;
    OlympusRange public range;
    OlympusTreasury public treasury;
    OlympusMinter public minter;
    OlympusRoles public roles;

    Operator public operator;
    BondCallback public callback;
    OlympusHeart public heart;
    OlympusPriceConfig public priceConfig;
    RolesAdmin public rolesAdmin;

    mapping(uint32 => SimIO.Params) internal params; // map of sim keys to sim params
    mapping(uint32 => mapping(uint32 => int256)) internal netflows; // map of sim keys to epochs to netflows

    // =========  EXTERNAL CONTRACTS  ========= //

    UserFactory public userCreator;
    address internal market;
    address internal guardian;
    address internal policy;

    RolesAuthority internal auth;
    BondAggregator internal aggregator;
    BondFixedTermTeller internal teller;
    BondFixedTermSDA internal auctioneer;
    MockOhm internal ohm;
    MockERC20 internal reserve;
    ZuniswapV2Factory internal lpFactory;
    ZuniswapV2Pair internal pool;
    ZuniswapV2Router internal router;
    MockPriceFeed internal ohmEthPriceFeed;
    MockPriceFeed internal reserveEthPriceFeed;

    // =========  SIMULATION VARIABLES ========= //

    /// @notice Determines which data is pulled from the input files and allows writing results to compare against the same seed.
    /// @dev This is set dynamically by the test generator.
    function SEED() internal pure virtual returns (uint32);

    /// @dev Set the below variables in .env file.

    /// @notice Number of sims to perform with the seed. It should match the number of keys.
    uint32 internal KEYS;

    /// @notice Number of epochs to run each simulation for.
    uint32 internal EPOCHS;

    /// @notice Duration of an epoch in seconds (real-time)
    uint32 internal EPOCH_DURATION;

    /// @notice Number of epochs between rebalancing the liquidity pool
    uint32 internal REBALANCE_FREQUENCY;

    /// @notice Max percent of treasury to use for rebalancing liquidity
    uint32 internal MAX_OUTFLOW_RATE;

    /* ========== SETUP ========== */

    function setUp() public {
        // Deploy dependencies and setup users for simulation

        // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch) to avoid weird time issues
        vm.warp(51 * 365 * 24 * 60 * 60);

        // Set simulation variables from environment
        KEYS = uint32(vm.envUint("KEYS"));
        EPOCHS = uint32(vm.envUint("EPOCHS"));
        EPOCH_DURATION = uint32(vm.envUint("EPOCH_DURATION"));
        REBALANCE_FREQUENCY = uint32(vm.envUint("REBALANCE_FREQUENCY"));
        MAX_OUTFLOW_RATE = uint32(vm.envUint("MAX_OUTFLOW_RATE"));

        // Create accounts for sim
        userCreator = new UserFactory();
        address[] memory users = userCreator.create(3);
        market = users[0];
        guardian = users[1];
        policy = users[2];

        {
            // Deploy bond system

            auth = new RolesAuthority(guardian, Authority(address(0)));

            // Deploy the bond system
            aggregator = new BondAggregator(guardian, auth);
            teller = new BondFixedTermTeller(guardian, aggregator, guardian, auth);
            auctioneer = new BondFixedTermSDA(teller, aggregator, guardian, auth);

            // Register auctioneer on the bond system
            vm.prank(guardian);
            aggregator.registerAuctioneer(auctioneer);
        }

        {
            // Deploy mock tokens and price feeds
            reserve = new MockERC20("Reserve", "RSV", 18); // deploying reserve before ohm in the broader context of this file means it will have a smaller address and therefore will be token0 in the LP pool
            ohm = new MockOhm("Olympus", "OHM", 9);
            require(address(reserve) < address(ohm)); // ensure reserve is token0 in the LP pool

            ohmEthPriceFeed = new MockPriceFeed();
            ohmEthPriceFeed.setDecimals(18);

            reserveEthPriceFeed = new MockPriceFeed();
            reserveEthPriceFeed.setDecimals(18);

            // Initialize price feeds

            // Set reserveEthPriceFeed to $1000 constant for the sim, changes will be reflected in the ohmEthPriceFeed
            reserveEthPriceFeed.setLatestAnswer(int256(1e15));
            reserveEthPriceFeed.setTimestamp(block.timestamp);

            // ohmEthPriceFeed is the price passed in to the sim, divided by 1000
            ohmEthPriceFeed.setLatestAnswer(int256(vm.envUint("PRICE") / 1e3));
            ohmEthPriceFeed.setTimestamp(block.timestamp);
        }

        {
            // Deploy ZuniswapV2 and Liquidity Pool
            lpFactory = new ZuniswapV2Factory();
            router = new ZuniswapV2Router(address(lpFactory));

            address poolAddress = lpFactory.createPair(address(reserve), address(ohm));
            pool = ZuniswapV2Pair(poolAddress);
        }

        {
            // Load sim data

            // Load params
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

    function rangeSetup(uint32 key) public {
        // Deploy the range system with the simulation parameters

        // Get the simulation parameters
        SimIO.Params memory _params = params[key];

        {
            /// Deploy kernel
            kernel = new Kernel(); // this contract will be the executor

            /// Deploy modules
            price = new OlympusPrice(
                kernel,
                ohmEthPriceFeed,
                uint48(24 hours),
                reserveEthPriceFeed,
                uint48(24 hours),
                uint48(vm.envUint("EPOCH_DURATION")),
                uint48(vm.envUint("MA_DURATION")),
                10 * 1e18 // TODO placeholder for liquid backing
            );
            range = new OlympusRange(
                kernel,
                ERC20(ohm), ERC20(reserve),
                vm.envUint("THRESHOLD_FACTOR"),
                uint256(_params.cushionSpread),
                uint256(_params.wallSpread)
            );
            treasury = new OlympusTreasury(kernel);
            minter = new OlympusMinter(kernel, address(ohm));
            roles = new OlympusRoles(kernel);
        }

        {
            /// Deploy bond callback
            callback = new BondCallback(kernel, IBondAggregator(address(aggregator)), ohm);

            /// Deploy operator
            operator = new Operator(
                kernel,
                IBondSDA(address(auctioneer)),
                callback,
                [ERC20(ohm), ERC20(reserve)],
                [
                    _params.cushionFactor, // cushionFactor
                    uint32(vm.envUint("CUSHION_DURATION")), // duration
                    uint32(vm.envUint("CUSHION_DEBT_BUFFER")), // debtBuffer
                    uint32(vm.envUint("CUSHION_DEPOSIT_INTERVAL")), // depositInterval
                    uint32(_params.reserveFactor), // reserveFactor
                    uint32(vm.envUint("REGEN_WAIT")), // regenWait
                    uint32(vm.envUint("REGEN_THRESHOLD")), // regenThreshold
                    uint32(vm.envUint("REGEN_OBSERVE")) // regenObserve
                    // uint32(vm.envUint("EPOCH_DURATION")) // observationFrequency
                ]
            );

            // Deploy PriceConfig
            priceConfig = new OlympusPriceConfig(kernel);

            // Deploy Heart
            heart = new OlympusHeart(
                kernel,
                operator,
                reserve,
                uint256(0) // no keeper rewards for sim
            );

            /// Deploy RolesAdmin
            rolesAdmin = new RolesAdmin(kernel);
        }

        {
            // Initialize kernel

            // Install modules
            kernel.executeAction(Actions.InstallModule, address(price));
            kernel.executeAction(Actions.InstallModule, address(range));
            kernel.executeAction(Actions.InstallModule, address(treasury));
            kernel.executeAction(Actions.InstallModule, address(minter));
            kernel.executeAction(Actions.InstallModule, address(roles));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(operator));
            kernel.executeAction(Actions.ActivatePolicy, address(callback));
            kernel.executeAction(Actions.ActivatePolicy, address(heart));
            kernel.executeAction(Actions.ActivatePolicy, address(priceConfig));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }
        {
            // Configure access control

            // Operator roles
            rolesAdmin.grantRole("operator_operate", address(heart));
            rolesAdmin.grantRole("operator_operate", guardian);
            rolesAdmin.grantRole("operator_reporter", address(callback));
            rolesAdmin.grantRole("operator_policy", policy);
            rolesAdmin.grantRole("operator_admin", guardian);

            // Bond callback roles
            rolesAdmin.grantRole("callback_whitelist", address(operator));
            rolesAdmin.grantRole("callback_whitelist", guardian);
            rolesAdmin.grantRole("callback_admin", guardian);

            // Heart roles
            rolesAdmin.grantRole("heart_admin", guardian);

            // PriceConfig roles
            rolesAdmin.grantRole("price_admin", guardian);
        }

        {
            // Set initial supply and liquidity balances
            uint256 initialSupply = vm.envUint("SUPPLY");
            uint256 liquidityReserves = vm.envUint("LIQUIDITY");
            uint256 treasuryReserves = vm.envUint("RESERVES");
            uint256 initialPrice = vm.envUint("INITIAL_PRICE");

            // Mint reserves + reserve liquidity to treasury
            reserve.mint(address(treasury), treasuryReserves + liquidityReserves);

            // Mint equivalent OHM to treasury for to provide as liquidity
            uint256 liquidityOhm = liquidityReserves.mulDiv(1e18 * 1e9, initialPrice * 1e18);
            ohm.mint(address(treasury), liquidityOhm);

            // Approve the liquidity pool for both tokens and deposit
            vm.startPrank(address(treasury));
            ohm.approve(address(router), type(uint256).max);
            reserve.approve(address(router), type(uint256).max);
            router.addLiquidity(
                address(reserve),
                address(ohm),
                liquidityReserves,
                liquidityOhm,
                liquidityReserves,
                liquidityOhm,
                address(treasury)
            );
            vm.stopPrank();

            // Get the difference between initial supply and OHM in LP, mint to the market
            uint256 supplyDiff = initialSupply - liquidityOhm;
            ohm.mint(market, supplyDiff);

            // Mint large amount of reserves to the market
            reserve.mint(market, 100_000_000_000 * 1e18);

            // Approve the Operator, Teller, and Router for the market with both tokens
            vm.startPrank(market);
            ohm.approve(address(operator), type(uint256).max);
            reserve.approve(address(operator), type(uint256).max);
            ohm.approve(address(teller), type(uint256).max);
            reserve.approve(address(teller), type(uint256).max);
            ohm.approve(address(router), type(uint256).max);
            reserve.approve(address(router), type(uint256).max);
            vm.stopPrank();
        }

        {
            // Initialize the system

            // Initialize the price module
            uint256 obs = vm.envUint("MA_DURATION") / vm.envUint("EPOCH_DURATION");
            uint256[] memory priceData = new uint256[](obs);
            uint256 movingAverage = vm.envUint("MOVING_AVERAGE");
            for (uint256 i; i < obs; ) {
                priceData[i] = movingAverage;
                unchecked {
                    i++;
                }
            }

            vm.startPrank(guardian);
            priceConfig.initialize(priceData, uint48(block.timestamp));

            // Set operator on the callback
            callback.setOperator(operator);

            // Initialize Operator
            operator.initialize();

            // Approve the Operator to create bonds with a callback
            auctioneer.setCallbackAuthStatus(address(operator), true);

            vm.stopPrank();
        }
    }

    // =========  SIMULATION HELPER FUNCTIONS ========= //
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
            return 1186;
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

    /// @notice Returns an adjustment percentage for the rebase based on the current price as a percentage with 4 decimals. i.e. 10000 = 1%.
    /// @dev Rebase adjustments based on v1 reward rate controller design
    function getRebaseAdjustment() internal view returns (uint256) {
        // Get current price and price levels
        uint256 currentPrice = price.getCurrentPrice();
        uint256 highWallPrice = range.price(true, true);
        uint256 highCushionPrice = range.price(false, true);
        uint256 lowWallPrice = range.price(true, false);
        uint256 lowCushionPrice = range.price(false, false);
        uint256 backingPrice = reserve.balanceOf(address(treasury)) * 1e9 / ohm.totalSupply();
        uint256 threeXPremiumPrice = backingPrice * 3;

        // Determine rebase adjustment based on price
        if (currentPrice > threeXPremiumPrice) {
            return 1250000;
        } else if (currentPrice > highWallPrice) {
            return 1125000;
        } else if (currentPrice > highCushionPrice) {
            return 1000000;
        } else if (currentPrice > lowCushionPrice) {
            return 1000000;
        } else if (currentPrice > lowWallPrice) {
            return 750000;
        } else if (currentPrice > backingPrice) {
            return 500000;
        } else {
            return 0;
        }
    }

    /// @dev Simulating rebases by minting OHM to the market account (at 80% rate) and the liquidity pool
    function rebase(bool dynamicRR) internal {
        uint256 perc = getRebasePercent();

        // Adjust rebase percent if dynamic reward rate is used
        if (dynamicRR) perc = perc * getRebaseAdjustment() / 1e6;

        // If percent is zero, do nothing
        if (perc == 0) return;

        // Mint OHM to the market account
        vm.startPrank(address(minter));
        ohm.mint(market, (ohm.balanceOf(market) * perc) / 1e6);

        // Mint OHM to the liquidity pool and sync the balances
        uint256 poolBalance = ohm.balanceOf(address(pool));

        ohm.mint(address(pool), (poolBalance * perc) / 1e6);
        vm.stopPrank();

        // Sync the pool balance
        pool.sync();
    }

    function updatePrice() internal {
        // Get current pool price
        uint256 currentPrice = poolPrice();

        // Set new price on feeds and update timestamps
        ohmEthPriceFeed.setLatestAnswer(int256(currentPrice / 1e3));
        ohmEthPriceFeed.setTimestamp(block.timestamp);
        reserveEthPriceFeed.setTimestamp(block.timestamp);
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
            address[] memory path = new address[](2);
            path[0] = address(reserve);
            path[1] = address(ohm);

            /// Get amount out for the reserves to swap
            uint256[] memory amounts = ZuniswapV2Library.getAmountsOut(
                address(lpFactory),
                amount,
                path
            );

            // Execute swap
            vm.prank(market);
            router.swapExactTokensForTokens(amount, amounts[1], path, sender);
        } else {
            // Swap amount of ohm for exact amount of reserves out
            // Create path to swap
            address[] memory path = new address[](2);
            path[0] = address(ohm);
            path[1] = address(reserve);

            uint256[] memory amounts = ZuniswapV2Library.getAmountsIn(
                address(lpFactory),
                amount,
                path
            );

            // Execute swap
            vm.prank(market);
            router.swapTokensForExactTokens(amount, amounts[1], path, sender);
        }

        /// Update price feeds after each swap
        updatePrice();
    }

    /// @notice Returns the price of the token implied by the liquidity pool
    function poolPrice() public view returns (uint256) {
        (uint256 reserveBal, uint256 ohmBal, ) = pool.getReserves();
        return reserveBal.mulDiv(1e18 * 1e9, ohmBal * 1e18);
    }

    /// @notice Returns the amount of token in to swap on the liquidity pool to move the price to a target value
    /// @dev Assumes that the price is in the correct direction for the token being provided. This is to ensure that the units you get back match the token you provide in.
    function amountToTargetPrice(ERC20 tokenIn, uint256 targetPrice)
        internal
        view
        returns (uint256 amountIn)
    {
        // Get existing data from pool
        (uint256 reserveBal, uint256 ohmBal, ) = pool.getReserves();
        uint256 currentPrice = reserveBal.mulDiv(1e18 * 1e9, ohmBal * 1e18);
        uint256 invariant = reserveBal * ohmBal * 1e9; // Multiplying by 1e9 to correct for OHM decimals

        // Compute new pool balance for token in at target price
        uint256 currentBal;
        uint256 newBal;
        if (tokenIn == reserve) {
            require(currentPrice <= targetPrice);
            currentBal = reserveBal;
            newBal = MathLibrary.sqrt(invariant * targetPrice) / 1e9; // Dividing by 1e9 to correct for OHM decimals
        } else {
            require(currentPrice >= targetPrice);
            currentBal = ohmBal;
            newBal = MathLibrary.sqrt(invariant / targetPrice);
        }

        // Compute amount to swap in to reach target price (account for LP fee)
        amountIn = (newBal - currentBal) * 1000 / 997;
    }

    function rebalanceLiquidity(uint32 key) internal {
        // Get current liquidity ratio
        uint256 reservesInTreasury = reserve.balanceOf(address(treasury));
        uint256 reservesInLiquidity = reserve.balanceOf(address(pool));
        uint256 reservesInTotal = reservesInTreasury + reservesInLiquidity;

        uint32 liquidityRatio = uint32((reservesInLiquidity * 1e4) / reservesInTotal);
        console2.log("Current Liq Ratio: ", liquidityRatio);

        // Cache the target ratio and the max ratio
        uint32 targetRatio = uint32(params[key].maxLiqRatio);

        // Compare ratios and calculate swap amount
        // If ratio is too low, sell reserves into the liquidity pool
        // If ratio is too high, buy reserves from the liquidity pool
        // Currently just doing one big atomic swap

        if (liquidityRatio < targetRatio) {
            // Sell reserves into the liquidity pool
            uint256 amountIn = (reservesInTotal * targetRatio) / 1e4 - reservesInLiquidity;
            uint256 maxIn = reservesInTreasury * MAX_OUTFLOW_RATE / 1e4;
            amountIn = amountIn > maxIn ? maxIn : amountIn;
            if (amountIn > price.getCurrentPrice() / 1e9) swap(address(treasury), true, amountIn);
        } else if (liquidityRatio > params[key].maxLiqRatio) {
            // Buy reserves from the liquidity pool
            uint256 amountOut = reservesInLiquidity - (reservesInTotal * targetRatio) / 1e4;
            if (amountOut > price.getCurrentPrice() / 1e9) swap(address(treasury), false, amountOut);
        }

        reservesInTreasury = reserve.balanceOf(address(treasury));
        reservesInLiquidity = reserve.balanceOf(address(pool));
        reservesInTotal = reservesInTreasury + reservesInLiquidity;

        liquidityRatio = uint32((reservesInLiquidity * 1e4) / reservesInTotal);
        console2.log("New Liq Ratio: ", liquidityRatio);
    }

    function marketAction(int256 netflow) internal {
        // Get the net flow for the key and epoch combination
        // int256 netflow = netflows[key][epoch];

        if (netflow == int256(0)) return; // If netflow is 0, no action is needed

        // Positive flows mean reserves are flowing in, negative flows mean reserves are flowing out
        bool reserveIn = netflow > int256(0);
        uint256 flow = reserveIn ? uint256(netflow) : uint256(-netflow);

        // Handle branching scenarios
        // If reserves are flowing in (market is buying OHM)
        if (reserveIn) {
            uint256 wallPrice = range.price(true, true);
            uint256 cushionPrice = range.price(false, true);
            uint256 currentPrice = price.getCurrentPrice();
            while (flow > currentPrice / 1e9) { // If below this amount, swaps will yield 0 OHM, which errors on the liquidity pool
                console2.log("High", flow);
                // Check if the RBS side is active, if not, swap all flow into the liquidity pool
                if (range.active(true)) {
                    // Check price against the upper wall and cushion
                    currentPrice = price.getCurrentPrice();
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
                            console2.log("  Wall swap", capacityInReserve);
                            flow -= capacityInReserve;
                        } else {
                            // If flow is less than capacity, swap the flow at the wall
                            uint256 minAmountOut = operator.getAmountOut(reserve, flow);
                            vm.prank(market);
                            operator.swap(reserve, flow, minAmountOut);
                            console2.log("  Wall swap", flow);
                            flow = 0;
                        }
                    } else if (currentPrice >= cushionPrice) {
                        // Bond against the cushion until it's not a good deal
                        // We assume there is a cushion here since these actions are taking place right after an epoch update
                        uint256 id = range.market(true);
                        if (id != type(uint256).max) {
                            uint256 bondScale = aggregator.marketScale(id);
                            while (
                                currentPrice >=
                                aggregator.marketPrice(id).mulDiv(oracleScale, bondScale * 1e9)
                                && aggregator.isLive(id)
                            ) {
                                uint256 maxBond = aggregator.maxAmountAccepted(id, address(treasury));
                                if (maxBond < 1e18) break;
                                if (maxBond > flow) {
                                    uint256 minAmountOut = aggregator.payoutFor(
                                        flow,
                                        id,
                                        address(treasury)
                                    );
                                    vm.prank(market);
                                    teller.purchase(market, address(treasury), id, flow, minAmountOut);
                                    console2.log("  Bonding", flow);
                                    flow = 0;
                                    break;
                                } else {
                                    uint256 minAmountOut = aggregator.payoutFor(
                                        maxBond,
                                        id,
                                        address(treasury)
                                    );
                                    vm.prank(market);
                                    teller.purchase(
                                        market,
                                        address(treasury),
                                        id,
                                        maxBond,
                                        minAmountOut
                                    );
                                    console2.log("  Bonding", maxBond);
                                    flow -= maxBond;
                                }
                            }
                        }

                        // If there is some flow remaining or no active bond market, swap it in the liquidity pool up to the wall price
                        if (flow > currentPrice / 1e9) {
                            // Get amount that can swapped in the liquidity pool to push price to wall price
                            uint256 maxReserveIn = amountToTargetPrice(reserve, wallPrice);
                            if (flow > maxReserveIn) {
                                // Swap the max amount in the liquidity pool
                                swap(market, true, maxReserveIn);
                                console2.log("  Swap after bonds", maxReserveIn);
                                flow -= maxReserveIn;
                            } else {
                                // Swap the flow in the liquidity pool
                                swap(market, true, flow);
                                console2.log("  Swap after bonds", flow);
                                flow = 0;
                            }
                        }
                    } else {
                        // If the market price is below the cushion price, swap into the liquidity pool up to the wall price
                        // Get amount that can swapped in the liquidity pool to push price to wall price
                        uint256 maxReserveIn = amountToTargetPrice(reserve, wallPrice);
                        if (flow > maxReserveIn) {
                            // Swap the max amount in the liquidity pool
                            swap(market, true, maxReserveIn);
                            console2.log("  Swap in LP", maxReserveIn);
                            flow -= maxReserveIn;
                        } else {
                            // Swap the flow in the liquidity pool
                            swap(market, true, flow);
                            console2.log("  Swap in LP", flow);
                            flow = 0;
                        }
                    }
                } else {
                    // If the RBS side is not active, swap all flow into the liquidity pool
                    swap(market, true, flow);
                    console2.log("  Inactive, Swap in LP", flow);
                    flow = 0;
                }
            }
        } else {
            // If reserves are flowing out (market is selling OHM)
            uint256 wallPrice = range.price(true, false);
            uint256 cushionPrice = range.price(false, false);
            uint256 currentPrice = price.getCurrentPrice();
            while (flow > currentPrice / 1e9) { // If below this amount, swaps will yield 0 OHM, which errors on the liquidity pool
                console2.log("Low", flow);
                // Check if the RBS side is active, if not, swap all flow into the liquidity pool
                if (range.active(false)) {
                    // Check price against the upper wall and cushion
                    currentPrice = price.getCurrentPrice();
                    uint256 oracleScale = 10**uint8(price.decimals());

                    // If the market price is below the wall price, swap at the wall up to its capacity
                    if (currentPrice <= wallPrice) {
                        uint256 capacity = range.capacity(false); // Lower side capacity is in reserves
                        if (flow > capacity) {
                            // If flow is greater than capacity, swap the capacity at the wall
                            uint256 amountIn = capacity.mulDiv(oracleScale * 1e9, wallPrice * 1e18); // Convert to OHM units
                            uint256 minAmountOut = operator.getAmountOut(ohm, amountIn);
                            vm.prank(market);
                            operator.swap(ohm, amountIn, minAmountOut);
                            console2.log("  Wall swap", capacity);
                            flow -= capacity;
                        } else {
                            // If flow is less than capacity, swap the flow at the wall
                            uint256 amountIn = flow.mulDiv(oracleScale * 1e9, wallPrice * 1e18); // Convert to OHM units
                            uint256 minAmountOut = operator.getAmountOut(ohm, amountIn);
                            vm.prank(market);
                            operator.swap(ohm, amountIn, minAmountOut);
                            console2.log("  Wall swap", flow);
                            flow = 0;
                        }
                    } else if (currentPrice <= cushionPrice) {
                        // Bond against the cushion until it's not a good deal
                        // We assume there is a cushion here since these actions are taking place right after an epoch update
                        uint256 id = range.market(false);
                        if (id != type(uint256).max) {
                            uint256 bondScale = aggregator.marketScale(id);
                            console2.log("  Current Price", currentPrice);
                            console2.log("  Bond Price", 10**(price.decimals() * 2) / aggregator.marketPrice(id).mulDiv(oracleScale * 1e9, bondScale));
                            while (
                                currentPrice <=
                                10**(price.decimals() * 2) /
                                    aggregator.marketPrice(id).mulDiv(oracleScale * 1e9, bondScale)
                                && aggregator.isLive(id)
                            ) {
                                uint256 maxBond = aggregator.maxAmountAccepted(id, address(treasury)); // in OHM units
                                uint256 maxPayout = aggregator.payoutFor(maxBond, id, address(treasury)); // in reserve units
                                if (maxPayout < 1e18) break;
                                uint256 bondPrice = aggregator.marketPrice(id);
                                if (maxPayout > flow) {
                                    uint256 amountIn = flow.mulDiv(bondPrice, bondScale); // convert to OHM units
                                    uint256 minAmountOut = aggregator.payoutFor(
                                        amountIn,
                                        id,
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
                                    console2.log("  Bonding", flow);
                                    flow = 0;
                                    break;
                                } else {
                                    // uint256 amountIn = maxPayout.mulDiv(bondPrice, bondScale); // convert to OHM units
                                    // uint256 minAmountOut = aggregator.payoutFor(
                                    //     amountIn,
                                    //     id,
                                    //     address(treasury)
                                    // );
                                    vm.prank(market);
                                    teller.purchase(
                                        market,
                                        address(treasury),
                                        id,
                                        maxBond,
                                        maxPayout
                                    );
                                    console2.log("  Bonding", maxPayout);
                                    flow -= maxPayout;
                                }
                            }
                        }

                        // If there is some flow remaining or no active bond market, swap it in the liquidity pool up to the wall price
                        if (flow > currentPrice / 1e9) {
                            // Get amount that can swapped in the liquidity pool to push price to wall price
                            uint256 maxOhmIn = amountToTargetPrice(ohm, wallPrice);
                            uint256 maxReserveOut = maxOhmIn.mulDiv(wallPrice * 1e18, oracleScale * 1e9); // convert to reserve units
                            if (flow > maxReserveOut) {
                                // Swap the max amount in the liquidity pool
                                swap(market, false, maxReserveOut);
                                console2.log("  Swap after bonds", maxReserveOut);
                                flow -= maxReserveOut;
                            } else {
                                // Swap the flow in the liquidity pool
                                swap(market, false, flow);
                                console2.log("  Swap after bonds", flow);
                                flow = 0;
                            }
                        }
                    } else {
                        // If the market price is below the cushion price, swap into the liquidity pool up to the wall price
                        // Get amount that can swapped in the liquidity pool to push price to wall price
                        uint256 maxOhmIn = amountToTargetPrice(ohm, wallPrice);
                        uint256 maxReserveOut = maxOhmIn.mulDiv(wallPrice * 1e18, oracleScale * 1e9); // convert to reserve units
                        if (flow > maxReserveOut) {
                            // Swap the max amount in the liquidity pool
                            swap(market, false, maxReserveOut);
                            console2.log("  Swap in LP", maxReserveOut);
                            flow -= maxReserveOut;
                        } else {
                            // Swap the flow in the liquidity pool
                            swap(market, false, flow);
                            console2.log("  Swap in LP", flow);
                            flow = 0;
                        }
                    }
                } else {
                    // If the RBS side is not active, swap all flow into the liquidity pool
                    swap(market, false, flow);
                    console2.log("  Inactive, Swap in LP", flow);
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
        OlympusRange.Range memory _range = range.range();

        // Create result struct
        result = SimIO.Result(
            epoch,
            rebalanced,
            marketCap,
            lastPrice,
            reservesInTotal,
            liquidityRatio,
            supply,
            _range.low.capacity,
            _range.high.capacity,
            _range.wall.low.price,
            _range.wall.high.price,
            _range.cushion.low.price,
            _range.cushion.high.price
        );
    }

    // =========  SIMULATION LOGIC ========= //
    function simulate(uint32 key) internal {
        // Deploy a RBS clone for the key
        rangeSetup(key);

        // Initialize variables for tracking status
        
        uint32 step = 1 hours;
        uint32 epochs = EPOCHS; // cache
        uint32 duration = EPOCH_DURATION; // cache
        uint32 rebalance_frequency = REBALANCE_FREQUENCY / duration; // cache
        bool dynamicRR = params[key].dynamicRR; // cache
        SimIO.Result[] memory results = new SimIO.Result[](epochs);
        int256 netflow;
        uint32 lastRebalance;

        uint32 steps = duration / step;
        vm.warp(block.timestamp + duration); // Move forward one epoch to allow beating the heart at the start
        duration = duration / steps;
        // Run simulation
        for (uint32 e; e < epochs; ++e) {
            console2.log("Epoch", e);
            // // 0. Warp time forward
            // vm.warp(block.timestamp + duration);

            // 1. Perform rebase
            rebase(dynamicRR);

            // 2. Perform rebalance
            if (e > lastRebalance + rebalance_frequency) {
                console2.log("Rebalance liquidity");
                rebalanceLiquidity(key);
                lastRebalance = e;
            } 

            netflow = netflows[key][e] / int256(uint256(steps));
            for (uint32 i; i < steps; ++i) {
                // 3. Update price and moving average data from LP pool
                updatePrice();

                // 4. RBS Operations triggered only on the epoch
                if (i == uint32(0)) heart.beat();

                // 5. Implement market actions for net flows
                marketAction(netflow);

                // Warp time forward
                vm.warp(block.timestamp + duration);
            }

            // 6. Store results for output
            results[e] = getResult(e, e == lastRebalance);
        }

        // Write results to output file
        SimIO.writeResults(SEED(), key, results);
    }
}
