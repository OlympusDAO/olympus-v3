// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {IERC165} from "@openzeppelin-5.3.0/utils/introspection/IERC165.sol";

/// @dev Test double that implements ERC-165 and explicitly rejects every interface query.
///      Used as a candidate configurator in negative `setConfigurator` paths to assert that
///      the periphery bridge rejects contracts that do not advertise
///      `ILZBridgeAndDelegateConfig` support.
contract MockERC165NonConfig is IERC165 {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4) external pure override returns (bool) {
        return false;
    }
}
