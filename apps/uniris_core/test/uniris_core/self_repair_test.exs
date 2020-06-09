defmodule UnirisCore.SelfRepairTest do
  use UnirisCoreCase, async: false

  alias UnirisCore.SelfRepair
  alias UnirisCore.Transaction
  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.BeaconSlot
  alias UnirisCore.BeaconSlot.TransactionInfo
  alias UnirisCore.Crypto

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    start_supervised!(UnirisCore.Storage.Cache)
    start_supervised!({UnirisCore.BeaconSlotTimer, slot_interval: 10_000})
    pid = start_supervised!({SelfRepair, interval: 10_000})
    {:ok, %{pid: pid}}
  end

  test "start_sync/2 starts the repair mechanism and download missing transactions" do
    me = self()

    MockStorage
    |> stub(:write_transaction_chain, fn chain ->
      send(me, chain)
      :ok
    end)

    MockNodeClient
    |> stub(:send_message, fn _, _, msg ->
      case msg do
        {:get_beacon_slots, _slots} ->
          [
            %BeaconSlot{
              transactions: [
                %TransactionInfo{
                  address: "fake_address",
                  type: :transfer,
                  timestamp: DateTime.utc_now()
                },
                %TransactionInfo{
                  address: "another_address",
                  type: :node,
                  timestamp: DateTime.utc_now()
                }
              ]
            }
          ]

        {:get_transaction, address} ->
          {:ok, %Transaction{
            address: "another_address",
            timestamp: DateTime.utc_now(),
            type: :node,
            data: %{},
            previous_public_key: "",
            previous_signature: "",
            origin_signature: ""
          }}

        {:get_transaction_chain, address} ->
          case address do
            "fake_address" ->
              {:ok,
              [
                %Transaction{
                  address: "fake_address",
                  timestamp: DateTime.utc_now(),
                  type: :transfer,
                  data: %{},
                  previous_public_key: "",
                  previous_signature: "",
                  origin_signature: ""
                }
              ]}
            "another_address" ->
              {:ok,
                [%Transaction{
                  address: "another_address",
                  timestamp: DateTime.utc_now(),
                  type: :node,
                  data: %{},
                  previous_public_key: "",
                  previous_signature: "",
                  origin_signature: ""
                }]}
          end
      end
    end)

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: Crypto.node_public_key(0),
      first_public_key: Crypto.node_public_key(0),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now() |> DateTime.add(-60),
      enrollment_date: DateTime.utc_now() |> DateTime.add(-60)
    })

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      last_public_key: :crypto.strong_rand_bytes(32),
      first_public_key: :crypto.strong_rand_bytes(32),
      network_patch: "AAA",
      geo_patch: "AAA",
      ready?: true,
      available?: true,
      enrollment_date: DateTime.utc_now() |> DateTime.add(-60)
    })

    SelfRepair.start_sync("AAA")
    Process.sleep(500)

    assert_received [%Transaction{type: :node}], 500
    assert_received [%Transaction{type: :transfer}], 500
  end
end
