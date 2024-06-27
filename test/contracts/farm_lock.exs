@version 1

condition triggered_by: transaction, on: deposit(end_timestamp) do
  if end_timestamp == "max" do
    end_timestamp = @END_DATE
  end

  if end_timestamp == "flex" do
    end_timestamp = 0
  end

  if transaction.timestamp >= @END_DATE do
    throw(message: "deposit impossible once farm is closed", code: 1001)
  end

  if end_timestamp > @END_DATE do
    throw(message: "deposit's end cannot be greater than farm's end", code: 1005)
  end

  if get_user_transfer_amount() <= 0 do
    throw(message: "deposit's amount must greater than 0", code: 1002)
  end

  true
end

actions triggered_by: transaction, on: deposit(end_timestamp) do
  now = Time.now()
  start = now

  if end_timestamp == "max" do
    end_timestamp = @END_DATE
  end

  if end_timestamp == "flex" do
    end_timestamp = 0
    start = nil
  end

  transfer_amount = get_user_transfer_amount()

  user_genesis_address = get_user_genesis(transaction)

  deposits = nil

  if now > @START_DATE do
    res = calculate_new_rewards()
    deposits = res.deposits
    State.set("rewards_reserved", res.rewards_reserved)
    State.set("last_calculation_timestamp", res.last_calculation_timestamp)
  else
    deposits = State.get("deposits", Map.new())
  end

  current_deposit = [amount: transfer_amount, reward_amount: 0, start: now, end: end_timestamp]

  user_deposits = Map.get(deposits, user_genesis_address, [])
  user_deposits = List.append(user_deposits, current_deposit)
  deposits = Map.set(deposits, user_genesis_address, user_deposits)

  State.set("deposits", deposits)

  lp_tokens_deposited = State.get("lp_tokens_deposited", 0)
  State.set("lp_tokens_deposited", lp_tokens_deposited + transfer_amount)
end

condition triggered_by: transaction, on: claim(deposit_index) do
  if transaction.timestamp <= @START_DATE do
    throw(message: "farm is not started yet", code: 2001)
  end

  now = Time.now()
  user_genesis_address = get_user_genesis(transaction)
  user_deposit = get_user_deposit(user_genesis_address, deposit_index)

  if user_deposit == nil do
    throw(message: "deposit not found", code: 2000)
  end

  if user_deposit.end > now do
    throw(message: "claiming before end of lock", code: 2002)
  end

  res = calculate_new_rewards()
  user_deposits = Map.get(res.deposits, user_genesis_address)
  user_deposit = List.at(user_deposits, deposit_index)

  user_deposit.reward_amount > 0
end

actions triggered_by: transaction, on: claim(deposit_index) do
  user_genesis_address = get_user_genesis(transaction)

  res = calculate_new_rewards()
  deposits = res.deposits
  State.set("last_calculation_timestamp", res.last_calculation_timestamp)

  user_deposits = Map.get(deposits, user_genesis_address)
  user_deposit = List.at(user_deposits, deposit_index)

  if @REWARD_TOKEN == "UCO" do
    Contract.add_uco_transfer(to: transaction.address, amount: user_deposit.reward_amount)
  else
    Contract.add_token_transfer(
      to: transaction.address,
      amount: user_deposit.reward_amount,
      token_address: @REWARD_TOKEN
    )
  end

  rewards_distributed = State.get("rewards_distributed", 0)
  State.set("rewards_distributed", rewards_distributed + user_deposit.reward_amount)
  State.set("rewards_reserved", res.rewards_reserved - user_deposit.reward_amount)

  user_deposit = Map.set(user_deposit, "reward_amount", 0)
  user_deposits = set_at(user_deposits, deposit_index, user_deposit)

  deposits = Map.set(deposits, user_genesis_address, user_deposits)
  State.set("deposits", deposits)
end

