defmodule ArchethicTest.Trigger do
  require Decimal
  alias Archethic.Crypto
  alias Archethic.Utils

  def new(seed \\ :crypto.strong_rand_bytes(10), index \\ 1) do
    if index < 1, do: throw("invalid index (must be 1 or more)")

    {genesis_public_key, _} = Crypto.derive_keypair(seed, 0)
    {public_key, _} = Crypto.derive_keypair(seed, index)
    {previous_public_key, _} = Crypto.derive_keypair(seed, index - 1)

    %{
      "address" => public_key |> Crypto.derive_address() |> Base.encode16(),
      "genesis_address" => genesis_public_key |> Crypto.derive_address() |> Base.encode16(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_unix(),
      "token_transfers" => %{},
      "uco_transfers" => %{},
      "previous_public_key" => previous_public_key |> Base.encode16()
    }
  end

  def get_previous_address(trigger) do
    trigger["previous_public_key"]
    |> Base.decode16!()
    |> Crypto.derive_address()
    |> Base.encode16()
  end

  def named_action(constants, action, args) do
    Map.put(constants, "__trigger", {action, args})
  end

  def timestamp(constants, datetime) do
    Map.put(constants, "timestamp", datetime |> DateTime.to_unix())
  end

  def token_transfer(constants, token_address, token_id, address, amount) do
    unless Decimal.is_decimal(amount), do: throw("amount must be decimal")

    transfer = %{
      "token_address" => token_address,
      "token_id" => token_id,
      "amount" => amount |> Utils.maybe_decimal_to_integer()
    }

    Map.update!(constants, "token_transfers", fn transfers_by_address ->
      Map.update(transfers_by_address, address, [transfer], &[transfer | &1])
    end)
  end
end
