// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansSeizerTaskProgressTest} from "../fixtures/BurnerLoansSeizerTaskProgressTest.sol";
import {SeizerTaskProgressHandler} from "../fixtures/SeizerTaskProgressHandler.sol";

/// @dev Two fixed registered assets, eight matured positions, constant prices, arbitrary
///      gas/scan settings, manual cursor recovery and pause/re-enable sequences.
///      No new loans or registry changes.
/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.fail-on-revert = true
/// forge-config: default.invariant.depth = 64
contract BurnerLoansSeizerTaskProgressInvariantTest is BurnerLoansSeizerTaskProgressTest {
    SeizerTaskProgressHandler internal _handler;

    function setUp() public virtual override {
        super.setUp();
        vm.prank(_fixtureAdmin);
        _task.addAsset(address(_asset));
        vm.prank(_fixtureAdmin);
        _task.addAsset(address(_otherAsset));
        for (uint256 i; i < 8; ++i) {
            // Eight deterministic, nonzero borrower identities.
            // forge-lint: disable-next-line(unsafe-typecast)
            _seedDebt(address(uint160(0x10000 + i)), 10e6, 1e9);
        }
        _mature();
        address taskAdmin = makeAddr("seizerTaskAdmin");
        address emergency = makeAddr("seizerTaskEmergency");
        _grantFixtureRole(BURNER_LOANS_ADMIN_ROLE, taskAdmin);
        _grantFixtureRole(EMERGENCY_ROLE, emergency);
        _handler = new SeizerTaskProgressHandler(_task, _seizerHeart, taskAdmin, emergency);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _handler.beat.selector;
        selectors[1] = _handler.pause.selector;
        selectors[2] = _handler.recover.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P02, BLSEIZ-EXECUTE-P03, BLSEIZ-EXECUTE-L01, BLSEIZ-ASSET-INDEX-P06, BLSEIZ-EXPIRED-CURSOR-P05, BLSEIZ-UNHEALTHY-CURSOR-P05.
    function invariant_schedulerAndAccountingRemainConsistent() public view {
        assertTrue(_handler.progressValid(), "Every enabled beat fairly rotates assets");
        assertLt(_task.nextAssetIndex(), 2, "Asset iterator remains within the fixed registry");
        assertEq(
            _task.expiredAssetCursor(address(_otherAsset)),
            0,
            "Empty B market keeps a zero borrower cursor after recovery"
        );
        uint32 market = _core.marketId(address(_asset));
        // Each fixed-book loan has 1e9 principal. The handler neither adds loans nor repays debt,
        // so (due + defaulted) / 1e9 independently recovers the original book size (8 or 12).
        // Compaction may leave a saved offset outside the current population between visits;
        // execute's boundary tests prove repair before discovery, and drain tests prove reachability.
        // forge-lint: disable-next-line(literal-instead-of-constant)
        uint256 originalPopulation = (_floan.getMarketPrincipalDue(market) +
            _floan.getMarketPrincipalDefaulted(market)) / 1e9;
        assertLt(
            _task.expiredAssetCursor(address(_asset)),
            originalPopulation,
            "Expiry offset stays within original book"
        );
        assertLt(
            _task.unhealthyAssetCursor(address(_asset)),
            originalPopulation,
            "Unhealthy offset stays within original book"
        );
        assertEq(
            _task.unhealthyAssetCursor(address(_otherAsset)),
            0,
            "Empty B market has no pending unhealthy offset"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            _floan.getMarketPrincipalDue(market),
            "Inventory and canonical principal agree"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            _floan.getMarketCollateral(market),
            "Custody liabilities equal canonical collateral"
        );
        assertEq(
            _asset.balanceOf(address(_task)),
            0,
            "Scheduler never receives keeper rewards or custody"
        );
    }
}
