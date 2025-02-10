// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {CoolerLtvOracle} from "policies/cooler/CoolerLtvOracle.sol";
import {ICoolerLtvOracle} from "policies/interfaces/cooler/ICoolerLtvOracle.sol";

import {RolesAdmin, Keycode, fromKeycode, toKeycode, Kernel, Module, Policy, Actions} from "policies/RolesAdmin.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {MockGohm} from "test/mocks/MockGohm.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract CoolerLtvOracleTestBase is Test {
    MockGohm internal gohm;
    MockERC20 internal usds;
    CoolerLtvOracle internal oracle;

    address internal immutable OVERSEER = makeAddr("overseer");
    address internal immutable OTHERS = makeAddr("others");

    uint96 internal constant defaultOLTV = 2_961.64e18; // [USDS/gOHM] == ~11 [USDS/OHM]
    uint96 internal constant defaultLLTV = 2_991.2564e18; // defaultOLTV + 1%
    uint96 internal constant defaultMaxDelta = 100e18; // 100 USDS
    uint32 internal constant defaultMinTargetTimeDelta = 1 weeks; // 1 week
    uint96 internal constant defaultMaxRateOfChange = uint96(0.1e18) / 1 days; // 0.1 USDS / day

    uint16 internal constant defaultMaxLLTVPremiumBps = 333; // LLTV is 3.33% above OLTV
    uint16 internal constant defaultLLTVPremiumBps = 100; // LLTV is 1% above OLTV

    Kernel internal kernel;
    OlympusRoles internal ROLES;
    RolesAdmin internal rolesAdmin;

    uint256 internal constant START_TIMESTAMP = 1_000_000;

    event OriginationLtvSetAt(
        uint96 oldOriginationLtv,
        uint96 newOriginationLtvTarget,
        uint256 targetTime
    );
    event MaxOriginationLtvDeltaSet(uint256 maxDelta);
    event MinOriginationLtvTargetTimeDeltaSet(uint32 maxTargetTimeDelta);
    event MaxOriginationLtvRateOfChangeSet(uint96 maxRateOfChange);
    event MaxLiquidationLtvPremiumBpsSet(uint96 maxPremiumBps);
    event LiquidationLtvPremiumBpsSet(uint96 premiumBps);

    function setUp() public virtual {
        vm.warp(START_TIMESTAMP);
        gohm = new MockGohm("gOHM", "gOHM", 18);
        usds = new MockERC20("USDS", "USDS", 18);

        kernel = new Kernel(); // this contract will be the executor

        oracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            defaultOLTV,
            defaultMaxDelta,
            defaultMinTargetTimeDelta,
            defaultMaxRateOfChange,
            defaultMaxLLTVPremiumBps,
            defaultLLTVPremiumBps
        );

        ROLES = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(oracle));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        rolesAdmin.grantRole("admin", OVERSEER);

        // Enanle the policy
        vm.startPrank(OVERSEER);
        oracle.enable(abi.encode(""));
        vm.stopPrank();
    }

    function checkOltvData(
        uint96 expectedStartingValue,
        uint32 expectedStartTime,
        uint96 expectedTargetValue,
        uint32 expectedTargetTime,
        uint96 expectedSlope
    ) internal view {
        (
            uint96 startingValue,
            uint32 startTime,
            uint96 targetValue,
            uint32 targetTime,
            uint96 slope
        ) = oracle.originationLtvData();
        assertEq(startingValue, expectedStartingValue, "startingValue");
        assertEq(startTime, expectedStartTime, "startTime");
        assertEq(targetValue, expectedTargetValue, "targetValue");
        assertEq(targetTime, expectedTargetTime, "targetTime");
        assertEq(slope, expectedSlope, "slope");
    }
}

