// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

contract ReentrantShareVault is MockERC4626 {
    error ReentrantShareVault_RedeemReverted();

    address internal _callbackInvoker;
    address internal _callbackTarget;
    bytes internal _callbackData;

    bool public callbackEnabled;
    bool public callbackSucceeded;
    bytes4 public callbackRevertSelector;
    bool public redeemShouldRevert;

    constructor(ERC20 asset_) MockERC4626(asset_, "Reentrant Share Vault", "rSHARE") {}

    // The fixture accepts arbitrary callback endpoints; zero addresses make the callback inert.
    // forge-lint: disable-next-line(missing-zero-check)
    function setCallbackFrom(address invoker_, address target_, bytes calldata data_) external {
        _callbackInvoker = invoker_;
        _callbackTarget = target_;
        _callbackData = data_;
        callbackEnabled = true;
    }

    function setRedeemShouldRevert(bool shouldRevert_) external {
        redeemShouldRevert = shouldRevert_;
    }

    function transfer(address to_, uint256 amount_) public override returns (bool) {
        bool success = super.transfer(to_, amount_);
        _executeCallback();
        return success;
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override returns (uint256 assets) {
        if (redeemShouldRevert) revert ReentrantShareVault_RedeemReverted();
        assets = super.redeem(shares_, receiver_, owner_);
        _executeCallback();
    }

    function _executeCallback() internal {
        if (callbackEnabled && msg.sender == _callbackInvoker) {
            callbackEnabled = false;
            bytes memory returnData;
            // The fixture must execute arbitrary callback data and retain failures for assertions.
            // forge-lint: disable-next-line(low-level-calls)
            (callbackSucceeded, returnData) = _callbackTarget.call(_callbackData);
            if (!callbackSucceeded && returnData.length >= 4) {
                // Only the leading four-byte error selector is retained after the length check.
                // forge-lint: disable-next-line(unsafe-typecast)
                callbackRevertSelector = bytes4(returnData);
            }
        }
    }
}
