defmodule Archethic.Contracts.Contract.Result.PublicFunctionResult.Value do
  @moduledoc false

  @enforce_keys [:value]
  defstruct [:value, logs: []]

  @type t :: %__MODULE__{
          value: any(),
          logs: list(String.t())
        }
end
