// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";

interface IPolicyEnablerV2 is IEnabler {
    enum State {
        AdminDisabled,
        Enabled,
        EmergencyDisabled
    }

    event Transition(
        address indexed by,
        State indexed from,
        State indexed to,
        bytes data,
        uint48 at
    );

    error InvalidTransition(State from, State to);

    function state() external view returns (State);

    function lastTransitionAt() external view returns (uint48);

    function reEnable() external;
}