contract CoolerLtvOracleTestAdmin is CoolerLtvOracleTestBase {
    function test_construction_failDecimalsCollateral() public {
        gohm = new MockGohm("gOHM", "gOHM", 6);
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.InvalidParam.selector));
        oracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            defaultOLTV,
            defaultMaxDelta,
            defaultMinTargetTimeDelta,
            defaultMaxRateOfChange,
            defaultMaxLLTVPremiumBps,
            defaultLLTVPremiumBps
        );
    }

    function test_construction_failDecimalsDebt() public {
        usds = new MockERC20("usds", "usds", 6);
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.InvalidParam.selector));
        oracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            defaultOLTV,
            defaultMaxDelta,
            defaultMinTargetTimeDelta,
            defaultMaxRateOfChange,
            defaultMaxLLTVPremiumBps,
            defaultLLTVPremiumBps
        );
    }

    function test_construction_failMaxLLTVPremiumTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.InvalidParam.selector));
        oracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            defaultOLTV,
            defaultMaxDelta,
            defaultMinTargetTimeDelta,
            defaultMaxRateOfChange,
            10_001,
            defaultLLTVPremiumBps
        );
    }

    function test_construction_failLLTVPremiumTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.InvalidParam.selector));
        oracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            defaultOLTV,
            defaultMaxDelta,
            defaultMinTargetTimeDelta,
            defaultMaxRateOfChange,
            9_999,
            10_000
        );
    }

    function test_construction_success() public view {
        assertEq(oracle.debtToken(), address(usds));
        assertEq(oracle.collateralToken(), address(gohm));

        checkOltvData(
            defaultOLTV,
            uint32(vm.getBlockTimestamp()),
            defaultOLTV,
            uint32(vm.getBlockTimestamp()),
            0
        );
        assertEq(oracle.maxOriginationLtvDelta(), defaultMaxDelta);
        assertEq(oracle.minOriginationLtvTargetTimeDelta(), defaultMinTargetTimeDelta);
        assertEq(oracle.maxOriginationLtvRateOfChange(), defaultMaxRateOfChange);
        assertEq(oracle.maxLiquidationLtvPremiumBps(), defaultMaxLLTVPremiumBps);
        assertEq(oracle.liquidationLtvPremiumBps(), defaultLLTVPremiumBps);

        assertEq(oracle.DECIMALS(), 18);
        assertEq(oracle.BASIS_POINTS_DIVISOR(), 10_000);

        assertEq(oracle.currentOriginationLtv(), defaultOLTV);
        assertEq(oracle.currentLiquidationLtv(), defaultLLTV);
        (uint96 originationLtv, uint96 liquidationLtv) = oracle.currentLtvs();
        assertEq(originationLtv, originationLtv);
        assertEq(liquidationLtv, defaultLLTV);
    }

    function test_configureDependencies_success() public {
        Keycode[] memory expectedDeps = new Keycode[](1);
        expectedDeps[0] = toKeycode("ROLES");

        Keycode[] memory deps = oracle.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
    }

    function test_configureDependencies_fail() public {
        vm.mockCall(
            address(ROLES),
            abi.encodeWithSelector(Module.VERSION.selector),
            abi.encode(uint8(2), uint8(1))
        );

        vm.expectRevert(
            abi.encodeWithSelector(Policy.Policy_WrongModuleVersion.selector, abi.encode([1]))
        );
        oracle.configureDependencies();
    }

    function test_requestPermissions() public view {
        // No extra permissions needed
        assertEq(oracle.requestPermissions().length, 0);
    }

    function test_setMaxOriginationLtvDelta() public {
        vm.startPrank(OVERSEER);

        vm.expectEmit(address(oracle));
        emit MaxOriginationLtvDeltaSet(0.11e18);

        oracle.setMaxOriginationLtvDelta(0.11e18);
        assertEq(oracle.maxOriginationLtvDelta(), 0.11e18);
    }

    function test_setMinOriginationLtvTargetTimeDelta() public {
        vm.startPrank(OVERSEER);

        vm.expectEmit(address(oracle));
        emit MinOriginationLtvTargetTimeDeltaSet(uint32(1 weeks));

        oracle.setMinOriginationLtvTargetTimeDelta(uint32(1 weeks));
        assertEq(oracle.minOriginationLtvTargetTimeDelta(), 1 weeks);
    }

    function test_setMaxOriginationLtvRateOfChange() public {
        vm.startPrank(OVERSEER);

        uint96 expectedRate = uint96(0.05e18) / uint32(1 weeks);
        vm.expectEmit(address(oracle));
        emit MaxOriginationLtvRateOfChangeSet(expectedRate);

        oracle.setMaxOriginationLtvRateOfChange(0.05e18, uint32(1 weeks));
        assertEq(oracle.maxOriginationLtvRateOfChange(), expectedRate);
    }

    function test_setMaxLiquidationLtvPremiumBps() public {
        vm.startPrank(OVERSEER);

        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.InvalidParam.selector));
        oracle.setMaxLiquidationLtvPremiumBps(10_001);

        emit MaxLiquidationLtvPremiumBpsSet(123);
        oracle.setMaxLiquidationLtvPremiumBps(123);
        assertEq(oracle.maxLiquidationLtvPremiumBps(), 123);
    }

    function test_setLiquidationLtvPremiumBps_failMax() public {
        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.InvalidParam.selector));
        oracle.setLiquidationLtvPremiumBps(defaultMaxLLTVPremiumBps + 1);
    }

    function test_setLiquidationLtvPremiumBps_failDecrease() public {
        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.CannotDecreaseLtv.selector));
        oracle.setLiquidationLtvPremiumBps(defaultLLTVPremiumBps - 1);
    }

    function test_setLiquidationLtvPremiumBps_success() public {
        assertEq(
            oracle.currentLiquidationLtv(),
            (defaultOLTV * (10_000 + defaultLLTVPremiumBps)) / 10_000
        );

        vm.startPrank(OVERSEER);
        emit MaxLiquidationLtvPremiumBpsSet(123);
        oracle.setLiquidationLtvPremiumBps(123);
        assertEq(oracle.liquidationLtvPremiumBps(), 123);

        assertEq(oracle.currentLiquidationLtv(), (defaultOLTV * (10_000 + 123)) / 10_000);
    }
}

