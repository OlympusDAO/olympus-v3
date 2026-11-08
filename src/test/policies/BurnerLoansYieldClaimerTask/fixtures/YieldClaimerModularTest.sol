// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

abstract contract YieldClaimerModularTest is BurnerLoansModularTest {
    BurnerLoansYieldClaimerTask internal _claimer;
    MockERC20 internal _yieldAsset;
    MockERC4626 internal _yieldVault;
    address internal _heart = address(0xBEA7);

    function setUp() public virtual override {
        super.setUp();
        _claimer = new BurnerLoansYieldClaimerTask(_kernel, address(_core), 2_000_000);
        _kernel.executeAction(Actions.ActivatePolicy, address(_claimer));
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(_claimer));
        _rolesAdmin.grantRole(HEART_ROLE, _heart);
        _claimer.enable("");
        (_yieldAsset, _yieldVault) = _newVault(false);
        _deposit(address(_yieldAsset), 2000e6);
    }

    function _deposit(address token_, uint128 amount_) internal {
        MockERC20(token_).mint(_borrower, amount_);
        vm.startPrank(_borrower);
        MockERC20(token_).approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(token_, amount_, _borrower);
        vm.stopPrank();
    }

    function _admitVault(address token_, address vault_, bool shares_) internal {
        _price.setPrice(token_, 1e18);
        _depositManager.addAsset(IERC20(token_), IERC4626(vault_), type(uint256).max, 0);
        _depositManager.addAssetPeriod(
            IERC20(token_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        _config.addAsset(
            token_,
            100_000e9,
            IBurnerLoansRisk.AssetRiskConfigInput(8500, 12500, 100, 30 days, 90 days, 1000e18),
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0),
            shares_
        );
    }

    function _newVault(bool shares_) internal returns (MockERC20 token, MockERC4626 vault) {
        token = new MockERC20("Yield collateral", "YC", 6);
        vault = new MockERC4626(OZERC20(address(token)), "Yield vault", "YV");
        _admitVault(address(token), address(vault), shares_);
    }

    function _assertNoPayoutCustody(address token_) internal view {
        assertEq(IERC20(token_).balanceOf(address(_claimer)), 0, "Task never holds yield");
        assertEq(
            IERC20(token_).balanceOf(address(_payout)),
            0,
            "Yield never enters payout custody"
        );
        (uint256 fees, , uint256 seized, , uint256 total) = _payout.pendingAmounts(token_);
        assertEq(fees + seized + total, 0, "No new pending payout obligation");
    }
}
