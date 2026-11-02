// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";

// Libraries
import {BURNER_LOANS_ADMIN_ROLE, EMERGENCY_ROLE, HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

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

    function setUp() public override {
        super.setUp();
        _task.addAsset(address(_asset));
        _task.addAsset(address(_otherAsset));
        for (uint256 i; i < 8; ++i) {
            // Eight deterministic, nonzero borrower identities.
            // forge-lint: disable-next-line(unsafe-typecast)
            _seedDebt(address(uint160(0x10000 + i)), 10e6, 1e9);
        }
        _mature();
        _handler = new SeizerTaskProgressHandler(_task);
        _rolesAdmin.grantRole(HEART_ROLE, address(_handler));
        _rolesAdmin.grantRole(BURNER_LOANS_ADMIN_ROLE, address(_handler));
        _rolesAdmin.grantRole(EMERGENCY_ROLE, address(_handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _handler.beat.selector;
        selectors[1] = _handler.pause.selector;
        selectors[2] = _handler.recover.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    // Scenarios: BLSEIZ-SELF-EXECUTE-P02, BLSEIZ-EXECUTE-P03, BLSEIZ-EXECUTE-L01, BLSEIZ-ASSET-INDEX-P06, BLSEIZ-BORROWER-CURSOR-P05.
    function invariant_schedulerAndAccountingRemainConsistent() public view {
        assertTrue(_handler.progressValid(), "Every enabled beat fairly rotates assets");
        assertLt(_task.nextAssetIndex(), 2, "Asset iterator remains within the fixed registry");
        assertEq(
            _task.assetCursor(address(_otherAsset)),
            0,
            "Empty B market keeps a zero borrower cursor after recovery"
        );
        uint32 market = _core.marketId(address(_asset));
        uint256 population = _floan.getActiveBorrowerCount(market);
        if (population == 0)
            assertEq(_task.assetCursor(address(_asset)), 0, "Empty market cursor is zero");
        else
            assertLt(
                _task.assetCursor(address(_asset)),
                population,
                "Committed cursor remains usable after defaults"
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
