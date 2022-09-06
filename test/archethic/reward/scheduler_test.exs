defmodule Archethic.Reward.SchedulerTest do
  use ArchethicCase, async: false

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.StartMining

  alias Archethic.Reward.Scheduler

  alias Archethic.TransactionChain.Transaction

  import Mox

  test "should initiate the reward scheduler and trigger mint reward" do
    MockDB
    |> stub(:get_latest_burned_fees, fn -> 0 end)

    {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")

    assert {:idle, %{interval: "*/1 * * * * *"}} = :sys.get_state(pid)

    send(pid, :node_up)

    assert {:idle, %{interval: "*/1 * * * * *"}} = :sys.get_state(pid)

    send(
      pid,
      {:node_update,
       %Node{
         authorized?: true,
         available?: true,
         first_public_key: Crypto.first_node_public_key()
       }}
    )

    assert {:scheduled, %{timer: _}} = :sys.get_state(pid)

    :erlang.trace(pid, true, [:receive])

    assert_receive {:trace, ^pid, :receive, :mint_rewards}, 3_000
  end

  describe "scheduler" do
    setup do
      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.last_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        average_availability: 1.0
      })
    end

    test "should send mint transaction when burning fees > 0 and node reward transaction" do
      MockDB
      |> stub(:get_latest_burned_fees, fn -> 15_000 end)

      me = self()

      assert {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")
      send(pid, :node_up)

      MockClient
      |> stub(:send_message, fn
        _, %StartMining{transaction: %Transaction{address: address, type: :mint_rewards}}, _ ->
          send(pid, {:new_transaction, address, :mint_rewards, DateTime.utc_now()})
          send(me, :mint_rewards)

        _, %StartMining{transaction: %{type: :node_rewards}}, _ ->
          send(me, :node_rewards)
      end)

      assert_receive :mint_rewards, 1_500
      assert_receive :node_rewards, 1_500
    end

    test "should not send transaction when burning fees = 0 and should send node rewards" do
      MockDB
      |> stub(:get_latest_burned_fees, fn -> 0 end)

      me = self()

      MockClient
      |> stub(:send_message, fn _, %StartMining{transaction: %{type: type}}, _ ->
        send(me, type)
      end)

      assert {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")
      send(pid, :node_up)

      refute_receive :mint_rewards, 1_200
      assert_receive :node_rewards, 1_500
    end
  end

  describe "Scheduler Behavior During Start" do
    test "should be idle(state with args) when node has not done Bootstrapping" do
      :persistent_term.put(:archethic_up, nil)

      {:ok, pid} = Scheduler.start_link(interval: "*/1 * * * * *")

      assert {:idle, %{interval: "*/1 * * * * *"}} = :sys.get_state(pid)
    end

    test "should wait for node :up message to start the scheduler, when node is not authorized and available" do
      :persistent_term.put(:archethic_up, nil)

      {:ok, pid} = Scheduler.start_link(interval: "*/2 * * * * *")

      assert {:idle, %{interval: "*/2 * * * * *"}} = :sys.get_state(pid)

      send(pid, :node_up)

      assert {:idle, %{interval: "*/2 * * * * *"}} = :sys.get_state(pid)
    end

    test "should wait for node :up message to start the scheduler, when node is authorized and available" do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      {:ok, pid} = Scheduler.start_link(interval: "*/3 * * * * *")

      assert {:idle, %{interval: "*/3 * * * * *"}} = :sys.get_state(pid)
      send(pid, :node_up)

      assert {:scheduled,
              %{
                interval: "*/3 * * * * *",
                index: _,
                next_address: _
              }} = :sys.get_state(pid)
    end

    test "Should use persistent_term :archethic_up when a Scheduler crashes, when a node is not authorized and available" do
      :persistent_term.put(:archethic_up, :up)

      {:ok, pid} = Scheduler.start_link(interval: "*/4 * * * * *")

      assert {:idle,
              %{
                interval: "*/4 * * * * *"
              }} = :sys.get_state(pid)

      :persistent_term.put(:archethic_up, nil)
    end

    test "Should use persistent_term :archethic_up when a Scheduler crashes, when a node is authorized and available" do
      :persistent_term.put(:archethic_up, :up)

      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3002,
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.first_node_public_key(),
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        geo_patch: "AAA",
        available?: true
      })

      {:ok, pid} = Scheduler.start_link(interval: "*/5 * * * * *")

      assert {:scheduled,
              %{
                interval: "*/5 * * * * *",
                index: _,
                next_address: _
              }} = :sys.get_state(pid)

      :persistent_term.put(:archethic_up, nil)
    end
  end
end