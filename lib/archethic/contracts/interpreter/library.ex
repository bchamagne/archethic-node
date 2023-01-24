defmodule Archethic.Contracts.Interpreter.Library do
  @moduledoc false

  alias Archethic.Election

  alias Archethic.TransactionChain
  alias Archethic.Contracts.ContractConstants
  alias Archethic.Contracts.Interpreter.Utils
  alias Archethic.Contracts.TransactionLookup

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetFirstPublicKey
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.FirstPublicKey

  @doc """
  Convert a string to an integer

  ## Examples

    iex> Library.int("12345")
    12345
  """
  @spec int(String.t()) :: integer()
  def int(text) do
    String.to_integer(text)
  end

  @doc """
  Convert a string to a float
  ## Examples

    iex> Library.float("12345.1")
    12345.1
  """
  @spec float(String.t()) :: float()
  def float(text) do
    String.to_float(text)
  end

  @doc """
  Convert a number (float or integer) to a string

  ## Examples

    iex> Library.string(12345)
    "12345"
  """
  @spec string(float() | integer()) :: String.t()
  def string(num) when is_integer(num) do
    Integer.to_string(num)
  end

  def string(num) when is_float(num) do
    Float.to_string(num)
  end

  @doc """
  Match a regex expression

  ## Examples

      iex> Library.regex_match?("abcdef024894", "^[a-z0-9]+$")
      true

      iex> Library.regex_match?("sfdl#@", "^[a-z0-9]+$")
      false
  """
  @spec regex_match?(binary(), binary()) :: boolean()
  def regex_match?(text, pattern) when is_binary(text) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, pattern} ->
        Regex.match?(pattern, text)

      _ ->
        false
    end
  end

  @doc """
  Extract data from a regex expression

  ## Examples

      iex> Library.regex_extract("abcdef024894", "^[a-z0-9]+$")
      "abcdef024894"

      iex> Library.regex_extract("sfdl#@", "^[a-z0-9]+$")
      ""

      iex> Library.regex_extract("sfdl#@", "[a-z0-9]+")
      "sfdl"
  """
  @spec regex_extract(binary(), binary()) :: binary()
  def regex_extract(text, pattern) when is_binary(text) and is_binary(pattern) do
    with {:ok, pattern} <- Regex.compile(pattern),
         [res] <- Regex.run(pattern, text) do
      res
    else
      _ ->
        ""
    end
  end

  @doc """
  Extract data from string using capture groups

  ## Examples

      iex> Library.regex_scan("foo", "bar")
      []

      iex> Library.regex_scan("toto,123\\ntutu,456\\n", "toto,([0-9]+)")
      ["123"]

      iex> Library.regex_scan("toto,123\\ntutu,456\\n", "t.t.,([0-9]+)")
      ["123", "456"]
  """
  @spec regex_scan(binary(), binary()) :: list(binary())
  def regex_scan(text, pattern) when is_binary(text) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, pattern} ->
        Regex.scan(pattern, text, capture: :all_but_first)
        |> Enum.map(fn
          [item] -> item
          other -> other
        end)

      _ ->
        []
    end
  end

  @doc """
  Return the text where all matches of pattern are replaced by the replacement.

  ## Examples

    iex> Library.regex_replace("toto,123\\ntutu,456\\n", "toto,123\\n", "toto,789\\n")
    "toto,789\\ntutu,456\\n"

    iex> Library.regex_replace("toto,123\\ntutu,456\\n", "toto,123\\n", "")
    "tutu,456\\n"

  """
  @spec regex_replace(binary(), binary(), binary()) :: binary()
  def regex_replace(text, pattern, replacement) do
    case Regex.compile(pattern) do
      {:ok, pattern} ->
        Regex.replace(pattern, text, replacement)

      _ ->
        text
    end
  end

  @doc ~S"""
  Extract data from a JSON path expression

  ## Examples

      iex> Library.json_path_extract("{ \"firstName\": \"John\", \"lastName\": \"Doe\"}", "$.firstName")
      "John"

      iex> Library.json_path_extract("{ \"firstName\": \"John\", \"lastName\": \"Doe\"}", "$.book")
      ""

  """
  @spec json_path_extract(binary(), binary()) :: binary()
  def json_path_extract(text, path) when is_binary(text) and is_binary(path) do
    res =
      text
      |> Jason.decode!()
      |> ExJSONPath.eval(path)

    case res do
      {:ok, [res | _]} ->
        res

      _ ->
        ""
    end
  end

  @doc ~S"""
  Match a json path expression

  ## Examples

       iex> Library.json_path_match?("{\"1622541930\":{\"uco\":{\"eur\":0.176922,\"usd\":0.21642}}}", "$.*.uco.usd")
       true
  """
  @spec json_path_match?(binary(), binary()) :: boolean()
  def json_path_match?(text, path) when is_binary(text) and is_binary(path) do
    case json_path_extract(text, path) do
      "" ->
        false

      _ ->
        true
    end
  end

  @doc """
  Hash a content

  ## Examples

      iex> Library.hash("hello")
      "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"
  """
  @spec hash(binary()) :: binary()
  def hash(content) when is_binary(content) do
    :crypto.hash(:sha256, Utils.maybe_decode_hex(content)) |> Base.encode16()
  end

  @doc """
  Determines if the value is inside the list

  ## Examples

      iex> Library.in?("hello", ["hi", "hello"])
      true

      iex> Library.in?(["a", "b"], ["a", "c", "b"])
      true
  """
  @spec in?(any(), list()) :: boolean()
  def in?(val, list) when is_list(val) and is_list(list) do
    Enum.all?(val, &(&1 in list))
  end

  def in?(val, list) when is_list(list) do
    val in list
  end

  @doc """
  Invokes fun for each element in the enumerable with the accumulator.
  """
  @spec reduce(Enumerable.t(), any(), (any(), any() -> any())) :: any()
  def reduce(list, acc, func) do
    Enum.reduce(list, acc, func)
  end

  @doc """
  Determines the size  of the input

  ## Examples

      iex> Library.size("hello")
      5

      iex> Library.size([1, 2, 3])
      3

      iex> Library.size(%{"a" => 1, "b" => 2})
      2
  """
  @spec size(binary() | list()) :: non_neg_integer()
  def size(binary) when is_binary(binary), do: binary |> Utils.maybe_decode_hex() |> byte_size()
  def size(list) when is_list(list), do: length(list)
  def size(map) when is_map(map), do: map_size(map)

  @doc """
  Append item to the list (slow)

  ## Examples

    iex> Library.append([], 1)
    [1]

    iex> Library.append([1], [2])
    [1, [2]]
  """
  @spec append(list(any()), any()) :: list(any())
  def append(list, item) do
    list ++ [item]
  end

  @doc """

  Prepend item to the list (fast)

  ## Examples
    iex> Library.prepend([], 1)
    [1]

    iex> Library.prepend([1], [2])
    [[2], 1]
  """
  @spec prepend(list(any()), any()) :: list(any())
  def prepend(list, item) do
    [item | list]
  end

  @doc """
  Concat both list

  ## Examples

    iex> Library.concat([], [])
    []

    iex> Library.concat("", "")
    ""

    iex> Library.concat("hello", " world")
    "hello world"

    iex> Library.concat([1,2], [3,4])
    [1,2,3,4]
  """
  @spec concat(list() | String.t(), list() | String.t()) :: list() | String.t()
  def concat(list1, list2) when is_list(list1) and is_list(list2) do
    list1 ++ list2
  end

  def concat(str1, str2) when is_binary(str1) and is_binary(str2) do
    str1 <> str2
  end

  @doc """
  Set the given `value` under `key` in `map`

  iex> tx = %{"type" => "transfer"}
  iex> Library.set(tx, "address", "0123abc")
  %{
    "type" => "transfer",
    "address" => "0123abc"
  }
  """
  @spec set(map(), binary(), any()) :: map()
  def set(map, key, value) do
    Map.put(map, key, value)
  end

  @doc """
  Return the head of list

  iex> Library.head([1,2,3])
  1
  """
  @spec head(list()) :: any()
  def head(list) do
    hd(list)
  end

  @doc """
  Get the genesis address of the chain
  """
  @spec get_genesis_address(binary()) ::
          binary()
  def get_genesis_address(address) do
    bin_address = Utils.maybe_decode_hex(address)
    nodes = Election.chain_storage_nodes(bin_address, P2P.authorized_and_available_nodes())
    {:ok, address} = download_first_address(nodes, bin_address)
    Base.encode16(address)
  end

  @doc """
  Get the inputs(type= :call) of the given transaction

  This is useful for contracts that want to throttle their calls
  """
  @spec get_calls(binary()) :: list(map())
  def get_calls(contract_address) do
    contract_address
    |> Utils.maybe_decode_hex()
    |> TransactionLookup.list_contract_transactions()
    |> Enum.map(fn {address, _, _} ->
      # TODO: parallelize
      {:ok, tx} = TransactionChain.get_transaction(address, [], :io)
      ContractConstants.from_transaction(tx)
    end)
  end

  @doc """
  Get the genesis public key
  """
  @spec get_genesis_public_key(binary()) :: binary()
  def get_genesis_public_key(address) do
    bin_address = Utils.maybe_decode_hex(address)
    nodes = Election.chain_storage_nodes(bin_address, P2P.authorized_and_available_nodes())
    {:ok, key} = download_first_public_key(nodes, bin_address)
    Base.encode16(key)
  end

  defp download_first_public_key([node | rest], public_key) do
    case P2P.send_message(node, %GetFirstPublicKey{public_key: public_key}) do
      {:ok, %FirstPublicKey{public_key: key}} -> {:ok, key}
      {:ok, _} -> download_first_public_key(rest, public_key)
      {:error, _} -> download_first_public_key(rest, public_key)
    end
  end

  defp download_first_public_key([], _address), do: {:error, :network_issue}

  defp download_first_address([node | rest], address) do
    case P2P.send_message(node, %GetGenesisAddress{address: address}) do
      {:ok, %GenesisAddress{address: address}} -> {:ok, address}
      {:error, _} -> download_first_address(rest, address)
    end
  end

  defp download_first_address([], _address), do: {:error, :network_issue}

  @doc """
  Return the current UNIX timestamp
  """
  @spec timestamp() :: non_neg_integer()
  def timestamp, do: DateTime.utc_now() |> DateTime.to_unix()
end
