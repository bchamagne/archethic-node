defmodule Archethic.TransactionChain.TransactionData.TokenLedger.Transfer do
  @moduledoc """
  Represents a Token ledger transfer
  """
  defstruct [:to, :amount, :token, conditions: [], token_id: 0]

  alias Archethic.Utils
  # impl token_id

  @typedoc """
  Transfer is composed from:
  - token: Token address
  - to: receiver address of the asset
  - amount: specify the number of Token to transfer to the recipients (in the smallest unit 10^-8)
  - conditions: specify to which address the Token can be used
  - token_id: To uniquely identify a token from a set a of token(token collection)
  """
  @type t :: %__MODULE__{
          token: binary(),
          to: binary(),
          amount: non_neg_integer(),
          conditions: list(binary()),
          token_id: non_neg_integer()
        }

  @doc """
  Serialize Token transfer into binary format

  ## Examples

      iex> %Transfer{
      ...>   token:  <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>    197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>   to: <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...>    85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
      ...>   amount: 1_050_000_000,
      ...>   token_id: 0
      ...> }
      ...> |> Transfer.serialize()
      <<
        # Token address
        0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175,
        # Transfer recipient
        0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
        85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14,
        # Transfer amount
        0, 0, 0, 0, 62, 149, 186, 128,
        # Token ID
        0
      >>
  """
  def serialize(%__MODULE__{token: token, to: to, amount: amount, token_id: token_id}) do
    <<token::binary, to::binary, amount::64, token_id::8>>
  end

  @doc """
  Deserialize an encoded Token transfer

  ## Examples

      iex> <<
      ...> 0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...> 197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175,
      ...> 0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...> 85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14,
      ...> 0, 0, 0, 0, 62, 149, 186, 128, 0>>
      ...> |> Transfer.deserialize()
      {
        %Transfer{
          token: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
            197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
          to: <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
            85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
          amount: 1_050_000_000,
          token_id: 0
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(data) do
    {token_address, rest} = Utils.deserialize_address(data)
    {recipient_address, <<amount::64, rest::bitstring>>} = Utils.deserialize_address(rest)
    <<token_id::8, rest::bitstring>> = rest

    {
      %__MODULE__{
        token: token_address,
        to: recipient_address,
        amount: amount,
        token_id: token_id
      },
      rest
    }
  end

  @doc """
  Forms Token.Transfer Struct from a map

  ## Examples

      iex> %{
      ...>  token:  <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>    197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
      ...>  to: <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
      ...>    85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
      ...>  amount: 1_050_000_000,
      ...>  token_id: 0
      ...> }
      ...> |> Transfer.from_map()
      %Transfer{
         token: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
           197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
         to: <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
           85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
         amount: 1_050_000_000,
         token_id: 0
      }
  """
  @spec from_map(map()) :: t()
  def from_map(transfer = %{}) do
    %__MODULE__{
      token: Map.get(transfer, :token),
      to: Map.get(transfer, :to),
      amount: Map.get(transfer, :amount),
      token_id: Map.get(transfer, :token_id)
    }
  end

  @doc """
    ## Examples

        iex> %Transfer{
        ...>   token:  <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
        ...>    197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
        ...>   to: <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
        ...>    85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
        ...>   amount: 1_050_000_000,
        ...>   token_id: 0
        ...> }
        ...> |> Transfer.to_map()
        %{
          token: <<0, 0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
            197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
          to: <<0, 0, 104, 134, 142, 120, 40, 59, 99, 108, 63, 166, 143, 250, 93, 186, 216, 117,
            85, 106, 43, 26, 120, 35, 44, 137, 243, 184, 160, 251, 223, 0, 93, 14>>,
          amount: 1_050_000_000,
          token_id: 0
        }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{token: token, to: to, amount: amount, token_id: token_id}) do
    %{
      token: token,
      to: to,
      amount: amount,
      token_id: token_id
    }
  end
end