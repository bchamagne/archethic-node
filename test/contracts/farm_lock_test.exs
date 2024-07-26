defmodule VestingTest do
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
  @reward_year_1 45_000_000
  @reward_year_2 22_500_000
  @reward_year_3 11_250_000
  @reward_year_4 8_750_000
  @initial_balance @reward_year_1 + @reward_year_2 + @reward_year_3 + @reward_year_4
  @seconds_in_day 86400
  @round_now_to 3600
  @start_date ~U[2024-07-17T00:00:00Z]
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

  test "deposit/1 should throw when farm ended", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "flex"})
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
      |> Trigger.named_action("deposit", %{"level" => "flex"})
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
      |> Trigger.named_action("deposit", %{"level" => "flex"})
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
      |> Trigger.named_action("deposit", %{"level" => "flex"})
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
      |> Trigger.named_action("deposit", %{"level" => "7"})
      |> Trigger.timestamp(@start_date |> DateTime.add(366 * @seconds_in_day))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 6002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "deposit/1 should throw when level is max and there is more than 3 years remaining", %{
    contract: contract
  } do
    state = %{}

    trigger =
      Trigger.new()
      |> Trigger.named_action("deposit", %{"level" => "max"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(100))

    assert {:throw, 6001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  property "deposit/1 should accept deposits if the farm hasn't started yet", %{
    contract: contract
  } do
    check all(
            deposits <-
              deposits_generator()
              |> StreamData.map(fn deposits ->
                Enum.map(deposits, fn {:deposit, payload} ->
                  {:deposit, %{payload | date: DateTime.add(@start_date, -1)}}
                end)
              end),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      asserts_get_user_infos(result_contract, deposit.seed, deposits,
        assert_fn: fn user_infos ->
          nil
          # also assert that no rewards calculated
          # assert Decimal.eq?(
          #          0,
          #          Enum.map(user_infos, & &1["reward_amount"]) |> Enum.reduce(&Decimal.add/2)
          #        )
        end
      )

      asserts_get_farm_infos(result_contract, deposits,
        assert_fn: fn farm_infos ->
          nil
          # also assert that no rewards calculated
          # assert farm_infos["remaining_rewards"] == @initial_balance
        end
      )
    end
  end

  property "deposit/1 should accept deposits if the farm has started", %{
    contract: contract
  } do
    check all(
            deposits <- deposits_generator(),
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
      |> Trigger.named_action("claim", %{"deposit_id" => "xx"})
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
      |> Trigger.named_action("claim", %{"deposit_id" => "xx"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    mock_genesis_address([trigger])

    assert {:throw, 6004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "claim/1 should throw if index is invalid", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("claim", %{"deposit_id" => "xx"})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 6004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "claim/1 should throw if called before the end of lock", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "1"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("claim", %{"deposit_id" => tick_to_id(0)})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 2002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "claim/1 should throw if reward_amount is 0", %{contract: contract} do
    state = %{}

    trigger0 =
      Trigger.new("seed2", 1)
      |> Trigger.named_action("deposit", %{"level" => "7"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new("999999999999"))

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new("0.00000143"))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("claim", %{"deposit_id" => tick_to_id(1)})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger0, trigger1, trigger2])

    assert {:throw, 2003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger0)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "claim/1 should transfer the funds and update the state", %{
    contract: contract
  } do
    check all(deposits <- deposits_generator()) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      # because flexible are merged we can't use the original deposits to generaate claim
      user_genesis_address = Enum.random(Map.keys(result_contract.state["deposits"]))
      deposit = Enum.random(result_contract.state["deposits"][user_genesis_address])

      deposit_seed =
        Enum.find(deposits, fn {:deposit, d} ->
          {genesis_public_key, _} = Crypto.derive_keypair(d.seed, 0)
          genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()
          genesis_address == user_genesis_address
        end)
        |> then(fn {:deposit, d} -> d.seed end)

      claim =
        {:claim,
         %{
           delay: 2000,
           seed: deposit_seed,
           deposit_id: deposit["id"]
         }}

      result_contract =
        run_actions([claim], result_contract, result_contract.state, result_contract.uco_balance,
          ignore_condition_failed: true
        )

      actions = deposits ++ [claim]

      asserts_get_user_infos(result_contract, deposit_seed, actions,
        assert_fn: fn user_infos ->
          nil
          # user_info = Enum.find(user_infos, &(&1["id"] == deposit["id"]))
          # assert user_info["reward_amount"] == 0
        end
      )

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # there's an edge case where the rewards_distributed can be 0
          # it happens with small deposits amount that generate less than 1e-8 rewards
          if Decimal.gt?(deposit["amount"], 1) do
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
      |> Trigger.named_action("withdraw", %{"amount" => 1, "deposit_id" => "xx"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    mock_genesis_address([trigger])

    assert {:throw, 6004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "withdraw/2 should throw if index is invalid", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("withdraw", %{"amount" => 1, "deposit_id" => "xx"})
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 6004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "withdraw/2 should throw if amount is bigger than deposit", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("withdraw", %{"amount" => 2, "deposit_id" => tick_to_id(1)})
      |> Trigger.timestamp(@start_date |> DateTime.add(2 * @seconds_in_day))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 3001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "withdraw/2 should throw if deposit is locked", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "1"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 2)
      |> Trigger.named_action("withdraw", %{"amount" => 1, "deposit_id" => tick_to_id(1)})
      |> Trigger.timestamp(@start_date |> DateTime.add(2 * @seconds_in_day))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 3002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "withdraw/2 should transfer the funds and update the state (withdraw everything)", %{
    contract: contract
  } do
    check all(
            deposits <- deposits_generator(),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      # because flexible are merged we can't use the original deposits to generaate withdraws
      withdraws =
        Enum.map(result_contract.state["deposits"], fn {user_genesis_address, user_deposits} ->
          seed =
            Enum.find(deposits, fn {:deposit, d} ->
              {genesis_public_key, _} = Crypto.derive_keypair(d.seed, 0)
              genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()
              genesis_address == user_genesis_address
            end)
            |> then(fn {:deposit, d} -> d.seed end)

          Enum.map(user_deposits, fn user_deposit ->
            delay =
              case user_deposit["end"] do
                0 ->
                  2000

                end_timestamp ->
                  trunc((end_timestamp - DateTime.to_unix(@start_date)) / @seconds_in_day)
              end

            {:withdraw,
             %{
               delay: delay,
               seed: seed,
               amount: user_deposit["amount"],
               deposit_id: user_deposit["id"]
             }}
          end)
        end)
        |> List.flatten()

      result_contract =
        run_actions(
          withdraws,
          result_contract,
          result_contract.state,
          result_contract.uco_balance
        )

      actions = deposits ++ withdraws

      asserts_get_user_infos(result_contract, deposit.seed, actions,
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
            deposits <- deposits_generator(),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      result_contract = run_actions(deposits, contract, %{}, @initial_balance)

      deposits_count_before =
        result_contract.state["deposits"]
        |> Map.values()
        |> Enum.map(&Kernel.length/1)
        |> Enum.sum()

      # because flexible are merged we can't use the original deposits to generaate withdraws
      withdraws =
        Enum.map(result_contract.state["deposits"], fn {user_genesis_address, user_deposits} ->
          seed =
            Enum.find(deposits, fn {:deposit, d} ->
              {genesis_public_key, _} = Crypto.derive_keypair(d.seed, 0)
              genesis_address = Crypto.derive_address(genesis_public_key) |> Base.encode16()
              genesis_address == user_genesis_address
            end)
            |> then(fn {:deposit, d} -> d.seed end)

          Enum.map(user_deposits, fn user_deposit ->
            delay =
              case user_deposit["end"] do
                0 ->
                  2000

                end_timestamp ->
                  trunc((end_timestamp - DateTime.to_unix(@start_date)) / @seconds_in_day)
              end

            {:withdraw,
             %{
               delay: delay,
               seed: seed,
               amount: Decimal.div(user_deposit["amount"], 2) |> Decimal.round(8),
               deposit_id: user_deposit["id"]
             }}
          end)
        end)
        |> List.flatten()

      result_contract =
        run_actions(
          withdraws,
          result_contract,
          result_contract.state,
          result_contract.uco_balance
        )

      deposits_count_after =
        result_contract.state["deposits"]
        |> Map.values()
        |> Enum.map(&Kernel.length/1)
        |> Enum.sum()

      actions = deposits ++ withdraws

      assert deposits_count_after == deposits_count_before
      asserts_get_user_infos(result_contract, deposit.seed, actions)
      asserts_get_farm_infos(result_contract, actions)
    end
  end

  test "relock/2 should throw if user has no deposit", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "level" => "1",
        "deposit_id" => "xx"
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(2))

    mock_genesis_address([trigger])

    assert {:throw, 6004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "relock/2 should throw if index is invalid", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{"level" => "1", "deposit_id" => "xx"})
      |> Trigger.timestamp(@start_date |> DateTime.add(2 * @seconds_in_day))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 6004} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if relock is done after farm's end", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "level" => "1",
        "deposit_id" => tick_to_id(0)
      })
      |> Trigger.timestamp(@end_date |> DateTime.add(1))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  test "relock/2 should throw if end_timestamp is past farm's end", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "flex"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "level" => "7",
        "deposit_id" => tick_to_id(0)
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(367 * @seconds_in_day))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 6002} =
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
      |> Trigger.named_action("deposit", %{"level" => "5"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "level" => "5",
        "deposit_id" => tick_to_id(0)
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4003} =
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
      |> Trigger.named_action("deposit", %{"level" => "5"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("relock", %{
        "level" => "4",
        "deposit_id" => tick_to_id(0)
      })
      |> Trigger.timestamp(@start_date |> DateTime.add(1))

    mock_genesis_address([trigger1, trigger2])

    assert {:throw, 4003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
  end

  property "relock/2 should transfer the rewards and update the state", %{
    contract: contract
  } do
    check all(
            deposits <- deposits_generator(max_level: 5),
            {:deposit, deposit} <- StreamData.member_of(deposits)
          ) do
      relock = %{
        delay: deposit.delay + 365,
        seed: deposit.seed,
        level: "6",
        deposit_id: deposit.deposit_id
      }

      actions = deposits ++ [{:relock, relock}]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions)

      asserts_get_user_infos(result_contract, relock.seed, actions,
        assert_fn: fn user_infos ->
          user_info = Enum.find(user_infos, &(&1["id"] == relock.deposit_id))
          assert Decimal.eq?(user_info["reward_amount"], 0)
          assert user_info["level"] == "6"
        end
      )
    end
  end

  test "calculate_rewards/0 should throw if farm has not started yet", %{contract: contract} do
    state = %{}

    trigger =
      Trigger.new("seed", 1)
      |> Trigger.named_action("calculate_rewards", %{})
      |> Trigger.timestamp(@start_date |> DateTime.add(-1))

    assert {:throw, 5001} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "calculate_rewards/0 should throw if farm has ended", %{contract: contract} do
    state = %{
      "last_calculation_timestamp" =>
        @end_date |> DateTime.add(1 * @seconds_in_day) |> DateTime.to_unix()
    }

    trigger =
      Trigger.new("seed", 1)
      |> Trigger.named_action("calculate_rewards", %{})
      |> Trigger.timestamp(@end_date |> DateTime.add(1 * @seconds_in_day))

    assert {:throw, 5002} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger)
  end

  test "calculate_rewards/0 should throw if already calculated", %{contract: contract} do
    state = %{}

    trigger1 =
      Trigger.new("seed", 1)
      |> Trigger.named_action("deposit", %{"level" => "1"})
      |> Trigger.timestamp(@start_date)
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger2 =
      Trigger.new("seed2", 1)
      |> Trigger.named_action("deposit", %{"level" => "1"})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day))
      |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, Decimal.new(1))

    trigger3 =
      Trigger.new("seed3", 1)
      |> Trigger.named_action("calculate_rewards", %{})
      |> Trigger.timestamp(@start_date |> DateTime.add(1 * @seconds_in_day) |> DateTime.add(1))

    mock_genesis_address([trigger1, trigger2, trigger3])

    assert {:throw, 5003} =
             contract
             |> prepare_contract(state)
             |> trigger_contract(trigger1)
             |> trigger_contract(trigger2)
             |> trigger_contract(trigger3)
  end

  describe "scenarios" do
    @tag :scenario
    test "a single deposit should generate rewards", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed", level: "5", amount: Decimal.new(1000)}},
        {:calculate, %{date: n_ticks_from_start(1)}}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # formula: (1/(365*24)) * 45_000_000 = 5136.986301369863
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "5136.986301369862")
        end
      )

      result_contract =
        run_actions(
          [{:calculate, %{date: n_ticks_from_start(2)}}],
          result_contract,
          result_contract.state,
          result_contract.uco_balance
        )

      # formula: (2/(365*24)) * 45_000_000 = 10273.972602739726
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "10273.97260273972")
        end
      )

      actions = [{:calculate, %{date: n_ticks_from_start(3)}}]

      result_contract =
        run_actions(
          actions,
          result_contract,
          result_contract.state,
          result_contract.uco_balance
        )

      # formula: (3/(365*24)) * 45_000_000 = 15410.95890410959
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "15410.95890410958")
        end
      )
    end

    @tag :scenario
    test "multiple deposits from multiple users should generate rewards", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed1", level: "2", amount: Decimal.new(1000)}},
        {:deposit,
         %{date: n_ticks_from_start(1), seed: "seed2", level: "5", amount: Decimal.new(1000)}}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # formula: (1/(365*24)) * 45_000_000 = 5136.986301369863
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "5136.986301369862")
        end
      )

      actions = [
        {:calculate, %{date: n_ticks_from_start(2)}}
      ]

      result_contract =
        run_actions(
          actions,
          result_contract,
          result_contract.state,
          result_contract.uco_balance
        )

      # D = (1/(365*24)) * 45_000_000
      # W = (0.14814814814814814, 0.8518518518518519)
      #
      # seed1 = (D * W.0) + prev_rewards = 5898.021308980213
      # seed2 = (D * W.1) + prev_rewards = 4375.951293759513
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "5898.021308980211")
        end
      )

      asserts_get_user_infos(result_contract, "seed2", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "4375.951293759511")
        end
      )
    end

    @tag :scenario
    test "multiple deposits from same users should generate rewards", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed1", level: "2", amount: Decimal.new(1000)}},
        {:deposit,
         %{date: n_ticks_from_start(1), seed: "seed1", level: "5", amount: Decimal.new(1000)}}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # formula: (1/(365*24)) * 45_000_000 = 5136.986301369863
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 2 == length(user_infos)

          assert Enum.all?(
                   user_infos,
                   &(&1["reward_amount"] in [
                       Decimal.new("5136.986301369862"),
                       0
                     ])
                 )
        end
      )

      actions = [
        {:calculate, %{date: n_ticks_from_start(2)}}
      ]

      result_contract =
        run_actions(
          actions,
          result_contract,
          result_contract.state,
          result_contract.uco_balance
        )

      # D = (1/(365*24)) * 45_000_000
      # W = (0.14814814814814814, 0.8518518518518519)
      #
      # seed1 = (D * W.0) + prev_rewards = 5898.021308980213
      # seed1 = (D * W.1) + prev_rewards = 4375.951293759513
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 2 == length(user_infos)

          assert Enum.all?(
                   user_infos,
                   &(&1["reward_amount"] in [
                       Decimal.new("5898.021308980211"),
                       Decimal.new("4375.951293759511")
                     ])
                 )
        end
      )
    end

    @tag :scenario
    test "flexible are merged together", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed1", level: "0", amount: Decimal.new(1000)}},
        {:deposit,
         %{date: n_ticks_from_start(1), seed: "seed1", level: "0", amount: Decimal.new(1000)}}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # formula: (1/(365*24)) * 45_000_000 = 5136.986301369863
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)

          assert Decimal.eq?(hd(user_infos)["reward_amount"], "5136.986301369862")
        end
      )
    end

    @tag :scenario
    test "giveaway is also distributed linearly", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed", level: "5", amount: Decimal.new(1000)}},
        {:calculate, %{date: n_ticks_from_start(1)}}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance + 4_000_000)

      # formula: ((1/(365*24)) * 45_000_000) + ((1/(365*4*24)) * 4_000_000) = 5251.141552511415
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "5251.141552511414")
        end
      )
    end

    @tag :scenario
    test "calculating multiple periods", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed", level: "5", amount: Decimal.new(1000)}},
        {:calculate, %{date: n_ticks_from_start(10)}}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      # formula: (10/(365*24)) * 45_000_000 = 51369.863013698625
      asserts_get_user_infos(result_contract, "seed", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "51369.86301369857")
        end
      )
    end

    @tag :scenario
    test "level change is considered", %{contract: contract} do
      genesis1 = seed_to_genesis("seed1")
      genesis2 = seed_to_genesis("seed2")

      distributed = Decimal.from_float(45_000_000 * ((7 * 24 - 1) / (365 * 24)))

      state = %{
        "last_calculation_timestamp" => n_ticks_from_start(7 * 24 - 1) |> DateTime.to_unix(),
        "deposits" => %{
          genesis1 => [
            %{
              "level" => "1",
              "amount" => Decimal.new(1000),
              "reward_amount" => 0,
              "start" => n_ticks_from_start(0) |> DateTime.to_unix(),
              "id" => n_ticks_from_start(0) |> DateTime.to_unix() |> Integer.to_string(),
              "end" => n_ticks_from_start(7 * 24) |> DateTime.to_unix()
            }
          ],
          genesis2 => [
            %{
              "level" => "7",
              "amount" => Decimal.new(1000),
              "reward_amount" => 0,
              "start" => n_ticks_from_start(0) |> DateTime.to_unix(),
              "id" => n_ticks_from_start(0) |> DateTime.to_unix() |> Integer.to_string(),
              "end" => n_ticks_from_start(1095 * 24) |> DateTime.to_unix()
            }
          ]
        },
        "rewards_reserved" => 0,
        "rewards_distributed" => distributed,
        "lp_tokens_deposited" => Decimal.new(2000),
        "lp_tokens_deposited_by_level" => %{
          "0" => 0,
          "1" => Decimal.new(1000),
          "2" => 0,
          "3" => 0,
          "4" => 0,
          "5" => 0,
          "6" => 0,
          "7" => Decimal.new(1000)
        }
      }

      actions = [
        {:calculate, %{date: n_ticks_from_start(7 * 24 + 1)}}
      ]

      result_contract =
        run_actions(
          actions,
          contract,
          state,
          Decimal.sub(@initial_balance, distributed)
        )

      # D = (1/(365*24)) * 45_000_000
      # W1 = (0.028138528138528136, 0.9718614718614719)
      # W2 = (0.015350877192982455, 0.9846491228070176)
      #
      # seed1 = (D * W1.0) + (D * W2.0) = 223.4044794426914
      # seed2 = (D * W1.1) + (D * W2.1) = 10050.568123297035
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "223.4044794426911")
        end
      )

      asserts_get_user_infos(result_contract, "seed2", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "10050.56812329702")
        end
      )
    end

    @tag :scenario
    test "year change is considered", %{contract: contract} do
      genesis1 = seed_to_genesis("seed1")
      genesis2 = seed_to_genesis("seed2")

      distributed = Decimal.from_float(45_000_000 * ((365 * 24 - 1) / (365 * 24)))

      state = %{
        "last_calculation_timestamp" => n_ticks_from_start(365 * 24 - 1) |> DateTime.to_unix(),
        "deposits" => %{
          genesis1 => [
            %{
              "level" => "7",
              "amount" => Decimal.new(1000),
              "reward_amount" => 0,
              "start" => n_ticks_from_start(0) |> DateTime.to_unix(),
              "id" => n_ticks_from_start(0) |> DateTime.to_unix() |> Integer.to_string(),
              "end" => n_ticks_from_start(1095 * 24) |> DateTime.to_unix()
            }
          ],
          genesis2 => [
            %{
              "level" => "7",
              "amount" => Decimal.new(1000),
              "reward_amount" => 0,
              "start" => n_ticks_from_start(0) |> DateTime.to_unix(),
              "id" => n_ticks_from_start(0) |> DateTime.to_unix() |> Integer.to_string(),
              "end" => n_ticks_from_start(1095 * 24) |> DateTime.to_unix()
            }
          ]
        },
        "rewards_reserved" => 0,
        "rewards_distributed" => distributed,
        "lp_tokens_deposited" => Decimal.new(2000),
        "lp_tokens_deposited_by_level" => %{
          "0" => 0,
          "1" => 0,
          "2" => 0,
          "3" => 0,
          "4" => 0,
          "5" => 0,
          "6" => 0,
          "7" => Decimal.new(2000)
        }
      }

      actions = [
        {:calculate, %{date: n_ticks_from_start(365 * 24 + 1)}}
      ]

      result_contract =
        run_actions(
          actions,
          contract,
          state,
          Decimal.sub(@initial_balance, distributed)
        )

      # D1 = (1/(365*24)) * 45_000_000
      # D2 = (1/(365*24)) * 22_500_000
      # W1 = (0.5, 0.5)
      # W2 = (0.5, 0.5)
      #
      # seed1 = (D1 * W1.0) + (D2 * W2.0) = 3852.7397260273974
      # seed2 = (D1 * W1.1) + (D2 * W2.1) = 3852.7397260273974
      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "3852.739726027465")
        end
      )

      asserts_get_user_infos(result_contract, "seed2", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "3852.739726027465")
        end
      )
    end

    @tag :scenario
    test "last tick should distribute everything", %{contract: contract} do
      genesis1 = seed_to_genesis("seed1")
      genesis2 = seed_to_genesis("seed2")

      state = %{
        "last_calculation_timestamp" => n_ticks_from_start(1460 * 24 - 1) |> DateTime.to_unix(),
        "deposits" => %{
          genesis1 => [
            %{
              "level" => "1",
              "amount" => Decimal.new(1000),
              "reward_amount" => 0,
              "start" => n_ticks_from_start(0) |> DateTime.to_unix(),
              "id" => n_ticks_from_start(0) |> DateTime.to_unix() |> Integer.to_string(),
              "end" => n_ticks_from_start(1460 * 24) |> DateTime.to_unix()
            }
          ],
          genesis2 => [
            %{
              "level" => "1",
              "amount" => Decimal.new(1000),
              "reward_amount" => 0,
              "start" => n_ticks_from_start(0) |> DateTime.to_unix(),
              "id" => n_ticks_from_start(0) |> DateTime.to_unix() |> Integer.to_string(),
              "end" => n_ticks_from_start(1460 * 24) |> DateTime.to_unix()
            }
          ]
        },
        "rewards_reserved" => 0,
        "rewards_distributed" => 0,
        "lp_tokens_deposited" => Decimal.new(2000),
        "lp_tokens_deposited_by_level" => %{
          "0" => 0,
          "1" => Decimal.new(2000),
          "2" => 0,
          "3" => 0,
          "4" => 0,
          "5" => 0,
          "6" => 0,
          "7" => 0
        }
      }

      actions = [
        {:calculate, %{date: n_ticks_from_start(1460 * 24)}}
      ]

      result_contract =
        run_actions(
          actions,
          contract,
          state,
          @initial_balance
        )

      asserts_get_user_infos(result_contract, "seed1", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "43750000")
        end
      )

      asserts_get_user_infos(result_contract, "seed2", actions,
        assert_fn: fn user_infos ->
          assert 1 == length(user_infos)
          assert Decimal.eq?(hd(user_infos)["reward_amount"], "43750000")
        end
      )
    end

    @tag :scenario
    test "withdraw all", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed", level: "0", amount: Decimal.new(1000)}},
        {:deposit,
         %{date: n_ticks_from_start(1), seed: "seed2", level: "0", amount: Decimal.new(1000)}},
        {:withdraw,
         %{
           date: n_ticks_from_start(2),
           seed: "seed",
           deposit_id: tick_to_id(0),
           amount: Decimal.new(1000)
         }},
        {:withdraw,
         %{
           date: n_ticks_from_start(3),
           seed: "seed2",
           deposit_id: tick_to_id(1),
           amount: Decimal.new(1000)
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # (3/(365*24)) * 45_000_000 = 15410.95890410959
          # 87500000 - 15410.95890410959 = 87484589.0410959
          assert Decimal.eq?(
                   Decimal.add(
                     farm_infos["rewards_distributed"],
                     result_contract.state["rewards_reserved"]
                   ),
                   "15410.95890410957"
                 )

          assert Decimal.eq?(farm_infos["remaining_rewards"], "87484589.0410959")
        end
      )
    end

    @tag :scenario
    test "withdraw partial", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed", level: "0", amount: Decimal.new(1000)}},
        {:deposit,
         %{date: n_ticks_from_start(1), seed: "seed2", level: "0", amount: Decimal.new(1000)}},
        {:withdraw,
         %{
           date: n_ticks_from_start(2),
           seed: "seed",
           deposit_id: tick_to_id(0),
           amount: Decimal.new(500)
         }},
        {:withdraw,
         %{
           date: n_ticks_from_start(3),
           seed: "seed2",
           deposit_id: tick_to_id(1),
           amount: Decimal.new(500)
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # (3/(365*24)) * 45_000_000 = 15410.95890410959
          # 87500000 - 15410.95890410959 = 87484589.0410959
          assert Decimal.eq?(
                   Decimal.add(
                     farm_infos["rewards_distributed"],
                     result_contract.state["rewards_reserved"]
                   ),
                   "15410.95890410957"
                 )

          assert Decimal.eq?(farm_infos["remaining_rewards"], "87484589.04109589")
        end
      )
    end

    @tag :scenario
    test "claiming should distribute rewards", %{contract: contract} do
      actions = [
        {:deposit,
         %{date: n_ticks_from_start(0), seed: "seed", level: "0", amount: Decimal.new(1000)}},
        {:deposit,
         %{date: n_ticks_from_start(1), seed: "seed2", level: "0", amount: Decimal.new(1000)}},
        {:claim,
         %{
           date: n_ticks_from_start(2),
           seed: "seed2",
           deposit_id: tick_to_id(1)
         }}
      ]

      result_contract = run_actions(actions, contract, %{}, @initial_balance)

      asserts_get_farm_infos(result_contract, actions,
        assert_fn: fn farm_infos ->
          # (0.5*1/(365*24)) * 45_000_000 = 2568.4931506849316
          # (1.5*1/(365*24)) * 45_000_000 = 7705.479452054795
          # 87500000 - 2568.4931506849316 - 7705.479452054795 = 87489726.02739726
          assert Decimal.eq?(farm_infos["rewards_distributed"], "2568.493150684931")
          assert Decimal.eq?(result_contract.state["rewards_reserved"], "7705.479452054789")
          assert Decimal.eq?(farm_infos["remaining_rewards"], "87489726.02739726")
        end
      )
    end
  end

  describe "Benchmark" do
    setup %{contract: contract} do
      state =
        "/Users/bastien/Documents/archethic-node/test/contracts/state.json"
        |> File.read!()
        |> Jason.decode!(floats: :decimals)

      contract = run_actions([], contract, state, Decimal.new("87375.46577807"))

      %{contract: contract}
    end

    @tag :benchmark
    test "get_user_infos", %{contract: contract} do
      start = System.monotonic_time(:millisecond)

      call_function(
        contract,
        "get_user_infos",
        ["0000B48A73C949BD7CC364188DD37DACF50498D81525EF98B38EC606617B43FFDCEC"],
        ~U[2024-07-24T07:00:00Z]
      )

      IO.puts("#{System.monotonic_time(:millisecond) - start}ms get_user_infos")
      assert true
    end

    @tag :benchmark
    test "get_farm_infos", %{contract: contract} do
      start = System.monotonic_time(:millisecond)

      call_function(
        contract,
        "get_farm_infos",
        [],
        ~U[2024-07-24T07:00:00Z]
      )

      IO.puts("#{System.monotonic_time(:millisecond) - start}ms get_farm_infos")
      assert true
    end

    @tag :benchmark
    test "calculate_rewards", %{contract: contract} do
      start = System.monotonic_time(:millisecond)

      actions = [
        {:calculate, %{date: ~U[2024-07-23T21:00:00Z]}}
      ]

      contract = run_actions(actions, contract, contract.state, contract.uco_balance)

      IO.puts("#{System.monotonic_time(:millisecond) - start}ms calculate_rewards")
      assert true
    end
  end

  defp asserts_get_farm_infos(contract, actions, opts \\ []) do
    uco_balance = contract.uco_balance

    time_now =
      case Keyword.get(opts, :time_now) do
        nil ->
          actions
          |> Enum.map(&elem(&1, 1).date)
          |> Enum.max(DateTime)

        datetime ->
          datetime
      end

    time_now_unix = DateTime.to_unix(time_now)

    farm_infos = call_function(contract, "get_farm_infos", [], time_now)

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
      # sum of remaining_rewards is equal to initial balance
      assert farm_infos["stats"]
             |> Map.values()
             |> Enum.map(& &1["remaining_rewards"])
             |> List.flatten()
             |> Enum.map(& &1["remaining_rewards"])
             |> Enum.reduce(&Decimal.add/2)
             |> then(fn total_remaining_rewards ->
               assert almost_equal(
                        Decimal.add(
                          Decimal.add(total_remaining_rewards, farm_infos["rewards_distributed"]),
                          contract.state["rewards_reserved"] || 0
                        ),
                        @initial_balance
                      )
             end)
    end

    # sum of rewards_amount == rewards_reserved
    rewards_reserved =
      contract.state["deposits"]
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(0, &Decimal.add(&1["reward_amount"], &2))

    # rewards_reserved may not exist (if there are only deposits when farm is not started)
    if contract.state["rewards_reserved"] do
      # should be equal but it's not because of imprecisions
      assert almost_equal(rewards_reserved, contract.state["rewards_reserved"])
    end

    # remaining_rewards subtracts the reserved rewards
    # should be equal but it's not because of imprecisions
    if farm_infos["remaining_rewards"] != 0 do
      assert almost_equal(
               Decimal.sub(uco_balance, rewards_reserved),
               farm_infos["remaining_rewards"]
             )
    end

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
          actions
          |> Enum.map(&elem(&1, 1).date)
          |> Enum.max(DateTime)

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

    for %{
          index: index,
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

      user_info = Enum.at(user_infos, index)

      assert index == user_info["index"]
      assert Decimal.eq?(amount, user_info["amount"])
      assert Decimal.compare(user_info["reward_amount"], 0) in [:eq, :gt]
      assert end_to_level(end_timestamp, time_now) == user_info["level"]

      if end_timestamp > DateTime.to_unix(time_now) do
        assert start_timestamp == user_info["start"]
        assert end_timestamp == user_info["end"]
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
      |> Enum.sort_by(&elem(&1, 1).date, DateTime)
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
    |> Enum.sort_by(&elem(&1, 1).date, DateTime)
    |> Enum.reduce(%{}, fn
      {:claim, _}, acc ->
        acc

      {:calculate, _}, acc ->
        acc

      {action, payload}, acc ->
        user_deposits = Map.get(acc, payload.seed, [])

        user_deposits =
          case action do
            :deposit ->
              start_timestamp = payload.date |> DateTime.to_unix()
              start_timestamp = start_timestamp - rem(start_timestamp, @round_now_to)

              end_timestamp = start_timestamp + level_to_seconds(payload.level)

              deposit = %{
                seed: payload.seed,
                amount: payload.amount,
                start_timestamp: start_timestamp,
                end_timestamp: end_timestamp,
                deposit_id: payload.date |> DateTime.to_unix() |> Integer.to_string()
              }

              user_deposits ++ [deposit]

            :withdraw ->
              Enum.map(user_deposits, fn d ->
                if d.deposit_id == payload.deposit_id do
                  Map.update!(d, :amount, &Decimal.sub(&1, payload.amount))
                else
                  d
                end
              end)

            :relock ->
              start_timestamp = payload.date |> DateTime.to_unix()

              start_timestamp = start_timestamp - rem(start_timestamp, @round_now_to)

              end_timestamp = start_timestamp + level_to_seconds(payload.level)

              Enum.map(user_deposits, fn d ->
                if d.deposit_id == payload.deposit_id do
                  d
                  |> Map.put(:start_timestamp, start_timestamp)
                  |> Map.put(:end_timestamp, end_timestamp)
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
      seed = Map.get(payload, :seed, "hardcoded-seed")
      index = Map.get(index_acc, seed, 1)
      index_acc = Map.put(index_acc, seed, index + 1)

      trigger =
        Trigger.new(seed, index)
        |> Trigger.timestamp(payload.date)

      trigger =
        case action do
          :calculate ->
            trigger
            |> Trigger.named_action("calculate_rewards", %{})

          :deposit ->
            trigger
            |> Trigger.named_action("deposit", %{"level" => payload.level})
            |> Trigger.token_transfer(@lp_token_address, 0, @farm_address, payload.amount)

          :claim ->
            trigger
            |> Trigger.named_action("claim", %{"deposit_id" => payload.deposit_id})

          :withdraw ->
            trigger
            |> Trigger.named_action("withdraw", %{
              "amount" => payload.amount,
              "deposit_id" => payload.deposit_id
            })

          :relock ->
            trigger
            |> Trigger.named_action("relock", %{
              "level" => payload.level,
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

  defp deposits_generator(opts \\ []) do
    StreamData.list_of(seed_generator(), min_length: 1, max_length: 5)
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
      |> Enum.sort_by(&elem(&1, 1).date, DateTime)
    end)
  end

  defp deposit_generator(seed, opts) do
    {delay_generator(), StreamData.constant(seed), amount_generator(opts), level_generator(opts)}
    |> StreamData.tuple()
    |> StreamData.map(fn {delay, seed, amount, level} ->
      {:deposit,
       %{
         amount: amount,
         date: delay,
         level: level,
         seed: seed,
         deposit_id: tick_to_id(delay)
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

  defp level_to_seconds(level), do: level_to_days(level) * @seconds_in_day

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

  defp n_ticks_from_start(n) do
    @start_date
    |> DateTime.add(n * @round_now_to)
  end

  defp tick_to_id(n) do
    n_ticks_from_start(n)
    |> DateTime.to_unix()
    |> Integer.to_string()
  end

  defp seed_to_genesis(seed) do
    {genesis_public_key, _} = Crypto.derive_keypair(seed, 0)
    Crypto.derive_address(genesis_public_key) |> Base.encode16()
  end

  defp generate_deposit(opts) do
    seed = Keyword.fetch!(opts, :seed)
    date = Keyword.fetch!(opts, :date)
    level = Keyword.get(opts, :level, "0")
    amount = Keyword.get(opts, :amount, Decimal.new(1000))
    reward_amount = Keyword.get(opts, :reward_amount, Decimal.new(0))
    genesis_address = seed_to_genesis(seed)

    %{
      genesis_address: genesis_address,
      state: %{
        "level" => level,
        "amount" => amount,
        "reward_amount" => reward_amount,
        "start" =>
          case level do
            "0" -> nil
            _ -> DateTime.to_unix(date)
          end,
        "id" => DateTime.to_unix(date) |> Integer.to_string(),
        "end" =>
          case level do
            "0" -> 0
            _ -> DateTime.to_unix(date) + level_to_seconds(level)
          end
      }
    }
  end

  defp almost_equal(a, b) do
    Decimal.abs(Decimal.sub(a, b)) |> Decimal.lt?("0.0001")
  end
end
