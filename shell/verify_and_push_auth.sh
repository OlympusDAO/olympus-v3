#!/usr/bin/env bash

# SPDX-FileCopyrightText: Contributors to OlympusDAO
# SPDX-License-Identifier: Unlicense

# Load environment variables
source .env

# Verify and push auth using script
forge script ./src/scripts/Deploy.sol:OlympusDeploy --sig "verifyAndPushAuth(address,address,address)()" $GUARDIAN_ADDRESS $POLICY_ADDRESS $EMERGENCY_ADDRESS --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow -vvv
# --broadcast