condition triggered_by: transaction, on: withdraw(amount, deposit_index) do
  user_genesis_address = get_user_genesis(transaction)
  user_deposit = get_user_deposit(user_genesis_address, deposit_index)

  if user_deposit == nil do
    throw(message: "deposit not found", code: 3000)
  end

  if amount > user_deposit.amount do
    throw(message: "amount requested is greater than amount deposited", code: 3003)
  end

  true
end

actions triggered_by: transaction, on: withdraw(amount, deposit_index) do
  user_genesis_address = get_user_genesis(transaction)

  deposits = nil
  rewards_reserved = 0

  if Time.now() > @START_DATE do
    res = calculate_new_rewards()
    deposits = res.deposits
    rewards_reserved = res.rewards_reserved
    State.set("last_calculation_timestamp", res.last_calculation_timestamp)
  else
    deposits = State.get("deposits", Map.new())
    rewards_reserved = State.get("rewards_reserved", 0)
  end

  user_deposits = Map.get(deposits, user_genesis_address)
  user_deposit = List.at(user_deposits, deposit_index)

  if user_deposit.reward_amount > 0 do
    if @REWARD_TOKEN == "UCO" do
      Contract.add_uco_transfer(to: transaction.address, amount: user_deposit.reward_amount)
    else
      Contract.add_token_transfer(
        to: transaction.address,
        amount: user_deposit.reward_amount,
        token_address: @REWARD_TOKEN
      )
    end

    rewards_distributed = State.get("rewards_distributed", 0)
    State.set("rewards_distributed", rewards_distributed + user_deposit.reward_amount)

    rewards_reserved = rewards_reserved - user_deposit.reward_amount
  end

  State.set("rewards_reserved", rewards_reserved)

  Contract.add_token_transfer(
    to: transaction.address,
    amount: amount,
    token_address: @LP_TOKEN_ADDRESS
  )

  lp_tokens_deposited = State.get("lp_tokens_deposited")
  State.set("lp_tokens_deposited", lp_tokens_deposited - amount)

  if amount == user_deposit.amount do
    user_deposits = delete_at(user_deposits, deposit_index)

    if List.size(user_deposits) > 0 do
      deposits = Map.set(deposits, user_genesis_address, user_deposits)
    else
      deposits = Map.delete(deposits, user_genesis_address)
    end
  else
    user_deposit = Map.set(user_deposit, "reward_amount", 0)
    user_deposit = Map.set(user_deposit, "amount", user_deposit.amount - amount)
    user_deposits = set_at(user_deposits, deposit_index, user_deposit)
    deposits = Map.set(deposits, user_genesis_address, user_deposits)
  end

  State.set("deposits", deposits)
end

condition triggered_by: transaction, on: relock(end_timestamp, deposit_index) do
  if end_timestamp == "max" do
    end_timestamp = @END_DATE
  end

  user_genesis_address = get_user_genesis(transaction)
  user_deposit = get_user_deposit(user_genesis_address, deposit_index)

  if user_deposit == nil do
    throw(message: "deposit not found", code: 4000)
  end

  if transaction.timestamp >= @END_DATE do
    throw(message: "relock impossible once farm is closed", code: 4002)
  end

  if end_timestamp > @END_DATE do
    throw(message: "relock's end cannot be past farm's end", code: 4003)
  end

  if user_deposit["end"] >= end_timestamp do
    throw(message: "relock's end cannot be inferior or equal to deposit's end", code: 4004)
  end

  true
end

