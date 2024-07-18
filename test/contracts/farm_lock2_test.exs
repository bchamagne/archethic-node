defmodule FarmLock2Test do
  use InterpreterCase, async: true
  use ExUnitProperties

  import InterpreterCase

  @code File.read!("/Users/bastien/Documents/archethic-node/test/contracts/farm_lock2.exs")
  @lp_token_address "00000000000000000000000000000000000000000000000000000000000000000001"
  @factory_address "00000000000000000000000000000000000000000000000000000000000000000002"
  @router_address "00000000000000000000000000000000000000000000000000000000000000000003"
  @master_address "00000000000000000000000000000000000000000000000000000000000000000004"
  @farm_address "00000000000000000000000000000000000000000000000000000000000000000005"
  @invalid_address "00000000000000000000000000000000000000000000000000000000000000000006"
  @reward_year_1 45_000_000
  @reward_year_2 22_500_000
  @reward_year_3 11_250_000
  @reward_year_4 8_750_000
  @initial_balance @reward_year_1 + @reward_year_2 + @reward_year_3 + @reward_year_4
  @seconds_in_day 86400
  @start_date ~U[2024-07-17T00:00:00Z]
  @end_date @start_date |> DateTime.add(4 * 365 * @seconds_in_day)

  setup do
    constants = [
      {"@SECONDS_IN_DAY", :int, @seconds_in_day},
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

  test "deposit/1 should throw when it's transfer to the farm is less than minimum", %{
    contract: contract
  } do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new("0.0000014"))

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
      |> Trigger.named_action("deposit", %{
        "end_timestamp" => @end_date |> DateTime.add(1) |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 1005} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "deposit/1 should throw when end_timestamp is in the past", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{
        "end_timestamp" => @start_date |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 1006} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  property "deposit/1 should accept deposits if the farm hasn't started yet", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <-
              deposits_generator(count)
              |> StreamData.map(fn deposits ->
                Enum.map(deposits, fn {:deposit, payload} ->
                  {:deposit, %{payload | delay: -1}}
                end)
              end),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, deposit.seed, deposits,
        assert_fn: fn user_infos ->
          # also assert that no rewards calculated
          assert Decimal.eq?(
                   0,
                   Enum.map(user_infos, & &1["rewards"]) |> Enum.reduce(&Decimal.add/2)
                 )
        end
      )

      # asserts_get_farm_infos(result_contract, deposits,
      #   assert_fn: fn farm_infos ->
      #     # also assert that no rewards calculated
      #     assert farm_infos["remaining_rewards"] == @initial_balance
      #   end
      # )
    end
  end

  property "deposit/1 should accept deposits if the farm has started", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)
      asserts_get_user_infos(result_contract, deposit.seed, deposits)
      asserts_get_farm_infos(result_contract, deposits)
    end
  end

  test "claim/1 should throw if farm hasn't started", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("claim", %{"deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(-1))

    assert {:throw, 2001} =
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

    mock_genesis_address([trigger])

    assert {:throw, 2000} =
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

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 2000} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "claim/1 should throw if called before the end of lock", %{contract: contract} do
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

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 2002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "claim/1 should not be allowed if rewards is 0", %{contract: contract} do
    state = %{}

    trigger0 =
      Trigger.new("seed2", 1)
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new("999999999999"))

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"end_timestamp" => "flex"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new("0.00000143"))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("claim", %{"deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger0, trigger1, trigger2])

    assert {:condition_failed, _} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger0)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "claim/1 should transfer the funds and update the state", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      deposit_duration_in_day = max(1, div(level_to_seconds(deposit.level), @seconds_in_day))

      claim =
        {:claim,
         %{
           delay: deposit.delay + deposit_duration_in_day,
           seed: deposit.seed,
           deposit_index: deposit.deposit_index
         }}

      actions = deposits ++ [claim]

      result_contract =
        run_actions(actions, contract, %{}, @initial_balance, ignore_condition_failed: true)

      asserts_get_user_infos(result_contract, deposit.seed, actions)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # there's an edge case where the rewards_distributed can be 0
          # it happens with small deposits amount that generate less than 1e-8 rewards
          if Decimal.gt?(deposit.amount, 1) do
            assert Decimal.gt?(farm_infos["rewards_distributed"], 0)
          end
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

    mock_genesis_address([trigger])

    assert {:throw, 3000} =
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

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 3000} =
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

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 3003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "withdraw/2 should throw if deposit is locked", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"end_timestamp" => "max"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("withdraw", %{"amount" => 1, "deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 3004} =
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
            withdraws <- withdraws_generator(deposits, :full),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      actions = deposits ++ withdraws

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      {genesis_public_key, _} = Crypto.derive_keypair(deposit.seed, 0)
      genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()

      asserts_get_user_infos(result_contract, genesis_address, actions,
        assert_fn: fn user_infos ->
          # no more deposit since everything is withdrawn
          assert user_infos == []
        end
      )

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # too small amount will have no rewards_distributed because of rounding imprecision
          if Enum.any?(deposits, fn {:deposit, d} ->
               Decimal.gt?(d.amount, Decimal.new("0.00000143"))
             end) do
            assert Decimal.gt?(farm_infos["rewards_distributed"], 0)
          end

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

  property "withdraw/2 should transfer the funds and update the state (partial withdraw)", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      withdraw_amount = Decimal.div(deposit.amount, 2) |> Decimal.round(8)

      withdraw =
        {:withdraw,
         %{
           delay: 2000,
           seed: deposit.seed,
           amount: withdraw_amount,
           deposit_id: delay_to_id(deposit.delay)
         }}

      actions = deposits ++ [withdraw]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, deposit.seed, actions,
        assert_fn: fn user_infos ->
          d = user_infos |> Enum.at(deposit.deposit_index)
          assert Decimal.eq?(d["tokens"], Decimal.sub(deposit.amount, withdraw_amount))
        end
      )
    end
  end

  test "relock/2 should throw if user has no deposit", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{"end_timestamp" => "max", "deposit_index" => 0})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger])

    assert {:throw, 4000} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "relock/2 should throw if index is invalid", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{
        "end_timestamp" => DateTime.to_unix(@start_date |> DateTime.add(1))
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{"end_timestamp" => "max", "deposit_index" => 50})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4000} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if relock is done after farm's end", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{
        "end_timestamp" => @start_date |> DateTime.add(1) |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "end_timestamp" => "max",
        "deposit_index" => 0
      })
      |> Trigger.timestamp(@end_date |> DateTime.add(1))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if end_timestamp is past farm's end", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{
        "end_timestamp" => @start_date |> DateTime.add(1) |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "end_timestamp" => @end_date |> DateTime.add(1) |> DateTime.to_unix(),
        "deposit_index" => 0
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if end_timestamp is before previous deposit's end", %{
    contract: contract
  } do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{
        "end_timestamp" => @start_date |> DateTime.add(1) |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "end_timestamp" => @start_date |> DateTime.add(-1) |> DateTime.to_unix(),
        "deposit_index" => 0
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if level == current level", %{
    contract: contract
  } do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{
        "end_timestamp" =>
          @start_date |> DateTime.add(370 * @seconds_in_day) |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "end_timestamp" =>
          @start_date |> DateTime.add(375 * @seconds_in_day) |> DateTime.to_unix(),
        "deposit_index" => 0
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if level < current level", %{
    contract: contract
  } do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{
        "end_timestamp" =>
          @start_date |> DateTime.add(370 * @seconds_in_day) |> DateTime.to_unix()
      })
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "end_timestamp" =>
          @start_date |> DateTime.add(50 * @seconds_in_day) |> DateTime.to_unix(),
        "deposit_index" => 0
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "relock/2 should transfer the rewards and update the state", %{
    contract: contract
  } do
    check all(
            count <- StreamData.integer(1..10),
            deposits <- deposits_generator(count, max_level: 5),
            {:deposit, deposit_to_relock} <- StreamData.member_of(deposits)
          ) do
      relock = %{
        delay: deposit_to_relock.delay + 1,
        seed: deposit_to_relock.seed,
        end_timestamp: "max",
        deposit_index: deposit_to_relock.deposit_index
      }

      actions = deposits ++ [{:relock, relock}]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions)

      asserts_get_user_infos(result_contract, relock.seed, actions,
        assert_fn: fn user_infos ->
          deposit = Enum.at(user_infos, relock.deposit_index)

          if relock.end_timestamp == "max" do
            assert deposit["end"] == @end_date |> DateTime.to_unix()
          else
            assert deposit["end"] == relock.end_timestamp
          end
        end
      )
    end
  end

  describe "scenarios" do
    @tag :scenario
    test "alone without state changes", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "7",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "2",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions)

      # formula: (180/365) * 45_000_000 = 22191780.821917806
      # imprecision due to rounding 8
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["rewards"], "22191780.6")
        end
      )
    end

    @tag :scenario
    test "alone with state changes", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "4",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "2",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      IO.inspect(result_contract.state)

      asserts_get_farm_infos(result_contract, actions)

      # formula: (180/365) * 45_000_000 = 22191780.821917806
      # imprecision due to rounding 8
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["rewards"], "22191780.6")
        end
      )
    end

    @tag :scenario
    test "giveaway is also distributed linearly", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "5",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "2",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance + 4_000_000)

      # formula: ((180/365) * 45_000_000) + ((180/(365*4)) * 4_000_000) = 22684931.50684931
      # imprecision due to rounding 8
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["rewards"], "22684931.28")
        end
      )
    end

    @tag :scenario
    test "2 deposits with many level changes", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "5",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           level: "2",
           seed: "seed2"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "2",
           seed: "seed3"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # D = (180/365) * 45_000_000
      # periods: 0-5, 5-28, 28-35, 35-180
      #
      # W1 = (1, 0)
      # W2 = (0.85185185, 0.14814814)
      # W3 = (0.91390728, 0.08609271)
      # W4 = (0.95172413, 0.04827586)
      #
      # seed1 = (5/180 * D * W1.0) + (23/180 * D * W2.0) + (7/180 * D * W3.0) + (145/180 * D * W4.0) = 20834376.455342464
      # seed2 = (5/180 * D * W1.1) + (23/180 * D * W2.1) + (7/180 * D * W3.1) + (145/180 * D * W4.1) = 1357404.1508219177
      # imprecision due to rounding 8
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["rewards"], "20834375.60709506")
        end
      )

      asserts_get_user_infos(result_contract, "seed2", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["rewards"], "1357404.05891518")
        end
      )
    end

    @tag :scenario
    test "2 deposits same user with many level changes", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "5",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           level: "2",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "2",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # D = (180/365) * 45_000_000
      # periods: 0-5, 5-28, 28-35, 35-180
      #
      # W1 = (1, 0)
      # W2 = (0.85185185, 0.14814814)
      # W3 = (0.91390728, 0.08609271)
      # W4 = (0.95172413, 0.04827586)
      #
      # seed1 = (5/180 * D * W1.0) + (23/180 * D * W2.0) + (7/180 * D * W3.0) + (145/180 * D * W4.0) = 20834376.455342464
      # seed1' = (5/180 * D * W1.1) + (23/180 * D * W2.1) + (7/180 * D * W3.1) + (145/180 * D * W4.1) = 1357404.1508219177
      # imprecision due to rounding 8
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 2 == length(user_infos)
          assert Decimal.eq?(Enum.at(user_infos, 0)["rewards"], "20834375.60709506")
          assert Decimal.eq?(Enum.at(user_infos, 1)["rewards"], "1357404.05891518")
        end
      )
    end

    @tag :scenario
    test "many flexible deposits are merged", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "0",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           level: "0",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "2",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # (180/365) * 45_000_000 = 22191780.821917806
      # imprecision due to rounding 8
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(Enum.at(user_infos, 0)["rewards"], "22191780.76943493")
        end
      )
    end

    @tag :scenario
    test "handle 0 deposit for a period", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "0",
           seed: "seed"
         }},
        {:withdraw,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           deposit_id: delay_to_id(0),
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 180,
           level: "0",
           seed: "seed2"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 365,
           level: "0",
           seed: "seed3"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # D = 45_000_000
      # periods: 0-5, 180-365
      #
      # seed1 = 5/365 * D = 616438.3561643836
      # seed2 = 360/365 * D = 44383561.64383562
      # imprecision due to rounding 8

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # 87_500_000 - 45_000_000
          assert farm_infos["remaining_rewards"] == 42_500_000
        end
      )
    end

    @tag :scenario
    test "year change", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "7",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 370,
           level: "5",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)

          # period: 0-365, 365-370
          # 45_000_000 + ((5/365)*22_500_000) = 45308219.17808219
          # imprecision due to rounding 8
          assert Decimal.eq?(hd(user_infos)["rewards"], "45308219.175")
        end
      )
    end

    @tag :scenario
    test "handle a gap at beginning", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           level: "7",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 365,
           level: "5",
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)

          # period: 5-365
          # 45_000_000
          assert Decimal.eq?(hd(user_infos)["rewards"], "45000000")
        end
      )
    end

    @tag :scenario
    test "alone always", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "0",
           seed: "seed"
         }},
        {:withdraw,
         %{
           amount: Decimal.new(1000),
           delay: 2000,
           deposit_id: delay_to_id(0),
           seed: "seed"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          assert farm_infos["remaining_rewards"] == 0
          assert farm_infos["rewards_distributed"] == @initial_balance
        end
      )
    end

    # @tag :scenario
    # test "alone always (with less than supposed balance)", %{contract: contract} do
    #   actions = [
    #     {:deposit,
    #      %{
    #        amount: Decimal.new(1000),
    #        delay: 0,
    #        level: "0",
    #        seed: "seed"
    #      }},
    #     {:withdraw,
    #      %{
    #        amount: Decimal.new(1000),
    #        delay: 2000,
    #        deposit_index: 0,
    #        seed: "seed"
    #      }}
    #   ]

    #   result_contract = run_actions(actions, contract, %{}, @initial_balance - 12)
    #   IO.inspect(state: result_contract.state, balance: result_contract.uco_balance)

    #   asserts_get_farm_infos(result_contract, actions,
    #     assert_fn: fn farm_infos ->
    #       assert farm_infos["remaining_rewards"] == 0
    #       assert farm_infos["rewards_distributed"] == @initial_balance
    #     end
    #   )
    # end

    @tag :scenario
    test "withdraw all", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "0",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           level: "0",
           seed: "seed2"
         }},
        {:withdraw,
         %{
           amount: Decimal.new(1000),
           delay: 10,
           deposit_id: delay_to_id(0),
           seed: "seed"
         }},
        {:withdraw,
         %{
           amount: Decimal.new(1000),
           delay: 15,
           deposit_id: delay_to_id(5),
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # 15/365 * 45_000_000 = 1849315.0684931506
          # 87500000 -  1849315.0684931506 = 85650684.93150684
          assert Decimal.eq?(farm_infos["rewards_distributed"], "1849314.36531688")
          assert Decimal.eq?(farm_infos["remaining_rewards"], "85650685.63468312")
        end
      )
    end

    @tag :scenario
    test "claiming should distribute rewards", %{contract: contract} do
      actions = [
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 0,
           level: "5",
           seed: "seed"
         }},
        {:deposit,
         %{
           amount: Decimal.new(1000),
           delay: 5,
           level: "5",
           seed: "seed2"
         }},
        {:claim,
         %{
           delay: 1000,
           deposit_id: delay_to_id(0),
           seed: "seed"
         }},
        {:claim,
         %{
           delay: 1001,
           deposit_id: delay_to_id(5),
           seed: "seed2"
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # IO.inspect(result_contract.state)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # 15/365 * 45_000_000 = 1849315.0684931506
          # 87_500_000 -  1849315.0684931506 = 85650684.93150684
          assert Decimal.eq?(
                   Decimal.add(
                     farm_infos["rewards_distributed"],
                     result_contract.state["rewards_reserved"] || 0
                   ),
                   "1849314.36531688"
                 )

          assert Decimal.eq?(farm_infos["remaining_rewards"], "85650685.63468312")
        end
      )
    end
  end

  describe "Benchmark" do
    setup %{contract: contract} do
      deposits =
        deposits_generator(200, deposits_per_seed: 1)
        |> Enum.take(1)
        |> List.flatten()

      contract = run_actions(deposits, contract, %{}, @initial_balance)

      %{contract: contract}
    end

    @tag :benchmark
    test "Time to run 200 deposits" do
      assert true
    end
  end

  defp asserts_get_farm_infos(contract, actions, opts \\ []) do
    uco_balance = contract.uco_balance

    time_now =
      case Keyword.get(opts, :time_now) do
        nil ->
          max_delay =
            actions
            |> Enum.reduce(0, fn {_, %{delay: delay}}, acc -> max(delay, acc) end)

          DateTime.add(@start_date, max_delay * @seconds_in_day)

        datetime ->
          datetime
      end

    time_now_unix = DateTime.to_unix(time_now)

    farm_infos = call_function(contract, "get_farm_infos", [], time_now)

    # IO.inspect(farm_infos)

    assert farm_infos["end_date"] == DateTime.to_unix(@end_date)
    assert farm_infos["start_date"] == DateTime.to_unix(@start_date)
    assert farm_infos["reward_token"] == "UCO"

    for {key, value} <- farm_infos["available_levels"] do
      assert key in available_levels_at(time_now)

      assert value == time_now_unix + level_to_seconds(key) ||
               value == DateTime.to_unix(@end_date)
    end

    assert farm_infos["stats"] |> Map.keys() == ["0", "1", "2", "3", "4", "5", "6", "7"]

    refute Decimal.negative?(Decimal.new(farm_infos["rewards_distributed"]))

    # tokens deposited is coherent with stats
    expected_lp_tokens_deposited =
      actions
      |> Enum.reduce(0, fn
        {:deposit, %{amount: amount}}, acc -> Decimal.add(acc, amount)
        {:withdraw, %{amount: amount}}, acc -> Decimal.sub(acc, amount)
        {:relock, _}, acc -> acc
        {:claim, _}, acc -> acc
      end)

    total_lp_tokens_deposited =
      farm_infos["stats"]
      |> Map.values()
      |> Enum.reduce(0, &Decimal.add(&1["lp_tokens_deposited"], &2))

    assert Decimal.eq?(expected_lp_tokens_deposited, total_lp_tokens_deposited)
    assert Decimal.eq?(expected_lp_tokens_deposited, farm_infos["lp_tokens_deposited"])

    if Decimal.positive?(total_lp_tokens_deposited) do
      # sum of rewards_allocated is equal to initial balance
      assert farm_infos["stats"]
             |> Map.values()
             |> Enum.map(& &1["rewards_allocated"])
             |> List.flatten()
             |> Enum.map(& &1["rewards"])
             |> Enum.reduce(&Decimal.add/2)
             |> then(fn total_rewards_allocated ->
               # total_rewards_allocated should be equal to initial balance
               # but it's not because of imprecisions
               assert Decimal.div(total_rewards_allocated, @initial_balance)
                      |> Decimal.gt?("0.9999")
             end)
    end

    rewards_reserved =
      if contract.state["rewards_reserved"] do
        contract.state["rewards_reserved"]
      else
        0
      end

    # remaining_rewards subtracts the reserved rewards
    assert Decimal.eq?(
             uco_balance
             |> Decimal.sub(rewards_reserved),
             farm_infos["remaining_rewards"]
           )

    # stats are there
    for stat <- Map.values(farm_infos["stats"]) do
      refute Decimal.negative?(Decimal.new(stat["deposits_count"]))
      assert Decimal.gt?(stat["weight"], 0)
      assert Decimal.lt?(stat["weight"], 1)
    end

    # custom asserts
    case Keyword.get(opts, :assert_fn) do
      nil -> :ok
      fun -> fun.(farm_infos)
    end
  end

  defp asserts_get_user_infos(contract, user_seed, actions, opts \\ []) do
    {genesis_public_key, _} = Crypto.derive_keypair(user_seed, 0)
    genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()

    expected_state =
      actions_to_expected_state(actions)
      |> Enum.filter(&(&1.seed == user_seed))

    time_now =
      case Keyword.get(opts, :time_now) do
        nil ->
          max_delay =
            actions
            |> Enum.reduce(0, fn {_, %{delay: delay}}, acc -> max(delay, acc) end)

          DateTime.add(@start_date, max_delay * @seconds_in_day)

        datetime ->
          datetime
      end

    user_infos =
      call_function(
        contract,
        "get_user_infos",
        [genesis_address],
        time_now
      )

    # IO.inspect(user_infos: user_infos)

    for %{
          id: id,
          amount: amount,
          start_timestamp: start_timestamp,
          end_timestamp: end_timestamp
        } <- expected_state do
      end_timestamp =
        if end_timestamp == "max" do
          @end_date |> DateTime.to_unix()
        else
          end_timestamp
        end

      user_info = Enum.find(user_infos, &(&1["id"] == id))
      refute is_nil(user_info)
      assert Decimal.eq?(amount, user_info["tokens"])
      assert Decimal.compare(user_info["rewards"], 0) in [:eq, :gt]
      assert end_to_level(end_timestamp, time_now) == user_info["level"]

      if end_timestamp > DateTime.to_unix(time_now) do
        assert start_timestamp == user_info["from"]
        assert end_timestamp == user_info["to"]
      end
    end

    # custom asserts
    case Keyword.get(opts, :assert_fn) do
      nil -> :ok
      fun -> fun.(user_infos)
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
              |> DateTime.add(payload.delay * @seconds_in_day)

            end_timestamp =
              start_timestamp
              |> DateTime.add(level_to_seconds(payload.level))
              |> DateTime.add(-1)

            deposit = %{
              seed: payload.seed,
              amount: payload.amount,
              start_timestamp:
                start_timestamp
                |> DateTime.to_unix(),
              end_timestamp:
                end_timestamp
                |> DateTime.to_unix(),
              id: start_timestamp |> DateTime.to_unix() |> Integer.to_string()
            }

            user_deposits ++ [deposit]

          :claim ->
            user_deposits

          :withdraw ->
            Enum.map(user_deposits, fn d ->
              if d.id == payload.deposit_id do
                Map.update!(d, :amount, &Decimal.sub(&1, payload.amount))
              else
                d
              end
            end)

          :relock ->
            start_timestamp =
              @start_date
              |> DateTime.add(payload.delay * @seconds_in_day)
              |> DateTime.to_unix()

            List.update_at(user_deposits, payload.deposit_index, fn d ->
              d
              |> Map.put(:start_timestamp, start_timestamp)
              |> Map.put(:end_timestamp, payload.end_timestamp)
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

      timestamp = @start_date |> DateTime.add(payload.delay * @seconds_in_day)

      trigger =
        case action do
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
              "deposit_index" => payload.deposit_index
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
        deposit_generator(seed, opts)
        |> Enum.take(Keyword.get(opts, :deposits_per_seed, 3))
        |> Enum.sort_by(&(elem(&1, 1) |> Access.get(:delay)))
        |> Enum.with_index()
        |> Enum.map(fn {{:deposit, deposit}, i} ->
          {:deposit, Map.put(deposit, :deposit_index, i)}
        end)
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
         seed: seed
       }}
    end)
  end

  defp withdraws_generator(deposits, :full) do
    StreamData.constant(
      deposits
      |> Enum.map(fn {:deposit, d} ->
        {:withdraw,
         %{
           delay: 2000 + d.delay,
           seed: d.seed,
           amount: d.amount,
           deposit_id: delay_to_id(d.delay)
         }}
      end)
    )
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
  end
end
