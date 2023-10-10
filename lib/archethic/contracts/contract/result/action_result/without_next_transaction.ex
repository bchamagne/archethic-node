defmodule Archethic.Contracts.Contract.Result.ActionResult.WithoutNextTransaction do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @enforce_keys [:next_state_utxo]
  defstruct [:next_state_utxo, logs: []]

  @type t :: %__MODULE__{
          next_state_utxo: nil | UnspentOutput.t(),
          logs: list(String.t())
        }
end