actions triggered_by: transaction, on: relock(end_timestamp, deposit_index) do
  if end_timestamp == "max" do
    end_timestamp = @END_DATE
  end

  now = Time.now()
  user_genesis_address = get_user_genesis(transaction)

  res = calculate_new_rewards()
  deposits = res.deposits
  State.set("last_calculation_timestamp", res.last_calculation_timestamp)

  user_deposits = Map.get(deposits, user_genesis_address)
  user_deposit = List.at(user_deposits, deposit_index)

  if user_deposit.reward_amount > 0 do
    if @REWARD_TOKEN == "UCO" do
      Contract.add_uco_transfer(to: transaction.address, amount: user_deposit.reward_amount)
    else
      Contract.add_token_transfer(
        to: transaction.address,
        amount: user_deposit.reward_amount,
        token_address: @REWARD_TOKEN
      )
    end
  end

  rewards_distributed = State.get("rewards_distributed", 0)
  State.set("rewards_distributed", rewards_distributed + user_deposit.reward_amount)
  State.set("rewards_reserved", res.rewards_reserved - user_deposit.reward_amount)

  user_deposit = Map.set(user_deposit, "reward_amount", 0)
  user_deposit = Map.set(user_deposit, "end", end_timestamp)
  user_deposits = set_at(user_deposits, deposit_index, user_deposit)

  deposits = Map.set(deposits, user_genesis_address, user_deposits)
  State.set("deposits", deposits)
end

condition(
  triggered_by: transaction,
  on: update_dates(new_start_date, new_end_date),
  as: [
    previous_public_key:
      (
        # Can only be updated by master chain of the dex
        previous_address = Chain.get_previous_address()
        Chain.get_genesis_address(previous_address) == @MASTER_ADDRESS
      ),
    content:
      (
        # Can update date only if farm is already ended
        now = Time.now()

        valid_update_date? = now >= @END_DATE
        valid_start_date? = now + 7200 <= new_start_date && now + 604_800 >= new_start_date

        valid_end_date? =
          new_start_date + 2_592_000 <= new_end_date &&
            new_start_date + 31_536_000 >= new_end_date

        valid_update_date? && valid_start_date? && valid_end_date?
      )
  ]
)

actions triggered_by: transaction, on: update_dates(new_start_date, new_end_date) do
  params = [
    @LP_TOKEN_ADDRESS,
    new_start_date,
    new_end_date,
    @REWARD_TOKEN,
    @FARM_ADDRESS
  ]

  new_code = Contract.call_function(@FACTORY_ADDRESS, "get_farm_code", params)

  if Code.is_valid?(new_code) && !Code.is_same?(new_code, contract.code) do
    Contract.set_type("contract")
    Contract.set_code(new_code)

    Contract.add_recipient(
      address: @ROUTER_ADDRESS,
      action: "update_farm_dates",
      args: [new_start_date, new_end_date]
    )

    res = calculate_new_rewards()
    State.set("deposits", res.deposits)
    State.set("rewards_reserved", res.rewards_reserved)
    State.delete("last_calculation_timestamp")
  end
end

condition(
  triggered_by: transaction,
  on: update_code(),
  as: [
    previous_public_key:
      (
        # Pool code can only be updated from the router contract of the dex

        # Transaction is not yet validated so we need to use previous address
        # to get the genesis address
        previous_address = Chain.get_previous_address()
        Chain.get_genesis_address(previous_address) == @ROUTER_ADDRESS
      )
  ]
)

actions triggered_by: transaction, on: update_code() do
  params = [
    @LP_TOKEN_ADDRESS,
    @START_DATE,
    @END_DATE,
    @REWARD_TOKEN,
    @FARM_ADDRESS
  ]

  new_code = Contract.call_function(@FACTORY_ADDRESS, "get_farm_code", params)

  if Code.is_valid?(new_code) && !Code.is_same?(new_code, contract.code) do
    Contract.set_type("contract")
    Contract.set_code(new_code)
  end
end

fun get_reward_token_balance() do
  if @REWARD_TOKEN == "UCO" do
    contract.balance.uco
  else
    key = [token_address: @REWARD_TOKEN, token_id: 0]
    Map.get(contract.balance.tokens, key, 0)
  end
end

fun get_user_transfer_amount() do
  transfers = Map.get(transaction.token_transfers, @FARM_ADDRESS, [])
  transfer = List.at(transfers, 0)

  if transfer == nil do
    throw(message: "no transfer found to the farm", code: 1003)
  end

  if transfer.token_address != @LP_TOKEN_ADDRESS do
    throw(message: "invalid token transfered to the farm", code: 1004)
  end

  transfer.amount
