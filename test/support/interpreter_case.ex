defmodule InterpreterCase do
  @moduledoc """
  We test contract via the interpreter directly
  We do not want to test the Contracts domain because it requires too much mocks
  """
  use ExUnit.CaseTemplate

  import Mox

  alias Archethic.Contracts.Interpreter
  alias Archethic.Contracts.Interpreter.ActionInterpreter
  alias Archethic.Contracts.Interpreter.ConditionValidator
  alias Archethic.Contracts.Interpreter.Library.ErrorContractThrow
  alias Archethic.Contracts.Conditions
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  using do
    quote do
      setup do
        # load the mocks
        unless :code.is_loaded(MockChain) do
          Mox.defmock(MockChain, for: Archethic.Contracts.Interpreter.Library.Common.Chain)
        end

        Application.put_env(
          :archethic,
          Archethic.Contracts.Interpreter.Library.Common.Chain,
          MockChain
        )

        Application.put_env(:archethic, MockChain, enabled: false)

        # unload the mocks
        on_exit(fn ->
          Application.put_env(
            :archethic,
            Archethic.Contracts.Interpreter.Library.Common.Chain,
            Archethic.Contracts.Interpreter.Library.Common.ChainImpl
          )
        end)

        :ok
      end

      import Mox
      alias Archethic.Crypto
      alias ArchethicTest.Trigger
    end
  end

  def trigger_contract(_, _, opts \\ [])
  def trigger_contract({:throw, code}, _, _), do: {:throw, code}

  def trigger_contract(contract, trigger, opts) do
    unless Map.has_key?(trigger, "__trigger"), do: throw("missing action to call")

    {{action_name, action_args}, trigger_constants} = Map.pop(trigger, "__trigger")
    trigger_type = {:transaction, action_name, map_size(action_args)}

    %Conditions{subjects: condition_ast} = Map.get(contract.conditions, trigger_type)

    constants =
      Map.merge(action_args, %{
        "transaction" => trigger_constants,
        "contract" => %{
          "balance" => %{
            "uco" => contract.uco_balance
          }
        },
        :time_now => trigger_constants["timestamp"],
        :functions => contract.functions,
        :encrypted_seed => Keyword.get(opts, :seed, :crypto.strong_rand_bytes(10)),
        :state => contract.state
      })

    # Define some default mock behaviour
    MockChain
    |> stub(
      :get_genesis_address,
      fn
        address when is_binary(address) -> throw("missing mock Chain.get_genesis_address/1")
        constants when is_map(constants) -> constants["genesis_address"]
      end
    )
    |> stub(
      :get_previous_address,
      &Archethic.Contracts.Interpreter.Library.Common.ChainImpl.get_previous_address/1
    )

    case ConditionValidator.execute_condition(condition_ast, constants) do
      {:error, failure} ->
        {:condition_failed, failure}

      {:ok, _} ->
        %{ast: action_ast} = Map.get(contract.triggers, trigger_type)

        {next_tx, next_state} =
          ActionInterpreter.execute(action_ast, constants, %Transaction{
            data: %TransactionData{code: ""}
          })

        case next_tx do
          nil ->
            contract
            |> Map.put(:state, next_state)

          _ ->
            # todo: many things
            contract
            |> Map.put(:state, next_state)
        end
    end
  rescue
    e in ErrorContractThrow ->
      {:throw, e.code}
  end

  def create_contract(code, constants) do
    code =
      Enum.reduce(constants, code, fn {placeholder, type, value}, acc ->
        String.replace(
          acc,
          placeholder,
          case type do
            :date -> value |> DateTime.to_unix() |> Integer.to_string()
            :string -> "\"#{value}\""
          end
        )
      end)

    {:ok, contract} = Interpreter.parse(code)
    contract
  end

  def prepare_contract(contract, state, uco_balance \\ 0) do
    contract
    |> Map.put(:state, state)
    |> Map.put(:uco_balance, uco_balance)
  end
end
