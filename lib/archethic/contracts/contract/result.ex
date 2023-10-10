defmodule Archethic.Contracts.Contract.Result do
  @moduledoc false

  alias __MODULE__.Error
  alias __MODULE__.ActionResult
  alias __MODULE__.ConditionResult
  alias __MODULE__.PublicFunctionResult

  @typedoc """
  This type represent the result of a Smart Contract's execution
  It can be either the result of an action/a condition/a public function.
  """
  @type t() :: Error.t() | ActionResult.t() | ConditionResult.t() | PublicFunctionResult.t()

  @doc """
  Is the result considered as valid?
  """
  @spec valid?(t()) :: boolean()
  def valid?(%Error{}), do: false
  def valid?(_), do: true
end