end

fun calculate_new_rewards() do
  now = Time.now()
  day = 86400
  year = 31_536_000

  deposits = State.get("deposits", Map.new())
  lp_tokens_deposited = State.get("lp_tokens_deposited", 0)
  rewards_reserved = State.get("rewards_reserved", 0)
  last_calculation_timestamp = State.get("last_calculation_timestamp", @START_DATE)

  if last_calculation_timestamp < now && last_calculation_timestamp < @END_DATE &&
       lp_tokens_deposited > 0 do
    log(now: now, last_calculation_timestamp: last_calculation_timestamp)
    duration_per_level = Map.new()
    duration_per_level = Map.set(duration_per_level, "0", 0)
    duration_per_level = Map.set(duration_per_level, "1", 7 * day)
    duration_per_level = Map.set(duration_per_level, "2", 30 * day)
    duration_per_level = Map.set(duration_per_level, "3", 90 * day)
    duration_per_level = Map.set(duration_per_level, "4", 180 * day)
    duration_per_level = Map.set(duration_per_level, "5", 365 * day)
    duration_per_level = Map.set(duration_per_level, "6", 730 * day)
    duration_per_level = Map.set(duration_per_level, "7", 1095 * day)

    end_of_years = [
      [year: 1, timestamp: @START_DATE + year],
      [year: 2, timestamp: @START_DATE + 2 * year],
      [year: 3, timestamp: @START_DATE + 3 * year],
      [year: 4, timestamp: @START_DATE + 4 * year]
    ]

    periods = []

    for end_of_year in end_of_years do
      if end_of_year.timestamp > last_calculation_timestamp && end_of_year.timestamp < now do
        periods =
          List.append(periods,
            start: last_calculation_timestamp,
            end: end_of_year.timestamp,
            year: end_of_year.year
          )

        periods =
          List.append(periods, start: end_of_year.timestamp, end: now, year: end_of_year.year + 1)
      end
    end

    if periods == [] do
      periods = [[start: last_calculation_timestamp, end: now, year: year]]
    end

    log(periods: periods)

    rewards_balance = 0

    if @REWARD_TOKEN == "UCO" do
      rewards_balance = contract.balance.uco
    else
      key = [token_address: @REWARD_TOKEN, token_id: 0]
      rewards_balance = Map.get(contract.balance.tokens, key, 0)
    end

    time_elapsed = now - last_calculation_timestamp
    time_remaining = @END_DATE - last_calculation_timestamp
    available_balance = rewards_balance - rewards_reserved

    # TODO: IF NOW >= END_DATE ALLOCATE ALL REMAINING
    amount_to_allocate_per_year = Map.new()

    amount_to_allocate_per_year =
      Map.set(amount_to_allocate_per_year, "1", @INITIAL_BALANCE * 0.5)

    amount_to_allocate_per_year =
      Map.set(amount_to_allocate_per_year, "2", @INITIAL_BALANCE * 0.25)

    amount_to_allocate_per_year =
      Map.set(amount_to_allocate_per_year, "3", @INITIAL_BALANCE * 0.125)

    amount_to_allocate_per_year =
      Map.set(amount_to_allocate_per_year, "4", @INITIAL_BALANCE * 0.125)

    weight_per_level = Map.new()
    weight_per_level = Map.set(weight_per_level, "0", 0.007)
    weight_per_level = Map.set(weight_per_level, "1", 0.013)
    weight_per_level = Map.set(weight_per_level, "2", 0.024)
    weight_per_level = Map.set(weight_per_level, "3", 0.043)
    weight_per_level = Map.set(weight_per_level, "4", 0.077)
    weight_per_level = Map.set(weight_per_level, "5", 0.138)
    weight_per_level = Map.set(weight_per_level, "6", 0.249)
    weight_per_level = Map.set(weight_per_level, "7", 0.449)

    # Extra balance on the chain is considered give away
    # we distributed them linearly
    giveaways = rewards_balance + State.get("rewards_distributed", 0) - @INITIAL_BALANCE
    giveaways_to_allocate = giveaways * (time_elapsed / time_remaining)

    log(giveaways_to_allocate: giveaways_to_allocate)

    amount_deposited_per_level = Map.new()
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "0", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "1", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "2", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "3", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "4", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "5", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "6", 0)
    amount_deposited_per_level = Map.set(amount_deposited_per_level, "7", 0)

    for address in Map.keys(deposits) do
      user_deposits = Map.get(deposits, address)

      for user_deposit in user_deposits do
        level = nil

        for l in Map.keys(duration_per_level) do
          if level == nil do
            duration = Map.get(duration_per_level, l)
            end_current_level = user_deposit.end - duration

            if now >= end_current_level do
              level = l
            end
          end
        end

        if level == nil do
          level = "7"
        end

        amount_deposited_per_level =
          Map.set(
            amount_deposited_per_level,
            level,
            Map.get(amount_deposited_per_level, level, 0) + user_deposit.amount
          )
      end
    end

    log(amount_deposited_per_level: amount_deposited_per_level)

    total_weighted_amount_deposited = 0

    for level in Map.keys(weight_per_level) do
      weight = Map.get(weight_per_level, level)
      amount_deposited = Map.get(amount_deposited_per_level, level)
      weighted_amount_deposited = amount_deposited * weight

      total_weighted_amount_deposited =
        total_weighted_amount_deposited + weighted_amount_deposited
    end

    log(total_weighted_amount_deposited: total_weighted_amount_deposited)

    if total_weighted_amount_deposited > 0 do
      amount_to_allocate_per_level_year = Map.new()

      for level in Map.keys(weight_per_level) do
        weight = Map.get(weight_per_level, level)
        amount_deposited = Map.get(amount_deposited_per_level, level)
        weighted_amount_deposited = amount_deposited * weight

        amount_to_allocate_per_level_year =
          Map.set(
            amount_to_allocate_per_level_year,
            level,
            [
              weighted_amount_deposited / total_weighted_amount_deposited *
                Map.get(amount_to_allocate_per_year, "1"),
              weighted_amount_deposited / total_weighted_amount_deposited *
                Map.get(amount_to_allocate_per_year, "2"),
              weighted_amount_deposited / total_weighted_amount_deposited *
                Map.get(amount_to_allocate_per_year, "3"),
              weighted_amount_deposited / total_weighted_amount_deposited *
                Map.get(amount_to_allocate_per_year, "4")
            ]
          )
      end

      log(amount_to_allocate_per_level_year: amount_to_allocate_per_level_year)

      for address in Map.keys(deposits) do
        user_deposits = Map.get(deposits, address)
        user_deposits_updated = []

        for user_deposit in user_deposits do
          log(user_deposit: user_deposit)
          ends_per_level = Map.new()

          for l in Map.keys(duration_per_level) do
            duration = Map.get(duration_per_level, l)
            end_current_level = user_deposit.end - duration

            ends_per_level =
              Map.set(
                ends_per_level,
                String.from_number(String.to_number(l) + 1),
                end_current_level
              )
          end

          log(ends_per_level: ends_per_level)

          periods2 = []

          for period in periods do
            log(period: period)
            periods3 = []

            for l in Map.keys(ends_per_level) do
              end_of_level = Map.get(ends_per_level, l)

              if end_of_level > period.start && end_of_level < period.end do
                periods3 =
                  List.append(periods3,
                    start: period.start,
                    end: end_of_level,
                    level: l,
                    year: period.year
                  )

                periods3 =
                  List.append(periods3,
                    start: end_of_level,
                    end: period.end,
                    level: String.from_number(String.to_number(l) - 1),
                    year: period.year
                  )
              end
            end

            if periods3 == [] do
              periods3 = [[start: period.start, end: period.end, year: period.year, duh: 1]]
            end

            periods2 = periods2 ++ periods3
          end

          log(periods2: periods2)

          amount_to_allocate = Map.get(amount_to_allocate_per_level, level)
          amount_deposited = Map.get(amount_deposited_per_level, level)

          new_reward_amount = amount_to_allocate * (user_deposit.amount / amount_deposited)

          if new_reward_amount > 0 do
            user_deposit =
              Map.set(
                user_deposit,
                "reward_amount",
                user_deposit.reward_amount + new_reward_amount
              )

            rewards_reserved = rewards_reserved + new_reward_amount

            last_calculation_timestamp = now
          end

          user_deposits_updated = List.append(user_deposits_updated, user_deposit)
        end

        deposits = Map.set(deposits, address, user_deposits_updated)
      end
    end
  end

  [
    deposits: deposits,
    rewards_reserved: rewards_reserved,
    last_calculation_timestamp: last_calculation_timestamp
  ]
