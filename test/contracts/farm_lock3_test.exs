defmodule FarmLock3Test do
  use InterpreterCase, async: true
  use ExUnitProperties

  import InterpreterCase

  @code File.read!("/Users/bastien/Documents/archethic-dex/contracts/contracts/farm_lock.exs")
  @lp_token_address "00000000000000000000000000000000000000000000000000000000000000000001"
  @factory_address "00000000000000000000000000000000000000000000000000000000000000000002"
  @router_address "00000000000000000000000000000000000000000000000000000000000000000003"
  @master_address "00000000000000000000000000000000000000000000000000000000000000000004"
  @farm_address "00000000000000000000000000000000000000000000000000000000000000000005"
  @invalid_address "00000000000000000000000000000000000000000000000000000000000000000006"
  @reward_year_1 45_000
  @reward_year_2 22_500
  @reward_year_3 11_250
  @reward_year_4 8_750
  @initial_balance @reward_year_1 + @reward_year_2 + @reward_year_3 + @reward_year_4
  @seconds_in_day 60
  @round_now_to 60
  @start_date ~U[2024-07-23 17:00:00Z]
  @end_date @start_date |> DateTime.add(4 * 365 * @seconds_in_day)

  setup do
    constants = [
      {"@SECONDS_IN_DAY", :int, @seconds_in_day},
      {"@ROUND_NOW_TO", :int, @round_now_to},
      {"@START_DATE", :date, @start_date},
      {"@END_DATE", :date, @end_date},
      {"@REWARDS_YEAR_1", :int, @reward_year_1},
      {"@REWARDS_YEAR_2", :int, @reward_year_2},
      {"@REWARDS_YEAR_3", :int, @reward_year_3},
      {"@REWARDS_YEAR_4", :int, @reward_year_4},
      {"@REWARD_TOKEN", :string, "UCO"},
      {"@FARM_ADDRESS", :string, @farm_address},
      {"@LP_TOKEN_ADDRESS", :string, @lp_token_address},
      {"@FACTORY_ADDRESS", :string, @factory_address},
      {"@ROUTER_ADDRESS", :string, @router_address},
      {"@MASTER_ADDRESS", :string, @master_address}
    ]

    {:ok, %{contract: create_contract(@code, constants)}}
  end

  describe "Benchmark" do
    setup %{contract: contract} do
      state =
        "/Users/bastien/Documents/archethic-node/test/contracts/state3.json"
        |> File.read!()
        |> Jason.decode!(floats: :decimals)

      contract = run_actions([], contract, state, Decimal.new("87375.46577807"))

      %{contract: contract}
    end

    @tag :benchmark
    test "calculate_rewards", %{contract: contract} do
      start = System.monotonic_time(:millisecond)

      actions = [
        {:calculate, %{datetime: ~U[2024-07-23T20:57:00Z], delay: 9999, seed: "bastien"}}
      ]

      contract = run_actions(actions, contract, contract.state, contract.uco_balance)

      IO.puts("#{System.monotonic_time(:millisecond) - start}ms calculate_rewards")
      assert true
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

  defp actions_to_expected_state(actions) do
    actions
    |> Enum.sort_by(&elem(&1, 1).delay)
    |> Enum.reduce(%{}, fn {action, payload}, acc ->
      user_deposits = Map.get(acc, payload.seed, [])

      user_deposits =
        case action do
          :deposit ->
            start_timestamp =
              @start_date
              |> DateTime.add(payload.delay * @seconds_in_day, :second)

            end_timestamp =
              start_timestamp
              |> DateTime.add(level_to_seconds(payload.level), :second)

            deposit = %{
              seed: payload.seed,
              amount: payload.amount,
              start_timestamp:
                start_timestamp
                |> DateTime.to_unix(),
              end_timestamp:
                end_timestamp
                |> DateTime.to_unix(),
              deposit_id: delay_to_id(payload.delay)
            }

            user_deposits ++ [deposit]

          :claim ->
            user_deposits

          :calculate ->
            user_deposits

          :withdraw ->
            Enum.map(user_deposits, fn d ->
              if d.deposit_id == payload.deposit_id do
                Map.update!(d, :amount, &Decimal.sub(&1, payload.amount))
              else
                d
              end
            end)

          :relock ->
            start_timestamp =
              @start_date
              |> DateTime.add(payload.delay * @seconds_in_day, :second)
              |> DateTime.to_unix()

            Enum.map(user_deposits, fn d ->
              if d.deposit_id == payload.deposit_id do
                d
                |> Map.put(:start_timestamp, start_timestamp)
                |> Map.put(:end_timestamp, payload.end_timestamp)
              else
                d
              end
            end)
        end

      Map.put(acc, payload.seed, user_deposits)
    end)
    |> Map.values()
    |> List.flatten()
  end

  defp actions_to_triggers(actions) do
    Enum.reduce(actions, {%{}, []}, fn {action, payload}, {index_acc, triggers_acc} ->
      seed = payload.seed
      index = Map.get(index_acc, seed, 1)
      index_acc = Map.put(index_acc, seed, index + 1)

      timestamp = @start_date |> DateTime.add(payload.delay * @seconds_in_day, :second)

      trigger =
        case action do
          :calculate ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(payload.datetime)
            |> Trigger.named_action("calculate_rewards", %{})

          :deposit ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
            |> Trigger.named_action("deposit", %{
              "end_timestamp" => DateTime.to_unix(timestamp) + level_to_seconds(payload.level)
            })
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, payload.amount)

          :claim ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
            |> Trigger.named_action("claim", %{"deposit_id" => payload.deposit_id})

          :withdraw ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
            |> Trigger.named_action("withdraw", %{
              "amount" => payload.amount,
              "deposit_id" => payload.deposit_id
            })

          :relock ->
            Trigger.new(payload.seed, index)
            |> Trigger.timestamp(timestamp)
            |> Trigger.named_action("relock", %{
              "end_timestamp" => payload.end_timestamp,
              "deposit_id" => payload.deposit_id
            })
        end

      {index_acc, [trigger | triggers_acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp amount_generator(opts) do
    # no need to generate a number bigger than 2 ** 64
    StreamData.float(
      min: Keyword.get(opts, :min_amount, 0.00000143),
      max: Keyword.get(opts, :max_amount, 18_446_744_073_709_551_615.0)
    )
    |> StreamData.map(&Decimal.from_float/1)
    |> StreamData.map(&Decimal.round(&1, 8))
  end

  defp level_generator(opts) do
    min_level = Keyword.get(opts, :min_level, 0)
    max_level = Keyword.get(opts, :max_level, 7)

    StreamData.integer(min_level..max_level)
    |> StreamData.map(&Integer.to_string/1)
  end

  defp delay_generator() do
    StreamData.integer(1..365)
  end

  defp seed_generator() do
    StreamData.binary(length: 10)
  end

  defp deposits_generator(seeds_count, opts \\ []) do
    StreamData.list_of(seed_generator(), length: seeds_count)
    |> StreamData.map(fn seeds ->
      Enum.map(seeds, fn seed ->
        Process.put("delays", [])

        deposit_generator(seed, opts)
        |> Stream.reject(fn {:deposit, deposit} ->
          delays = Process.get("delays")
          # nonsense to have multiple operation on the same chain at the same time
          if deposit.delay in delays do
            true
          else
            Process.put("delays", [deposit.delay | delays])
            false
          end
        end)
        |> Enum.take(Keyword.get(opts, :deposits_per_seed, 3))
      end)
      |> List.flatten()
      |> Enum.sort_by(&(elem(&1, 1) |> Access.get(:delay)))
    end)
  end

  defp deposit_generator(seed, opts) do
    {delay_generator(), StreamData.constant(seed), amount_generator(opts), level_generator(opts)}
    |> StreamData.tuple()
    |> StreamData.map(fn {delay, seed, amount, level} ->
      {:deposit,
       %{
         amount: amount,
         delay: delay,
         level: level,
         seed: seed,
         deposit_id: delay_to_id(delay)
       }}
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

  defp level_to_seconds(lvl), do: level_to_days(lvl) * @seconds_in_day

  defp available_levels_at(datetime) do
    {availables, _} =
      ["1", "2", "3", "4", "5", "6", "7"]
      |> Enum.reduce({[], false}, fn level, {acc, reached_end} ->
        if DateTime.compare(
             datetime,
             @end_date |> DateTime.add(-1 * level_to_days(level) * @seconds_in_day)
           ) in [:lt, :eq] do
          {[level | acc], reached_end}
        else
          if !reached_end do
            {[level | acc], true}
          else
            {acc, reached_end}
          end
        end
      end)

    if DateTime.compare(datetime, @end_date) == :lt do
      ["0" | Enum.reverse(availables)]
    else
      Enum.reverse(availables)
    end
  end

  defp end_to_level(end_timestamp, time_now) do
    case end_timestamp |> DateTime.from_unix!() |> DateTime.diff(time_now) do
      diff when diff > 730 * @seconds_in_day -> "7"
      diff when diff > 365 * @seconds_in_day -> "6"
      diff when diff > 180 * @seconds_in_day -> "5"
      diff when diff > 90 * @seconds_in_day -> "4"
      diff when diff > 30 * @seconds_in_day -> "3"
      diff when diff > 7 * @seconds_in_day -> "2"
      diff when diff > 0 -> "1"
      _ -> "0"
    end
  end

  defp delay_to_id(delay) do
    @start_date
    |> DateTime.add(delay * @seconds_in_day)
    |> DateTime.to_unix()
    |> Integer.to_string()
  end
end
