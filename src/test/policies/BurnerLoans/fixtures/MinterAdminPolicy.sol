// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

contract MinterAdminPolicy is Policy {
    MINTRv1 internal _mintr;

    constructor(Kernel kernel_) Policy(kernel_) {}

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MINTR");
        _mintr = MINTRv1(getModuleAddress(dependencies[0]));
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](2);
        requests[0] = Permissions({
            keycode: toKeycode("MINTR"),
            funcSelector: _mintr.increaseMintApproval.selector
        });
        requests[1] = Permissions({
            keycode: toKeycode("MINTR"),
            funcSelector: _mintr.deactivate.selector
        });
    }

    function approveMinter(address policy_, uint256 amount_) external {
        _mintr.increaseMintApproval(policy_, amount_);
    }

    function deactivateMinter() external {
        _mintr.deactivate();
    }
}
