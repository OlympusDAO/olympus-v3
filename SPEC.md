# Bophades

## Intro

Bophades is the third revision of Olympus protocol. It is a complete rewrite of the core contracts utilizing
the Default framework, which allows the system to take a modular approach to the protocol organization while
maintaining immutability and straightforward data flows. This architecture emphasizes readability and simplicity
to allow for an easily understandable system.

## Scope

-   Kernel
-   Minter (module)
-   Treasury (module)
-   Guidance (policy/module)
-   Governor (policy/module)
-   Auth (module)

## Kernel, Modules and Policies

-   Kernel
    -   Control center for protocol management and governance
    -   Has clearly defined "actions" for governance to control
    -   Handles adding and removing modules and policies to the system
    -   Stores, grants and revokes roles defined in modules and policies
-   Modules
    -   Storage of protocol shared state
    -   Have minimal dependencies
    -   Define a 5 byte keycode identifier used as a reference for the kernel and dependent policies
    -   Can be upgraded by installing a new module with the same keycode
    -   Has a `VERSION()` function with major and minor version numbers
    -   Defines roles to allow policies to call module functions
-   Policies
    -   Contracts for user interactions
    -   Generally contain isolated state
    -   Requests roles from kernel to call module functions

## Kernel Access Control system

-   The kernel contains a role based access control system for gating function access for modules and policies
-   Roles are defined as bytes32 strings in the `ROLES()` function of a module or policy
-   Roles are stored in the kernel's `roles` mapping
-   Roles must be activated in order for them to be granted by the kernel
-   Roles can be granted and revoked by the executor

-   Modules
    -   Module roles are prefixed by the module's keycode. ex: TRSRY_Withdrawer
    -   Roles are to be activated by the `InstallModule` action
    -   Roles are deactivated in two ways:
        -   If a role does not persist in a new module version after an upgrade
        -   By governance
-   Policies
    -   Policy roles are prefixed by a special keycode POLCY. ex: POLCY_DebtManager
    -   Roles are to be activated by the `ApprovePolicy` governance action
    -   Roles are deactivated by the `TerminatePolicy` governance action
    -   Roles are granted to a policy by the `requestRoles()` function
        -   Policy writers must ensure the requested role already exists and is active

## Treasury
