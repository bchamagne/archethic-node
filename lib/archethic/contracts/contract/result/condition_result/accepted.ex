defmodule Archethic.Contracts.Contract.Result.ConditionResult.Accepted do
  @moduledoc false

  defstruct logs: []

  @type t :: %__MODULE__{
          logs: list(String.t())
        }
end
