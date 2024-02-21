defmodule Archethic.Mining.ValidationContext do
  @moduledoc """
  Represent the transaction validation workflow state
  """
  defstruct [
    :transaction,
    :previous_transaction,
    :welcome_node,
    :coordinator_node,
    :cross_validation_nodes,
    :validation_stamp,
    :validation_time,
    :contract_context,
    :genesis_address,
    resolved_addresses: %{},
    unspent_outputs: [],
    cross_validation_stamps: [],
    cross_validation_nodes_confirmation: <<>>,
    chain_storage_nodes: [],
    chain_storage_nodes_view: <<>>,
    beacon_storage_nodes: [],
    beacon_storage_nodes_view: <<>>,
    io_storage_nodes: [],
    io_storage_nodes_view: <<>>,
    sub_replication_tree: %{
      chain: <<>>,
      beacon: <<>>,
      IO: <<>>
    },
    full_replication_tree: %{
      chain: [],
      beacon: [],
      IO: []
    },
    previous_storage_nodes: [],
    valid_pending_transaction?: false,
    pending_transaction_error_detail: "",
    storage_nodes_confirmations: [],
    sub_replication_tree_validations: []
  ]

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining
  alias Archethic.Mining.ProofOfWork
  alias Archethic.Mining.SmartContractValidation

  alias Archethic.OracleChain

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.Replication

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Recipient

  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          previous_transaction: nil | Transaction.t(),
          unspent_outputs: list(VersionedUnspentOutput.t()),
          resolved_addresses: %{Crypto.prepended_hash() => Crypto.prepended_hash()},
          welcome_node: Node.t(),
          coordinator_node: Node.t(),
          cross_validation_nodes: list(Node.t()),
          previous_storage_nodes: list(Node.t()),
          chain_storage_nodes: list(Node.t()),
          beacon_storage_nodes: list(Node.t()),
          io_storage_nodes: list(Node.t()),
          cross_validation_nodes_confirmation: bitstring(),
          validation_stamp: nil | ValidationStamp.t(),
          full_replication_tree: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          sub_replication_tree: %{
            chain: bitstring(),
            beacon: bitstring(),
            IO: bitstring()
          },
          cross_validation_stamps: list(CrossValidationStamp.t()),
          chain_storage_nodes_view: bitstring(),
          beacon_storage_nodes_view: bitstring(),
          valid_pending_transaction?: boolean(),
          storage_nodes_confirmations: list({index :: non_neg_integer(), signature :: binary()}),
          pending_transaction_error_detail: binary(),
          sub_replication_tree_validations: list(Crypto.key()),
          contract_context: nil | Contract.Context.t(),
          genesis_address: binary()
        }

  @doc """
  Create a new mining context.

  It extracts coordinator and cross validation nodes from the validation nodes list

  It computes P2P views based on the cross validation nodes, beacon and chain storage nodes availability

  ## Examples

    iex> ValidationContext.new(
    ...>   transaction: %Transaction{},
    ...>   welcome_node: %Node{last_public_key: "key1"},
    ...>   coordinator_node: %Node{last_public_key: "key2"},
    ...>   cross_validation_nodes: [%Node{last_public_key: "key3"}],
    ...>   chain_storage_nodes: [%Node{last_public_key: "key4"}, %Node{last_public_key: "key5"}],
    ...>   beacon_storage_nodes: [%Node{last_public_key: "key6"}, %Node{last_public_key: "key7"}]
    ...> )
    %ValidationContext{
      transaction: %Transaction{},
      welcome_node: %Node{last_public_key: "key1"},
      coordinator_node: %Node{last_public_key: "key2"},
      cross_validation_nodes: [%Node{last_public_key: "key3"}],
      cross_validation_nodes_confirmation: <<0::1>>,
      chain_storage_nodes: [%Node{last_public_key: "key4"}, %Node{last_public_key: "key5"}],
      beacon_storage_nodes: [%Node{last_public_key: "key6"}, %Node{last_public_key: "key7"}]
    }
  """
  @spec new(opts :: Keyword.t()) :: t()
  def new(attrs \\ []) when is_list(attrs) do
    nb_cross_validation_nodes =
      attrs
      |> Keyword.get(:cross_validation_nodes, [])
      |> length()

    struct!(
      %__MODULE__{cross_validation_nodes_confirmation: <<0::size(nb_cross_validation_nodes)>>},
      attrs
    )
  end

  @doc """
  Set the pending transaction validation flag and the returned error
  """
  @spec set_pending_transaction_validation(t(), boolean(), binary()) :: t()
  def set_pending_transaction_validation(context = %__MODULE__{}, valid?, error_reason \\ "")
      when is_boolean(valid?) do
    %{
      context
      | valid_pending_transaction?: valid?,
        pending_transaction_error_detail: error_reason
    }
  end

  @doc """
  Determine if the enough context has been retrieved

  ## Examples

    iex> %ValidationContext{
    ...>  cross_validation_nodes_confirmation: <<1::1, 0::1, 1::1>>,
    ...>  cross_validation_nodes: [
    ...>    %Node{first_public_key: "key1"},
    ...>    %Node{first_public_key: "key2"},
    ...>    %Node{first_public_key: "key3"}
    ...>  ]
    ...> }
    ...> |> ValidationContext.enough_confirmations?()
    false

    iex> %ValidationContext{
    ...>  cross_validation_nodes_confirmation: <<1::1, 1::1, 1::1>>,
    ...>  cross_validation_nodes: [
    ...>    %Node{first_public_key: "key1"},
    ...>    %Node{first_public_key: "key2"},
    ...>    %Node{first_public_key: "key3"}
    ...>  ]
    ...> }
    ...> |> ValidationContext.enough_confirmations?()
    true
  """
  @spec enough_confirmations?(t()) :: boolean()
  def enough_confirmations?(%__MODULE__{
        cross_validation_nodes: cross_validation_nodes,
        cross_validation_nodes_confirmation: confirmed_nodes
      }) do
    Enum.reduce(cross_validation_nodes, <<>>, fn _, acc -> <<1::1, acc::bitstring>> end) ==
      confirmed_nodes
  end

  @doc """
  Confirm a cross validation node by setting a bit to 1 in the confirmation list

  ## Examples

    iex> %ValidationContext{
    ...>  cross_validation_nodes: [
    ...>    %Node{last_public_key: "key2"},
    ...>    %Node{last_public_key: "key3"}
    ...>  ],
    ...>  cross_validation_nodes_confirmation: <<0::1, 0::1>>
    ...> }
    ...> |> ValidationContext.confirm_validation_node("key3")
    %ValidationContext{
      cross_validation_nodes: [
        %Node{last_public_key: "key2"},
        %Node{last_public_key: "key3"}
      ],
      cross_validation_nodes_confirmation: <<0::1, 1::1>>
    }
  """
  def confirm_validation_node(
        context = %__MODULE__{cross_validation_nodes: cross_validation_nodes},
        node_public_key
      ) do
    index = Enum.find_index(cross_validation_nodes, &(&1.last_public_key == node_public_key))

    Map.update!(
      context,
      :cross_validation_nodes_confirmation,
      &Utils.set_bitstring_bit(&1, index)
    )
  end

  @doc """
  Get the list confirmed cross validation nodes

  ## Examples

    iex> %ValidationContext{
    ...>   cross_validation_nodes: [
    ...>     %Node{last_public_key: "key1"},
    ...>     %Node{last_public_key: "key2"},
    ...>     %Node{last_public_key: "key3"},
    ...>     %Node{last_public_key: "key4"},
    ...>   ],
    ...>   cross_validation_nodes_confirmation: <<0::1, 1::1, 0::1, 1::1>>
    ...> }
    ...> |> ValidationContext.get_confirmed_validation_nodes()
    [
      %Node{last_public_key: "key2"},
      %Node{last_public_key: "key4"}
    ]
  """
  @spec get_confirmed_validation_nodes(t()) :: list(Node.t())
  def get_confirmed_validation_nodes(%__MODULE__{
        cross_validation_nodes: cross_validation_nodes,
        cross_validation_nodes_confirmation: cross_validation_confirmation
      }) do
    cross_validation_confirmation
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.reduce([], fn
      {1, index}, acc ->
        case Enum.at(cross_validation_nodes, index) do
          nil ->
            acc

          node ->
            [node | acc]
        end

      {0, _}, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  def set_confirmed_validation_nodes(
        context = %__MODULE__{},
        cross_validation_nodes_confirmation
      ) do
    %{context | cross_validation_nodes_confirmation: cross_validation_nodes_confirmation}
  end

  @doc """
  Add the validation stamp to the mining context
  """
  @spec add_validation_stamp(t(), ValidationStamp.t()) :: t()
  def add_validation_stamp(context = %__MODULE__{}, stamp = %ValidationStamp{}) do
    %{context | validation_stamp: stamp}
  end

  @doc """
  Determines if the expected cross validation stamps have been received

  ## Examples

    iex> %ValidationContext{
    ...>  cross_validation_stamps: [
    ...>    %CrossValidationStamp{},
    ...>    %CrossValidationStamp{},
    ...>    %CrossValidationStamp{},
    ...>  ],
    ...>  cross_validation_nodes: [
    ...>    %Node{},
    ...>    %Node{},
    ...>    %Node{},
    ...>    %Node{},
    ...>  ],
    ...>  cross_validation_nodes_confirmation: <<1::1, 1::1, 1::1, 1::1>>
    ...> }
    ...> |> ValidationContext.enough_cross_validation_stamps?()
    false
  """
  @spec enough_cross_validation_stamps?(t()) :: boolean()
  def enough_cross_validation_stamps?(
        context = %__MODULE__{
          cross_validation_stamps: stamps
        }
      ) do
    confirmed_cross_validation_nodes = get_confirmed_validation_nodes(context)
    length(confirmed_cross_validation_nodes) == length(stamps)
  end

  @doc """
  Determines if the atomic commitment has been reached from the cross validation stamps.
  """
  @spec atomic_commitment?(t()) :: boolean()
  def atomic_commitment?(%__MODULE__{transaction: tx, cross_validation_stamps: stamps}) do
    %{tx | cross_validation_stamps: stamps}
    |> Transaction.atomic_commitment?()
  end

  @doc """
  Add a cross validation stamp if not exists
  """
  @spec add_cross_validation_stamp(t(), CrossValidationStamp.t()) :: t()
  def add_cross_validation_stamp(
        context = %__MODULE__{
          validation_stamp: validation_stamp
        },
        stamp = %CrossValidationStamp{
          node_public_key: from
        }
      ) do
    cond do
      !cross_validation_node?(context, from) ->
        context

      !CrossValidationStamp.valid_signature?(stamp, validation_stamp) ->
        context

      cross_validation_stamp_exists?(context, from) ->
        context

      true ->
        Map.update!(context, :cross_validation_stamps, &[stamp | &1])
    end
  end

  defp cross_validation_stamp_exists?(
         %__MODULE__{cross_validation_stamps: stamps},
         node_public_key
       )
       when is_binary(node_public_key) do
    Enum.any?(stamps, &(&1.node_public_key == node_public_key))
  end

  @doc """
  Determines if a node is a cross validation node

  ## Examples

    iex> %ValidationContext{
    ...>   coordinator_node: %Node{last_public_key: "key1"},
    ...>   cross_validation_nodes: [
    ...>     %Node{last_public_key: "key2"},
    ...>     %Node{last_public_key: "key3"},
    ...>     %Node{last_public_key: "key4"},
    ...>   ]
    ...> }
    ...> |> ValidationContext.cross_validation_node?("key3")
    true

    iex> %ValidationContext{
    ...>   coordinator_node: %Node{last_public_key: "key1"},
    ...>   cross_validation_nodes: [
    ...>     %Node{last_public_key: "key2"},
    ...>     %Node{last_public_key: "key3"},
    ...>     %Node{last_public_key: "key4"},
    ...>   ]
    ...> }
    ...> |> ValidationContext.cross_validation_node?("key1")
    false
  """
  @spec cross_validation_node?(t(), Crypto.key()) :: boolean()
  def cross_validation_node?(
        %__MODULE__{cross_validation_nodes: cross_validation_nodes},
        node_public_key
      )
      when is_binary(node_public_key) do
    Enum.any?(cross_validation_nodes, &(&1.last_public_key == node_public_key))
  end

  @doc """
  Add the replication tree and initialize the replication nodes confirmation list

  ## Examples

    iex> %ValidationContext{
    ...>    full_replication_tree: %{ chain: [<<0::1, 1::1>>, <<1::1, 0::1>>],  beacon: [<<0::1, 1::1>>, <<1::1, 0::1>>], IO: [<<0::1, 1::1>>, <<1::1, 0::1>>] },
    ...>    sub_replication_tree: %{ chain: <<1::1, 0::1>>, beacon: <<1::1, 0::1>>, IO: <<1::1, 0::1>> },
    ...> } = %ValidationContext{
    ...>    coordinator_node: %Node{last_public_key: "key1"},
    ...>    cross_validation_nodes: [%Node{last_public_key: "key2"}],
    ...>    cross_validation_nodes_confirmation: <<1::1>>
    ...> }
    ...> |> ValidationContext.add_replication_tree(%{ chain: [<<0::1, 1::1>>, <<1::1, 0::1>>], beacon: [<<0::1, 1::1>>, <<1::1, 0::1>>], IO: [<<0::1, 1::1>>, <<1::1, 0::1>>] }, "key2")
  """
  @spec add_replication_tree(
          t(),
          replication_trees :: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          node_public_key :: Crypto.key()
        ) :: t()
  def add_replication_tree(
        context = %__MODULE__{
          coordinator_node: coordinator_node
        },
        tree = %{chain: chain_tree, beacon: beacon_tree, IO: io_tree},
        node_public_key
      )
      when is_list(chain_tree) and is_list(beacon_tree) and is_list(io_tree) and
             is_binary(node_public_key) do
    confirmed_cross_validation_nodes = get_confirmed_validation_nodes(context)

    validation_nodes = [coordinator_node | confirmed_cross_validation_nodes]
    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == node_public_key))

    sub_chain_tree = Enum.at(chain_tree, validator_index)

    sub_beacon_tree = Enum.at(beacon_tree, validator_index)

    # IO tree can be empty, if there are not recipients
    sub_io_tree = Enum.at(io_tree, validator_index, [])

    %{
      context
      | sub_replication_tree: %{
          chain: sub_chain_tree,
          beacon: sub_beacon_tree,
          IO: sub_io_tree
        },
        full_replication_tree: tree
    }
  end

  @doc """
  Get the entire list of storage nodes (transaction chain, beacon chain, I/O)

  ## Examples

    iex> %ValidationContext{
    ...>   chain_storage_nodes: [%Node{first_public_key: "key1"}, %Node{first_public_key: "key2"}],
    ...>   beacon_storage_nodes: [%Node{first_public_key: "key3"}, %Node{first_public_key: "key1"}],
    ...>   io_storage_nodes: [%Node{first_public_key: "key4"}, %Node{first_public_key: "key5"}]
    ...> }
    ...> |> ValidationContext.get_storage_nodes()
    %{
      %Node{first_public_key: "key1"} => [:beacon, :chain],
      %Node{first_public_key: "key2"} => [:chain],
      %Node{first_public_key: "key3"} => [:beacon],
      %Node{first_public_key: "key4"} => [:IO],
      %Node{first_public_key: "key5"} => [:IO]
    }
  """
  @spec get_storage_nodes(t()) :: list(Node.t())
  def get_storage_nodes(%__MODULE__{
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: io_storage_nodes
      }) do
    [{:chain, chain_storage_nodes}, {:beacon, beacon_storage_nodes}, {:IO, io_storage_nodes}]
    |> Enum.reduce(%{}, fn {role, nodes}, acc ->
      Enum.reduce(nodes, acc, fn node, acc ->
        Map.update(acc, node, [role], &[role | &1])
      end)
    end)
  end

  defp get_storage_nodes_tree_indexes(tree) do
    tree
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.filter(&match?({1, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Get the transaction validated including the validation stamp and cross validation stamps
  """
  @spec get_validated_transaction(t()) :: Transaction.t()
  def get_validated_transaction(%__MODULE__{
        transaction: transaction,
        validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
      }) do
    %{
      transaction
      | validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
    }
  end

  @doc """
  Initialize the transaction mining context
  """
  @spec put_transaction_context(
          t(),
          Transaction.t(),
          list(VersionedUnspentOutput.t()),
          list(Node.t()),
          bitstring(),
          bitstring(),
          bitstring()
        ) :: t()
  def put_transaction_context(
        context = %__MODULE__{},
        previous_transaction,
        unspent_outputs,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      ) do
    context
    |> Map.put(:previous_transaction, previous_transaction)
    |> Map.put(:unspent_outputs, unspent_outputs)
    |> Map.put(:previous_storage_nodes, previous_storage_nodes)
    |> Map.put(:chain_storage_nodes_view, chain_storage_nodes_view)
    |> Map.put(:beacon_storage_nodes_view, beacon_storage_nodes_view)
    |> Map.put(:io_storage_nodes_view, io_storage_nodes_view)
  end

  @doc """
  Aggregate the transaction mining context with the incoming context retrieved from the validation nodes

  ## Examples

    iex> %ValidationContext{
    ...>    previous_storage_nodes: [%Node{first_public_key: "key1"}],
    ...>    chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
    ...>    beacon_storage_nodes_view: <<1::1, 0::1, 1::1>>,
    ...>    io_storage_nodes_view: <<1::1, 0::1, 0::1>>,
    ...>    cross_validation_nodes: [%Node{last_public_key: "key3"}, %Node{last_public_key: "key5"}],
    ...>    cross_validation_nodes_confirmation: <<0::1, 0::1>>
    ...> }
    ...> |> ValidationContext.aggregate_mining_context(
    ...>    [%Node{first_public_key: "key2"}],
    ...>    <<1::1, 0::1, 1::1>>,
    ...>    <<1::1, 1::1, 1::1>>,
    ...>    <<1::1, 0::1, 0::1>>,
    ...>    "key5"
    ...> )
    %ValidationContext{
      previous_storage_nodes: [
        %Node{first_public_key: "key1"},
        %Node{first_public_key: "key2"}
      ],
      chain_storage_nodes_view: <<1::1, 1::1, 1::1>>,
      beacon_storage_nodes_view: <<1::1, 1::1, 1::1>>,
      io_storage_nodes_view: <<1::1, 0::1, 0::1>>,
      cross_validation_nodes_confirmation: <<0::1, 1::1>>,
      cross_validation_nodes: [%Node{last_public_key: "key3"}, %Node{last_public_key: "key5"}]
    }
  """
  @spec aggregate_mining_context(
          t(),
          list(Node.t()),
          bitstring(),
          bitstring(),
          bitstring(),
          Crypto.key()
        ) :: t()
  def aggregate_mining_context(
        context = %__MODULE__{},
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view,
        from
      )
      when is_list(previous_storage_nodes) and
             is_bitstring(chain_storage_nodes_view) and
             is_bitstring(beacon_storage_nodes_view) and
             is_bitstring(io_storage_nodes_view) do
    if cross_validation_node?(context, from) do
      context
      |> confirm_validation_node(from)
      |> aggregate_p2p_views(
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      )
      |> aggregate_previous_storage_nodes(previous_storage_nodes)
    else
      context
    end
  end

  defp aggregate_p2p_views(
         context = %__MODULE__{
           chain_storage_nodes_view: chain_storage_nodes_view1,
           beacon_storage_nodes_view: beacon_storage_nodes_view1,
           io_storage_nodes_view: io_storage_nodes_view1
         },
         chain_storage_nodes_view2,
         beacon_storage_nodes_view2,
         io_storage_nodes_view2
       )
       when is_bitstring(chain_storage_nodes_view2) and
              is_bitstring(beacon_storage_nodes_view2) and
              is_bitstring(io_storage_nodes_view2) do
    %{
      context
      | chain_storage_nodes_view:
          Utils.aggregate_bitstring(chain_storage_nodes_view1, chain_storage_nodes_view2),
        beacon_storage_nodes_view:
          Utils.aggregate_bitstring(beacon_storage_nodes_view1, beacon_storage_nodes_view2),
        io_storage_nodes_view:
          Utils.aggregate_bitstring(io_storage_nodes_view1, io_storage_nodes_view2)
    }
  end

  defp aggregate_previous_storage_nodes(
         context = %__MODULE__{previous_storage_nodes: previous_nodes},
         received_previous_storage_nodes
       )
       when is_list(received_previous_storage_nodes) do
    previous_storage_nodes = P2P.distinct_nodes([previous_nodes, received_previous_storage_nodes])
    %{context | previous_storage_nodes: previous_storage_nodes}
  end

  @doc """
  Return the validation nodes
  """
  @spec get_validation_nodes(t()) :: list(Node.t())
  def get_validation_nodes(
        context = %__MODULE__{
          coordinator_node: coordinator_node
        }
      ) do
    confirmed_cross_validation_nodes = get_confirmed_validation_nodes(context)
    [coordinator_node | confirmed_cross_validation_nodes] |> P2P.distinct_nodes()
  end

  @doc """
  Create a validation stamp based on the validation context and add it to the context
  """
  @spec create_validation_stamp(t()) :: t()
  def create_validation_stamp(
        context = %__MODULE__{
          transaction: tx = %Transaction{data: %TransactionData{recipients: recipients}},
          previous_transaction: prev_tx,
          valid_pending_transaction?: valid_pending_transaction?,
          validation_time: validation_time,
          resolved_addresses: resolved_addresses,
          contract_context: contract_context
        }
      ) do
    protocol_version = Mining.protocol_version()

    {valid_contract_execution?, encoded_state} =
      SmartContractValidation.valid_contract_execution?(contract_context, prev_tx, tx)

    resolved_recipients = resolved_recipients(recipients, resolved_addresses)

    {valid_contract_recipients?, contract_recipients_fee} =
      validate_contract_recipients(tx, resolved_recipients, validation_time)

    fee =
      calculate_fee(
        tx,
        contract_context,
        contract_recipients_fee,
        validation_time,
        encoded_state
      )

    {sufficient_funds?, ledger_operations} =
      get_ledger_operations(context, fee, validation_time, encoded_state)

    validation_stamp =
      %ValidationStamp{
        protocol_version: protocol_version,
        timestamp: validation_time,
        proof_of_work: do_proof_of_work(tx),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx, prev_tx]),
        proof_of_election: Election.validation_nodes_election_seed_sorting(tx, validation_time),
        ledger_operations: ledger_operations,
        recipients: resolved_recipients |> Enum.map(& &1.address),
        error:
          get_validation_error(
            prev_tx,
            tx,
            sufficient_funds?,
            valid_pending_transaction?,
            resolved_recipients,
            validation_time,
            valid_contract_execution?,
            valid_contract_recipients?
          )
      }
      |> ValidationStamp.sign()

    %{context | validation_stamp: validation_stamp}
  end

  defp calculate_fee(
         tx,
         contract_context,
         contract_recipients_fee,
         validation_time,
         encoded_state
       ) do
    previous_usd_price =
      validation_time
      |> OracleChain.get_last_scheduling_date()
      |> OracleChain.get_uco_price()
      |> Keyword.fetch!(:usd)

    Mining.get_transaction_fee(
      tx,
      contract_context,
      previous_usd_price,
      validation_time,
      encoded_state,
      contract_recipients_fee
    )
  end

  defp get_ledger_operations(
         %__MODULE__{
           transaction: tx = %Transaction{address: address, type: tx_type},
           unspent_outputs: unspent_outputs,
           resolved_addresses: resolved_addresses,
           contract_context: contract_context
         },
         fee,
         validation_time,
         encoded_state
       ) do
    movements = Transaction.get_movements(tx)
    protocol_version = Mining.protocol_version()

    {sufficient_funds?, ops} =
      LedgerOperations.consume_inputs(
        %LedgerOperations{fee: fee},
        address,
        validation_time |> DateTime.truncate(:millisecond),
        unspent_outputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, validation_time, protocol_version),
        encoded_state,
        contract_context
      )

    new_ops =
      LedgerOperations.build_resolved_movements(ops, movements, resolved_addresses, tx_type)

    {sufficient_funds?, new_ops}
  end

  @spec get_validation_error(
          prev_tx :: nil | Transaction.t(),
          tx :: Transaction.t(),
          sufficient_funds? :: boolean(),
          valid_pending_transaction? :: boolean(),
          resolved_recipients :: list(Recipient.t()),
          validation_time :: DateTime.t(),
          valid_contract_execution? :: boolean(),
          valid_contract_recipients? :: boolean()
        ) :: nil | ValidationStamp.error()
  defp get_validation_error(
         prev_tx,
         tx,
         sufficient_funds?,
         valid_pending_transaction?,
         resolved_recipients,
         validation_time,
         valid_contract_execution?,
         valid_contract_recipients?
       ) do
    cond do
      not valid_pending_transaction? ->
        :invalid_pending_transaction

      not sufficient_funds? ->
        :insufficient_funds

      not valid_inherit_condition?(prev_tx, tx, validation_time) ->
        :invalid_inherit_constraints

      not valid_contract_execution? ->
        :invalid_contract_execution

      not valid_contract_recipients_distinct?(resolved_recipients) ->
        :recipients_not_distinct

      not valid_contract_recipients? ->
        :invalid_recipients_execution

      true ->
        nil
    end
  end

  def valid_contract_recipients_distinct?(resolved_recipients) do
    resolved_recipients_addresses = Enum.map(resolved_recipients, & &1.address)

    resolved_recipients_addresses == Enum.uniq(resolved_recipients_addresses)
  end

  defp validate_contract_recipients(_tx, [], _validation_time), do: {true, 0}

  defp validate_contract_recipients(tx, resolved_recipients, validation_time),
    do: SmartContractValidation.validate_contract_calls(resolved_recipients, tx, validation_time)

  ####################
  defp valid_inherit_condition?(
         prev_tx = %Transaction{data: %TransactionData{code: code}},
         next_tx = %Transaction{},
         validation_time
       )
       when code != "" do
    case Contracts.execute_condition(
           :inherit,
           Contract.from_transaction!(prev_tx),
           next_tx,
           nil,
           validation_time
         ) do
      {:ok, _logs} -> true
      _ -> false
    end
  end

  # handle cases:
  #   - first transaction
  #   - previous has no code
  defp valid_inherit_condition?(_prev_tx, _next_tx, _validation_time), do: true

  @doc """
  Create a replication tree based on the validation context (storage nodes and validation nodes)
  and store it as a bitstring list.

  ## Examples

      iex> %ValidationContext{
      ...>   coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
      ...>   cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC",  last_public_key: "key2"}],
      ...>   chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB", available?: true}, %Node{first_public_key: "key4", network_patch: "EFC", available?: true}],
      ...>   cross_validation_nodes_confirmation: <<1::1>>,
      ...>   chain_storage_nodes_view: <<1::1, 1::1>>,
      ...>   beacon_storage_nodes_view: <<1::1, 1::1>>
      ...> }
      ...> |> ValidationContext.create_replication_tree()
      %ValidationContext{
        sub_replication_tree: %{
          chain: <<1::1, 0::1>>,
          beacon: <<>>,
          IO: <<>>
        },
        full_replication_tree: %{
          IO: [],
          beacon: [],
          chain: [<<1::1, 0::1>>, <<0::1, 1::1>>]
        },
        coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
        cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC", last_public_key: "key2"}],
        chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB", available?: true}, %Node{first_public_key: "key4", network_patch: "EFC", available?: true}],
        cross_validation_nodes_confirmation: <<1::1>>,
        chain_storage_nodes_view: <<1::1, 1::1>>,
        beacon_storage_nodes_view: <<1::1, 1::1>>
      }

      iex> %ValidationContext{
      ...>   coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
      ...>   cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC",  last_public_key: "key2"}],
      ...>   chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB", available?: true}, %Node{first_public_key: "key4", network_patch: "EFC", available?: true}, %Node{first_public_key: "key5", network_patch: "A0C", available?: true}, %Node{first_public_key: "key6", network_patch: "BBB", available?: true}],
      ...>   cross_validation_nodes_confirmation: <<1::1>>,
      ...>   chain_storage_nodes_view: <<0::1, 1::1, 1::1, 0::1>>,
      ...> }
      ...> |> ValidationContext.create_replication_tree()
      %ValidationContext{
        sub_replication_tree: %{
          chain: <<0::1, 0::1, 1::1, 0::1>>,
          beacon: <<>>,
          IO: <<>>
        },
        full_replication_tree: %{
          IO: [],
          beacon: [],
          chain: [<<0::1, 0::1, 1::1, 0::1>>, <<0::1, 1::1, 0::1, 0::1>>]
        },
        coordinator_node: %Node{first_public_key: "key1", network_patch: "AAA", last_public_key: "key1"},
        cross_validation_nodes: [%Node{first_public_key: "key2", network_patch: "FAC", last_public_key: "key2"}],
         chain_storage_nodes: [%Node{first_public_key: "key3", network_patch: "BBB", available?: true}, %Node{first_public_key: "key4", network_patch: "EFC", available?: true}, %Node{first_public_key: "key5", network_patch: "A0C", available?: true}, %Node{first_public_key: "key6", network_patch: "BBB", available?: true}],
        cross_validation_nodes_confirmation: <<1::1>>,
        chain_storage_nodes_view: <<0::1, 1::1, 1::1, 0::1>>
      }
  """
  @spec create_replication_tree(t()) :: t()
  def create_replication_tree(
        context = %__MODULE__{
          chain_storage_nodes: chain_storage_nodes,
          chain_storage_nodes_view: chain_storage_nodes_view,
          beacon_storage_nodes: beacon_storage_nodes,
          beacon_storage_nodes_view: beacon_storage_nodes_view,
          io_storage_nodes: io_storage_nodes,
          io_storage_nodes_view: io_storage_nodes_view
        }
      ) do
    validation_nodes = get_validation_nodes(context)

    chain_replication_tree =
      Replication.generate_tree(
        validation_nodes,
        filter_node_list_by_view(chain_storage_nodes, chain_storage_nodes_view)
      )

    beacon_replication_tree =
      Replication.generate_tree(
        validation_nodes,
        filter_node_list_by_view(
          beacon_storage_nodes,
          beacon_storage_nodes_view
        )
      )

    io_replication_tree =
      Replication.generate_tree(
        validation_nodes,
        filter_node_list_by_view(io_storage_nodes, io_storage_nodes_view)
      )

    tree = %{
      chain:
        Enum.map(chain_replication_tree, fn {_, list} ->
          P2P.bitstring_from_node_subsets(chain_storage_nodes, list)
        end),
      beacon:
        Enum.map(beacon_replication_tree, fn {_, list} ->
          P2P.bitstring_from_node_subsets(beacon_storage_nodes, list)
        end),
      IO:
        Enum.map(io_replication_tree, fn {_, list} ->
          P2P.bitstring_from_node_subsets(io_storage_nodes, list)
        end)
    }

    sub_tree = %{
      chain: tree |> Map.get(:chain) |> Enum.at(0, <<>>),
      beacon: tree |> Map.get(:beacon) |> Enum.at(0, <<>>),
      IO: tree |> Map.get(:IO) |> Enum.at(0, <<>>)
    }

    %{
      context
      | sub_replication_tree: sub_tree,
        full_replication_tree: tree
    }
  end

  defp filter_node_list_by_view(node_list, nodes_view) do
    view_list = Utils.bitstring_to_integer_list(nodes_view)

    node_list
    |> Enum.with_index()
    # We take only the node which are locally available from the validation nodes
    |> Enum.filter(fn {_node, index} ->
      Enum.at(view_list, index) == 1
    end)
    |> Enum.map(fn {node, _index} -> node end)
  end

  defp do_proof_of_work(tx) do
    result =
      tx
      |> ProofOfWork.list_origin_public_keys_candidates()
      |> ProofOfWork.find_transaction_origin_public_key(tx)

    case result do
      {:ok, pow} ->
        pow

      {:error, :not_found} ->
        ""
    end
  end

  @doc """
  Cross validate the validation stamp using the validation context as reference and
  listing the potential inconsistencies.

  The cross validation stamp is therefore signed and stored in the context
  """
  @spec cross_validate(t()) :: t()
  def cross_validate(context = %__MODULE__{validation_stamp: validation_stamp}) do
    inconsistencies = validation_stamp_inconsistencies(context)

    cross_stamp =
      %CrossValidationStamp{inconsistencies: inconsistencies}
      |> CrossValidationStamp.sign(validation_stamp)

    %{context | cross_validation_stamps: [cross_stamp]}
  end

  defp validation_stamp_inconsistencies(
         context = %__MODULE__{
           transaction: tx = %Transaction{data: %TransactionData{recipients: recipients}},
           previous_transaction: prev_tx,
           resolved_addresses: resolved_addresses,
           contract_context: contract_context,
           validation_stamp:
             stamp = %ValidationStamp{
               timestamp: validation_time,
               ledger_operations: %LedgerOperations{fee: stamp_fee}
             }
         }
       ) do
    resolved_recipients = resolved_recipients(recipients, resolved_addresses)

    {valid_contract_execution?, next_state} =
      SmartContractValidation.valid_contract_execution?(contract_context, prev_tx, tx)

    {valid_contract_recipients?, contract_recipients_fee} =
      validate_contract_recipients(tx, resolved_recipients, validation_time)

    fee =
      calculate_fee(
        tx,
        contract_context,
        contract_recipients_fee,
        validation_time,
        next_state
      )

    {sufficient_funds?, ledger_operations} =
      get_ledger_operations(context, stamp_fee, validation_time, next_state)

    subsets_verifications = [
      timestamp: fn -> valid_timestamp(stamp, context) end,
      signature: fn -> valid_stamp_signature(stamp, context) end,
      proof_of_work: fn -> valid_stamp_proof_of_work?(stamp, context) end,
      proof_of_integrity: fn -> valid_stamp_proof_of_integrity?(stamp, context) end,
      proof_of_election: fn -> valid_stamp_proof_of_election?(stamp, context) end,
      transaction_fee: fn -> valid_stamp_fee?(stamp, fee) end,
      transaction_movements: fn -> valid_stamp_transaction_movements?(stamp, context) end,
      recipients: fn -> valid_stamp_recipients?(stamp, context) end,
      unspent_outputs: fn -> valid_stamp_unspent_outputs?(stamp, ledger_operations) end,
      error: fn ->
        valid_stamp_error?(
          stamp,
          context,
          valid_contract_execution?,
          valid_contract_recipients?,
          sufficient_funds?,
          resolved_recipients
        )
      end,
      protocol_version: fn -> valid_protocol_version?(stamp) end
    ]

    subsets_verifications
    |> Enum.map(&{elem(&1, 0), elem(&1, 1).()})
    |> Enum.filter(&match?({_, false}, &1))
    |> Enum.map(&elem(&1, 0))
  end

  defp valid_timestamp(%ValidationStamp{timestamp: timestamp}, %__MODULE__{
         validation_time: validation_time
       }) do
    diff = DateTime.diff(timestamp, validation_time)
    diff <= 10 and diff > -10
  end

  defp valid_stamp_signature(stamp = %ValidationStamp{}, %__MODULE__{
         coordinator_node: %Node{last_public_key: coordinator_node_public_key}
       }) do
    ValidationStamp.valid_signature?(stamp, coordinator_node_public_key)
  end

  defp valid_stamp_proof_of_work?(%ValidationStamp{proof_of_work: pow}, %__MODULE__{
         transaction: tx
       }) do
    case pow do
      "" ->
        do_proof_of_work(tx) == ""

      _ ->
        Transaction.verify_origin_signature?(tx, pow) and
          pow in ProofOfWork.list_origin_public_keys_candidates(tx)
    end
  end

  defp valid_stamp_proof_of_integrity?(%ValidationStamp{proof_of_integrity: poi}, %__MODULE__{
         transaction: tx,
         previous_transaction: prev_tx
       }),
       do: TransactionChain.proof_of_integrity([tx, prev_tx]) == poi

  defp valid_stamp_proof_of_election?(
         %ValidationStamp{proof_of_election: poe, timestamp: timestamp},
         %__MODULE__{
           transaction: tx
         }
       ),
       do: poe == Election.validation_nodes_election_seed_sorting(tx, timestamp)

  defp valid_stamp_fee?(
         %ValidationStamp{ledger_operations: %LedgerOperations{fee: stamp_fee}},
         expected_fee
       ) do
    stamp_fee == expected_fee
  end

  defp valid_stamp_error?(
         %ValidationStamp{error: error, timestamp: validation_time},
         %__MODULE__{
           transaction: tx,
           previous_transaction: prev_tx,
           valid_pending_transaction?: valid_pending_transaction?
         },
         valid_contract_execution?,
         valid_contract_recipients?,
         sufficient_funds?,
         resolved_recipients
       ) do
    expected_error =
      get_validation_error(
        prev_tx,
        tx,
        sufficient_funds?,
        valid_pending_transaction?,
        resolved_recipients,
        validation_time,
        valid_contract_execution?,
        valid_contract_recipients?
      )

    error == expected_error
  end

  defp valid_stamp_recipients?(
         %ValidationStamp{recipients: stamp_recipients},
         %__MODULE__{
           transaction: %Transaction{data: %TransactionData{recipients: recipients}},
           resolved_addresses: resolved_addresses
         }
       ) do
    recipients_addresses =
      recipients
      |> resolved_recipients(resolved_addresses)
      |> Enum.map(& &1.address)

    Enum.all?(recipients_addresses, &(&1 in stamp_recipients))
  end

  defp valid_stamp_transaction_movements?(
         %ValidationStamp{
           ledger_operations:
             _ops = %LedgerOperations{
               transaction_movements: transaction_movements
             }
         },
         %__MODULE__{
           transaction: tx = %Transaction{type: tx_type},
           resolved_addresses: resolved_addresses
         }
       ) do
    movements = Transaction.get_movements(tx)

    %LedgerOperations{transaction_movements: resolved_movements} =
      %LedgerOperations{}
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx_type)

    length(resolved_movements) == length(transaction_movements) and
      Enum.all?(resolved_movements, &(&1 in transaction_movements))
  end

  defp valid_stamp_unspent_outputs?(
         %ValidationStamp{
           ledger_operations: %LedgerOperations{unspent_outputs: next_unspent_outputs}
         },
         %LedgerOperations{unspent_outputs: expected_unspent_outputs}
       ) do
    expected_unspent_outputs == next_unspent_outputs
  end

  defp valid_protocol_version?(%ValidationStamp{protocol_version: version}),
    do: Mining.protocol_version() == version

  @doc """
  Get the chain storage node position
  """
  @spec get_chain_storage_position(t(), node_public_key :: Crypto.key()) ::
          {:ok, non_neg_integer()} | {:error, :not_found}
  def get_chain_storage_position(
        %__MODULE__{chain_storage_nodes: chain_storage_nodes, validation_time: validation_time},
        node_public_key
      ) do
    if Enum.any?(chain_storage_nodes, &(&1.first_public_key == node_public_key)) do
      node_index = ReplicationAttestation.get_node_index(node_public_key, validation_time)
      {:ok, node_index}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Get the list of chain replication nodes
  """
  @spec get_chain_replication_nodes(t()) :: list(Node.t())
  def get_chain_replication_nodes(%__MODULE__{
        sub_replication_tree: %{
          chain: sub_tree
        },
        chain_storage_nodes: storage_nodes
      }) do
    sub_tree
    |> get_storage_nodes_tree_indexes
    |> Enum.map(&Enum.at(storage_nodes, &1))
  end

  @doc """
  Get the list of beacon replication nodes
  """
  @spec get_beacon_replication_nodes(t()) :: list(Node.t())
  def get_beacon_replication_nodes(%__MODULE__{
        sub_replication_tree: %{beacon: sub_tree},
        beacon_storage_nodes: storage_nodes
      }) do
    sub_tree
    |> get_storage_nodes_tree_indexes
    |> Enum.map(&Enum.at(storage_nodes, &1))
  end

  @doc """
  Add the storage node confirmation
  """
  @spec add_storage_confirmation(t(), node_index :: non_neg_integer(), signature :: binary()) ::
          t()
  def add_storage_confirmation(
        context = %__MODULE__{},
        index,
        signature
      ) do
    Map.update!(context, :storage_nodes_confirmations, &[{index, signature} | &1])
  end

  @doc """
  Determine if all the chain storage nodes returned a confirmation
  """
  @spec enough_storage_confirmations?(t()) :: boolean()
  def enough_storage_confirmations?(
        context = %__MODULE__{
          storage_nodes_confirmations: storage_nodes_confirmation
        }
      ) do
    nb_confirmed_replications = Enum.count(storage_nodes_confirmation)

    context
    |> get_chain_replication_nodes
    |> Enum.count() == nb_confirmed_replications
  end

  @doc """
  Return the list of nodes which confirmed the transaction replication

  We use the authorized_and_available_nodes as a common reference between the nodes
  """
  @spec get_confirmed_replication_nodes(t()) :: list(Node.t())
  def get_confirmed_replication_nodes(%__MODULE__{
        validation_time: validation_time,
        storage_nodes_confirmations: storage_nodes_confirmations
      }) do
    nodes =
      P2P.authorized_and_available_nodes(validation_time)
      |> Enum.sort_by(& &1.first_public_key)

    Enum.map(storage_nodes_confirmations, fn {index, _} ->
      Enum.at(nodes, index)
    end)
  end

  @doc """
  Get the list of I/O replication nodes
  """
  @spec get_io_replication_nodes(t()) :: list(Node.t())
  def get_io_replication_nodes(%__MODULE__{
        sub_replication_tree: %{
          IO: []
        }
      }),
      do: []

  def get_io_replication_nodes(%__MODULE__{
        sub_replication_tree: %{
          IO: sub_tree
        },
        io_storage_nodes: storage_nodes,
        chain_storage_nodes: chain_storage_nodes
      }) do
    sub_tree
    |> get_storage_nodes_tree_indexes
    |> Enum.map(&Enum.at(storage_nodes, &1))
    |> Enum.reject(&Utils.key_in_node_list?(chain_storage_nodes, &1.first_public_key))
  end

  @doc """
  Get the first available error or nil
  """
  @spec get_first_error(t()) :: atom()
  def get_first_error(%__MODULE__{
        validation_stamp: %ValidationStamp{error: nil},
        cross_validation_stamps: cross_validation_stamps
      }) do
    cross_validation_stamps
    |> Enum.reduce_while(nil, fn
      %CrossValidationStamp{inconsistencies: []}, nil -> {:cont, nil}
      %CrossValidationStamp{inconsistencies: [first_error | _rest]}, nil -> {:halt, first_error}
    end)
  end

  def get_first_error(%__MODULE__{validation_stamp: %ValidationStamp{error: error}}), do: error

  @doc """
  Add a replication nodes validation confirmation
  """
  @spec add_replication_validation(t(), Crypto.key()) :: t()
  def add_replication_validation(context = %__MODULE__{}, node_public_key) do
    Map.update!(context, :sub_replication_tree_validations, &[node_public_key | &1])
  end

  @doc """
  Determine if the replication validations are sufficient
  """
  @spec enough_replication_validations?(t()) :: boolean()
  def enough_replication_validations?(%__MODULE__{
        sub_replication_tree_validations: sub_replication_tree_validations,
        full_replication_tree: %{chain: chain_replication_tree}
      }) do
    length(chain_replication_tree) == length(sub_replication_tree_validations)
  end

  @doc """
  Returns the entire list (availables) of the chain replication nodes
  """
  @spec get_full_chain_replication_nodes(t()) :: list(Node.t())
  def get_full_chain_replication_nodes(%__MODULE__{
        chain_storage_nodes: chain_storage_nodes,
        full_replication_tree: %{chain: chain_replication_tree}
      }) do
    chain_replication_tree
    |> Enum.map(&Archethic.Utils.bitstring_to_integer_list/1)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.map(fn x ->
      if Enum.member?(x, 1) do
        1
      else
        0
      end
    end)
    |> Enum.with_index()
    |> Enum.filter(fn {available, _} -> available == 1 end)
    |> Enum.map(fn {_, i} ->
      Enum.at(chain_storage_nodes, i)
    end)
  end

  defp resolved_recipients(recipients, resolved_addresses) do
    Enum.reduce(recipients, [], fn r = %Recipient{address: address}, acc ->
      resolved = Map.get(resolved_addresses, address)
      [%Recipient{r | address: resolved} | acc]
    end)
    |> Enum.reverse()
  end
end
