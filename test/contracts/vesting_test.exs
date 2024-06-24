defmodule VestingTest do
  use InterpreterCase, async: true
  use ExUnitProperties

  import InterpreterCase

  @code File.read!("./test/contracts/vesting_contract.exs")
  @lp_token_address "00000000000000000000000000000000000000000000000000000000000000000001"
  @factory_address "00000000000000000000000000000000000000000000000000000000000000000002"
  @router_address "00000000000000000000000000000000000000000000000000000000000000000003"
  @master_address "00000000000000000000000000000000000000000000000000000000000000000004"
  @farm_address "00000000000000000000000000000000000000000000000000000000000000000005"
  @invalid_address "00000000000000000000000000000000000000000000000000000000000000000006"
  @start_date ~U[2024-01-01T00:00:00Z]
  @end_date ~U[2028-01-01T00:00:00Z]
  @initial_balance 90_000_000

  setup do
    constants = [
      {"@START_DATE", :date, @start_date},
      {"@END_DATE", :date, @end_date},
      {"@REWARD_TOKEN", :string, "UCO"},
      {"@FARM_ADDRESS", :string, @farm_address},
      {"@LP_TOKEN_ADDRESS", :string, @lp_token_address},
      {"@FACTORY_ADDRESS", :string, @factory_address},
      {"@ROUTER_ADDRESS", :string, @router_address},
      {"@MASTER_ADDRESS", :string, @master_address}
    ]

    {:ok, %{contract: create_contract(@code, constants)}}
  end

  test "deposit/1 should throw when it is past farm's end", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@end_date |> DateTime.add(1))

    assert {:throw, 1001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "deposit/1 should throw when it's transfer to the farm is 0", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(0))

    assert {:throw, 1002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "deposit/1 should throw when it contains no transfer to the farm", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date)

    assert {:throw, 1003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "deposit/1 should throw when it's transfer to the farm is not the correct token", %{
    contract: contract
  } do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@invalid_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 1004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "deposit/1 should throw when level is invalid", %{
    contract: contract
  } do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "-1"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 1005} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  property "deposit/1 should accept deposits if the farm hasn't started yet (1 user)", %{
    contract: contract
  } do
    check all(deposits <- deposits_generator(1)) do
      deposits =
        deposits
        |> Enum.map(fn {:deposit, payload} ->
          {:deposit, %{payload | delay: -1}}
        end)

      user_seed =
        deposits
        |> hd()
        |> elem(1)
        |> Access.get(:seed)

      max_delay =
        deposits
        |> Enum.reduce(0, fn {:deposit, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      {genesis_public_key, _} = Crypto.derive_keypair(user_seed, 0)
      genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()

      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, genesis_address, deposits,
        time_now: max_date,
        assert_fn: fn user_infos ->
          # also assert that no rewards calculated
          assert Decimal.eq?(
                   0,
                   Enum.map(user_infos, & &1["reward_amount"]) |> Enum.reduce(&Decimal.add/2)
                 )
        end
      )
    end
  end

  property "deposit/1 should accept deposits if the farm hasn't started yet (many users)", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count)
          ) do
      deposits =
        deposits
        |> Enum.map(fn {:deposit, payload} ->
          {:deposit, %{payload | delay: -1}}
        end)

      max_delay =
        deposits
        |> Enum.reduce(0, fn {:deposit, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, deposits,
        time_now: max_date,
        assert_fn: fn farm_infos ->
          # also assert that no rewards calculated
          assert farm_infos["remaining_rewards"] == @initial_balance
          assert farm_infos["rewards_reserved"] == 0
        end
      )
    end
  end

  property "deposit/1 should accept deposits if the farm has started (1 user)", %{
    contract: contract
  } do
    check all(deposits <- deposits_generator(1)) do
      user_seed =
        deposits
        |> hd()
        |> elem(1)
        |> Access.get(:seed)

      max_delay =
        deposits
        |> Enum.reduce(0, fn {:deposit, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      {genesis_public_key, _} = Crypto.derive_keypair(user_seed, 0)
      genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()

      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, genesis_address, deposits, time_now: max_date)
    end
  end

  property "deposit/1 should accept deposits if the farm has started (many users)", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count)
          ) do
      max_delay =
        deposits
        |> Enum.reduce(0, fn {:deposit, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, deposits, time_now: max_date)
    end
  end

  test "claim/1 should throw if farm hasn't started", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("claim", %{"deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(-1))

    assert {:throw, 2000} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "claim/1 should throw if user has no deposits", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("claim", %{"deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    MockChain
    |> expect(:get_genesis_address, fn _ -> trigger["genesis_address"] end)

    assert {:throw, 2001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "claim/1 should throw if index is invalid", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("claim", %{"deposit_index" => 999})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    MockChain
    |> expect(:get_genesis_address, 2, fn _ -> trigger1["genesis_address"] end)

    assert {:throw, 2002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "claim/1 should not be allowed if reward_amount is 0", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("claim", %{"deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    MockChain
    |> expect(:get_genesis_address, 3, fn _ -> trigger1["genesis_address"] end)

    assert {:condition_failed, _} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "claim/1 should transfer the funds and update the state", %{
    contract: contract
  } do
    check all(
            deposits <-
              StreamData.constant(
                deposit: %{
                  amount: Decimal.new("4611686018427388000.00000000"),
                  delay: 103,
                  level: "2",
                  seed: <<47, 96, 15, 116, 103, 39, 145, 144, 14, 125>>
                },
                deposit: %{
                  amount: Decimal.new("1E-8"),
                  delay: 232,
                  level: "2",
                  seed: <<47, 96, 15, 116, 103, 39, 145, 144, 14, 125>>
                },
                deposit: %{
                  amount: Decimal.new("1E-8"),
                  delay: 266,
                  level: "2",
                  seed: <<47, 96, 15, 116, 103, 39, 145, 144, 14, 125>>
                }
              ),
            claims <-
              StreamData.constant(
                claim: %{
                  delay: 104,
                  index: 0,
                  seed: <<47, 96, 15, 116, 103, 39, 145, 144, 14, 125>>
                },
                claim: %{
                  delay: 233,
                  index: 0,
                  seed: <<47, 96, 15, 116, 103, 39, 145, 144, 14, 125>>
                },
                claim: %{
                  delay: 267,
                  index: 0,
                  seed: <<47, 96, 15, 116, 103, 39, 145, 144, 14, 125>>
                }
              ),
              max_runs: 1,
              max_shrinking_steps: 0
          ) do
      # check all(
      #         count <- StreamData.integer(1..10),
      #         deposits <- deposits_generator(count),
      #         claims <- claims_generator(deposits)
      #       ) do
      actions = deposits ++ claims

      result_contract =
        run_actions(actions, contract, %{}, @initial_balance, ignore_condition_failed: true)

      max_delay =
        claims
        |> Enum.reduce(0, fn {:claim, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      IO.inspect(result_contract.state)

      asserts_get_farm_infos(result_contract, actions,
        time_now: max_date,
        assert_fn: fn farm_infos ->
        IO.inspect(farm_infos)
          assert farm_infos["stats"]
                 |> Map.values()
                 |> Enum.map(& &1["rewards_distributed"])
                 |> Enum.reduce(&Decimal.add/2)
                 |> Decimal.gt?(0)
        end
      )
    end
  end

  test "withdraw/2 should throw if user has no deposits", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("withdraw", %{"amount" => 1, "deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    MockChain
    |> expect(:get_genesis_address, fn _ -> trigger["genesis_address"] end)

    assert {:throw, 3001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "withdraw/2 should throw if index is invalid", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("withdraw", %{"amount" => 1, "deposit_index" => 999})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    MockChain
    |> expect(:get_genesis_address, 2, fn _ -> trigger1["genesis_address"] end)

    assert {:throw, 3002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "withdraw/2 should throw if amount is bigger than deposit", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "0"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("withdraw", %{"amount" => 2, "deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    MockChain
    |> expect(:get_genesis_address, 2, fn _ -> trigger1["genesis_address"] end)

    assert {:throw, 3003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "withdraw/2 should transfer the funds and update the state (withdraw max amount)", %{
    contract: contract
  } do
    check all(
            amounts_durations_seeds <-
              StreamData.list_of(
                StreamData.tuple(
                  {amount_generator(), StreamData.integer(1..365), StreamData.binary(length: 10)}
                ),
                min_length: 2,
                max_length: 10
              )
          ) do
      db =
        amounts_durations_seeds
        |> Enum.with_index()
        |> Enum.map(fn {{amount, duration, seed}, i} ->
          {
            amount,
            duration,
            Trigger.new(seed, 1)
            |> Trigger.named_action("deposit", %{"level" => "0"})
            |> Trigger.timestamp(@start_date |> DateTime.add(i + 1, :day))
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount),
            Trigger.new(seed, 2)
            |> Trigger.named_action("withdraw", %{
              "amount" => amount,
              "deposit_index" => 0
            })
            |> Trigger.timestamp(@start_date |> DateTime.add(i + 1 + duration, :day))
          }
        end)

      state = %{}

      triggers =
        (Enum.map(db, &elem(&1, 2)) ++ Enum.map(db, &elem(&1, 3)))
        |> Enum.sort_by(& &1["timestamp"])

      MockChain
      |> stub(:get_genesis_address, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state, uco_balance: next_uco_balance} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      assert 0 == map_size(next_state["deposits"])
      assert Decimal.eq?(0, next_state["lp_tokens_deposited"])
      assert Decimal.eq?(0, next_state["rewards_reserved"])

      assert Decimal.add(next_uco_balance, next_state["rewards_distributed"])
             |> Decimal.eq?(@initial_balance)
    end
  end

  property "withdraw/2 should transfer the funds and update the state (withdraw partial amount)",
           %{
             contract: contract
           } do
    check all(
            amounts_durations_seeds <-
              StreamData.list_of(
                StreamData.tuple(
                  {amount_generator(), StreamData.integer(1..365), StreamData.binary(length: 10)}
                ),
                min_length: 2,
                max_length: 10
              )
          ) do
      db =
        amounts_durations_seeds
        |> Enum.with_index()
        |> Enum.map(fn {{deposit_amount, duration, seed}, i} ->
          withdraw_amount = Decimal.div(deposit_amount, 2) |> Decimal.max("0.00000001")

          {
            deposit_amount,
            withdraw_amount,
            duration,
            Trigger.new(seed, 1)
            |> Trigger.named_action("deposit", %{"level" => "0"})
            |> Trigger.timestamp(@start_date |> DateTime.add(i + 1, :day))
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, deposit_amount),
            Trigger.new(seed, 2)
            |> Trigger.named_action("withdraw", %{
              "amount" => withdraw_amount,
              "deposit_index" => 0
            })
            |> Trigger.timestamp(@start_date |> DateTime.add(i + 1 + duration, :day))
          }
        end)

      state = %{}

      triggers =
        (Enum.map(db, &elem(&1, 3)) ++ Enum.map(db, &elem(&1, 4)))
        |> Enum.sort_by(& &1["timestamp"])

      MockChain
      |> stub(:get_genesis_address, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state, uco_balance: next_uco_balance} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      deposits = next_state["deposits"]

      assert amounts_durations_seeds
             |> Enum.reject(&Decimal.eq?(elem(&1, 0), Decimal.new("0.00000001")))
             |> length() == map_size(deposits)

      for {deposit_amount, withdraw_amount, _duration, trigger1, _trigger2} <- db do
        user_deposits = deposits[trigger1["genesis_address"]]

        remaining = Decimal.sub(deposit_amount, withdraw_amount)

        if Decimal.eq?(0, remaining) do
          assert is_nil(user_deposits)
        else
          refute user_deposits
                 |> Enum.find(&Decimal.eq?(&1["amount"], remaining))
                 |> is_nil()
        end
      end

      assert Decimal.eq?(
               next_state["rewards_reserved"],
               next_state["deposits"]
               |> Map.values()
               |> List.flatten()
               |> Enum.map(& &1["reward_amount"])
               |> Enum.reduce(0, &Decimal.add/2)
             )

      assert Decimal.add(next_uco_balance, next_state["rewards_distributed"])
             |> Decimal.eq?(@initial_balance)
    end
  end

  property "get_user_infos/1 should return the deposits details", %{contract: contract} do
    check all(
            amounts_levels_seeds <-
              StreamData.list_of(
                StreamData.tuple({
                  amount_generator(),
                  StreamData.integer(0..7) |> StreamData.map(&Integer.to_string/1),
                  StreamData.binary(length: 10)
                }),
                min_length: 2,
                max_length: 10
              )
          ) do
      db =
        amounts_levels_seeds
        |> Enum.with_index()
        |> Enum.map(fn {{amount, level, seed}, i} ->
          {
            amount,
            level,
            i,
            Trigger.new(seed, 1)
            |> Trigger.named_action("deposit", %{"level" => level})
            |> Trigger.timestamp(@start_date |> DateTime.add(i + 1, :day))
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount)
          }
        end)

      state = %{}

      triggers =
        Enum.map(db, &elem(&1, 3))
        |> Enum.sort_by(& &1["timestamp"])

      MockChain
      |> stub(:get_genesis_address, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert result_contract =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      for {amount, level, i, trigger} <- db do
        user_infos =
          call_function(result_contract, "get_user_infos", [trigger["genesis_address"]])

        assert length(user_infos) == 1
        user_info = hd(user_infos)
        assert String.to_integer(user_info["level"]) <= String.to_integer(level)
        assert Decimal.eq?(user_info["amount"], amount)
        assert 0 == user_info["index"]

        assert Decimal.eq?(
                 user_info["end"],
                 @start_date
                 |> DateTime.add(i + 1, :day)
                 |> DateTime.add(level_to_days(level) * 86400, :second)
                 |> DateTime.to_unix()
               )
      end
    end
  end

  property "get_farm_infos/0 should return the farm details", %{contract: contract} do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count)
          ) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, deposits)
    end
  end

  defp asserts_get_farm_infos(contract, actions, opts \\ []) do
    uco_balance = contract.uco_balance

    farm_infos =
      call_function(
        contract,
        "get_farm_infos",
        [],
        Keyword.get(opts, :time_now, DateTime.utc_now())
      )

    assert farm_infos["end_date"] == DateTime.to_unix(@end_date)
    assert farm_infos["start_date"] == DateTime.to_unix(@start_date)
    assert farm_infos["reward_token"] == "UCO"
    assert farm_infos["stats"] |> Map.keys() == ["0", "1", "2", "3", "4", "5", "6", "7"]

    # tokens deposited is coherent with stats
    expected_lp_tokens_deposited =
      actions
      |> Enum.reduce(0, fn
        {:deposit, %{amount: amount}}, acc -> Decimal.add(acc, amount)
        {:withdraw, %{amount: amount}}, acc -> Decimal.sub(acc, amount)
        {:claim, _}, acc -> acc
      end)

    assert farm_infos["stats"]
           |> Map.values()
           |> Enum.reduce(0, &Decimal.add(&1["lp_tokens_deposited"], &2))
           |> Decimal.eq?(expected_lp_tokens_deposited)

    # remaining_rewards & rewards_reserved are coherent
    assert Decimal.eq?(
             Decimal.sub(uco_balance, farm_infos["rewards_reserved"]),
             farm_infos["remaining_rewards"]
           )

    # stats are there
    for stat <- Map.values(farm_infos["stats"]) do
      refute Decimal.negative?(Decimal.new(stat["deposits_count"]))
      refute Decimal.negative?(Decimal.new(stat["lp_tokens_deposited"]))
      refute Decimal.negative?(Decimal.new(stat["rewards_distributed"]))
    end

    # custom asserts
    case Keyword.get(opts, :assert_fn) do
      nil -> :ok
      fun -> fun.(farm_infos)
    end
  end

  defp asserts_get_user_infos(contract, genesis_address, deposits, opts \\ []) do
    user_infos =
      call_function(
        contract,
        "get_user_infos",
        [genesis_address],
        Keyword.get(opts, :time_now, DateTime.utc_now())
      )

    for {{:deposit, deposit}, i} <- Enum.with_index(deposits) do
      user_info = Enum.at(user_infos, i)

      # index is present
      assert i == user_info["index"]

      # amount is the same
      assert Decimal.eq?(deposit.amount, user_info["amount"])

      # end is calculated by the initial_level
      assert @start_date
             |> DateTime.add(deposit.delay, :day)
             |> DateTime.add(level_to_days(deposit.level) * 86400, :second)
             |> DateTime.to_unix() == user_info["end"]

      # level is <= initial_level
      assert String.to_integer(user_info["level"]) <= String.to_integer(deposit.level)

      # reward amount is >= 0
      assert Decimal.compare(user_info["reward_amount"], 0) in [:eq, :gt]

      # custom asserts
      case Keyword.get(opts, :assert_fn) do
        nil -> :ok
        fun -> fun.(user_infos)
      end
    end
  end

  defp mock_genesis_address(triggers) do
    MockChain
    |> stub(:get_genesis_address, fn
      previous_address ->
        trigger =
          Enum.find(
            triggers,
            &(Trigger.get_previous_address(&1) == previous_address)
          )

        trigger["genesis_address"]
    end)
  end

  defp run_actions(actions, contract, state, uco_balance, opts \\ []) do
    triggers =
      actions
      |> Enum.sort_by(&elem(&1, 1).delay)
      |> actions_to_triggers()

    mock_genesis_address(triggers)

    Enum.reduce(
      triggers,
      prepare_contract(contract, state, uco_balance),
      &trigger_contract(&2, &1, opts)
    )
  end

  defp actions_to_triggers(actions) do
    Enum.reduce(actions, {%{}, []}, fn {action, payload}, {index_acc, triggers_acc} ->
      seed = payload.seed
      index = Map.get(index_acc, seed, 1)
      index_acc = Map.put(index_acc, seed, index + 1)

      trigger =
        case action do
          :deposit ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(@start_date |> DateTime.add(payload.delay, :day))
            |> Trigger.named_action("deposit", %{"level" => payload.level})
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, payload.amount)

          :claim ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(@start_date |> DateTime.add(payload.delay, :day))
            |> Trigger.named_action("claim", %{"deposit_index" => payload.index})

          :withdraw ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(@start_date |> DateTime.add(payload.delay, :day))
            |> Trigger.named_action("withdraw", %{
              "amount" => payload.amount,
              "deposit_index" => payload.index
            })
        end

      {index_acc, [trigger | triggers_acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp amount_generator() do
    # no need to generate a number bigger than 2 ** 64
    StreamData.float(min: 0.00000001, max: 18_446_744_073_709_551_615.0)
    |> StreamData.map(&Decimal.from_float/1)
    |> StreamData.map(&Decimal.round(&1, 8))
  end

  defp level_generator() do
    StreamData.integer(0..7)
    |> StreamData.map(&Integer.to_string/1)
  end

  defp delay_generator() do
    StreamData.integer(1..365)
  end

  defp seed_generator() do
    StreamData.binary(length: 10)
  end

  defp deposits_generator(seeds_count, deposits_per_seed \\ 1..4) do
    StreamData.list_of(seed_generator(), length: seeds_count)
    |> StreamData.map(fn seeds ->
      Enum.map(seeds, fn seed ->
        deposit_generator(seed)
        |> Enum.take(3)
      end)
      |> List.flatten()
      |> Enum.sort_by(&(elem(&1, 1) |> Access.get(:delay)))
    end)
  end

  defp deposit_generator(seed) do
    {delay_generator(), StreamData.constant(seed), amount_generator(), level_generator()}
    |> StreamData.tuple()
    |> StreamData.map(fn {delay, seed, amount, level} ->
      {:deposit,
       %{
         amount: amount,
         delay: delay,
         level: level,
         seed: seed
       }}
    end)
  end

  defp claims_generator(deposits) do
    StreamData.bind(StreamData.integer(1..365), fn i ->
      StreamData.constant(
        Enum.map(deposits, fn {:deposit, %{delay: delay, seed: seed}} ->
          # FIXME: index
          {:claim, %{delay: delay + i, seed: seed, index: 0}}
        end)
      )
    end)
  end

  defp withdraws_generator(deposits) do
    StreamData.bind(StreamData.integer(1..365), fn i ->
      StreamData.constant(
        Enum.map(deposits, fn {:deposit, %{delay: delay, seed: seed, amount: amount}} ->
          # FIXME: index
          # TODO: random amount
          {:withdraw, %{delay: delay + i, seed: seed, amount: amount, index: 0}}
        end)
      )
    end)
  end

  defp level_to_days("0"), do: 0
  defp level_to_days("1"), do: 7
  defp level_to_days("2"), do: 30
  defp level_to_days("3"), do: 90
  defp level_to_days("4"), do: 180
  defp level_to_days("5"), do: 365
  defp level_to_days("6"), do: 730
  defp level_to_days("7"), do: 1095
end
