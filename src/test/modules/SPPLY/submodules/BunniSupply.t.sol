// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

// Test
import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

// Mocks
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {ComputeAddress} from "test/libraries/ComputeAddress.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Uniswap V3
import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {UniswapV3Pool} from "test/lib/UniswapV3/UniswapV3Pool.sol";
import {SwapRouter} from "test/lib/UniswapV3/SwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {PoolHelper} from "test/policies/UniswapV3/PoolHelper.sol";

// Bophades Modules
import "src/modules/SPPLY/OlympusSupply.sol";

// SPPLY Submodules
import {BunniSupply} from "src/modules/SPPLY/submodules/BunniSupply.sol";

// Bunni external contracts
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {BunniToken} from "src/external/bunni/BunniToken.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {BunniManager} from "policies/UniswapV3/BunniManager.sol";

import {BunniSetup} from "test/policies/UniswapV3/BunniSetup.sol";

contract BunniSupplyTest is Test {
    using FullMath for uint256;

    MockOhm internal ohmToken;
    MockERC20 internal usdcToken;
    MockERC20 internal wethToken;
    MockGohm internal gohmToken;
    address internal ohmAddress;
    address internal usdcAddress;

    BunniSupply internal submoduleBunniSupply;

    BunniSetup internal bunniSetup;
    BunniManager internal bunniManager;
    IUniswapV3Pool internal uniswapPool;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IBunniToken internal poolToken;
    BunniKey internal poolTokenKey;
    UniswapV3Factory internal uniswapFactory;
    SwapRouter internal swapRouter;
    address internal bunniLensAddress;
    address internal poolTokenAddress;

    address writePRICE;
    address writeSPPLY;

    address moduleSPPLY;

    address internal policy;

    UserFactory public userFactory;

    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals
    uint256 internal constant INITIAL_CROSS_CHAIN_SUPPLY = 0; // 0 OHM

    // OHM-USDC Uni V3 pool, based on: 0x893f503fac2ee1e5b78665db23f9c94017aae97d
    // token0: OHM, token1: USDC
    // Current tick: -44579
    uint160 internal constant OHM_USDC_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_0 = -2463052984970;
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_1 = -2463079732370;

    // OHM-wETH Uni V3 pool, based on: 0x88051b0eea095007d3bef21ab287be961f3d8598
    // Current tick: 156194
    uint160 internal constant OHM_WETH_SQRTPRICEX96 = 195181081174522229204497247535278;
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_WETH_TICK_CUMULATIVE_0 = -2463078395000;
    int56 internal constant OHM_WETH_TICK_CUMULATIVE_1 = -2462984678600;
    uint256 internal constant OHM_WETH_RATIO = 164785850452; // OHM per ETH

    uint16 internal constant TWAP_MAX_DEVIATION_BPS = 100; // 1%
    uint32 internal constant TWAP_OBSERVATION_WINDOW = 600; // 10 minutes

    uint8 internal constant PRICE_DECIMALS = 18;

    uint256 internal constant USDC_PRICE = 1 * 10 ** PRICE_DECIMALS;
    uint256 internal constant OHM_PRICE = 115897 * 1e14; // 11.5897 USDC per OHM in 18 decimal places
    uint256 internal constant WETH_PRICE = 2000 * 1e18; // 2000 USDC per WETH in 18 decimal places

    uint256 internal constant OHM_AMOUNT = 100_000e9;
    uint256 internal USDC_AMOUNT = OHM_AMOUNT.mulDiv(OHM_PRICE, 1e18).mulDiv(1e6, 1e9);

    int24 private constant TICK = 887270; // (887272/(500/50))*(500/50)

    uint16 private constant SLIPPAGE_DEFAULT = 100; // 1%

    uint24 private constant POOL_FEE = 500;

    // Events
    event BunniTokenAdded(address token_, address bunniLens_);
    event BunniTokenRemoved(address token_);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohmToken = new MockOhm("Olympus", "OHM", 9);

            // The USDC address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 usdcSalt = ComputeAddress.generateSalt(
                address(ohmToken),
                true,
                type(MockERC20).creationCode,
                abi.encode("USDC", "USDC", 6),
                address(this)
            );
            usdcToken = new MockERC20{salt: usdcSalt}("USDC", "USDC", 6);

            // The WETH address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 wethSalt = ComputeAddress.generateSalt(
                address(ohmToken),
                true,
                type(MockERC20).creationCode,
                abi.encode("Wrapped Ether", "wETH", 18),
                address(this)
            );
            wethToken = new MockERC20{salt: wethSalt}("Wrapped Ether", "wETH", 18);

            // The address of gOHM does not need to be deterministic
            gohmToken = new MockGohm(GOHM_INDEX);

            ohmAddress = address(ohmToken);
            usdcAddress = address(usdcToken);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            policy = users[0];
        }

        // Deploy BunniSetup
        {
            bunniSetup = new BunniSetup(ohmAddress, address(gohmToken), address(this), policy);

            bunniManager = bunniSetup.bunniManager();
            bunniHub = bunniSetup.bunniHub();
            bunniLens = bunniSetup.bunniLens();
            bunniLensAddress = address(bunniLens);
            uniswapFactory = bunniSetup.uniswapFactory();
            swapRouter = new SwapRouter(address(uniswapFactory), address(wethToken));
            moduleSPPLY = address(bunniSetup.SPPLY());
        }

        // Deploy writer policies
        {
            (address writePRICE_, address writeSPPLY_, ) = bunniSetup.createWriterPolicies();

            writePRICE = writePRICE_;
            writeSPPLY = writeSPPLY_;
        }

        // Set up the submodule(s)
        {
            (, address supply_) = bunniSetup.createSubmodules(writePRICE, writeSPPLY);

            submoduleBunniSupply = BunniSupply(supply_);
        }

        // Mock values, to avoid having to set up all of PRICEv2 and submodules
        {
            bunniSetup.mockGetPrice(ohmAddress, OHM_PRICE);
            bunniSetup.mockGetPrice(usdcAddress, USDC_PRICE);
            bunniSetup.mockGetPrice(address(wethToken), WETH_PRICE);
        }

        // Set up the UniV3 pool
        {
            (IUniswapV3Pool pool_, BunniKey memory key_, IBunniToken poolToken_) = _setUpPool(
                ohmAddress,
                usdcAddress,
                OHM_USDC_SQRTPRICEX96,
                OHM_USDC_TICK_CUMULATIVE_0,
                OHM_USDC_TICK_CUMULATIVE_1
            );

            uniswapPool = pool_;
            poolToken = poolToken_;
            poolTokenAddress = address(poolToken_);
            poolTokenKey = key_;
        }

        // Deposit into the pool
        {
            // Mint USDC
            usdcToken.mint(address(bunniSetup.TRSRY()), USDC_AMOUNT);

            // Deposit
            vm.startPrank(policy);
            bunniManager.deposit(
                address(uniswapPool),
                ohmAddress,
                OHM_AMOUNT,
                USDC_AMOUNT,
                SLIPPAGE_DEFAULT
            );
            vm.stopPrank();
        }
    }

    function _getOhmReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        if (key_.pool.token0() == ohmAddress) {
            return reserve0;
        } else {
            return reserve1;
        }
    }

    function _getReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        return (reserve0, reserve1);
    }

    function _expectRevert_invalidBunniToken(address token_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            token_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_invalidBunniLens(address lens_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniLens.selector,
            lens_
        );
        vm.expectRevert(err);
    }

    function _getBunniKey(
        IUniswapV3Pool pool_,
        IBunniToken token_
    ) internal view returns (BunniKey memory) {
        return
            BunniKey({pool: pool_, tickLower: token_.tickLower(), tickUpper: token_.tickUpper()});
    }

    function _setUpPool(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96_,
        int56 sqrtPriceX96Cumulative0_,
        int56 sqrtPriceX96Cumulative1_
    ) internal returns (IUniswapV3Pool, BunniKey memory, IBunniToken) {
        address poolAddress_ = bunniSetup.setUpPool(token0_, token1_, POOL_FEE, sqrtPriceX96_);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress_);

        // Mock observations for the Uniswap V3 pool
        bunniSetup.mockPoolObservations(
            address(pool),
            TWAP_OBSERVATION_WINDOW,
            sqrtPriceX96Cumulative0_,
            sqrtPriceX96Cumulative1_
        );

        // Deploy a pool token
        vm.prank(policy);
        IBunniToken poolToken_ = bunniManager.deployPoolToken(address(pool));

        return (pool, _getBunniKey(pool, poolToken_), poolToken_);
    }

    function _depositIntoPool(
        IUniswapV3Pool uniswapPool_,
        MockERC20 otherToken_,
        uint256 otherAmount_,
        uint256 ohmAmount_
    ) internal {
        // Mint USDC
        otherToken_.mint(address(bunniSetup.TRSRY()), otherAmount_);

        // Deposit
        vm.startPrank(policy);
        bunniManager.deposit(
            address(uniswapPool_),
            ohmAddress,
            ohmAmount_,
            otherAmount_,
            SLIPPAGE_DEFAULT
        );
        vm.stopPrank();
    }

    function _swap(
        IUniswapV3Pool pool_,
        address tokenIn_,
        address tokenOut_,
        address recipient_,
        uint256 amountIn_,
        uint256 token1Token0Price
    ) internal returns (uint256) {
        // Approve transfer
        vm.prank(recipient_);
        IERC20(tokenIn_).approve(address(swapRouter), amountIn_);

        // Get the parameters
        ISwapRouter.ExactInputSingleParams memory params = PoolHelper.getSwapParams(
            pool_,
            tokenIn_,
            tokenOut_,
            amountIn_,
            recipient_,
            token1Token0Price,
            500,
            TICK
        );

        // Perform the swap
        vm.prank(recipient_);
        swapRouter.exactInputSingle(params);

        return params.amountOutMinimum;
    }

    function _mockPoolUnlocked(IUniswapV3Pool pool_, bool unlocked_) internal {
        // Get the current values for slot0
        UniswapV3Pool.Slot0 memory slot0;
        {
            (
                uint160 sqrtPriceX96,
                int24 tick,
                uint16 obsIndex,
                uint16 obsCard,
                uint16 obsCardNext,
                uint8 feeProtocol,

            ) = pool_.slot0();

            slot0 = UniswapV3Pool.Slot0({
                sqrtPriceX96: sqrtPriceX96,
                tick: tick,
                observationIndex: obsIndex,
                observationCardinality: obsCard,
                observationCardinalityNext: obsCardNext,
                feeProtocol: feeProtocol,
                unlocked: unlocked_
            });
        }

        vm.mockCall(
            address(pool_),
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(slot0)
        );
    }

    // =========  TESTS ========= //

    // =========  Module Information ========= //

    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleBunniSupply.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleBunniSupply.PARENT()), "SPPLY");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleBunniSupply.SUBKEYCODE()), "SPPLY.BNI");
    }

    // [X] Constructor
    //  [X] Incorrect parent

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new BunniSupply(Module(newLocations[0]));
    }

    function test_submodule_parent_notSpply_reverts() public {
        // Pass the PRICEv2 module as the parent
        Module modulePrice = bunniSetup.PRICE();

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BunniSupply(modulePrice);
    }

    // =========  getCollateralizedOhm ========= //

    // [X] getCollateralizedOhm

    function test_getCollateralizedOhm() public {
        // Register the pool with the submodule
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    // =========  getProtocolOwnedBorrowableOhm ========= //

    // [X] getProtocolOwnedBorrowableOhm

    function test_getProtocolOwnedBorrowableOhm() public {
        // Register the pool with the submodule
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getProtocolOwnedBorrowableOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityOhm ========= //

    // [X] getProtocolOwnedLiquidityOhm
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens
    //  [X] reverts on TWAP deviation
    //  [X] respects observation window
    //  [X] respects deviation

    function test_getProtocolOwnedLiquidityOhm_noTokens() public {
        // Don't add the token

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), 0);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken() public {
        // There should not be any uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertEq(fee0, 0);
        assertEq(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), ohmReserves);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_uncollectedFeesFuzz(
        uint256 usdcSwapAmount_
    ) public {
        // Swap enough to generate fees, but not enough to trigger a TWAP deviation
        uint256 usdcSwapAmount = uint256(bound(usdcSwapAmount_, 1_000e6, 10_000e6));

        // Swap USDC for OHM
        uint256 swapOneAmountOut;
        {
            // Mint the USDC
            usdcToken.mint(address(this), usdcSwapAmount);

            // Swap
            swapOneAmountOut = _swap(
                uniswapPool,
                usdcAddress,
                ohmAddress,
                address(this),
                usdcSwapAmount,
                OHM_PRICE
            );
        }

        // Swap OHM for USDC
        {
            // Swap
            _swap(uniswapPool, ohmAddress, usdcAddress, address(this), swapOneAmountOut, OHM_PRICE);
        }

        // There should now be uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertGt(fee0, 0);
        assertGt(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, ) = _getReserves(poolTokenKey, bunniLens);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), ohmReserves_ + fee0);
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_observationWindow() public {
        uint32 observationWindow = 500;

        // Update the pool observations
        bunniSetup.mockPoolObservations(
            address(uniswapPool),
            observationWindow,
            OHM_USDC_TICK_CUMULATIVE_0,
            OHM_USDC_TICK_CUMULATIVE_1
        );

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            observationWindow
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (OHM_USDC_TICK_CUMULATIVE_1 - OHM_USDC_TICK_CUMULATIVE_0) /
            int32(observationWindow);

        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6
        assertGt(twapRatio, 0); // Sanity check

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    function test_getProtocolOwnedLiquidityOhm_singleToken_deviationBps() public {
        uint16 deviationBps = 1000; // 10%

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            deviationBps, // Wider deviation
            TWAP_OBSERVATION_WINDOW
        );

        // Mock the pool returning a TWAP that would normally deviate enough to revert
        int56 tickCumulative0_ = -2463052904970;
        int56 tickCumulative1_ = OHM_USDC_TICK_CUMULATIVE_1;
        bunniSetup.mockPoolObservations(
            address(uniswapPool),
            TWAP_OBSERVATION_WINDOW,
            tickCumulative0_,
            tickCumulative1_
        );

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);

        assertEq(submoduleBunniSupply.getProtocolOwnedLiquidityOhm(), ohmReserves);
    }

    function test_getProtocolOwnedLiquidityOhm_multipleToken() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (
            IUniswapV3Pool poolTwo,
            BunniKey memory poolTokenKeyTwo,
            IBunniToken poolTokenTwo
        ) = _setUpPool(
                ohmAddress,
                address(wethToken),
                OHM_WETH_SQRTPRICEX96,
                OHM_WETH_TICK_CUMULATIVE_0,
                OHM_WETH_TICK_CUMULATIVE_1
            );
        _depositIntoPool(poolTwo, wethToken, 10e18, (10e18 * OHM_WETH_RATIO) / 1e18);
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            address(poolTokenTwo),
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of OHM in the pool, which should be consistent with the lens value
        uint256 ohmReserves = _getOhmReserves(poolTokenKey, bunniLens);
        uint256 ohmReservesTwo = _getOhmReserves(poolTokenKeyTwo, bunniLens);

        // Call
        uint256 polo = submoduleBunniSupply.getProtocolOwnedLiquidityOhm();

        assertTrue(polo > 0, "should be non-zero");
        assertEq(polo, ohmReserves + ohmReservesTwo);
    }

    function test_getProtocolOwnedLiquidityOhm_reentrancyReverts() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set the UniV3 pair to be locked, which indicates re-entrancy
        _mockPoolUnlocked(uniswapPool, false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    function test_getProtocolOwnedLiquidityOhm_twapDeviationReverts() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Mock the pool returning a TWAP that deviates enough to revert
        int56 tickCumulative0_ = -2463052904970;
        int56 tickCumulative1_ = OHM_USDC_TICK_CUMULATIVE_1;
        bunniSetup.mockPoolObservations(
            address(uniswapPool),
            TWAP_OBSERVATION_WINDOW,
            tickCumulative0_,
            tickCumulative1_
        );

        // Calculate the expected TWAP price
        // 11436143
        int56 timeWeightedTick = (tickCumulative1_ - tickCumulative0_) /
            int32(TWAP_OBSERVATION_WINDOW);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio by more than TWAP_MAX_DEVIATION_BPS
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityOhm();
    }

    // =========  getProtocolOwnedTreasuryOhm  ========= //

    function test_getProtocolOwnedTreasuryOhm() public {
        // Register the pool with the submodule
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Will always be zero
        assertEq(submoduleBunniSupply.getProtocolOwnedTreasuryOhm(), 0);
    }

    // =========  getProtocolOwnedLiquidityReserves ========= //

    // [X] getProtocolOwnedLiquidityReserves
    //  [X] no tokens
    //  [X] single token
    //  [X] multiple tokens
    //  [X] reverts on TWAP deviation
    //  [X] respects observation window
    //  [X] respects deviation

    function test_getProtocolOwnedLiquidityReserves_noTokens() public {
        // Don't add the token

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 0);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken() public {
        // There should not be any uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertEq(fee0, 0);
        assertEq(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken_uncollectedFeesFuzz(
        uint256 usdcSwapAmount_
    ) public {
        // Swap enough to generate fees, but not enough to trigger a TWAP deviation
        uint256 usdcSwapAmount = uint256(bound(usdcSwapAmount_, 1_000e6, 10_000e6));

        // Swap USDC for OHM
        uint256 swapOneAmountOut;
        {
            // Mint the USDC
            usdcToken.mint(address(this), usdcSwapAmount);

            // Swap
            swapOneAmountOut = _swap(
                uniswapPool,
                usdcAddress,
                ohmAddress,
                address(this),
                usdcSwapAmount,
                OHM_PRICE
            );
        }

        // Swap OHM for USDC
        {
            // Swap
            _swap(uniswapPool, ohmAddress, usdcAddress, address(this), swapOneAmountOut, OHM_PRICE);
        }

        // There should now be uncollected fees
        (uint256 fee0, uint256 fee1) = bunniLens.getUncollectedFees(poolTokenKey);
        assertGt(fee0, 0);
        assertGt(fee1, 0);

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_ + fee0);
        assertEq(reserves[0].balances[1], usdcReserves_ + fee1);

        // Check that the reserves and OHM values are consistent
        assertEq(reserves[0].balances[0], submoduleBunniSupply.getProtocolOwnedLiquidityOhm());
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken_observationWindow() public {
        uint32 observationWindow = 500;

        // Update the pool observations
        bunniSetup.mockPoolObservations(
            address(uniswapPool),
            observationWindow,
            OHM_USDC_TICK_CUMULATIVE_0,
            OHM_USDC_TICK_CUMULATIVE_1
        );

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            observationWindow
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (OHM_USDC_TICK_CUMULATIVE_1 - OHM_USDC_TICK_CUMULATIVE_0) /
            int32(observationWindow);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6
        assertGt(twapRatio, 0); // Sanity check

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
    }

    function test_getProtocolOwnedLiquidityReserves_singleToken_deviationBps() public {
        uint16 deviationBps = 1000; // 10%

        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            deviationBps, // Wider deviation
            TWAP_OBSERVATION_WINDOW
        );

        // Mock the pool returning a TWAP that would normally deviate enough to revert
        // 11436143
        int56 tickCumulative0_ = -2463052904970;
        int56 tickCumulative1_ = OHM_USDC_TICK_CUMULATIVE_1;
        bunniSetup.mockPoolObservations(
            address(uniswapPool),
            TWAP_OBSERVATION_WINDOW,
            tickCumulative0_,
            tickCumulative1_
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 1);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);
    }

    function test_getProtocolOwnedLiquidityReserves_multipleToken() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (
            IUniswapV3Pool poolTwo,
            BunniKey memory poolTokenKeyTwo,
            IBunniToken poolTokenTwo
        ) = _setUpPool(
                ohmAddress,
                address(wethToken),
                OHM_WETH_SQRTPRICEX96,
                OHM_WETH_TICK_CUMULATIVE_0,
                OHM_WETH_TICK_CUMULATIVE_1
            );
        _depositIntoPool(poolTwo, wethToken, 10e18, (10e18 * OHM_WETH_RATIO) / 1e18);
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            address(poolTokenTwo),
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        (uint256 ohmReservesTwo_, uint256 wethReservesTwo_) = _getReserves(
            poolTokenKeyTwo,
            bunniLens
        );

        SPPLYv1.Reserves[] memory reserves = submoduleBunniSupply
            .getProtocolOwnedLiquidityReserves();

        assertEq(reserves.length, 2);

        assertEq(reserves[0].source, poolTokenAddress);
        assertEq(reserves[0].tokens.length, 2);
        assertEq(reserves[0].tokens[0], ohmAddress);
        assertEq(reserves[0].tokens[1], usdcAddress);
        assertEq(reserves[0].balances.length, 2);
        assertEq(reserves[0].balances[0], ohmReserves_);
        assertEq(reserves[0].balances[1], usdcReserves_);

        assertEq(reserves[1].source, address(poolTokenTwo));
        assertEq(reserves[1].tokens.length, 2);
        assertEq(reserves[1].tokens[0], ohmAddress);
        assertEq(reserves[1].tokens[1], address(wethToken));
        assertEq(reserves[1].balances.length, 2);
        assertEq(reserves[1].balances[0], ohmReservesTwo_);
        assertEq(reserves[1].balances[1], wethReservesTwo_);
    }

    function test_getProtocolOwnedLiquidityReserves_reentrancyReverts() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set the UniV3 pair to be locked, which indicates re-entrancy
        _mockPoolUnlocked(uniswapPool, false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
    }

    function test_getProtocolOwnedLiquidityReserves_twapDeviationReverts() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Mock the pool returning a TWAP that deviates enough to revert
        int56 tickCumulative0_ = -2416639538393;
        int56 tickCumulative1_ = -2416640880953;
        bunniSetup.mockPoolObservations(
            address(uniswapPool),
            TWAP_OBSERVATION_WINDOW,
            tickCumulative0_,
            tickCumulative1_
        );

        // Calculate the expected TWAP price
        int56 timeWeightedTick = (tickCumulative1_ - tickCumulative0_) /
            int32(TWAP_OBSERVATION_WINDOW);
        uint256 twapRatio = OracleLibrary.getQuoteAtTick(
            int24(timeWeightedTick),
            uint128(10 ** 9), // token0 (OHM) decimals
            ohmAddress,
            usdcAddress
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniSupply.getProtocolOwnedLiquidityReserves();
    }

    // =========  addBunniToken ========= //

    // [X] addBunniToken
    //  [X] reverts if not parent
    //  [X] reverts if token is address(0)
    //  [X] reverts if lens is address(0)
    //  [X] reverts if token already added
    //  [X] reverts if invalid token
    //  [X] reverts if invalid lens
    //  [X] reverts if token and lens hub addresses don't match
    //  [X] reverts in TWAP deviation is invalid
    //  [X] reverts if observation window is invalid
    //  [X] single token
    //  [X] multiple tokens, single lens
    //  [X] multiple tokens, multiple lenses

    function test_addBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writeSPPLY)
        );
        vm.expectRevert(err);

        vm.prank(writeSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_tokenAddressZero_reverts() public {
        _expectRevert_invalidBunniToken(address(0));

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            address(0),
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_lensAddressZero_reverts() public {
        _expectRevert_invalidBunniLens(address(0));

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            address(0),
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_alreadyAdded_reverts() public {
        // Register one token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        _expectRevert_invalidBunniToken(poolTokenAddress);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_invalidTokenReverts() public {
        _expectRevert_invalidBunniToken(ohmAddress);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            ohmAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_invalidLensReverts() public {
        _expectRevert_invalidBunniLens(ohmAddress);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            ohmAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_hubMismatchReverts() public {
        // Deploy a new hub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            policy,
            0 // No protocol fee
        );

        // Deploy a new lens
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_HubMismatch.selector,
            address(bunniHub),
            address(newBunniHub)
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            address(newBunniLens),
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_twapMaxDeviationOutOfBoundsReverts(
        uint256 twapMaxDeviationBps_
    ) public {
        uint16 twapMaxDeviationBps = uint16(bound(twapMaxDeviationBps_, 10001, type(uint16).max));

        // Expect error
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidTwapMaxDeviationBps.selector,
            address(poolTokenAddress),
            10000,
            twapMaxDeviationBps
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            twapMaxDeviationBps,
            TWAP_OBSERVATION_WINDOW
        );
    }

    function test_addBunniToken_twapObservationWindowBelowMinimum(
        uint256 twapObservationWindow_
    ) public {
        uint32 twapObservationWindow = uint32(bound(twapObservationWindow_, 0, 18));

        // Expect error
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidTwapObservationWindow.selector,
            address(poolTokenAddress),
            19,
            twapObservationWindow
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            twapObservationWindow
        );
    }

    function test_addBunniToken() public {
        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Check that the token was added
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_addBunniToken_fuzz(
        uint256 twapMaxDeviationBps_,
        uint256 twapObservationWindow_
    ) public {
        uint16 twapMaxDeviationBps = uint16(bound(twapMaxDeviationBps_, 0, 10000));
        uint32 twapObservationWindow = uint32(bound(twapObservationWindow_, 19, type(uint32).max));

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            twapMaxDeviationBps,
            twapObservationWindow
        );

        // Check that the token was added
        (
            BunniToken _bunniToken,
            BunniLens _bunniLens,
            uint16 _twapMaxDeviationBps,
            uint32 _twapObservationWindow
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(_bunniToken), poolTokenAddress);
        assertEq(address(_bunniLens), bunniLensAddress);
        assertEq(_twapMaxDeviationBps, twapMaxDeviationBps);
        assertEq(_twapObservationWindow, twapObservationWindow);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_addBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensAddress);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Check that the token was added
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        (
            BunniToken bunniTokenTwo_,
            BunniLens bunniLensTwo_,
            uint16 twapMaxDeviationBpsTwo_,
            uint32 twapObservationWindowTwo_
        ) = submoduleBunniSupply.bunniTokens(1);
        assertEq(address(bunniTokenTwo_), poolTokenTwoAddress);
        assertEq(address(bunniLensTwo_), bunniLensAddress);
        assertEq(twapMaxDeviationBpsTwo_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindowTwo_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
    }

    function test_addBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Expect an event
        vm.expectEmit(true, true, false, true);
        emit BunniTokenAdded(poolTokenTwoAddress, bunniLensTwoAddress);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensTwoAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Check that the token was added
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        (
            BunniToken bunniTokenTwo_,
            BunniLens bunniLensTwo_,
            uint16 twapMaxDeviationBpsTwo_,
            uint32 twapObservationWindowTwo_
        ) = submoduleBunniSupply.bunniTokens(1);
        assertEq(address(bunniTokenTwo_), poolTokenTwoAddress);
        assertEq(address(bunniLensTwo_), bunniLensTwoAddress);
        assertEq(twapMaxDeviationBpsTwo_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindowTwo_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 2);
    }

    // =========  removeBunniToken ========= //

    // [X] removeBunniToken
    //  [X] reverts if not parent
    //  [X] reverts if address(0)
    //  [X] reverts if not added
    //  [X] single token
    //  [X] multiple tokens, single lens
    //  [X] multiple tokens, multiple lenses

    function test_removeBunniToken_notParent_reverts() public {
        bytes memory err = abi.encodeWithSignature("Submodule_OnlyParent(address)", address(this));
        vm.expectRevert(err);

        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_notParent_writer_reverts() public {
        bytes memory err = abi.encodeWithSignature(
            "Submodule_OnlyParent(address)",
            address(writeSPPLY)
        );
        vm.expectRevert(err);

        vm.prank(writeSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken_addressZero_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            address(0)
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(address(0));
    }

    function test_removeBunniToken_notAdded_reverts() public {
        bytes memory err = abi.encodeWithSelector(
            BunniSupply.BunniSupply_Params_InvalidBunniToken.selector,
            poolTokenAddress
        );
        vm.expectRevert(err);

        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);
    }

    function test_removeBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove token
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        assertEq(submoduleBunniSupply.bunniTokenCount(), 0);
        assertEq(submoduleBunniSupply.getCollateralizedOhm(), 0);
    }

    function test_removeBunniToken_multipleTokens_singleLens() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenTwoAddress);
        assertEq(address(bunniLens_), bunniLensAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    function test_removeBunniToken_multipleTokens_multipleLenses() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Set up a second pool and token
        (, , IBunniToken poolTokenTwo) = _setUpPool(
            ohmAddress,
            address(wethToken),
            OHM_WETH_SQRTPRICEX96,
            OHM_WETH_TICK_CUMULATIVE_0,
            OHM_WETH_TICK_CUMULATIVE_1
        );
        address poolTokenTwoAddress = address(poolTokenTwo);

        // Set up a new Lens
        BunniLens bunniLensTwo = new BunniLens(bunniHub);
        address bunniLensTwoAddress = address(bunniLensTwo);

        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenTwoAddress,
            bunniLensTwoAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit BunniTokenRemoved(poolTokenAddress);

        // Remove one of the tokens
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.removeBunniToken(poolTokenAddress);

        // Check that the token was removed
        (
            BunniToken bunniToken_,
            BunniLens bunniLens_,
            uint16 twapMaxDeviationBps_,
            uint32 twapObservationWindow_
        ) = submoduleBunniSupply.bunniTokens(0);
        assertEq(address(bunniToken_), poolTokenTwoAddress);
        assertEq(address(bunniLens_), bunniLensTwoAddress);
        assertEq(twapMaxDeviationBps_, TWAP_MAX_DEVIATION_BPS);
        assertEq(twapObservationWindow_, TWAP_OBSERVATION_WINDOW);

        assertEq(submoduleBunniSupply.bunniTokenCount(), 1);
    }

    // =========  hasBunniToken ========= //

    // [X] hasBunniToken
    //  [X] false if address(0)
    //  [X] false if not added
    //  [X] true if added

    function test_hasBunniToken_addressZero() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(address(0));

        // Check
        assertFalse(hasToken);
    }

    function test_hasBunniToken_differentAddress() public {
        // Do NOT add Bunni Token to BunniSupply

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertFalse(hasToken);
    }

    function test_hasBunniToken() public {
        // Add bunni token to BunniSupply
        vm.prank(moduleSPPLY);
        submoduleBunniSupply.addBunniToken(
            poolTokenAddress,
            bunniLensAddress,
            TWAP_MAX_DEVIATION_BPS,
            TWAP_OBSERVATION_WINDOW
        );

        // Call
        bool hasToken = submoduleBunniSupply.hasBunniToken(poolTokenAddress);

        // Check
        assertTrue(hasToken);
    }
}
