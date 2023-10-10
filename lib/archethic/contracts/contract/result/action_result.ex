defmodule Archethic.Contracts.Contract.Result.ActionResult do
  @moduledoc false

  alias __MODULE__.WithNextTransaction
  alias __MODULE__.WithoutNextTransaction

  @type t() :: WithNextTransaction.t() | WithoutNextTransaction.t()
end
