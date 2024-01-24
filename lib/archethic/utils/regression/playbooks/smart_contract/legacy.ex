defmodule Archethic.Utils.Regression.Playbook.SmartContract.Legacy do
  @moduledoc """
  This contract is triggered every minutes(prod) or every seconds(dev)
  It should send 0.1 UCO to the recipient chain every tick
  """

  alias Archethic.Contracts
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils
  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract

  require Logger

  def play(storage_nonce_pubkey, endpoint) do
    trigger_seed = SmartContract.random_seed()
    contract_seed = SmartContract.random_seed()
    recipient_address = SmartContract.random_address()
    amount_to_send = Utils.to_bigint(0.1)
    ticks_count = 4

    Api.send_funds_to_seeds(
      %{
        contract_seed => 10,
        trigger_seed => 10
      },
      endpoint
    )

    sleep_ms = 200 + ticks_count * Contracts.minimum_trigger_interval()

    contract_address =
      SmartContract.deploy(
        contract_seed,
        %TransactionData{
          code:
            contract_code(recipient_address, amount_to_send)
            |> TransactionData.compress_code()
        },
        storage_nonce_pubkey,
        endpoint
      )

    # wait some ticks
    Logger.debug("Sleeping for #{ticks_count} ticks (#{div(sleep_ms, 1000)} seconds)")
    Process.sleep(sleep_ms)

    balance = Api.get_uco_balance(recipient_address, endpoint)

    SmartContract.trigger(trigger_seed, contract_address, endpoint, content: "CLOSE_CONTRACT")

    # there's a slight change there will be 1 more tick due to playbook code
    if balance in [ticks_count * amount_to_send, (1 + ticks_count) * amount_to_send] do
      Logger.info(
        "Smart contract 'legacy' received #{Utils.from_bigint(balance)} UCOs after #{ticks_count} ticks"
      )
    else
      Logger.error(
        "Smart contract 'legacy' received #{Utils.from_bigint(balance)} UCOs after #{ticks_count} ticks"
      )
    end
  end

  defp contract_code(address, amount) do
    ~s"""
    # GENERATED BY PLAYBOOK

    condition inherit: [
      code: true,
      uco_transfers: true
    ]

    condition transaction: []
    actions triggered_by: transaction do
      if transaction.content == "CLOSE_CONTRACT" do
        set_code("condition inherit: []")
      end
    end

    actions triggered_by: interval, at: "* * * * * *" do
      set_type transfer
      add_uco_transfer to: "#{Base.encode16(address)}", amount: #{amount}
    end
    """
  end
end
