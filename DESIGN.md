# Bophades

## Intro
Bophades is the third revision of Olympus protocol. It is a complete rewrite of the core contracts utilizing
the Default framework, which allows the system to take a pluggable, modular approach to its contracts while
maintaining immutability.

## Scope
- Kernel
- Minter (module)
- Treasury (module)
- Guidance (policy/module)
- Governor (policy/module)
- Auth (module)

## Authorization System
- Primary goal is to lock down the treasury and who has access to it.
- The Kernel handles which policies have write access (ability to mutate state) to modules
- The AUTHR module has controls which addresses can call gated policy functions
- AUTHR module is a fork of MultiRolesAuthority from Solmate

## Treasury