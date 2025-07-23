#!/bin/bash

dfx identity use minter

dfx canister call icrc1_ledger_canister icrc1_transfer "(record { to = record { owner = principal \"$1\"; }; amount = $2; })"

dfx identity use default