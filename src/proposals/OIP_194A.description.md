# OIP-194A: Cooler Drip Acceleration

## Context

OIP-194A implements the follow-up drip schedule to realize additional borrowing power from backing gains captured in OIP-191.

## Objective

The DAO recovered an estimated $0.49/OHM of backing gain in OIP-191. That gain is repurposed in this proposal by raising the Cooler V2 target origination LTV to 3123.1833 USDS/gOHM in a phased manner.

This is equivalent to ~131.9269 USDS/gOHM over six months and is implemented as a linear target via the cooler LTV oracle so borrowers can benefit progressively instead of through a discrete jump.

## Actions

1. Relax the max origination LTV rate-of-change guard on CoolerLtvOracle to permit scheduling the proposed target increment.
    - Current guard: 1_157_407_407_407 (1_157_407_407_407 / 1e18 = 0.000001157407407 USDS/gOHM/second; \* 86400 = 0.1 USDS/gOHM/day)
    - Proposal guard: 10_000_000_000_000 (10_000_000_000_000 / 1e18 = 0.00001 USDS/gOHM/second; \* 86400 = 0.864 USDS/gOHM/day)
    - Rationale: required to move to 3123.1833 USDS/gOHM by 2026-10-27 while submission occurs against the current schedule state. Required schedule rate from current on-chain state at submission: 7_964_547_568_016 (7_964_547_568_016 / 1e18 = 0.000007964547568016 USDS/gOHM/second; \* 86400 = 0.6881369098765824 USDS/gOHM/day).
2. Set the target origination LTV on CoolerLtvOracle to 3123.1833 USDS/gOHM (3123183268921960038400 in 18dp) with a target date of 2026-10-27 00:00:00 UTC (1793059200).
