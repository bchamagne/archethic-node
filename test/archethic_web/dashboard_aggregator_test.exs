defmodule ArchethicWeb.DashboardAggregatorTest do
  use ExUnit.Case

  alias ArchethicWeb.DashboardAggregator
  alias Archethic.PubSub

  setup do
    DashboardAggregator.start_link()
    :ok
  end

  test "get_all/0 with a single bucket" do
    PubSub.notify_mining_completed(~U[2023-11-22 16:26:00Z], 8_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:26:20Z], 9_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:26:59Z], 3_000_000_000, true)

    buckets = DashboardAggregator.get_all()

    assert [~U[2023-11-22 16:26:00Z]] = Map.keys(buckets)
    assert 3 = length(Map.get(buckets, ~U[2023-11-22 16:26:00Z]))
  end

  test "get_all/0 with many buckets" do
    PubSub.notify_mining_completed(~U[2023-11-22 16:26:01Z], 8_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:27:02Z], 9_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:27:03Z], 9_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:28:03Z], 3_000_000_000, true)

    buckets = DashboardAggregator.get_all()

    assert [~U[2023-11-22 16:26:00Z], ~U[2023-11-22 16:27:00Z], ~U[2023-11-22 16:28:00Z]] =
             Map.keys(buckets)

    assert 1 = length(Map.get(buckets, ~U[2023-11-22 16:26:00Z]))
    assert 2 = length(Map.get(buckets, ~U[2023-11-22 16:27:00Z]))
    assert 1 = length(Map.get(buckets, ~U[2023-11-22 16:28:00Z]))
  end

  test "get_since/1" do
    PubSub.notify_mining_completed(~U[2023-11-22 16:26:01Z], 8_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:27:02Z], 9_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:27:03Z], 9_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:28:03Z], 3_000_000_000, true)
    PubSub.notify_mining_completed(~U[2023-11-22 16:28:04Z], 3_000_000_000, true)

    buckets = DashboardAggregator.get_since(~U[2023-11-22 16:28:00Z])

    assert [~U[2023-11-22 16:28:00Z]] = Map.keys(buckets)

    assert 2 = length(Map.get(buckets, ~U[2023-11-22 16:28:00Z]))
  end

  test "buckets are cleaned automatically" do
    now = DateTime.utc_now()

    PubSub.notify_mining_completed(DateTime.add(now, -70, :minute), 8_000_000_000, true)
    PubSub.notify_mining_completed(DateTime.add(now, -60, :minute), 8_000_000_000, true)
    PubSub.notify_mining_completed(DateTime.add(now, -59, :minute), 8_000_000_000, true)
    PubSub.notify_mining_completed(DateTime.add(now, -3, :minute), 8_000_000_000, true)
    PubSub.notify_mining_completed(DateTime.add(now, -2, :minute), 8_000_000_000, true)
    PubSub.notify_mining_completed(DateTime.add(now, -1, :minute), 8_000_000_000, true)

    send(Process.whereis(DashboardAggregator), :clean_state)

    buckets = DashboardAggregator.get_all()

    assert 4 = length(Map.keys(buckets))
  end
end
