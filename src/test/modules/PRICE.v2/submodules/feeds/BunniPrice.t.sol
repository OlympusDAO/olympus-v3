// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {FullMath} from "libraries/FullMath.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {Test, stdError} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {fromKeycode, Module} from "src/Kernel.sol";
import {fromSubKeycode} from "src/Submodules.sol";

import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";

// Mocks
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

// Bunni contracts
import {BunniPrice} from "src/modules/PRICE/submodules/feeds/BunniPrice.sol";
import {BunniHub} from "src/external/bunni/BunniHub.sol";
import {BunniLens} from "src/external/bunni/BunniLens.sol";
import {IBunniToken} from "src/external/bunni/interfaces/IBunniToken.sol";
import {BunniKey} from "src/external/bunni/base/Structs.sol";
import {BunniManager} from "src/policies/UniswapV3/BunniManager.sol";

import {UniswapV3Factory} from "test/lib/UniswapV3/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {UniswapV3Pool} from "test/lib/UniswapV3/UniswapV3Pool.sol";

import {BunniSetup} from "test/policies/UniswapV3/BunniSetup.sol";

// Libraries
import {FullMath} from "libraries/FullMath.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {ComputeAddress} from "test/libraries/ComputeAddress.sol";
import {UniswapV3OracleHelper} from "libraries/UniswapV3/Oracle.sol";

