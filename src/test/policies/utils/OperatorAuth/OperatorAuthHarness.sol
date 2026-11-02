// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {OperatorAuth} from "src/policies/utils/OperatorAuth.sol";

contract OperatorAuthHarness is OperatorAuth {
    function requireSenderAuthorized(address sender_, address onBehalfOf_) external view {
        _requireSenderAuthorized(sender_, onBehalfOf_);
    }
}
