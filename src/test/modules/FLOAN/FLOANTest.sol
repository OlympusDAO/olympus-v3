// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test
import {Test} from "@forge-std-1.9.6/Test.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

// Contracts
import {Actions, Kernel, Module} from "src/Kernel.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {OlympusFixedTermLoan} from "src/modules/FLOAN/OlympusFixedTermLoan.sol";

abstract contract FLOANTest is Test {
    using ModuleTestFixtureGenerator for Module;

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

        manager = Module(address(floan)).generateGodmodeFixture(type(OlympusFixedTermLoan).name);
        otherManager = Module(address(floan)).generateGodmodeFixture(
            type(OlympusFixedTermLoan).name
        );
        facility = Module(address(floan)).generateGodmodeFixture(type(OlympusFixedTermLoan).name);
        otherFacility = Module(address(floan)).generateGodmodeFixture(
            type(OlympusFixedTermLoan).name
        );

        kernel.executeAction(Actions.ActivatePolicy, manager);
        kernel.executeAction(Actions.ActivatePolicy, otherManager);
        kernel.executeAction(Actions.ActivatePolicy, facility);
        kernel.executeAction(Actions.ActivatePolicy, otherFacility);

        collateralToken = makeAddr("collateralToken");
        otherCollateralToken = makeAddr("otherCollateralToken");
        debtToken = makeAddr("debtToken");
        otherDebtToken = makeAddr("otherDebtToken");
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
    ) internal pure returns (IFLOANv1.Market memory) {
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
                collateralFactorBps: 9_000,
                minCollateralRatioBps: 12_000,
                baseFeeBps: 100,
                collateralDecimals: 18,
                debtDecimals: 9,
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
            _market(manager_, facility_, collateralToken_, debtToken_, principalCap_),
            abi.encode(uint256(123))
        );
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
}