contract BunniPriceTest is Test {
    using FullMath for uint256;

    IUniswapV3Pool internal uniswapPool;

    BunniPrice internal submoduleBunniPrice;

    MockOhm internal ohmToken;
    MockERC20 internal usdcToken;
    address internal OHM;
    address internal USDC;
    uint8 internal constant OHM_DECIMALS = 9;
    uint8 internal constant USDC_DECIMALS = 6;

    BunniSetup internal bunniSetup;
    BunniManager internal bunniManager;
    BunniHub internal bunniHub;
    BunniLens internal bunniLens;
    IBunniToken internal poolToken;
    BunniKey internal poolTokenKey;
    UniswapV3Factory internal uniswapFactory;
    address internal bunniLensAddress;
    address internal poolTokenAddress;

    address internal policy;

    UserFactory public userFactory;

    address writePRICE;
    address writeSPPLY;

    uint24 private constant POOL_FEE = 500;

    // OHM-USDC Uni V3 pool, based on: 0x893f503fac2ee1e5b78665db23f9c94017aae97d
    // token0: OHM, token1: USDC
    uint128 internal constant POOL_LIQUIDITY = 349484367626548;
    // Current tick: -44579
    uint160 internal constant POOL_SQRTPRICEX96 = 8529245188595251053303005012; // From OHM-USDC, 1 OHM = 11.5897 USDC
    // NOTE: these numbers are fudged to match the current tick and default observation window from BunniManager
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_0 = -2463052984970;
    int56 internal constant OHM_USDC_TICK_CUMULATIVE_1 = -2463079732370;

    uint8 internal constant PRICE_DECIMALS = 18;
    uint8 internal constant POOL_TOKEN_DECIMALS = 18;

    uint256 internal constant USDC_PRICE = 1 * 10 ** PRICE_DECIMALS;
    uint256 internal constant OHM_PRICE = 115897 * 1e14; // 11.5897 USDC per OHM in 18 decimal places

    uint16 internal constant TWAP_MAX_DEVIATION_BPS = 100; // 1%
    uint32 internal constant TWAP_OBSERVATION_WINDOW = 600;

    uint16 private constant SLIPPAGE_DEFAULT = 100; // 1%

    uint256 internal constant OHM_AMOUNT = 100_000e9;
    uint256 internal USDC_AMOUNT = OHM_AMOUNT.mulDiv(OHM_PRICE, 1e18).mulDiv(1e6, 1e9);

    function setUp() public {
        vm.warp(51 * 365 * 24 * 60 * 60); // Set timestamp at roughly Jan 1, 2021 (51 years since Unix epoch)

        // Tokens
        {
            ohmToken = new MockOhm("OHM", "OHM", OHM_DECIMALS);

            // The USDC address needs to be higher than ohm, so generate a salt to ensure that
            bytes32 usdcSalt = ComputeAddress.generateSalt(
                address(ohmToken),
                true,
                type(MockERC20).creationCode,
                abi.encode("USDC", "USDC", USDC_DECIMALS),
                address(this)
            );
            usdcToken = new MockERC20{salt: usdcSalt}("USDC", "USDC", USDC_DECIMALS);

            OHM = address(ohmToken);
            USDC = address(usdcToken);
        }

        // Locations
        {
            userFactory = new UserFactory();
            address[] memory users = userFactory.create(1);
            policy = users[0];
        }

        // Deploy BunniSetup
        {
            bunniSetup = new BunniSetup(OHM, USDC, address(this), policy);

            bunniManager = bunniSetup.bunniManager();
            bunniHub = bunniSetup.bunniHub();
            bunniLens = bunniSetup.bunniLens();
            bunniLensAddress = address(bunniLens);
            uniswapFactory = bunniSetup.uniswapFactory();
        }

        // Deploy writer policies
        {
            (address writePRICE_, address writeSPPLY_, ) = bunniSetup.createWriterPolicies();

            writePRICE = writePRICE_;
            writeSPPLY = writeSPPLY_;
        }

        // Set up the submodule(s)
        {
            (address price_, ) = bunniSetup.createSubmodules(writePRICE, writeSPPLY);

            submoduleBunniPrice = BunniPrice(price_);
        }

        // Set up the UniV3 pool
        {
            address pool_ = bunniSetup.setUpPool(OHM, USDC, POOL_FEE, POOL_SQRTPRICEX96);

            uniswapPool = IUniswapV3Pool(pool_);
        }

        // Mock observations for the Uniswap V3 pool
        {
            bunniSetup.mockPoolObservations(
                address(uniswapPool),
                TWAP_OBSERVATION_WINDOW,
                OHM_USDC_TICK_CUMULATIVE_0,
                OHM_USDC_TICK_CUMULATIVE_1
            );
        }

        // Mock values, to avoid having to set up all of PRICEv2 and submodules
        {
            bunniSetup.mockGetPrice(OHM, OHM_PRICE);
            bunniSetup.mockGetPrice(USDC, USDC_PRICE);
        }

        // Deploy a pool token
        {
            // Deploy the token
            vm.startPrank(policy);
            poolToken = bunniManager.deployPoolToken(address(uniswapPool));
            vm.stopPrank();

            poolTokenAddress = address(poolToken);
            poolTokenKey = _getBunniKey(uniswapPool, poolToken);
        }

        // Deposit into the pool
        {
            // Mint USDC
            usdcToken.mint(address(bunniSetup.TRSRY()), USDC_AMOUNT);

            // Deposit
            vm.startPrank(policy);
            bunniManager.deposit(
                address(uniswapPool),
                OHM,
                OHM_AMOUNT,
                USDC_AMOUNT,
                SLIPPAGE_DEFAULT
            );
            vm.stopPrank();
        }
    }

    // =========  HELPER METHODS ========= //

    function mockERC20Decimals(address asset_, uint8 decimals_) internal {
        vm.mockCall(asset_, abi.encodeWithSignature("decimals()"), abi.encode(decimals_));
    }

    function _expectRevert_invalidBunniToken(address token_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_Params_InvalidBunniToken.selector,
            token_
        );
        vm.expectRevert(err);
    }

    function _expectRevert_invalidBunniLens(address lens_) internal {
        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_Params_InvalidBunniLens.selector,
            lens_
        );
        vm.expectRevert(err);
    }

    function _mockPoolUnlocked(bool unlocked_) internal {
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

            ) = uniswapPool.slot0();

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
            address(uniswapPool),
            abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
            abi.encode(slot0)
        );
    }

    function _getBunniKey(
        IUniswapV3Pool pool_,
        IBunniToken token_
    ) internal view returns (BunniKey memory) {
        return
            BunniKey({pool: pool_, tickLower: token_.tickLower(), tickUpper: token_.tickUpper()});
    }

    function _getReserves(
        BunniKey memory key_,
        BunniLens lens_
    ) internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1) = lens_.getReserves(key_);
        return (reserve0, reserve1);
    }

    // ========= TESTS ========= //

    // [X] Submodule
    //  [X] Version
    //  [X] Subkeycode

    function test_submodule_version() public {
        uint8 major;
        uint8 minor;
        (major, minor) = submoduleBunniPrice.VERSION();
        assertEq(major, 1);
        assertEq(minor, 0);
    }

    function test_submodule_parent() public {
        assertEq(fromKeycode(submoduleBunniPrice.PARENT()), "PRICE");
    }

    function test_submodule_subkeycode() public {
        assertEq(fromSubKeycode(submoduleBunniPrice.SUBKEYCODE()), "PRICE.BNI");
    }

    // [X] Constructor
    //  [X] Incorrect parent

    function test_submodule_parent_notModule_reverts() public {
        // Feed in a different address
        address[] memory newLocations = userFactory.create(1);

        // There's no error message, so just check that a revert happens when attempting to call the module
        vm.expectRevert();

        new BunniPrice(Module(newLocations[0]));
    }

    function test_submodule_parent_notPrice_reverts() public {
        Module parent = bunniSetup.MINTR();

        bytes memory err = abi.encodeWithSignature("Submodule_InvalidParent()");
        vm.expectRevert(err);

        new BunniPrice(parent);
    }

    // [X] getBunniTokenPrice
    //  [X] Reverts if params.bunniLens is zero
    //  [X] Reverts if params.bunniLens is not a valid BunniLens
    //  [X] Reverts if bunniToken is zero
    //  [X] Reverts if bunniToken is not a valid BunniToken
    //  [X] Reverts if bunniToken and bunniLens do not have the same BunniHub
    //  [X] Reverts if any of the reserve assets are not defined as assets in PRICE
    //  [X] Reverts if the reserves deviate from the TWAP
    //  [X] Correctly calculates balances for different decimal scale
    //  [X] Correctly handles different output decimals

    function test_getBunniTokenPrice_zeroBunniLensReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: address(0),
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniLens(address(0));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_invalidBunniLensReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: address(bunniHub),
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniLens(address(bunniHub));

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_zeroBunniTokenReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniToken(address(0));

        submoduleBunniPrice.getBunniTokenPrice(address(0), PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_invalidBunniTokenReverts() public {
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        _expectRevert_invalidBunniToken(address(bunniHub));

        submoduleBunniPrice.getBunniTokenPrice(address(bunniHub), PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_hubMismatchReverts() public {
        // Deploy a new hub
        BunniHub newBunniHub = new BunniHub(
            uniswapFactory,
            policy,
            0 // No protocol fee
        );

        // Deploy a new lens
        BunniLens newBunniLens = new BunniLens(newBunniHub);

        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_Params_HubMismatch.selector,
            address(bunniHub),
            address(newBunniHub)
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: address(newBunniLens),
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_zeroPriceReverts(uint256 tokenIndex_) public {
        uint8 tokenIndex = uint8(bound(tokenIndex_, 0, 1));

        // Mock the price of the token to be zero
        address zeroPriceAddress = tokenIndex == 0 ? OHM : USDC;
        bunniSetup.mockGetPriceZero(zeroPriceAddress);

        // Expect a revert
        bytes memory err = abi.encodeWithSelector(
            PRICEv2.PRICE_PriceZero.selector,
            zeroPriceAddress
        );
        vm.expectRevert(err);

        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice() public {
        uint256 outputScale = 10 ** PRICE_DECIMALS;

        // Calculate the expected price
        (uint256 ohmReserve_, uint256 usdcReserve_) = _getReserves(poolTokenKey, bunniLens);
        uint256 ohmReserve = ohmReserve_.mulDiv(outputScale, 10 ** OHM_DECIMALS);
        uint256 usdcReserve = usdcReserve_.mulDiv(outputScale, 10 ** USDC_DECIMALS);
        uint256 expectedPrice = (ohmReserve.mulDiv(OHM_PRICE, outputScale) +
            usdcReserve.mulDiv(USDC_PRICE, outputScale)).mulDiv(
                10 ** POOL_TOKEN_DECIMALS,
                poolToken.totalSupply()
            ); // Scale: PRICE_DECIMALS

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        uint256 price = submoduleBunniPrice.getBunniTokenPrice(
            poolTokenAddress,
            PRICE_DECIMALS,
            params
        );

        // Check values
        assertTrue(price > 0, "should be non-zero");
        assertApproxEqAbs(price, expectedPrice, 1e9);
    }

    function test_getBunniTokenPrice_noLiquidity() public {
        // Create another pool
        address pool_ = bunniSetup.setUpPool(OHM, USDC, 3000, POOL_SQRTPRICEX96);

        // Deploy a token for the pool, but don't deposit liquidity
        vm.startPrank(policy);
        IBunniToken poolToken_ = bunniManager.deployPoolToken(pool_);
        vm.stopPrank();

        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );

        // Expect the TWAP ratio check to fail
        bytes memory err = abi.encodeWithSelector(
            UniswapV3OracleHelper.UniswapV3OracleHelper_InvalidObservation.selector,
            pool_,
            TWAP_OBSERVATION_WINDOW
        );
        vm.expectRevert(err);

        // Call
        submoduleBunniPrice.getBunniTokenPrice(address(poolToken_), PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_twapDeviationReverts() public {
        // Determine the amount of reserves in the pool, which should be consistent with the lens value
        (uint256 ohmReserves_, uint256 usdcReserves_) = _getReserves(poolTokenKey, bunniLens);
        // 11421651 = 11.42 USD/OHM
        uint256 reservesRatio = usdcReserves_.mulDiv(1e9, ohmReserves_); // USDC decimals: 6

        // Mock the pool returning a TWAP that deviates enough to revert
        int56 tickCumulative0_ = -2416639538393;
        int56 tickCumulative1_ = -2416640880953;
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0_;
        tickCumulatives[1] = tickCumulative1_;
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
            OHM,
            USDC
        ); // USDC decimals: 6

        // Set up revert
        // Will revert as the TWAP deviates from the reserves ratio
        bytes memory err = abi.encodeWithSelector(
            BunniPrice.BunniPrice_PriceMismatch.selector,
            address(uniswapPool),
            twapRatio,
            reservesRatio
        );
        vm.expectRevert(err);

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }

    function test_getBunniTokenPrice_outputDecimalsFuzz(uint256 outputDecimals_) public {
        uint8 outputDecimals = uint8(bound(outputDecimals_, 6, 30));
        uint256 outputScale = 10 ** outputDecimals;

        uint256 ohmPrice = 11 * outputScale;
        uint256 usdcPrice = 1 * outputScale;

        // Mock the PRICE decimals
        bunniSetup.mockGetPrice(OHM, ohmPrice);
        bunniSetup.mockGetPrice(USDC, usdcPrice);

        // Calculate the expected price
        (uint256 ohmReserve_, uint256 usdcReserve_) = _getReserves(poolTokenKey, bunniLens);
        uint256 ohmReserve = ohmReserve_.mulDiv(outputScale, 10 ** OHM_DECIMALS);
        uint256 usdcReserve = usdcReserve_.mulDiv(outputScale, 10 ** USDC_DECIMALS);
        uint256 expectedPrice = (ohmReserve.mulDiv(ohmPrice, outputScale) +
            usdcReserve.mulDiv(usdcPrice, outputScale)).mulDiv(
                10 ** POOL_TOKEN_DECIMALS,
                poolToken.totalSupply()
            ); // Scale: outputDecimals

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        uint256 price = submoduleBunniPrice.getBunniTokenPrice(
            poolTokenAddress,
            outputDecimals,
            params
        );

        // Check values
        assertTrue(price > 0, "should be non-zero");
        assertEq(price, expectedPrice);
    }

    function test_getBunniTokenPrice_reentrancyReverts() public {
        // Set the UniV3 pair to be locked, which indicates re-entrancy
        _mockPoolUnlocked(false);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(
            BunniLens.BunniLens_Reentrant.selector,
            address(uniswapPool)
        );
        vm.expectRevert(err);

        // Call
        bytes memory params = abi.encode(
            BunniPrice.BunniParams({
                bunniLens: bunniLensAddress,
                twapMaxDeviationsBps: TWAP_MAX_DEVIATION_BPS,
                twapObservationWindow: TWAP_OBSERVATION_WINDOW
            })
        );
        submoduleBunniPrice.getBunniTokenPrice(poolTokenAddress, PRICE_DECIMALS, params);
    }
}
