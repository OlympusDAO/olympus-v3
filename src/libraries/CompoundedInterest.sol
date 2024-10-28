// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

library CompoundedInterest {
    using FixedPointMathLib for uint256;

    function continuouslyCompounded(
        uint256 principal, 
        uint256 elapsedSecs, 
        uint96 interestRatePerSec
    ) internal pure returns (uint256 result) {
        return principal.mulWadDown(
            uint256(wadExp(int256(interestRatePerSec * elapsedSecs)))
        );
    }
}