contract CoolerLtvOracleTestNotEnabled is CoolerLtvOracleTestBase {
    function setUp() public override {
        super.setUp();

        vm.startPrank(OVERSEER);
        oracle.disable(abi.encode(""));
        vm.stopPrank();
    }

    function test_access_setMaxOriginationLtvDelta() public {
        vm.prank(OVERSEER);
        oracle.setMaxOriginationLtvDelta(0.15e18);

        assertEq(oracle.maxOriginationLtvDelta(), 0.15e18);
    }

    function test_access_setMinOriginationLtvTargetTimeDelta() public {
        vm.prank(OVERSEER);
        oracle.setMinOriginationLtvTargetTimeDelta(uint32(vm.getBlockTimestamp() + 1));

        assertEq(oracle.minOriginationLtvTargetTimeDelta(), uint32(vm.getBlockTimestamp() + 1));
    }

    function test_access_setMaxOriginationLtvRateOfChange() public {
        vm.prank(OVERSEER);
        oracle.setMaxOriginationLtvRateOfChange(0.01e18, 1 days);

        assertEq(oracle.maxOriginationLtvRateOfChange(), 0.01e18 / uint96(1 days));
    }

    function test_access_setOriginationLtvAt() public {
        vm.prank(OVERSEER);
        oracle.setOriginationLtvAt(defaultOLTV, uint32(vm.getBlockTimestamp()) + 365 days);

        assertEq(oracle.currentOriginationLtv(), defaultOLTV);
    }

    function test_access_setMaxLiquidationLtvPremiumBps() public {
        vm.prank(OVERSEER);
        oracle.setMaxLiquidationLtvPremiumBps(123);

        assertEq(oracle.maxLiquidationLtvPremiumBps(), 123);
    }

    function test_access_setLiquidationLtvPremiumBps() public {
        vm.prank(OVERSEER);
        oracle.setLiquidationLtvPremiumBps(123);

        assertEq(oracle.liquidationLtvPremiumBps(), 123);
    }
}

