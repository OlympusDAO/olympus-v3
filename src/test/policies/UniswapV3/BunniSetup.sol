// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.15;

import {Test} from "forge-std/Test.sol";
import {ModuleTestFixtureGenerator} from "test/lib/ModuleTestFixtureGenerator.sol";

import "src/Kernel.sol";

// Bophades modules
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusPricev2} from "modules/PRICE/OlympusPrice.v2.sol";
import {PRICEv2} from "modules/PRICE/PRICE.v2.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";

// Submodules
import {BunniPrice} from "modules/PRICE/submodules/feeds/BunniPrice.sol";
import {BunniSupply} from "modules/SPPLY/submodules/BunniSupply.sol";

// Bophades policies
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

// Bunni contracts
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";

// Uniswap V3
import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3Pool} from "test/lib/UniswapV3/UniswapV3Pool.sol";
import {IUniswapV3PoolState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";

contract BunniSetup is Test {
    using ModuleTestFixtureGenerator for OlympusPricev2;
    using ModuleTestFixtureGenerator for OlympusSupply;
    using ModuleTestFixtureGenerator for OlympusTreasury;

    // Keep the max reward low and fee high, so that the capped reward is low
    uint256 public constant HARVEST_REWARD = 1e9;
    uint16 public constant HARVEST_REWARD_FEE = 1000; // 10%
    uint48 public constant HARVEST_FREQUENCY = uint48(24 hours);

    // Bophades contracts
    Kernel public kernel;

    // Bophades modules
    OlympusRoles public ROLES;
    OlympusTreasury public TRSRY;
    OlympusMinter public MINTR;
    OlympusPricev2 public PRICE;
    OlympusSupply public SPPLY;

    // Bophades policies
    BunniManager public bunniManager;
    RolesAdmin public rolesAdmin;

    // Bunni contracts
    BunniHub public bunniHub;
    BunniLens public bunniLens;

    // Uniswap V3
    UniswapV3Factory public uniswapFactory;

    constructor(address ohm_, address gOHM_, address owner, address adminUser) {
        // Perform the setup as the calling contract, so that it can conduct further operations
        vm.startPrank(owner);

        // Deploy kernel
        {
            kernel = new Kernel();
        }

        // Deploy modules
        {
            ROLES = new OlympusRoles(kernel);
            TRSRY = new OlympusTreasury(kernel);
            MINTR = new OlympusMinter(kernel, ohm_);
            PRICE = new OlympusPricev2(kernel, uint8(18), uint32(8 hours));

            address[2] memory tokens = [ohm_, gOHM_];
            SPPLY = new OlympusSupply(kernel, tokens, 0);
        }

        // Deploy the BunniManager policy
        {
            bunniManager = new BunniManager(
                kernel,
                HARVEST_REWARD,
                HARVEST_REWARD_FEE,
                HARVEST_FREQUENCY
            );

            // Deploy Uniswap V3 factory
            uniswapFactory = new UniswapV3Factory();

            // Deploy BunniHub
            bunniHub = new BunniHub(
                uniswapFactory,
                address(bunniManager),
                0 // No protocol fee
            );

            // Deploy BunniLens
            bunniLens = new BunniLens(bunniHub);
        }

        // Deploy the RolesAdmin policy
        {
            rolesAdmin = new RolesAdmin(kernel);
        }

        // Initialize system
        {
            // Install modules
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(PRICE));
            kernel.executeAction(Actions.InstallModule, address(SPPLY));

            // Approve policies
            kernel.executeAction(Actions.ActivatePolicy, address(bunniManager));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Access control
        {
            // BunniManager
            rolesAdmin.grantRole("bunni_admin", adminUser);
        }

        // Everything beyond this is done as the admin user
        vm.stopPrank();

        // Set the BunniHub on the bunniManager policy
        {
            vm.prank(adminUser);
            bunniManager.setBunniLens(address(bunniLens));
        }
    }

    function createWriterPolicies() public returns (address, address, address) {
        // Generate the policies
        address writePRICE = PRICE.generateGodmodeFixture(type(OlympusPricev2).name);
        address writeSPPLY = SPPLY.generateGodmodeFixture(type(OlympusSupply).name);
        address writeTRSRY = TRSRY.generateGodmodeFixture(type(OlympusTreasury).name);

        // Activate the policies
        vm.startPrank(msg.sender);
        kernel.executeAction(Actions.ActivatePolicy, address(writePRICE));
        kernel.executeAction(Actions.ActivatePolicy, address(writeSPPLY));
        kernel.executeAction(Actions.ActivatePolicy, address(writeTRSRY));
        vm.stopPrank();

        return (writePRICE, writeSPPLY, writeTRSRY);
    }

    function createSubmodules(
        address writePRICE,
        address writeSPPLY
    ) public returns (address, address) {
        // PRICE Submodule
        BunniPrice priceSubmoduleBunni = new BunniPrice(PRICE);

        vm.startPrank(writePRICE);
        PRICE.installSubmodule(priceSubmoduleBunni);
        vm.stopPrank();

        // SPPLY Submodule
        BunniSupply supplySubmoduleBunni = new BunniSupply(SPPLY);

        vm.startPrank(writeSPPLY);
        SPPLY.installSubmodule(supplySubmoduleBunni);
        vm.stopPrank();

        return (address(priceSubmoduleBunni), address(supplySubmoduleBunni));
    }

    /// @notice             Creates a Uniswap V3 pool
    ///
    /// @param token0       The first token in the pair
    /// @param token1       The second token in the pair
    /// @param fee          The fee tier of the pool
    /// @param sqrtPriceX96 The initial price of the pool
    /// @return             The address of the pool
    function setUpPool(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) public returns (address) {
        // Create the Uniswap V3 pool
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.createPool(token0, token1, fee));

        // Initialize it
        pool.initialize(sqrtPriceX96);

        return address(pool);
    }

    function mockPoolObservations(
        address pool_,
        uint32 period_,
        int56 tickCumulative0_,
        int56 tickCumulative1_
    ) public {
        // Input
        uint32[] memory observationWindow = new uint32[](2);
        observationWindow[0] = period_;
        observationWindow[1] = 0;

        // Output
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;

        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

        vm.mockCall(
            pool_,
            abi.encodeWithSelector(UniswapV3Pool.observe.selector, observationWindow),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    function mockPoolTick(address pool_, int24 tick_) public {
        vm.mockCall(
            pool_,
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(uint160(0), tick_, uint16(0), uint16(0), uint16(0), uint8(0), true)
        );
    }

    function mockPoolPosition(
        address pool_,
        int24 tickLower_,
        int24 tickUpper_,
        uint128 liquidity_,
        uint256 feeGrowthInside0Last_,
        uint256 feeGrowthInside1Last_,
        uint256 cached0_,
        uint256 cached1_
    ) public {
        vm.mockCall(
            pool_,
            abi.encodeWithSelector(
                IUniswapV3PoolState.positions.selector,
                abi.encodePacked(address(bunniHub), tickLower_, tickUpper_)
            ),
            abi.encode(liquidity_, feeGrowthInside0Last_, feeGrowthInside1Last_, cached0_, cached1_)
        );
    }

    function mockPoolTicks(
        address pool_,
        int24 tick_,
        uint256 feeGrowthOutside0X128_,
        uint256 feeGrowthOutside1X128_
    ) public {
        vm.mockCall(
            pool_,
            abi.encodeWithSelector(IUniswapV3PoolState.ticks.selector, tick_),
            abi.encode(
                uint128(0),
                int128(0),
                feeGrowthOutside0X128_,
                feeGrowthOutside1X128_,
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0)
            )
        );
    }

    function mockPoolFeeGrowthGlobal(
        address pool_,
        uint256 feeGrowthGlobal0X128_,
        uint256 feeGrowthGlobal1X128_
    ) public {
        vm.mockCall(
            pool_,
            abi.encodeWithSelector(IUniswapV3PoolState.feeGrowthGlobal0X128.selector),
            abi.encode(feeGrowthGlobal0X128_)
        );

        vm.mockCall(
            pool_,
            abi.encodeWithSelector(IUniswapV3PoolState.feeGrowthGlobal1X128.selector),
            abi.encode(feeGrowthGlobal1X128_)
        );
    }

    function mockGetPrice(address asset_, uint256 price_) public {
        vm.mockCall(
            address(PRICE),
            abi.encodeWithSignature("getPrice(address)", address(asset_)),
            abi.encode(price_)
        );
    }

    function mockGetPriceZero(address asset_) public {
        bytes memory err = abi.encodeWithSelector(PRICEv2.PRICE_PriceZero.selector, asset_);

        vm.mockCallRevert(
            address(PRICE),
            abi.encodeWithSignature("getPrice(address)", asset_),
            err
        );
    }
}
