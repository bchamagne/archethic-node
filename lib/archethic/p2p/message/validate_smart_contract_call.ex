defmodule Archethic.P2P.Message.ValidateSmartContractCall do
  @moduledoc """
  Represents a message to validate a smart contract call
  """

  @enforce_keys [:recipient, :transaction, :inputs_before]
  defstruct [:recipient, :transaction, :inputs_before]

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.Mining
  alias Archethic.OracleChain
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData.Recipient

  @type t :: %__MODULE__{
          recipient: Recipient.t(),
          transaction: Transaction.t(),
          inputs_before: DateTime.t()
        }

  @doc """
  Serialize message into binary
  """
  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        recipient: recipient,
        transaction: tx = %Transaction{},
        inputs_before: time = %DateTime{}
      }) do
    tx_version = Transaction.version()
    recipient_bin = Recipient.serialize(recipient, tx_version)

    <<recipient_bin::binary, Transaction.serialize(tx)::bitstring,
      DateTime.to_unix(time, :millisecond)::64>>
  end

  @doc """
  Deserialize the encoded message
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(data) when is_bitstring(data) do
    tx_version = Transaction.version()
    {recipient, rest} = Recipient.deserialize(data, tx_version)
    {tx, <<timestamp::64, rest::bitstring>>} = Transaction.deserialize(rest)

    {
      %__MODULE__{
        recipient: recipient,
        transaction: tx,
        inputs_before: DateTime.from_unix!(timestamp, :millisecond)
      },
      rest
    }
  end

  @spec process(t(), Crypto.key()) :: SmartContractCallValidation.t()
  def process(
        %__MODULE__{
          recipient: recipient = %Recipient{address: recipient_address},
          transaction: transaction = %Transaction{},
          inputs_before: datetime
        },
        _
      ) do
    # During the validation of a call there is no validation_stamp yet.
    # We need one because the contract might want to access transaction.timestamp
    # which is bound to validation_stamp.timestamp
    transaction = %Transaction{
      transaction
      | validation_stamp: ValidationStamp.generate_dummy(timestamp: datetime)
    }

    with {:ok, contract_tx} <- TransactionChain.get_transaction(recipient_address),
         {:ok, contract} <- Contracts.from_transaction(contract_tx),
         trigger when not is_nil(trigger) <- Contract.get_trigger_for_recipient(recipient),
         maybe_state_utxo <- Contracts.State.get_utxo_from_transaction(contract_tx),
         true <-
           Contracts.valid_condition?(trigger, contract, transaction, recipient, datetime),
         execution_result <-
           Contracts.execute_trigger(trigger, contract, transaction, recipient, maybe_state_utxo,
             time_now: datetime
           ) do
      %SmartContractCallValidation{
        valid?: Contract.Result.valid?(execution_result),
        fee: calculate_fee(execution_result, contract, datetime)
      }
    else
      _ ->
        %SmartContractCallValidation{valid?: false, fee: 0}
    end
  end

  defp calculate_fee(
         %Contract.Result.ActionResult.WithNextTransaction{
           next_tx: next_tx,
           next_state_utxo: maybe_state_utxo
         },
         contract = %Contract{transaction: %Transaction{address: contract_address}},
         timestamp
       ) do
    index = TransactionChain.get_size(contract_address)

    case Contract.sign_next_transaction(contract, next_tx, index) do
      {:ok, tx} ->
        previous_usd_price =
          timestamp
          |> OracleChain.get_last_scheduling_date()
          |> OracleChain.get_uco_price()
          |> Keyword.fetch!(:usd)

        # Here we use a nil contract_context as we return the fees the user has to pay for the contract
        Mining.get_transaction_fee(
          tx,
          nil,
          previous_usd_price,
          timestamp,
          Mining.protocol_version(),
          maybe_state_utxo
        )

      _ ->
        0
    end
  end

  defp calculate_fee(_, _, _), do: 0
end
