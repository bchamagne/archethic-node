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
  alias Archethic.Contracts.Interpreter.FunctionInterpreter
  alias Archethic.Contracts.Interpreter.Library.ErrorContractThrow
  alias Archethic.Contracts.Conditions
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils

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
        :state => contract.state
      })

    case ConditionValidator.execute_condition(condition_ast, constants) do
      {:error, failure, _logs} ->
        if Keyword.get(opts, :ignore_condition_failed, false) do
          contract
        else
          {:condition_failed, failure}
        end

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
            |> Map.update!(:uco_balance, fn previous_balance ->
              uco_transfers_amount =
                next_tx.data.ledger.uco.transfers
                |> Enum.map(
                  &(&1.amount
                    |> Utils.bigint_to_decimal()
                    |> Utils.maybe_decimal_to_integer())
                )
                |> Enum.reduce(0, &Decimal.add/2)

              Decimal.sub(previous_balance, uco_transfers_amount)
            end)
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
            :int -> value |> Integer.to_string()
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

  def call_function(contract, function_name, args_values, time_now \\ DateTime.utc_now()) do
    %{functions: functions} = contract
    %{ast: ast, args: args_names} = Map.get(functions, {function_name, length(args_values)})

    constants = %{
      "contract" => %{
        "balance" => %{
          "uco" => contract.uco_balance
        }
      },
      :time_now => DateTime.to_unix(time_now),
      :state => contract.state
    }

    FunctionInterpreter.execute(ast, constants, args_names, args_values)
  end
end
