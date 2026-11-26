// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.27;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {MockERC7540ExternalShareVault} from "src/test/mocks/MockERC7540ExternalShareVault.sol";
import {DepositManagerDonationTest} from "./fixtures/DepositManagerDonationTest.sol";
import {DepositManagerDonationVault} from "./fixtures/DepositManagerDonationActors.sol";
import {DepositManagerDonationHandler} from "./fixtures/DepositManagerDonationHandler.sol";

contract DepositManagerDonationInvariantTest is DepositManagerDonationTest {
    DepositManagerDonationHandler internal _handler;

    function setUp() public override {
        super.setUp();
        MockERC20[3] memory tokens;
        address[3] memory vaults;
        IERC20[3] memory custody;
        for (uint256 r; r < 3; ++r) {
            tokens[r] = new MockERC20("Invariant donation underlying", "IDU", 18);
            if (r == 1)
                vaults[r] = address(new DepositManagerDonationVault(OZIERC20(address(tokens[r]))));
            if (r == 2)
                vaults[r] = address(
                    new MockERC7540ExternalShareVault(
                        OZIERC20(address(tokens[r])),
                        false,
                        false,
                        true
                    )
                );
            vm.startPrank(ADMIN);
            depositManager.addAsset(
                IERC20(address(tokens[r])),
                IERC4626(vaults[r]),
                type(uint256).max,
                0
            );
            depositManager.addAssetPeriod(IERC20(address(tokens[r])), 1, DEPOSIT_OPERATOR);
            depositManager.addAssetPeriod(IERC20(address(tokens[r])), 1, _otherOperator);
            vm.stopPrank();
            custody[r] = r == 0
                ? IERC20(address(tokens[r]))
                : depositManager.getAssetWithdrawalToken(IERC20(address(tokens[r])), true);
        }
        _handler = new DepositManagerDonationHandler(
            depositManager,
            ADMIN,
            tokens,
            vaults,
            custody,
            [DEPOSIT_OPERATOR, _otherOperator],
            [_donor, makeAddr("independentDonor")]
        );
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = _handler.donate.selector;
        selectors[1] = _handler.deposit.selector;
        selectors[2] = _handler.withdraw.selector;
        selectors[3] = _handler.claimYield.selector;
        selectors[4] = _handler.borrow.selector;
        selectors[5] = _handler.repay.selector;
        selectors[6] = _handler.gain.selector;
        selectors[7] = _handler.loss.selector;
        selectors[8] = _handler.unsolicited.selector;
        selectors[9] = _handler.pauseResume.selector;
        selectors[10] = _handler.assertModels.selector;
        targetSelector(FuzzSelector(address(_handler), selectors));
        targetContract(address(_handler));
    }

    // Scenarios: DM-DONATE-P15, DM-DONATE-P16, DM-DONATE-P17.
    function invariant_donationsPreserveIndependentPrincipalAndCustodyModels() public view {
        _handler.assertModels();
    }

    // Scenarios: DM-DONATE-P15, DM-DONATE-P16, DM-DONATE-P17.
    function test_givenAllCustodyRoutes_whenDeterministicActionSequence() public {
        for (uint8 r; r < 3; ++r) {
            _handler.deposit(r, 0, 100e15);
            _handler.deposit(r, 1, 70e15);
            _handler.borrow(r, 0, 10e15);
            _handler.repay(r, 0, 1, 5e15);
            _handler.donate(r, 1, 0, 20e15);
            _handler.claimYield(r, 1, 5e15);
            _handler.withdraw(r, 0, 5e15);
            _handler.unsolicited(r, 2e15);
        }
        _handler.loss(0, 10e15);
        _handler.loss(1, 10e15);
        _handler.donate(1, 0, 1, 1e15);
        _handler.donate(2, 0, 0, 1e15);
        _handler.deposit(1, 0, 1e15);
        _handler.deposit(2, 0, 1e15);
        _handler.pauseResume();
        _handler.donate(0, 0, 0, 1e15);
        _handler.donate(1, 1, 1, 1e15);
        _handler.pauseResume();
        _handler.gain(0, 10e15);
        _handler.gain(1, 10e15);
        _handler.assertModels();
        assertGe(
            _handler.donations(),
            7,
            "Seed sequence executes donations across routes and pause"
        );
        assertGe(_handler.deposits(), 6, "Seed sequence executes ordinary deposits on each route");
        assertEq(_handler.borrows(), 3, "Seed sequence exercises borrowing on each route");
        assertEq(_handler.repayments(), 3, "Seed sequence exercises repayments on each route");
        assertEq(_handler.withdrawals(), 3, "Seed sequence exercises receipt exits on each route");
        assertEq(_handler.yieldClaims(), 3, "Seed sequence exercises yield on each route");
    }
}
