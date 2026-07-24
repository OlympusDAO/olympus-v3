// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {MockDepositManager} from "src/test/mocks/MockDepositManager.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansDepositCollateralTest is BurnerLoansTest {
    address internal operator;

    function setUp() public override {
        super.setUp();
        operator = makeAddr("operator");
        _addDefaultUsdsAsset();
    }

    modifier givenMockDepositManager() {
        _useMockDepositManager();
        _;
    }

    // Condition tree:
    // - Market state: the collateral/debt pair resolves to a non-Burner-Loans config ID
    // - Config data state: malformed and not decodable as Burner Loans data
    // - Action: preview and execute a collateral deposit
    // - Expected branch: both reject the incompatible schema before decoding config data
    function test_givenDifferentConfigId_revertsBeforeDecoding() public {
        bytes16 incompatibleConfigId = bytes16("Different config");
        uint32 marketId = _replaceMarketConfigForTest(address(usds), incompatibleConfigId, hex"01");
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_IncompatibleMarketConfig.selector,
            marketId,
            incompatibleConfigId
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Market state: the collateral/debt pair has the Burner Loans config ID
    // - Config data state: malformed encoded byte length
    // - Action: preview and execute a collateral deposit
    // - Expected branch: both reject the byte length before ABI decoding
    function test_givenInvalidConfigDataLength_revertsBeforeDecoding() public {
        uint32 marketId = _replaceMarketConfigForTest(
            address(usds),
            bytes16("Burner Loans v1"),
            hex"01"
        );
        bytes memory expectedError = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidMarketConfigData.selector,
            marketId,
            1
        );

        vm.expectRevert(expectedError);
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(expectedError);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Authorization state: owner acts on own account
    // - Custody path: direct DepositManager custody
    // - Expected branch: collateral is credited from DepositManager actual amount
    function test_depositCollateral_givenOwnerCaller_creditsDirectCustody() public {
        _mintAndApprove(address(usds), alice, 1_000e6);
        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            1_000e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 1_000e6, 1_000e6);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            1_000e6,
            alice
        );

        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, 1_000e6, "deposited");
        assertEq(total, 1_000e6, "total");
        _assertPositionAndActiveDebt(address(usds), alice, 1_000e6, 0, 0);
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
        assertEq(usds.balanceOf(address(depositManager)), 1_000e6, "deposit manager balance");
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            1_000e6,
            "receipt balance"
        );
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            1_000e6,
            "deposit manager liabilities"
        );
    }

    // Condition tree:
    // - Caller: owner (`alice`)
    // - Contract balance state: unsolicited collateral dust was transferred directly to BurnerLoans
    // - Custody path: direct DepositManager custody for the new deposit amount
    // - Expected branch: deposit succeeds because the operation does not create additional residual balance
    function test_depositCollateral_givenPreexistingDirectDust_creditsDirectCustody() public {
        usds.mint(address(burnerLoans), 1);
        _mintAndApprove(address(usds), alice, 1_000e6);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            1_000e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 1_000e6, 1_000e6);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            1_000e6,
            alice
        );

        assertEq(deposited, 1_000e6, "deposited");
        assertEq(total, 1_000e6, "total");
        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(usds.balanceOf(address(burnerLoans)), 1, "preexisting dust remains");
        assertEq(usds.balanceOf(address(depositManager)), 1_000e6, "deposit manager balance");
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            1_000e6,
            "deposit manager liabilities"
        );
    }

    // Condition tree:
    // - Position state: active debt with configured collateral and maturity
    // - PRICE state: stale after the initial collateral deposit
    // - Action: owner deposits additional direct-custody collateral
    // - Expected branch: deposit succeeds without PRICE and changes only credited collateral
    function test_depositCollateral_givenActiveDebtAndStalePrice_preservesDebtAndMaturity() public {
        _mintAndApprove(address(usds), alice, 1_000e6);
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 1_000e6, 1_000e6);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(usds), 1_000e6, alice);

        uint256 debtOhm = 1e9;
        uint48 maturity = _setActiveDebtForAlice(1_000e6, debtOhm);
        vm.warp(block.timestamp + 10 days);
        price.setTimestamp(uint48(block.timestamp - 9 hours));
        _mintAndApprove(address(usds), alice, 100e6);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            100e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 100e6, 100e6);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            100e6,
            alice
        );

        assertEq(deposited, 100e6, "deposited");
        assertEq(total, 1_100e6, "total collateral");
        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        _assertPositionAndActiveDebt(address(usds), alice, 1_100e6, debtOhm, maturity);
    }

    // Condition tree:
    // - Position state: active debt with configured collateral and maturity
    // - PRICE state: collateral price is zero after the initial collateral deposit
    // - Action: owner previews and deposits additional direct-custody collateral
    // - Expected branch: deposit succeeds without PRICE and changes only credited collateral
    function test_depositCollateral_givenActiveDebtAndZeroPrice_preservesDebtAndMaturity() public {
        _mintAndApprove(address(usds), alice, 1_000e6);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(usds), 1_000e6, alice);

        uint256 debtOhm = 1e9;
        uint48 maturity = _setActiveDebtForAlice(1_000e6, debtOhm);
        price.setPrice(address(usds), 0);
        _mintAndApprove(address(usds), alice, 100e6);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            100e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 100e6, 100e6);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            100e6,
            alice
        );

        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, 100e6, "deposited");
        assertEq(total, 1_100e6, "total collateral");
        _assertPositionAndActiveDebt(address(usds), alice, 1_100e6, debtOhm, maturity);
    }

    // Condition tree:
    // - Position state: collateral asset remains configured and enabled
    // - PRICE state: configured collateral price is zero
    // - Action: owner previews and deposits direct-custody collateral
    // - Expected branch: deposit succeeds without PRICE and preview equals the write result
    function test_depositCollateral_givenZeroPrice_succeedsWithoutPriceRead() public {
        price.setPrice(address(usds), 0);
        _mintAndApprove(address(usds), alice, 100e6);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            100e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 100e6, 100e6);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            100e6,
            alice
        );

        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, 100e6, "deposited");
        assertEq(total, 100e6, "total");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            100e6,
            "position collateral"
        );
    }

    // Condition tree:
    // - Position state: owner starts without collateral
    // - Custody path: two sequential direct DepositManager deposits
    // - Action: owner previews and performs the second deposit after the first credit
    // - Expected branch: preview total and position include both deposits without residual custody balance
    function test_depositCollateral_givenExistingCollateral_updatesPreviewTotalAndPosition()
        public
    {
        _mintAndApprove(address(usds), alice, 400e6);
        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 400e6, 400e6);
        vm.prank(alice);
        burnerLoans.depositCollateral(address(usds), 400e6, alice);

        _mintAndApprove(address(usds), alice, 600e6);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            600e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, 600e6, 600e6);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            600e6,
            alice
        );

        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, 600e6, "deposited");
        assertEq(total, 1_000e6, "total");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            1_000e6,
            "position collateral"
        );
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
        assertEq(usds.balanceOf(address(depositManager)), 1_000e6, "deposit manager balance");
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            1_000e6,
            "deposit manager liabilities"
        );
    }

    // Condition tree:
    // - Caller: authorized operator
    // - Authorization state: owner authorized operator through a future deadline
    // - Custody path: direct DepositManager custody
    // - Expected branch: operator funds deposit and owner receives credited collateral
    function test_depositCollateral_givenAuthorizedOperator_creditsOwnerPosition() public {
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        _mintAndApprove(address(usds), alice, 1_000e6);
        _mintAndApprove(address(usds), operator, 250e6);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            250e6,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(operator, address(usds), alice, 250e6, 250e6);
        vm.prank(operator);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            250e6,
            alice
        );

        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, 250e6, "deposited");
        assertEq(total, 250e6, "total");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            250e6,
            "owner collateral"
        );
        assertEq(usds.balanceOf(operator), 0, "operator balance");
        assertEq(usds.balanceOf(alice), 1_000e6, "owner balance");
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: no authorization from owner to operator
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check reverts before custody
    function test_depositCollateral_givenUnauthorizedOperator_reverts() public {
        _mintAndApprove(address(usds), alice, 1e6);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(usds.balanceOf(alice), 1e6, "owner balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans balance");
        assertEq(usds.balanceOf(address(depositManager)), 0, "deposit manager balance");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "owner collateral"
        );
    }

    // Condition tree:
    // - Caller: operator
    // - Authorization state: owner authorization expired before call
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check reverts before custody
    function test_depositCollateral_givenExpiredAuthorization_reverts() public {
        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1));
        vm.warp(block.timestamp + 2);
        _mintAndApprove(address(usds), operator, 1e6);

        vm.prank(operator);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: fuzzed caller that is neither owner nor authorized operator
    // - Authorization state: owner has authorized only `operator`
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: authorization check reverts for every non-owner, non-operator caller
    function test_depositCollateral_givenUnauthorizedCaller_reverts(address caller_) public {
        vm.assume(caller_ != alice);
        vm.assume(caller_ != operator);

        _setAuthorizationAndExpectEvent(alice, operator, uint48(block.timestamp + 1 days));
        _mintAndApprove(address(usds), caller_, 1e6);

        vm.prank(caller_);
        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - Amount: zero
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: amount validation reverts before custody
    function test_depositCollateral_givenZeroAmount_reverts() public {
        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroAmount.selector);
        burnerLoans.depositCollateral(address(usds), 0, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - Asset: not configured in BurnerLoans
    // - Parameters: positive amount, onBehalfOf is owner
    // - Expected branch: asset configuration validation reverts
    function test_depositCollateral_givenUnsupportedAsset_reverts() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNSUP", USDS_DECIMALS);
        _mintAndApprove(address(unsupported), alice, 1e6);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
                address(unsupported)
            )
        );
        burnerLoans.depositCollateral(address(unsupported), 1e6, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - BurnerLoans state: globally disabled after asset configuration
    // - Custody state: DepositManager asset period remains healthy
    // - Expected branch: deposit reverts because global disable blocks state changes
    function test_depositCollateral_givenGlobalDisabled_reverts() public {
        vm.prank(emergency);
        burnerLoans.disable("");
        _mintAndApprove(address(usds), alice, 1e6);

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - Asset state: disabled after configuration
    // - Custody state: DepositManager asset period remains healthy
    // - Expected branch: deposit reverts because asset disable blocks new exposure
    function test_depositCollateral_givenAssetOriginationsDisabled_reverts() public {
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(usds), false);
        _mintAndApprove(address(usds), alice, 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
                address(usds)
            )
        );
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AssetOriginationsDisabled.selector,
                address(usds)
            )
        );
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: configured asset period disabled for BurnerLoans
    // - Parameters: asset remains configured in BurnerLoans
    // - Expected branch: custody support validation reverts
    function test_depositCollateral_givenDepositManagerPeriodDisabled_reverts() public {
        depositManager.disableAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        _mintAndApprove(address(usds), alice, 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.depositCollateral(address(usds), 1e6, alice);
    }

    // Condition tree:
    // - Custody implementation: real DepositManager with a configured and enabled period
    // - Operator authorization: BurnerLoans' DepositManager deposit-operator role is revoked
    // - Action: owner previews, then attempts a direct-custody deposit
    // - Expected branch: preview remains an accounting estimate, write reverts at DepositManager and rolls back
    function test_depositCollateral_givenBurnerLoansIsNotDepositOperator_reverts() public {
        _mintAndApprove(address(usds), alice, 1_000e6);
        bytes32 depositOperatorRole = depositManager.ROLE_DEPOSIT_OPERATOR();
        vm.prank(admin);
        rolesAdmin.revokeRole(depositOperatorRole, address(burnerLoans));

        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            1_000e6,
            alice
        );
        assertEq(previewDeposit, 1_000e6, "preview deposit");
        assertEq(previewTotal, 1_000e6, "preview total");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, depositOperatorRole)
        );
        burnerLoans.depositCollateral(address(usds), 1_000e6, alice);

        assertEq(usds.balanceOf(alice), 1_000e6, "alice balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
        assertEq(
            depositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            0,
            "liabilities"
        );
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
    }

    // Condition tree:
    // - Custody implementation: real DepositManager disabled at the contract level
    // - Action: owner previews and then attempts a new collateral deposit
    // - Expected branch: preview and write reject unavailable custody before funds move
    function test_depositCollateral_givenDepositManagerDisabled_reverts() public {
        _mintAndApprove(address(usds), alice, 1_000e6);
        vm.prank(admin);
        depositManager.disable("");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.previewDepositCollateral(address(usds), 1_000e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(depositManager)
            )
        );
        burnerLoans.depositCollateral(address(usds), 1_000e6, alice);

        assertEq(usds.balanceOf(alice), 1_000e6, "alice balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: asset minimum deposit exceeds requested amount
    // - Parameters: asset is configured and enabled in BurnerLoans
    // - Expected branch: preview and write reject before custody transfer
    function test_depositCollateral_givenDepositManagerMinimumDepositNotMet_reverts() public {
        depositManager.setAssetMinimumDeposit(IERC20(address(usds)), 2e6);
        _mintAndApprove(address(usds), alice, 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(usds),
                1e6,
                2e6
            )
        );
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(usds),
                1e6,
                2e6
            )
        );
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(usds.balanceOf(alice), 1e6, "alice balance");
        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: asset deposit cap is lower than requested amount
    // - Parameters: asset is configured and enabled in BurnerLoans
    // - Expected branch: preview and write reject before custody transfer
    function test_depositCollateral_givenDepositManagerDepositCapExceeded_reverts() public {
        depositManager.setAssetDepositCap(IERC20(address(usds)), 999e6);
        _mintAndApprove(address(usds), alice, 1_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(usds),
                0,
                999e6
            )
        );
        burnerLoans.previewDepositCollateral(address(usds), 1_000e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(usds),
                0,
                999e6
            )
        );
        burnerLoans.depositCollateral(address(usds), 1_000e6, alice);

        assertEq(usds.balanceOf(alice), 1_000e6, "alice balance");
        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
    }

    // Condition tree:
    // - Caller: owner
    // - Token state: caller has balance but no BurnerLoans allowance
    // - Parameters: asset is configured, positive amount
    // - Expected branch: token transferFrom failure reverts before position credit
    function test_depositCollateral_givenMissingApproval_reverts() public {
        usds.mint(alice, 1e6);

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
    }

    // Condition tree:
    // - Caller: owner
    // - Token state: caller approved BurnerLoans but has insufficient balance
    // - Parameters: asset is configured, positive amount
    // - Expected branch: token transferFrom failure reverts before position credit
    function test_depositCollateral_givenInsufficientBalance_reverts() public {
        vm.prank(alice);
        usds.approve(address(burnerLoans), 1e6);

        vm.prank(alice);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
    }

    // Condition tree:
    // - Caller: owner
    // - Custody path: DepositManager asset uses ERC4626 vault with existing yield
    // - Rounding: vault share rate makes actual withdrawable amount differ from raw input
    // - Expected branch: credited collateral equals DepositManager actual amount
    function test_depositCollateral_givenVaultCustody_creditsActualAmount() public {
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAssetWithYield();
        uint128 amount = 1_000e6;
        _mintAndApprove(address(vaultAsset), alice, amount);
        (uint256 receiptTokenId, ) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );

        uint256 expectedCredit = _expectedVaultCredit(vault, amount);
        (uint256 previewCredit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(vaultAsset),
            amount,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(
            alice,
            address(vaultAsset),
            alice,
            amount,
            expectedCredit
        );
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(vaultAsset),
            amount,
            alice
        );

        _assertDepositMatchesPreview(
            address(vaultAsset),
            alice,
            previewCredit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, expectedCredit, "deposited");
        assertEq(total, expectedCredit, "total");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            expectedCredit,
            "deposit manager liabilities"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "burner loans asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "burner loans share residual");
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            expectedCredit,
            "receipt balance"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Amount: fuzzed positive direct-custody deposit
    // - Parameters: asset is configured, onBehalfOf is owner
    // - Expected branch: credited collateral tracks amount exactly for direct custody
    function test_depositCollateral_givenDirectCustodyAmount_creditsAmount(uint128 amount_) public {
        amount_ = uint128(bound(amount_, 1, 1_000_000e6));
        _mintAndApprove(address(usds), alice, amount_);
        (uint256 previewDeposit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(usds),
            amount_,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(alice, address(usds), alice, amount_, amount_);
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(usds),
            amount_,
            alice
        );

        _assertDepositMatchesPreview(
            address(usds),
            alice,
            previewDeposit,
            previewTotal,
            deposited,
            total
        );
        assertEq(deposited, amount_, "deposited");
        assertEq(total, amount_, "total");
    }

    // Condition tree:
    // - Caller: owner
    // - Custody path: vault with fuzzed share-rate/yield skew
    // - Amount: fuzzed positive deposit
    // - Expected branch: write credits the actual DepositManager amount, which can differ from the view quote
    function test_depositCollateral_givenVaultShareRate_creditsWithdrawableAmount(
        uint128 amount_,
        uint256 yield_
    ) public {
        amount_ = uint128(bound(amount_, 1, 1_000_000e6));
        yield_ = bound(yield_, 1, 10_000_000e6);
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _seedVault(vaultAsset, vault, 1_000_000e6);
        vaultAsset.mint(address(vault), yield_);
        _mintAndApprove(address(vaultAsset), alice, amount_);

        uint256 expectedCredit = _expectedVaultCredit(vault, amount_);
        vm.assume(expectedCredit > 0);
        (uint256 previewCredit, uint256 previewTotal) = burnerLoans.previewDepositCollateral(
            address(vaultAsset),
            amount_,
            alice
        );

        vm.expectEmit(true, true, true, true, address(burnerLoans));
        emit IBurnerLoans.CollateralDeposited(
            alice,
            address(vaultAsset),
            alice,
            amount_,
            expectedCredit
        );
        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(vaultAsset),
            amount_,
            alice
        );

        assertEq(deposited, expectedCredit, "deposited");
        assertEq(total, expectedCredit, "total");
        assertGt(previewCredit, 0, "preview credit");
        assertEq(previewTotal, previewCredit, "preview total");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            expectedCredit,
            "position collateral"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "burner loans asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "burner loans share residual");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            expectedCredit,
            "deposit manager liabilities"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Custody path: real DepositManager ERC4626 vault
    // - Vault state: fuzzed yield accrues after the caller reads the deposit preview
    // - Expected branch: write credits DepositManager's current actual amount, not the stale quote
    function test_depositCollateral_givenVaultYieldAfterPreview_creditsCurrentActualAmount(
        uint256 yield_
    ) public {
        uint128 amount = 1e6;
        yield_ = bound(yield_, 1, 1_000_000e6);
        uint256 seededAssets = yield_ * amount + 1;
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _seedVault(vaultAsset, vault, seededAssets);
        _mintAndApprove(address(vaultAsset), alice, amount);

        (uint256 quotedCredit, uint256 quotedTotal) = burnerLoans.previewDepositCollateral(
            address(vaultAsset),
            amount,
            alice
        );
        vaultAsset.mint(address(vault), yield_);
        uint256 expectedCredit = _expectedVaultCredit(vault, amount);

        assertTrue(quotedCredit != expectedCredit, "quote changes after yield");

        vm.prank(alice);
        (uint256 deposited, uint256 total) = burnerLoans.depositCollateral(
            address(vaultAsset),
            amount,
            alice
        );

        assertEq(deposited, expectedCredit, "deposited");
        assertEq(total, expectedCredit, "total");
        assertEq(total, quotedTotal - quotedCredit + deposited, "updated total");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            expectedCredit,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            expectedCredit,
            "deposit manager liabilities"
        );
    }

    // Condition tree:
    // - Caller: owner
    // - Custody path: vault with fuzzed high share rate
    // - Rounding: previewDeposit(amount) rounds to zero shares, so withdrawable credit is zero
    // - Expected branch: preview rejects the deposit before state-changing custody can create accounting drift
    function test_depositCollateral_givenVaultShareRateRoundsCreditToZero_reverts(
        uint128 amount_
    ) public {
        amount_ = uint128(bound(amount_, 1, 1_000e6));
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        uint256 seedAmount = 1_000_000e6;
        _seedVault(vaultAsset, vault, seedAmount);
        vaultAsset.mint(address(vault), amount_ * seedAmount);
        _mintAndApprove(address(vaultAsset), alice, amount_);

        assertEq(_expectedVaultCredit(vault, amount_), 0, "expected zero credit");
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroCollateralCredit.selector);
        burnerLoans.previewDepositCollateral(address(vaultAsset), amount_, alice);
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: injected removal of the configured period after asset configuration
    // - Parameters: asset remains configured and enabled in BurnerLoans
    // - Expected branch: preview and write reject unsupported custody before token transfer
    function test_depositCollateral_givenInjectedUnsupportedPeriod_reverts()
        public
        givenMockDepositManager
    {
        mockDepositManager.removeAssetPeriod(
            IERC20(address(usds)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        _mintAndApprove(address(usds), alice, 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(mockDepositManager)
            )
        );
        burnerLoans.previewDepositCollateral(address(usds), 1e6, alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
                address(mockDepositManager)
            )
        );
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(usds.balanceOf(alice), 1e6, "alice balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager state: injected deposit failure after BurnerLoans pulls collateral
    // - Parameters: asset is configured, positive amount
    // - Expected branch: transaction rollback leaves position and balances unchanged
    function test_depositCollateral_givenInjectedDepositManagerFailure_reverts()
        public
        givenMockDepositManager
    {
        _mintAndApprove(address(usds), alice, 1e6);
        mockDepositManager.setDepositReverts(true);

        vm.prank(alice);
        vm.expectRevert(MockDepositManager.MockDepositManager_TransferFailed.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
        assertEq(usds.balanceOf(alice), 1e6, "alice balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager accounting: injected deposit returns zero withdrawable credit
    // - Parameters: asset is configured, amount is positive
    // - Expected branch: zero credit reverts and transaction rollback preserves balances
    function test_depositCollateral_givenInjectedZeroWithdrawableCredit_reverts()
        public
        givenMockDepositManager
    {
        _mintAndApprove(address(usds), alice, 1e6);
        mockDepositManager.setDepositActualAmountOverride(true, 0);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroCollateralCredit.selector);
        burnerLoans.depositCollateral(address(usds), 1e6, alice);

        assertEq(usds.balanceOf(alice), 1e6, "alice balance");
        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
    }

    // Condition tree:
    // - Caller: owner
    // - DepositManager accounting: injected zero withdrawable credit for fuzzed positive input
    // - Parameters: direct custody transfer would otherwise succeed
    // - Expected branch: no BurnerLoans or DepositManager accounting is retained
    function test_depositCollateral_givenInjectedZeroWithdrawableCreditAmount_reverts(
        uint128 amount_
    ) public givenMockDepositManager {
        amount_ = uint128(bound(amount_, 1, 1_000_000e6));
        _mintAndApprove(address(usds), alice, amount_);
        mockDepositManager.setDepositActualAmountOverride(true, 0);

        vm.prank(alice);
        vm.expectRevert(IBurnerLoans.BurnerLoans_ZeroCollateralCredit.selector);
        burnerLoans.depositCollateral(address(usds), amount_, alice);

        assertEq(usds.balanceOf(alice), amount_, "alice balance");
        assertEq(usds.balanceOf(address(burnerLoans)), 0, "burner loans residual");
        assertEq(
            mockDepositManager.getOperatorLiabilities(IERC20(address(usds)), address(burnerLoans)),
            0,
            "liabilities"
        );
        assertEq(burnerLoans.getPosition(address(usds), alice).depositedCollateral, 0, "position");
    }

    function _expectedVaultCredit(
        MockERC4626 vault_,
        uint256 amount_
    ) internal view returns (uint256) {
        uint256 shares = vault_.previewDeposit(amount_);
        if (shares == 0) return 0;
        return (shares * (vault_.totalAssets() + amount_)) / (vault_.totalSupply() + shares);
    }

    function _mintAndApprove(address asset_, address owner_, uint256 amount_) internal {
        MockERC20(asset_).mint(owner_, amount_);
        vm.prank(owner_);
        MockERC20(asset_).approve(address(burnerLoans), amount_);
    }

    function _addVaultAssetWithYield() internal returns (MockERC20, MockERC4626) {
        (MockERC20 vaultAsset, MockERC4626 vault) = _addVaultAsset();
        _seedVault(vaultAsset, vault, 1_000_000e6);
        vaultAsset.mint(address(vault), 100e6);
        return (vaultAsset, vault);
    }

    function _seedVault(MockERC20 vaultAsset_, MockERC4626 vault_, uint256 amount_) internal {
        vaultAsset_.mint(address(this), amount_);
        vaultAsset_.approve(address(vault_), amount_);
        vault_.deposit(amount_, address(this));
    }

    function _addVaultAsset() internal returns (MockERC20 vaultAsset, MockERC4626 vault) {
        vaultAsset = new MockERC20("Vault USDS", "vUSDS", USDS_DECIMALS);
        vault = new MockERC4626(ERC20(address(vaultAsset)), "Vault", "VAULT");
        _configurePrice(address(vaultAsset), 1e18);
        depositManager.addAsset(
            IERC20(address(vaultAsset)),
            IERC4626(address(vault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(vaultAsset),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
    }

    function _setActiveDebtForAlice(
        uint256 collateral_,
        uint256 debtOhm_
    ) internal returns (uint48 maturity_) {
        maturity_ = uint48(block.timestamp + 30 days);
        burnerLoans.setPositionForTest(
            address(usds),
            alice,
            IBurnerLoans.Position({
                depositedCollateral: collateral_,
                debtOhm: debtOhm_,
                maturity: maturity_,
                lastBorrowBlock: uint48(block.number),
                status: IBurnerLoans.PositionStatus.Active
            })
        );
        burnerLoans.setActiveDebtForTest(address(usds), debtOhm_, debtOhm_);
    }
}