end

export fun(get_farm_infos()) do
  now = Time.now()
  reward_token_balance = 0
  day = 86400

  if @REWARD_TOKEN == "UCO" do
    reward_token_balance = contract.balance.uco
  else
    key = [token_address: @REWARD_TOKEN, token_id: 0]
    reward_token_balance = Map.get(contract.balance.tokens, key, 0)
  end

  remaining_rewards = nil

  if reward_token_balance != nil do
    remaining_rewards = reward_token_balance - State.get("rewards_reserved", 0)
  end

  deposits = State.get("deposits", Map.new())
  lp_tokens_deposited = State.get("lp_tokens_deposited", 0)

  weight_per_level = Map.new()
  weight_per_level = Map.set(weight_per_level, "0", 0.007)
  weight_per_level = Map.set(weight_per_level, "1", 0.013)
  weight_per_level = Map.set(weight_per_level, "2", 0.024)
  weight_per_level = Map.set(weight_per_level, "3", 0.043)
  weight_per_level = Map.set(weight_per_level, "4", 0.077)
  weight_per_level = Map.set(weight_per_level, "5", 0.138)
  weight_per_level = Map.set(weight_per_level, "6", 0.249)
  weight_per_level = Map.set(weight_per_level, "7", 0.449)

  available_levels = Map.new()
  available_levels = Map.set(available_levels, "0", now + 0)
  available_levels = Map.set(available_levels, "1", now + 7 * day)
  available_levels = Map.set(available_levels, "2", now + 30 * day)
  available_levels = Map.set(available_levels, "3", now + 90 * day)
  available_levels = Map.set(available_levels, "4", now + 180 * day)
  available_levels = Map.set(available_levels, "5", now + 365 * day)
  available_levels = Map.set(available_levels, "6", now + 730 * day)
  available_levels = Map.set(available_levels, "7", now + 1095 * day)

  stats = Map.new()

  stats =
    Map.set(stats, "0",
      weight: Map.get(weight_per_level, "0"),
      rewards_allocated: Map.get(weight_per_level, "0") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "1",
      weight: Map.get(weight_per_level, "1"),
      rewards_allocated: Map.get(weight_per_level, "1") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "2",
      weight: Map.get(weight_per_level, "2"),
      rewards_allocated: Map.get(weight_per_level, "2") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "3",
      weight: Map.get(weight_per_level, "3"),
      rewards_allocated: Map.get(weight_per_level, "3") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "4",
      weight: Map.get(weight_per_level, "4"),
      rewards_allocated: Map.get(weight_per_level, "4") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "5",
      weight: Map.get(weight_per_level, "5"),
      rewards_allocated: Map.get(weight_per_level, "5") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "6",
      weight: Map.get(weight_per_level, "6"),
      rewards_allocated: Map.get(weight_per_level, "6") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  stats =
    Map.set(stats, "7",
      weight: Map.get(weight_per_level, "7"),
      rewards_allocated: Map.get(weight_per_level, "7") * reward_token_balance,
      lp_tokens_deposited: 0,
      deposits_count: 0,
      tvl_ratio: 0
    )

  for user_genesis in Map.keys(deposits) do
    user_deposits = Map.get(deposits, user_genesis)

    for user_deposit in user_deposits do
      level = nil

      for l in Map.keys(available_levels) do
        if level == nil do
          until = Map.get(available_levels, l)

          if user_deposit.end <= until do
            level = l
          end
        end
      end

      if level == nil do
        level = "7"
      end

      stats_for_level = Map.get(stats, level)

      lp_tokens_deposited_for_level =
        Map.get(stats_for_level, "lp_tokens_deposited") + user_deposit.amount

      deposits_count_for_level = Map.get(stats_for_level, "deposits_count") + 1
      tvl_ratio = lp_tokens_deposited_for_level / lp_tokens_deposited

      stats_for_level =
        Map.set(stats_for_level, "lp_tokens_deposited", lp_tokens_deposited_for_level)

      stats_for_level = Map.set(stats_for_level, "tvl_ratio", tvl_ratio)

      stats_for_level = Map.set(stats_for_level, "deposits_count", deposits_count_for_level)
      stats = Map.set(stats, level, stats_for_level)
    end
  end

  [
    lp_token_address: @LP_TOKEN_ADDRESS,
    reward_token: @REWARD_TOKEN,
    start_date: @START_DATE,
    end_date: @END_DATE,
    remaining_rewards: remaining_rewards,
    rewards_distributed: State.get("rewards_distributed", 0),
    available_levels: available_levels,
    stats: stats
  ]
end

export fun(get_user_infos(user_genesis_address)) do
  now = Time.now()
  day = 86400
  reply = []

  user_genesis_address = String.to_hex(user_genesis_address)

  available_levels = Map.new()
  available_levels = Map.set(available_levels, "0", now + 0)
  available_levels = Map.set(available_levels, "1", now + 7 * day)
  available_levels = Map.set(available_levels, "2", now + 30 * day)
  available_levels = Map.set(available_levels, "3", now + 90 * day)
  available_levels = Map.set(available_levels, "4", now + 180 * day)
  available_levels = Map.set(available_levels, "5", now + 365 * day)
  available_levels = Map.set(available_levels, "6", now + 730 * day)
  available_levels = Map.set(available_levels, "7", now + 1095 * day)

  deposits = State.get("deposits", Map.new())
  user_deposits = Map.get(deposits, user_genesis_address, [])

  # REFAIRE l'equivalent d'un calculate_new_reward

  i = 0

  for user_deposit in user_deposits do
    level = nil

    for l in Map.keys(available_levels) do
      if level == nil do
        until = Map.get(available_levels, l)

        if user_deposit.end <= until do
          level = l
        end
      end
    end

    if level == nil do
      level = "7"
    end

    info = [
      index: i,
      amount: user_deposit.amount,
      reward_amount: user_deposit.reward_amount,
      level: level
    ]

    if user_deposit.end > now do
      info = Map.set(info, "end", user_deposit.end)
      info = Map.set(info, "start", user_deposit.start)
    end

    reply = List.append(reply, info)
    i = i + 1
  end

  reply
end

fun get_user_genesis(transaction) do
  previous_address = Chain.get_previous_address(transaction)
  Chain.get_genesis_address(previous_address)
end

fun get_user_deposit(user_genesis_address, deposit_index) do
  deposits = State.get("deposits", Map.new())
  user_deposits = Map.get(deposits, user_genesis_address, [])
  List.at(user_deposits, deposit_index)
end

fun set_at(list, index, value) do
  list2 = []
  i = 0

  for _ in list do
    if i == index do
      list2 = List.append(list2, value)
    else
      list2 = List.append(list2, List.at(list, i))
    end

    i = i + 1
  end

  list2
end

fun delete_at(list, index) do
  list2 = []
  i = 0

  for _ in list do
    if i != index do
      list2 = List.append(list2, List.at(list, i))
    end

    i = i + 1
  end

  list2
end
