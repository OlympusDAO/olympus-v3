// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test
import {Test} from "@forge-std-1.16.2/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {ModulePermissions} from "src/test/lib/generated/ModulePermissions.sol";

// Contracts
import {Actions, Kernel, Module} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";

abstract contract FLOANTest is Test {
    using ModuleTestFixtureGenerator for OlympusFixedTermLoan;

    Kernel internal kernel;
    OlympusFixedTermLoan internal floan;

    address internal manager;
    address internal otherManager;
    address internal facility;
    address internal otherFacility;
    address internal collateralToken;
    address internal otherCollateralToken;
    address internal debtToken;
    address internal otherDebtToken;
    address internal borrower;
    address internal otherBorrower;

    function setUp() public virtual {
        kernel = new Kernel();
        floan = new OlympusFixedTermLoan(kernel);
        kernel.executeAction(Actions.InstallModule, address(floan));

        manager = floan.generateMultiFunctionFixture(ModulePermissions.olympusFixedTermLoan());
        otherManager = floan.generateMultiFunctionFixture(ModulePermissions.olympusFixedTermLoan());
        facility = floan.generateMultiFunctionFixture(ModulePermissions.olympusFixedTermLoan());
        otherFacility = floan.generateMultiFunctionFixture(
            ModulePermissions.olympusFixedTermLoan()
        );

        kernel.executeAction(Actions.ActivatePolicy, manager);
        kernel.executeAction(Actions.ActivatePolicy, otherManager);
        kernel.executeAction(Actions.ActivatePolicy, facility);
        kernel.executeAction(Actions.ActivatePolicy, otherFacility);

        collateralToken = address(new MockERC20("Collateral", "COL", 18));
        otherCollateralToken = address(new MockERC20("Other Collateral", "OCOL", 6));
        debtToken = address(new MockERC20("Debt", "DEBT", 9));
        otherDebtToken = address(new MockERC20("Other Debt", "ODEBT", 18));
        borrower = makeAddr("borrower");
        otherBorrower = makeAddr("otherBorrower");
        vm.warp(1 days);
        vm.roll(100);
    }

    function _market(
        address manager_,
        address facility_,
        address collateralToken_,
        address debtToken_,
        uint128 principalCap_
    ) internal view returns (IFLOANv1.Market memory) {
        return
            IFLOANv1.Market({
                collateralToken: collateralToken_,
                debtToken: debtToken_,
                manager: manager_,
                facility: facility_,
                configId: bytes16("Test market v1"),
                principalCap: principalCap_,
                termLength: 30 days,
                maxMaturityHorizon: 365 days,
                maxLtvBps: 8_500,
                baseFeeBps: 100,
                collateralDecimals: collateralToken_ == otherCollateralToken ? 6 : 18,
                debtDecimals: debtToken_ == otherDebtToken ? 18 : 9,
                originationsEnabled: true
            });
    }

    function _createMarket(
        address manager_,
        address facility_,
        address collateralToken_,
        address debtToken_,
        uint128 principalCap_
    ) internal returns (uint32 marketId) {
        vm.prank(manager_);
        marketId = floan.createMarket(
            _marketInput(_market(manager_, facility_, collateralToken_, debtToken_, principalCap_)),
            abi.encode(uint256(123))
        );
    }

    function _marketInput(
        IFLOANv1.Market memory market_
    ) internal pure returns (IFLOANv1.MarketInput memory) {
        return
            IFLOANv1.MarketInput({
                collateralToken: market_.collateralToken,
                debtToken: market_.debtToken,
                manager: market_.manager,
                facility: market_.facility,
                configId: market_.configId,
                principalCap: market_.principalCap,
                termLength: market_.termLength,
                maxMaturityHorizon: market_.maxMaturityHorizon,
                maxLtvBps: market_.maxLtvBps,
                baseFeeBps: market_.baseFeeBps
            });
    }

    function _createPositionWithDebt(
        uint32 marketId_,
        address facility_,
        address borrower_,
        uint128 principal_
    ) internal returns (uint64 positionId) {
        vm.startPrank(facility_);
        positionId = floan.createPosition(marketId_, borrower_);
        floan.increaseDebt(positionId, principal_, 0, uint48(block.timestamp + 30 days));
        vm.stopPrank();
    }

    function _createPosition(
        uint32 marketId_,
        address facility_,
        address borrower_
    ) internal returns (uint64 positionId) {
        vm.prank(facility_);
        positionId = floan.createPosition(marketId_, borrower_);
    }

    function _expectKernelPermissionRevert(address caller_) internal {
        vm.assume(caller_ != manager && caller_ != otherManager);
        vm.assume(caller_ != facility && caller_ != otherFacility);
        vm.prank(caller_);
        vm.expectRevert(abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, caller_));
    }

    function _assertMarket(uint32 marketId_, IFLOANv1.Market memory expected_) internal view {
        IFLOANv1.Market memory actual = floan.getMarket(marketId_);
        assertEq(actual.collateralToken, expected_.collateralToken, "market collateral token");
        assertEq(actual.debtToken, expected_.debtToken, "market debt token");
        assertEq(actual.manager, expected_.manager, "market manager");
        assertEq(actual.facility, expected_.facility, "market facility");
        assertEq(actual.configId, expected_.configId, "market config ID");
        assertEq(actual.principalCap, expected_.principalCap, "market principal cap");
        assertEq(actual.termLength, expected_.termLength, "market term length");
        assertEq(
            actual.maxMaturityHorizon,
            expected_.maxMaturityHorizon,
            "market maturity horizon"
        );
        assertEq(actual.maxLtvBps, expected_.maxLtvBps, "market maximum LTV");
        assertEq(actual.baseFeeBps, expected_.baseFeeBps, "market base fee");
        assertEq(
            actual.collateralDecimals,
            expected_.collateralDecimals,
            "market collateral decimals"
        );
        assertEq(actual.debtDecimals, expected_.debtDecimals, "market debt decimals");
        assertEq(
            actual.originationsEnabled,
            expected_.originationsEnabled,
            "market originations enabled"
        );
    }

    function _assertPosition(uint64 positionId_, IFLOANv1.Position memory expected_) internal view {
        IFLOANv1.Position memory actual = floan.getPosition(positionId_);
        assertEq(actual.borrower, expected_.borrower, "position borrower");
        assertEq(actual.marketId, expected_.marketId, "position market ID");
        assertEq(actual.collateral, expected_.collateral, "position collateral");
        assertEq(actual.principalDrawn, expected_.principalDrawn, "position principal drawn");
        assertEq(actual.principalDue, expected_.principalDue, "position principal due");
        assertEq(actual.interestDue, expected_.interestDue, "position interest due");
        assertEq(actual.maturity, expected_.maturity, "position maturity");
        assertEq(actual.lastBorrowBlock, expected_.lastBorrowBlock, "position last borrow block");
    }

    function _assertPositionIndexes(
        uint64 positionId_,
        uint32 marketId_,
        address borrower_,
        uint256 expectedPositionCount_,
        uint256 expectedBorrowerPositionCount_,
        uint256 expectedMarketPositionCount_,
        uint256 expectedPairPositionCount_
    ) internal view {
        uint256[] memory borrowerIds = floan.getPositionIdsForBorrower(borrower_);
        uint256[] memory marketIds = floan.getPositionIdsForMarket(marketId_);
        uint256[] memory pairIds = floan.getPositionIdsForMarketAndBorrower(marketId_, borrower_);
        assertEq(floan.getPositionCount(), expectedPositionCount_, "position count");
        assertEq(borrowerIds.length, expectedBorrowerPositionCount_, "borrower position count");
        assertEq(marketIds.length, expectedMarketPositionCount_, "market position count");
        assertEq(pairIds.length, expectedPairPositionCount_, "pair position count");
        assertTrue(_contains(borrowerIds, positionId_), "borrower index contains position");
        assertTrue(_contains(marketIds, positionId_), "market index contains position");
        assertTrue(_contains(pairIds, positionId_), "pair index contains position");
    }

    function _contains(uint256[] memory values_, uint256 value_) internal pure returns (bool) {
        for (uint256 i; i < values_.length; ++i) {
            if (values_[i] == value_) return true;
        }
        return false;
    }
}
