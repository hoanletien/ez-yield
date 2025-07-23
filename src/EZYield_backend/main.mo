import Bool "mo:base/Bool";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Time "mo:base/Time";
import Float "mo:base/Float";
import Debug "mo:base/Debug";
import Map "mo:motoko-hash-map/Map";
import ICRCLedger "canister:icrc1_ledger_canister";

actor class StakingDapp() = this {

  public type Stake = {
    amount : Nat;
    startTime : Int;
  };

  let transferFee : Nat = 10_000;

  let totalTimeInAYear : Int = 31536000000000000;

  let { phash } = Map;
  stable let usersStakes : Map.Map<Principal, Stake> = Map.new();

  private func transfer_funds_from_user(user : Principal, _amount : Nat) : async Bool {

    let allowAmount = await ICRCLedger.icrc2_allowance({
      account = { owner = user; subaccount = null };
      spender = {
        owner = Principal.fromActor(this);
        subaccount = null;
      };
    });

    let transferResults = await ICRCLedger.icrc2_transfer_from({
      spender_subaccount = null;

      from = {
        owner = user;
        subaccount = null;
      };
      to = {
        owner = Principal.fromActor(this);
        subaccount = null;
      };
      amount = _amount;
      fee = null;
      memo = null;
      created_at_time = null;

    });

    switch (transferResults) {
      case (#Ok(vakue)) { return true };
      case (#Err(error)) {
        return false;
      };
    };

  };

  private func transfer_tokens_from_canister(_amount : Nat, user : Principal) : async Bool {

    let transferResults = await ICRCLedger.icrc1_transfer({
      from_subaccount = null;
      to = {
        owner = user;
        subaccount = null;
      };
      fee = null;
      amount = _amount;
      memo = null;
      created_at_time = null;
    });

    switch (transferResults) {
      case (#Ok(value)) { return true };
      case (#Err(error)) { return false };
    };

  };

  private func calculate_rewards(_amount : Nat, _startTime : Int) : async Nat {
    let timeElapsed = Time.now() - _startTime;
    let realElapsedTime = Float.div(Float.fromInt(timeElapsed), Float.fromInt(totalTimeInAYear));
    let rewards = Float.mul(Float.mul(Float.fromInt(_amount), 0.08), realElapsedTime);
    return Int.abs(Float.toInt(rewards));
  };

  public shared ({ caller }) func claim_rewards() : async Result.Result<(), Text> {
    switch (Map.get(usersStakes, phash, caller)) {
      case (null) {
        return #err("no stake found");
      };
      case (?stake) {
        //get their rewards
        let rewards = await calculate_rewards(stake.amount, stake.startTime);
        if (rewards < 30000) {
          return #err("rewards too low, cant be claimed, keep staking");
        } else {
          let transfer = await transfer_tokens_from_canister(rewards - transferFee, caller);
          if (transfer) {
            Map.set(usersStakes, phash, caller, { stake with startTime = Time.now() });
            return #ok();
          } else {
            return #err("reward transfer failed");
          };
        };
      };
    };
  };

  public shared ({ caller }) func stake_tokens(_amount : Nat) : async Result.Result<(), Text> {
    let results = await transfer_funds_from_user(caller, _amount);
    if (results) {
      Map.set(usersStakes, phash, caller, { amount = _amount; startTime = Time.now() });
      return #ok();
    } else {
      return #err("unable to stake tokens");
    };
  };

  public shared ({ caller }) func unstake_tokens() : async Result.Result<(), Text> {
    switch (Map.get(usersStakes, phash, caller)) {
      case (?data) {
        let rewards = await calculate_rewards(data.amount, data.startTime);

        let transfered = await transfer_tokens_from_canister(data.amount + rewards - transferFee, caller);
        if (transfered) {
          let _ = Map.remove(usersStakes, phash, caller);
          return #ok();
        } else {
          return #err("transfer failed");
        };
      };
      case (null) { return #err("no stake found") };
    };
  };

  public func get_user_stake_info(user : Principal) : async Result.Result<{ amount : Nat; rewards : Nat; startTime : Int }, Text> {
    switch (Map.get(usersStakes, phash, user)) {
      case (?stake) {
        let rewards = await calculate_rewards(stake.amount, stake.startTime);
        return #ok({
          amount = stake.amount;
          rewards = rewards;
          startTime = stake.startTime;
        });
      };
      case (null) { return #err("no stake found") };
    };
  };

};
