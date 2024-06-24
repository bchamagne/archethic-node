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

  test "deposit/1 should throw when farm ended", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
      |> Trigger.timestamp(@end_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    assert {:throw, 1001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end


  test "deposit/1 should throw when it's transfer to the farm is 0", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
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
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
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
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@invalid_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 1004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end


  test "deposit/1 should throw when end_timestamp is past farm's ended", %{contract: contract} do
      state = %{}

      trigger =
        Trigger.new()
        |> Trigger.named_action("deposit", %{"end_timestamp" => @end_date |> DateTime.add(1) |> DateTime.to_unix() })
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
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
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
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
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
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count),
            claims <- claims_generator(deposits)
          ) do
      actions = deposits ++ claims

      result_contract =
        run_actions(actions, contract, %{}, @initial_balance, ignore_condition_failed: true)

      max_delay =
        claims
        |> Enum.reduce(0, fn {:claim, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      asserts_get_farm_infos(result_contract, actions,
        time_now: max_date,
        assert_fn: fn farm_infos ->
          assert Decimal.gt?(farm_infos["rewards_distributed"], 0)
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
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
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
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
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

  property "withdraw/2 should transfer the funds and update the state (withdraw everything)", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count),
            withdraws <- withdraws_generator(deposits, :full)
          ) do
      actions = deposits ++ withdraws

      result_contract =
        run_actions(actions, contract, %{}, @initial_balance, ignore_condition_failed: true)

      max_delay =
        withdraws
        |> Enum.reduce(0, fn {_, %{delay: delay}}, acc -> max(delay, acc) end)

      max_date = DateTime.add(@start_date, max_delay, :day)

      asserts_get_farm_infos(result_contract, actions,
        time_now: max_date,
        assert_fn: fn farm_infos ->
          assert Decimal.gt?(farm_infos["rewards_distributed"], 0)
          assert Decimal.eq?(0, farm_infos["rewards_reserved"])

          assert Decimal.eq?(
                   0,
                   farm_infos["stats"]
                   |> Map.values()
                   |> Enum.map(& &1["lp_tokens_deposited"])
                   |> Enum.reduce(&Decimal.add/2)
                 )
        end
      )
    end
  end

  # property "withdraw/2 should transfer the funds and update the state (withdraw partial)", %{
  #   contract: contract
  # } do
  #   check all(
  #           count <- StreamData.integer(1..10),
  #           deposits <- deposits_generator(count),
  #           withdraws <- withdraws_generator(deposits, :partial)
  #         ) do
  #     actions = deposits ++ withdraws

  #     result_contract =
  #       run_actions(actions, contract, %{}, @initial_balance, ignore_condition_failed: true)

  #     max_delay =
  #       withdraws
  #       |> Enum.reduce(0, fn {_, %{delay: delay}}, acc -> max(delay, acc) end)

  #     max_date = DateTime.add(@start_date, max_delay, :day)

  #     asserts_get_farm_infos(result_contract, actions,
  #       time_now: max_date,
  #       assert_fn: fn farm_infos ->
  #         assert Decimal.gt?(farm_infos["rewards_distributed"], 0)
  #         assert Decimal.eq?(0, farm_infos["rewards_reserved"])

  #         assert Decimal.eq?(
  #                  0,
  #                  farm_infos["stats"]
  #                  |> Map.values()
  #                  |> Enum.map(& &1["lp_tokens_deposited"])
  #                  |> Enum.reduce(&Decimal.add/2)
  #                )
  #       end
  #     )
  #   end
  # end

  defp asserts_get_farm_infos(contract, actions, opts) do
    uco_balance = contract.uco_balance
    time_now = Keyword.get(opts, :time_now, DateTime.utc_now())
    time_now_unix = DateTime.to_unix(time_now)
    farm_infos = call_function(contract, "get_farm_infos", [], time_now)

    assert farm_infos["end_date"] == DateTime.to_unix(@end_date)
    assert farm_infos["start_date"] == DateTime.to_unix(@start_date)
    assert farm_infos["reward_token"] == "UCO"

    for {key, value} <- farm_infos["available_levels"] do
      assert key in ["0", "1", "2", "3", "4", "5", "6", "7"]
      assert value == time_now_unix + level_to_days(key) * 86400
    end

    assert farm_infos["stats"] |> Map.keys() == ["0", "1", "2", "3", "4", "5", "6", "7"]

    refute Decimal.negative?(Decimal.new(farm_infos["rewards_distributed"]))

    # tokens deposited is coherent with stats
    expected_lp_tokens_deposited =
      actions
      |> Enum.reduce(0, fn
        {:deposit, %{amount: amount}}, acc -> Decimal.add(acc, amount)
        {:withdraw, %{amount: amount}}, acc -> Decimal.sub(acc, amount)
        {:claim, _}, acc -> acc
      end)

    total_lp_tokens_deposited =
      farm_infos["stats"]
      |> Map.values()
      |> Enum.reduce(0, &Decimal.add(&1["lp_tokens_deposited"], &2))

    assert Decimal.eq?(expected_lp_tokens_deposited, total_lp_tokens_deposited)

    if Decimal.positive?(total_lp_tokens_deposited) do
      # sum of tvl_ratio is equal to 1
      assert farm_infos["stats"]
             |> Map.values()
             |> Enum.reduce(0, &Decimal.add(&1["tvl_ratio"], &2))
             # we can't compare directly because the ratio are not precise
             |> Decimal.gt?(Decimal.new("0.9999"))

      # sum of rewards_allocated is equal to uco_balance
      assert farm_infos["stats"]
             |> Map.values()
             |> Enum.reduce(0, &Decimal.add(&1["rewards_allocated"], &2))
             |> then(fn total_rewards_allocated ->
               # we can't compare directly because the ratio are not precise
               Decimal.div(uco_balance, total_rewards_allocated)
               |> Decimal.round()
               |> Decimal.eq?(1)
             end)
    end

    # remaining_rewards & rewards_reserved are coherent
    assert Decimal.eq?(
             Decimal.sub(uco_balance, farm_infos["rewards_reserved"]),
             farm_infos["remaining_rewards"]
           )

    # stats are there
    for stat <- Map.values(farm_infos["stats"]) do
      refute Decimal.negative?(Decimal.new(stat["deposits_count"]))
    end

    # custom asserts
    case Keyword.get(opts, :assert_fn) do
      nil -> :ok
      fun -> fun.(farm_infos)
    end
  end

  defp asserts_get_user_infos(contract, genesis_address, deposits, opts) do
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

      timestamp = @start_date |> DateTime.add(payload.delay, :day)

      trigger =
        case action do
          :deposit ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
            |> Trigger.named_action("deposit", %{"end_timestamp" => DateTime.to_unix(timestamp) + (level_to_days(payload.level) * 86400)})
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, payload.amount)

          :claim ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
            |> Trigger.named_action("claim", %{"deposit_index" => payload.index})

          :withdraw ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
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
        |> Enum.take(Enum.random(deposits_per_seed))
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

  defp withdraws_generator(deposits, :full) do
    StreamData.bind(StreamData.integer(1..365), fn i ->
      StreamData.constant(
        Enum.map(deposits, fn {:deposit, %{delay: delay, seed: seed, amount: amount}} ->
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
