@version 1

condition triggered_by: transaction, on: deposit(end_timestamp) do
  now = Time.now()

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

  if end_timestamp != 0 && end_timestamp < now do
    throw(message: "deposit's end cannot be in the past", code: 1006)
  end

  if get_user_transfer_amount() < 0.00000143 do
    throw(message: "deposit's minimum amount is 0.00000143", code: 1002)
  end

  true
end

actions triggered_by: transaction, on: deposit(end_timestamp) do
  now = Time.now()
  day = @SECONDS_IN_DAY
  year = 365 * day

  if end_timestamp == "max" do
    end_timestamp = @END_DATE
  end

  if end_timestamp == "flex" do
    end_timestamp = 0
  end

  transfer_amount = get_user_transfer_amount()
  user_genesis_address = get_user_genesis()
  id = String.from_number(now)

  # log(
  #   label: "deposit",
  #   end_timestamp: (end_timestamp - @START_DATE) / 86400,
  #   user: user_genesis_address
  # )

  # split the deposit in many sub-deposits
  # 1 for each state change (level or year)
  sub_deposits = []

  years_periods = get_years_periods(now, @END_DATE)

  if end_timestamp == 0 do
    # flexible
    for year_period in years_periods do
      sub_deposits =
        List.append(sub_deposits,
          user: user_genesis_address,
          id: id,
          level: 0,
          year: year_period.year,
          tokens: transfer_amount,
          rewards: 0,
          from: year_period.from,
          from_human: (year_period.from - @START_DATE) / 86400,
          to: year_period.to,
          to_human: (year_period.to - @START_DATE) / 86400
        )
    end
  else
    levels = all_levels()
    levels_froms = Map.new()

    for level in levels do
      levels_froms = Map.set(levels_froms, level, now + level_to_duration(level))
    end

    max_level = deposit_max_level(end_timestamp, levels_froms)

    # construct the periods from right to left
    cursor = @END_DATE

    for year_period in reverse(years_periods) do
      for level in 0..max_level do
        level_to = cursor
        level_from = nil

        if level == 0 do
          level_from = end_timestamp
        else
          level_from = end_timestamp - level_to_duration(level)
        end

        # log(
        #   year_period: year_period,
        #   level: level,
        #   level_from: (level_from - @START_DATE) / 86400,
        #   level_to: (level_to - @START_DATE) / 86400
        # )

        if level_from < year_period.to && level_to > year_period.from do
          bounded_from = year_period.from

          if bounded_from < level_from do
            bounded_from = level_from
          end

          if bounded_from < now do
            bounded_from = now
          end

          bounded_to = year_period.to

          if bounded_to > level_to do
            bounded_to = level_to
          end

          sub_deposits =
            List.prepend(sub_deposits,
              user: user_genesis_address,
              id: id,
              level: level,
              year: year_period.year,
              tokens: transfer_amount,
              rewards: 0,
              from: bounded_from,
              from_human: (bounded_from - @START_DATE) / 86400,
              to: bounded_to,
              to_human: (bounded_to - @START_DATE) / 86400
            )

          cursor = bounded_from
        end
      end
    end
  end

  # TODO: clean old?
  # TODO: merge flexible
  previous_sub_deposits = State.get("sub_deposits", [])
  sub_deposits = previous_sub_deposits ++ sub_deposits
  sub_deposits = List.sort_by(sub_deposits, "from")
  State.set("sub_deposits", sub_deposits)
end

export fun(get_user_infos(user_genesis_address)) do
  now = Time.now()
  day = @SECONDS_IN_DAY
  year = 365 * day

  user_genesis_address = String.to_hex(user_genesis_address)

  sub_deposits = State.get("sub_deposits", [])
  user_sub_deposits_by_id = Map.new()

  for sub_deposit in sub_deposits do
    if sub_deposit.user == user_genesis_address do
      previous_sub_deposits_for_id = Map.get(user_sub_deposits_by_id, sub_deposit.id, [])
      sub_deposits_for_id = List.append(previous_sub_deposits_for_id, sub_deposit)

      user_sub_deposits_by_id =
        Map.set(user_sub_deposits_by_id, sub_deposit.id, sub_deposits_for_id)
    end
  end

  reply = []

  # sub_deposits to deposits
  for id in Map.keys(user_sub_deposits_by_id) do
    sub_deposits_for_id = Map.get(user_sub_deposits_by_id, id)
    max_level = 0
    min_from = nil
    max_to = nil
    tokens = nil
    rewards = 0

    for sub_deposit in sub_deposits_for_id do
      tokens = sub_deposit.tokens
      rewards = rewards + sub_deposit.rewards

      if sub_deposit.from != nil && (min_from == nil || min_from > sub_deposit.from) do
        min_from = sub_deposit.from
      end

      if sub_deposit.to != nil && sub_deposit.level != 0 &&
           (max_to == nil || max_to < sub_deposit.to) do
        max_to = sub_deposit.to
      end

      if sub_deposit.to >= now && max_level < sub_deposit.level do
        max_level = sub_deposit.level
      end
    end

    to_human = nil

    if max_to != nil do
      to_human = (max_to - @START_DATE) / 86400
    end

    reply =
      List.append(reply,
        id: id,
        tokens: tokens,
        rewards: rewards,
        level: max_level,
        from: min_from,
        from_human: (min_from - @START_DATE) / 86400,
        to: max_to,
        to_human: to_human
      )
  end

  reply
end

fun get_years_periods(from, to) do
  day = @SECONDS_IN_DAY
  year = 365 * day

  years = [
    [year: 1, from: @START_DATE, to: @START_DATE + 1 * year - 1],
    [year: 2, from: @START_DATE + 1 * year, to: @START_DATE + 2 * year - 1],
    [year: 3, from: @START_DATE + 2 * year, to: @START_DATE + 3 * year - 1],
    [year: 4, from: @START_DATE + 3 * year, to: @START_DATE + 4 * year - 1]
  ]

  periods = []

  for year in years do
    if from < year.to && to > year.from do
      bounded_from = year.from

      if bounded_from < from do
        bounded_from = from
      end

      bounded_to = year.to

      if bounded_to > to do
        bounded_to = to
      end

      periods =
        List.append(periods,
          year: year.year,
          from: bounded_from,
          from_human: (bounded_from - @START_DATE) / 86400,
          to: bounded_to,
          to_human: (bounded_to - @START_DATE) / 86400
        )
    end
  end

  periods
end

fun reverse(list) do
  reversed = []

  for item in list do
    reversed = List.prepend(reversed, item)
  end

  reversed
end

fun deposit_max_level(end_timestamp, levels_froms) do
  deposit_level = nil

  for level in Map.keys(levels_froms) do
    level_from = Map.get(levels_froms, level)

    if deposit_level == nil && end_timestamp <= level_from do
      deposit_level = level
    end
  end

  if deposit_level == nil do
    deposit_level = 7
  end

  deposit_level
end

fun all_levels() do
  0..7
end

fun level_to_duration(level) do
  day = @SECONDS_IN_DAY

  duration = nil

  if level == 0 do
    duration = 0
  end

  if level == 1 do
    duration = 7 * day
  end

  if level == 2 do
    duration = 30 * day
  end

  if level == 3 do
    duration = 90 * day
  end

  if level == 4 do
    duration = 180 * day
  end

  if level == 5 do
    duration = 365 * day
  end

  if level == 6 do
    duration = 730 * day
  end

  if level == 7 do
    duration = 1095 * day
  end

  duration
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

fun get_user_genesis() do
  previous_address = Chain.get_previous_address(transaction)
  Chain.get_genesis_address(previous_address)
end
