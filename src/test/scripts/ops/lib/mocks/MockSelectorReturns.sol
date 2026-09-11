// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

/// @notice A mock that answers any call with the raw return data configured for its selector,
///         or reverts. Stands in for a router, an on-ramp or a fee quoter whose return shapes a
///         test wants to control word by word.
contract MockSelectorReturns {
    mapping(bytes4 => bytes) internal _returnData;
    mapping(bytes4 => bool) internal _reverts;

    /// @notice Sets the raw return data of a selector and clears its revert flag.
    function setReturn(bytes4 selector_, bytes memory data_) external {
        _returnData[selector_] = data_;
        _reverts[selector_] = false;
    }

    /// @notice Makes a selector revert with empty data.
    function setRevert(bytes4 selector_) external {
        _reverts[selector_] = true;
    }

    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        if (_reverts[msg.sig]) revert();
        bytes memory data = _returnData[msg.sig];
        // solhint-disable-next-line no-inline-assembly
        assembly {
            return(add(data, 32), mload(data))
        }
    }
}
