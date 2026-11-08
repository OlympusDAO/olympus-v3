// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Contracts
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

abstract contract BurnerLoansReferralTest is BurnerLoansDebtTest {
    address internal _referrer = address(0xFEED);

    function _mockFeeComponents(uint256 protocolFee_, uint256 referralFee_) internal {
        _mockRisk(0);
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(protocolFee_, referralFee_)
        );
    }

    function _feeCall(
        uint256 principal_,
        uint16 terms_,
        address referrer_
    ) internal view returns (bytes memory) {
        return
            abi.encodeCall(
                IBurnerLoansRisk.fee,
                (
                    IBurnerLoansCore.PriceSnapshot(1e18, 1e18, 1e18),
                    _core.marketId(address(_asset)),
                    principal_,
                    terms_,
                    referrer_
                )
            );
    }
}