contract CoolerLtvOracleTestAccess is CoolerLtvOracleTestBase {
    function expectOnlyOverseer() internal {
        vm.startPrank(OTHERS);
        vm.expectRevert(abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, ADMIN_ROLE));
    }

    function test_access_setMaxOriginationLtvDelta() public {
        expectOnlyOverseer();
        oracle.setMaxOriginationLtvDelta(0.15e18);
    }

    function test_access_setMinOriginationLtvTargetTimeDelta() public {
        expectOnlyOverseer();
        oracle.setMinOriginationLtvTargetTimeDelta(uint32(vm.getBlockTimestamp() + 1));
    }

    function test_access_setMaxOriginationLtvRateOfChange() public {
        expectOnlyOverseer();
        oracle.setMaxOriginationLtvRateOfChange(0.01e18, 1 days);
    }

    function test_access_setOriginationLtvAt() public {
        expectOnlyOverseer();
        oracle.setOriginationLtvAt(1.02e18, uint32(vm.getBlockTimestamp() + 1 weeks));
    }

    function test_access_setMaxLiquidationLtvPremiumBps() public {
        expectOnlyOverseer();
        oracle.setMaxLiquidationLtvPremiumBps(123);
    }

    function test_access_setLiquidationLtvPremiumBps() public {
        expectOnlyOverseer();
        oracle.setLiquidationLtvPremiumBps(123);
    }
}

