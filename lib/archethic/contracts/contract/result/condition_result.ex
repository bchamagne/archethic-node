defmodule Archethic.Contracts.Contract.Result.ConditionResult do
  @moduledoc false

  alias __MODULE__.Accepted
  alias __MODULE__.Rejected

  @type t() :: Accepted.t() | Rejected.t()
end
