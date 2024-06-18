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

  property "deposit/1 should accept deposits if the farm hasn't started yet", %{
    contract: contract
  } do
    check all(amounts <- StreamData.list_of(amount_generator(), min_length: 1, max_length: 10)) do
      db =
        amounts
        |> Enum.with_index()
        |> Enum.map(fn {amount, i} ->
          {amount,
           Trigger.new()
           |> Trigger.named_action("deposit", %{"level" => "0"})
           |> Trigger.timestamp(@start_date |> DateTime.add(-(i + 1), :minute))
           |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount)}
        end)
        |> Enum.reverse()

      state = %{}
      triggers = Enum.map(db, &elem(&1, 1))
      triggers_count = length(triggers)

      MockChain
      |> expect(:get_genesis_address, triggers_count, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state),
                 &trigger_contract(&2, &1)
               )

      deposits = next_state["deposits"]
      lp_token_deposited = next_state["lp_token_deposited"]

      assert triggers_count == map_size(deposits)

      for {amount, trigger} <- db do
        user_deposits = deposits[trigger["genesis_address"]]

        refute user_deposits
               |> Enum.find(&Decimal.eq?(&1["amount"], amount))
               |> is_nil()
      end

      expected_lp_tokens = Enum.reduce(db, Decimal.new(0), &Decimal.add(elem(&1, 0), &2))

      assert Decimal.eq?(lp_token_deposited, expected_lp_tokens)
    end
  end

  property "deposit/1 should accept deposits if the farm has already started", %{
    contract: contract
  } do
    check all(
            amounts <- StreamData.list_of(amount_generator(), min_length: 2, max_length: 10),
            max_runs: 1
          ) do
      db =
        amounts
        |> Enum.with_index()
        |> Enum.map(fn {amount, i} ->
          {amount,
           Trigger.new()
           |> Trigger.named_action("deposit", %{"level" => "0"})
           |> Trigger.timestamp(@start_date |> DateTime.add(i + 1, :minute))
           |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount)}
        end)

      state = %{}
      triggers = Enum.map(db, &elem(&1, 1))
      triggers_count = length(triggers)

      MockChain
      |> expect(:get_genesis_address, triggers_count, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      deposits = next_state["deposits"]
      lp_token_deposited = next_state["lp_token_deposited"]

      assert triggers_count == map_size(deposits)

      for {amount, trigger} <- db do
        user_deposits = deposits[trigger["genesis_address"]]

        refute user_deposits
               |> Enum.find(&Decimal.eq?(&1["amount"], amount))
               |> is_nil()
      end

      expected_lp_tokens = Enum.reduce(db, Decimal.new(0), &Decimal.add(elem(&1, 0), &2))

      assert Decimal.eq?(lp_token_deposited, expected_lp_tokens)
    end
  end

  property "deposit/1 should calculate the lock end based on the level", %{
    contract: contract
  } do
    check all(
            amounts_levels <-
              StreamData.list_of(
                StreamData.tuple({amount_generator(), level_generator()}),
                min_length: 2,
                max_length: 10
              )
          ) do
      db =
        amounts_levels
        |> Enum.with_index()
        |> Enum.map(fn {{amount, level}, i} ->
          timestamp = @start_date |> DateTime.add(i + 1, :minute)

          {amount, level, timestamp,
           Trigger.new()
           |> Trigger.named_action("deposit", %{"level" => Integer.to_string(level)})
           |> Trigger.timestamp(timestamp)
           |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount)}
        end)

      state = %{}
      triggers = Enum.map(db, &elem(&1, 3))
      triggers_count = length(triggers)

      MockChain
      |> expect(:get_genesis_address, triggers_count, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      for {_amount, level, timestamp, trigger} <- db do
        user_deposits = next_state["deposits"][trigger["genesis_address"]]

        expected_end =
          timestamp
          |> DateTime.add(level_to_days(level), :day)
          |> DateTime.to_unix()

        refute user_deposits
               |> Enum.find(&Decimal.eq?(&1["end"], expected_end))
               |> is_nil()
      end
    end
  end

  property "deposit/1 should keep track of multiple deposits per user", %{
    contract: contract
  } do
    check all(
            seed <- StreamData.binary(length: 10),
            amounts_levels <-
              StreamData.list_of(
                StreamData.tuple({amount_generator(), level_generator()}),
                min_length: 2,
                max_length: 10
              )
          ) do
      db =
        amounts_levels
        |> Enum.with_index()
        |> Enum.map(fn {{amount, level}, i} ->
          timestamp = @start_date |> DateTime.add(i + 1, :minute)

          {amount,
           Trigger.new(seed)
           |> Trigger.named_action("deposit", %{"level" => Integer.to_string(level)})
           |> Trigger.timestamp(timestamp)
           |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount)}
        end)

      state = %{}
      triggers = Enum.map(db, &elem(&1, 1))
      triggers_count = length(triggers)

      MockChain
      |> expect(:get_genesis_address, triggers_count, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      for {amount, trigger} <- db do
        user_deposits = next_state["deposits"][trigger["genesis_address"]]

        refute user_deposits
               |> Enum.find(&Decimal.eq?(&1["amount"], amount))
               |> is_nil()
      end

      expected_lp_tokens = Enum.reduce(db, Decimal.new(0), &Decimal.add(elem(&1, 0), &2))
      assert Decimal.eq?(next_state["lp_token_deposited"], expected_lp_tokens)
    end
  end

  property "rewards_reserved is the sum of the deposits rewards amount", %{
    contract: contract
  } do
    check all(amounts <- StreamData.list_of(amount_generator(), min_length: 2, max_length: 10)) do
      db =
        amounts
        |> Enum.with_index()
        |> Enum.map(fn {amount, i} ->
          {amount,
           Trigger.new()
           |> Trigger.named_action("deposit", %{"level" => "0"})
           |> Trigger.timestamp(@start_date |> DateTime.add(i + 1, :minute))
           |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, amount)}
        end)

      state = %{}
      triggers = Enum.map(db, &elem(&1, 1))
      triggers_count = length(triggers)

      MockChain
      |> expect(:get_genesis_address, triggers_count, fn
        previous_address ->
          trigger =
            Enum.find(
              triggers,
              &(Trigger.get_previous_address(&1) == previous_address)
            )

          trigger["genesis_address"]
      end)

      assert %{state: next_state} =
               Enum.reduce(
                 triggers,
                 prepare_contract(contract, state, @initial_balance),
                 &trigger_contract(&2, &1)
               )

      # assert the last_calculation_timestamp is the latest trigger timestamp
      assert next_state["last_calculation_timestamp"] ==
               DateTime.add(@start_date, triggers_count, :minute) |> DateTime.to_unix()

      # assert the sum of deposits reward
      assert Decimal.eq?(
               next_state["rewards_reserved"],
               next_state["deposits"]
               |> Map.values()
               |> List.flatten()
               |> Enum.map(& &1["reward_amount"])
               |> Enum.reduce(0, &Decimal.add/2)
             )
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

  test "claim/1 should throw if reward_amount is 0", %{contract: contract} do
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

    assert {:throw, 2003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  defp amount_generator() do
    StreamData.float(min: 0.00000001)
    |> StreamData.map(&Decimal.from_float/1)
    |> StreamData.map(&Decimal.round(&1, 8))
  end

  defp level_generator() do
    StreamData.integer(0..7)
  end

  defp level_to_days(0), do: 0
  defp level_to_days(1), do: 7
  defp level_to_days(2), do: 30
  defp level_to_days(3), do: 90
  defp level_to_days(4), do: 180
  defp level_to_days(5), do: 365
  defp level_to_days(6), do: 730
  defp level_to_days(7), do: 1095
end

# test "claim/1 should throw if index is invalid", %{contract: contract} do
#   state = %{}

#   trigger =
#     Trigger.new()
#     |> Trigger.named_action("claim", %{"deposit_index" => 999})
#     |> Trigger.timestamp(@end_date |> DateTime.add(1))

#   assert {:throw, 2001} =
#            contract
#            |> prepare_contract(state)
#            |> trigger_contract(trigger)
# end
