// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20 as OZERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {BL_YIELD_CLAIMER_ROLE} from "src/policies/burnerloans/libraries/LoanActionRoles.sol";

// Contracts
import {Actions} from "src/Kernel.sol";
import {BurnerLoansYieldClaimerTask} from "src/policies/burnerloans/BurnerLoansYieldClaimerTask.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC4626} from "src/test/mocks/MockERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {BurnerLoansSeizeIntegrationTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeIntegrationTestBase.sol";

// Literals are independent expected values and boundary seeds.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansSeizeSharesIntegrationTest is BurnerLoansSeizeIntegrationTestBase {
    function _shareAsset() internal returns (MockERC20 token, MockERC4626 vault) {
        token = new MockERC20("Share collateral", "SC", 6);
        vault = new MockERC4626(OZERC20(address(token)), "Share vault", "SV");
        token.mint(address(this), 100);
        assertTrue(token.approve(address(vault), 1), "Seed vault approval succeeds");
        vault.deposit(1, address(this));
        assertTrue(token.transfer(address(vault), 99), "Seed vault yield transfer succeeds");
        _admitVault(
            address(token),
            address(vault),
            IBurnerLoansRisk.AssetRiskConfigInput(10000, 10000, 100, 30 days, 90 days, 1000),
            true
        );
    }

    // Scenarios: BLLIQ-SEIZE-N02, BLLIQ-SEIZE-P18.
    function test_givenSubShareReward_whenSharesSeized_thenWholeShareToTreasury() public {
        (MockERC20 token, MockERC4626 vault) = _shareAsset();
        _open(address(token), _borrower, 100, 1);
        // Each share is 100 raw assets. floor(100*1%)=1 raw asset; floor(1/100)=0 shares.
        _expire();
        _assertSeizure(address(token), address(vault), 0, 1);
    }

    // Scenarios: BLLIQ-SEIZE-N04, BLLIQ-SEIZE-P18.
    function test_givenPositiveCreditAndZeroShareOutput_whenSeized_thenNoPayout() public {
        (MockERC20 token, MockERC4626 vault) = _shareAsset();
        _open(address(token), _borrower, 100, 1);
        token.mint(address(vault), 200);
        // Two shares now backed by 400 assets. Redeeming 100 credited assets as shares floors to 0.
        _expire();
        _assertSeizure(address(token), address(vault), 0, 0);
        assertEq(
            vault.balanceOf(address(_depositManager)),
            1,
            "Rounding dust remains in DepositManager"
        );
        BurnerLoansYieldClaimerTask claimer = new BurnerLoansYieldClaimerTask(
            _kernel,
            address(_core),
            2_000_000
        );
        _kernel.executeAction(Actions.ActivatePolicy, address(claimer));
        _rolesAdmin.grantRole(BL_YIELD_CLAIMER_ROLE, address(claimer));
        claimer.enable("");
        (address output, uint256 claimed) = claimer.claimYield(address(token));
        assertEq(output, address(vault), "Dust claimed in share units");
        assertEq(claimed, 1, "One remaining share is claimable yield");
        assertEq(vault.balanceOf(_payout.treasury()), 1, "Treasury receives retained share");
        assertEq(vault.balanceOf(address(_depositManager)), 0, "Custody dust fully claimed");
    }

    // Scenarios: BLLIQ-SEIZE-R03, BLLIQ-SEIZE-P18.
    function test_givenExternalSharesWithDifferentDecimals_whenSeized_thenActualShareTokenPaid()
        public
    {
        MockERC20 token = new MockERC20("18 decimal collateral", "COL", 18);
        MockERC7540ExternalShareVault vault = new MockERC7540ExternalShareVault(
            OZERC20(address(token)),
            false,
            true,
            true
        );
        _admitVault(
            address(token),
            address(vault),
            IBurnerLoansRisk.AssetRiskConfigInput(10000, 10000, 100, 30 days, 90 days, 1000e18),
            true
        );
        _open(address(token), _borrower, 2000e18, 100e9);
        // 2000e18 underlying / 1e12 = 2000e6 external shares.
        // Reward = 1% of 2000e18 = 20e18 -> 20e6 shares. Treasury = 1980e6 shares.
        _expire();
        _assertSeizure(address(token), vault.share(), 20e6, 1980e6);
        assertEq(token.balanceOf(_keeper), 0, "Keeper receives shares, no underlying");
        assertEq(token.balanceOf(address(vault)), 2000e18, "Asynchronous vault retains underlying");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