contract CoolerLtvOracleTestOLTV is CoolerLtvOracleTestBase {
    function test_setOriginationLtvAt_cannotDecreaseOLTV() public {
        uint96 newTargetOltv = defaultOLTV - 1;
        vm.startPrank(OVERSEER);
        vm.expectRevert(abi.encodeWithSelector(ICoolerLtvOracle.CannotDecreaseLtv.selector));
        oracle.setOriginationLtvAt(newTargetOltv, uint32(vm.getBlockTimestamp()) + 1 weeks);
    }

    function test_setOriginationLtvAt_immediate_successUp() public {
        uint96 newTargetOltv = 3_000e18;
        vm.startPrank(OVERSEER);
        oracle.setMinOriginationLtvTargetTimeDelta(0);
        oracle.setMaxOriginationLtvRateOfChange(100e18, 1);

        uint32 setTime = uint32(vm.getBlockTimestamp());
        uint32 targetTime = setTime + 1;

        vm.expectEmit(address(oracle));
        emit OriginationLtvSetAt(defaultOLTV, newTargetOltv, targetTime);

        oracle.setOriginationLtvAt(newTargetOltv, targetTime);
        checkOltvData(defaultOLTV, setTime, newTargetOltv, targetTime, 38.36e18);

        // The same after the targetTime
        skip(10 days);
        checkOltvData(defaultOLTV, setTime, newTargetOltv, targetTime, 38.36e18);
    }

    function test_setOriginationLtvAt_breachDeltaUp() public {
        uint96 newTargetOltv = defaultOLTV + defaultMaxDelta + 1;
        vm.startPrank(OVERSEER);
        oracle.setMaxOriginationLtvRateOfChange(100e18, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoolerLtvOracle.BreachedMaxOriginationLtvDelta.selector,
                defaultOLTV,
                newTargetOltv,
                defaultMaxDelta
            )
        );
        oracle.setOriginationLtvAt(newTargetOltv, uint32(vm.getBlockTimestamp()) + 1 weeks);

        newTargetOltv -= 1;
        oracle.setOriginationLtvAt(newTargetOltv, uint32(vm.getBlockTimestamp()) + 1 weeks);
    }

    function test_setOriginationLtvAt_breachMinDateDelta() public {
        uint96 newTargetOltv = 3_000e18;
        vm.startPrank(OVERSEER);
        oracle.setMaxOriginationLtvRateOfChange(100e18, 1);

        // targetTime < now
        uint32 targetTime = uint32(vm.getBlockTimestamp()) - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoolerLtvOracle.BreachedMinDateDelta.selector,
                targetTime,
                vm.getBlockTimestamp(),
                defaultMinTargetTimeDelta
            )
        );
        oracle.setOriginationLtvAt(newTargetOltv, targetTime);

        // targetTime <= now
        targetTime = uint32(vm.getBlockTimestamp());
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoolerLtvOracle.BreachedMinDateDelta.selector,
                targetTime,
                vm.getBlockTimestamp(),
                defaultMinTargetTimeDelta
            )
        );
        oracle.setOriginationLtvAt(newTargetOltv, targetTime);

        // (targetTime - now) < minOriginationLtvTargetTimeDelta
        targetTime = uint32(vm.getBlockTimestamp()) + 7 days - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoolerLtvOracle.BreachedMinDateDelta.selector,
                targetTime,
                vm.getBlockTimestamp(),
                defaultMinTargetTimeDelta
            )
        );
        oracle.setOriginationLtvAt(newTargetOltv, targetTime);

        // Works with a 7 day target date
        targetTime = uint32(vm.getBlockTimestamp()) + 7 days;
        oracle.setOriginationLtvAt(newTargetOltv, targetTime);
        checkOltvData(
            defaultOLTV,
            uint32(vm.getBlockTimestamp()),
            newTargetOltv,
            targetTime,
            63425925925925
        );
    }

    function test_setOriginationLtvAt_breachMaxOltvRateOfChange() public {
        vm.startPrank(OVERSEER);
        oracle.setMaxOriginationLtvDelta(1e18);
        oracle.setMaxOriginationLtvRateOfChange(0.30e18, 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoolerLtvOracle.BreachedMaxOriginationLtvRateOfChange.selector,
                uint96(0.3e18 + 1e7) / 30 days,
                uint96(0.3e18) / 30 days
            )
        );
        oracle.setOriginationLtvAt(
            defaultOLTV + 0.30e18 + 1e7,
            uint32(vm.getBlockTimestamp() + 30 days)
        );

        oracle.setOriginationLtvAt(defaultOLTV + 0.30e18, uint32(vm.getBlockTimestamp() + 30 days));
    }

    function test_setOriginationLtvAt_flatAtTargetTime() public {
        uint96 newTargetOltv = 3_000e18;
        vm.startPrank(OVERSEER);
        oracle.setMinOriginationLtvTargetTimeDelta(0);
        oracle.setMaxOriginationLtvRateOfChange(100e18, 1);

        oracle.setOriginationLtvAt(newTargetOltv, uint32(vm.getBlockTimestamp()) + 1);
        // check at target date we're at the target OLTV
        skip(1);
        uint96 actualOLTV = oracle.currentOriginationLtv();
        assertEq(newTargetOltv, actualOLTV);
        // check in future price has remained static
        skip(1 days);
        actualOLTV = oracle.currentOriginationLtv();
        assertEq(newTargetOltv, actualOLTV);
    }

    function test_setOriginationLtvAt_increasesAtExpectedRateSecs() public {
        uint96 newTargetOltv = 3_000e18;
        vm.startPrank(OVERSEER);
        oracle.setMinOriginationLtvTargetTimeDelta(0);
        oracle.setMaxOriginationLtvRateOfChange(100e18, 1);

        uint96 currentOltv = oracle.currentOriginationLtv();
        assertEq(defaultOLTV, currentOltv);
        oracle.setOriginationLtvAt(newTargetOltv, uint32(vm.getBlockTimestamp()) + 4);
        checkOltvData(
            defaultOLTV,
            uint32(vm.getBlockTimestamp()),
            newTargetOltv,
            uint32(vm.getBlockTimestamp()) + 4,
            9.59e18
        );

        currentOltv = oracle.currentOriginationLtv();
        assertEq(defaultOLTV, currentOltv);
        skip(1);
        currentOltv = oracle.currentOriginationLtv();
        assertEq(2_971.23e18, currentOltv);
        skip(1);
        currentOltv = oracle.currentOriginationLtv();
        assertEq(2_980.82e18, currentOltv);
        skip(1);
        currentOltv = oracle.currentOriginationLtv();
        assertEq(2_990.41e18, currentOltv);
        skip(1);
        currentOltv = oracle.currentOriginationLtv();
        assertEq(3_000e18, currentOltv);
        skip(1);
        currentOltv = oracle.currentOriginationLtv();
        assertEq(3_000e18, currentOltv);
    }

    function test_setOriginationLtvAt_increasesAtExpectedRateYear() public {
        // OLTV @ now      = 1.5e18
        // OLTV @ 365 days = 2.5e18
        uint96 oltvStart = 3_000e18;
        uint96 oltvDelta = 10e18;
        uint256 MAX_DELTA = 1e8; // Small (expected) rounding diffs

        oracle = new CoolerLtvOracle(
            address(kernel),
            address(gohm),
            address(usds),
            oltvStart,
            10e18,
            1 days,
            defaultMaxRateOfChange,
            defaultMaxLLTVPremiumBps,
            defaultLLTVPremiumBps
        );
        kernel.executeAction(Actions.ActivatePolicy, address(oracle));

        vm.startPrank(OVERSEER);
        oracle.setOriginationLtvAt(
            oltvStart + oltvDelta,
            uint32(vm.getBlockTimestamp()) + 365 days
        );

        uint256 currentOltv = oracle.currentOriginationLtv();
        assertEq(currentOltv, oltvStart);

        uint256 startingTime = vm.getBlockTimestamp();

        // 1/10th in
        vm.warp(startingTime + (365 days / 10));
        currentOltv = oracle.currentOriginationLtv();
        assertApproxEqAbs(currentOltv, oltvStart + oltvDelta / 10, MAX_DELTA);

        // half way in
        vm.warp(startingTime + (365 days / 2));
        currentOltv = oracle.currentOriginationLtv();
        assertApproxEqAbs(currentOltv, oltvStart + oltvDelta / 2, MAX_DELTA);

        // 9/10ths in
        vm.warp(startingTime + ((365 days * 9) / 10));
        currentOltv = oracle.currentOriginationLtv();
        assertApproxEqAbs(currentOltv, oltvStart + (oltvDelta * 9) / 10, MAX_DELTA);

        // 1 second before end
        vm.warp(startingTime + (365 days - 1));
        currentOltv = oracle.currentOriginationLtv();
        assertEq(currentOltv, 3_009.999999682881712163e18); // just less than oltvStart+oltvDelta

        // At end
        vm.warp(startingTime + (365 days));
        currentOltv = oracle.currentOriginationLtv();
        assertEq(currentOltv, oltvStart + oltvDelta);

        // At end + 1 day
        vm.warp(startingTime + (365 days + 1 days));
        currentOltv = oracle.currentOriginationLtv();
        assertEq(currentOltv, oltvStart + oltvDelta);
    }

    function test_setOriginationLtvAt_keepTheSame() public {
        assertEq(oracle.currentOriginationLtv(), defaultOLTV);

        vm.startPrank(OVERSEER);
        oracle.setOriginationLtvAt(defaultOLTV, uint32(vm.getBlockTimestamp()) + 365 days);

        checkOltvData(
            defaultOLTV,
            uint32(vm.getBlockTimestamp()),
            defaultOLTV,
            uint32(vm.getBlockTimestamp()) + 365 days,
            0
        );

        skip(100 days);
        assertEq(oracle.currentOriginationLtv(), defaultOLTV);
    }
}
