defmodule ArchethicCache.LRU do
  @moduledoc """
  A cache that stores the values in an ETS table.
  There are hooks available to be able to add effects (ex: write to disk).

  It keeps track of the order and bytes in the genserver state.
  The `bytes_used` are tracked in here because if we just monitor ETS table size, we would not be able to have a disk cache.
  The `keys` are used to determine the Least Recent Used (first is the most recent used, last is the least recent used).

  We do not store the values directly in ETS but we insert a pair {size, value} instead.
  Because size can be modified with the hooks
  (ex: For LRUDisk, we discard the value from the ETS table, but still want to know the size written to disk)
  """

  @spec start_link(GenServer.name(), non_neg_integer(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def start_link(name, max_bytes, opts \\ []) do
    GenServer.start_link(__MODULE__, [name, max_bytes, opts], name: name)
  end

  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(server, key, value) do
    GenServer.cast(server, {:put, key, value})
  end

  @spec get(GenServer.server(), term()) :: nil | term()
  def get(server, key) do
    GenServer.call(server, {:get, key})
  end

  @spec purge(GenServer.server()) :: :ok
  def purge(server) do
    GenServer.call(server, :purge)
  end

  def init([name, max_bytes, opts]) do
    table = :ets.new(:"aecache_#{name}", [:set, {:read_concurrency, true}])

    {:ok,
     %{
       table: table,
       bytes_max: max_bytes,
       bytes_used: 0,
       keys: [],
       put_fn: Keyword.get(opts, :put_fn, fn _key, value -> value end),
       get_fn: Keyword.get(opts, :get_fn, fn _key, value -> value end),
       evict_fn: Keyword.get(opts, :evict_fn, fn _key, _value -> :ok end)
     }}
  end

  def handle_call({:get, key}, _from, state) do
    {reply, new_state} =
      case :ets.lookup(state.table, key) do
        [{^key, {_size, value}}] ->
          {
            state.get_fn.(key, value),
            %{state | keys: state.keys |> move_front(key)}
          }

        [] ->
          {nil, state}
      end

    {:reply, reply, new_state}
  end

  def handle_call(:purge, _from, state) do
    # we call the evict_fn to be able to clean effects (ex: file written to disk)
    :ets.tab2list(state.table)
    |> Enum.each(fn {key, {_size, value}} ->
      _ = state.evict_fn.(key, value)
    end)

    :ets.delete_all_objects(state.table)
    {:reply, :ok, %{state | keys: [], bytes_used: 0}}
  end

  def handle_cast({:put, key, value}, state) do
    size = :erlang.external_size(value)

    if size > state.bytes_max do
      {:noreply, state}
    else
      # maybe evict some keys to make space
      state =
        evict_until(state, fn state ->
          state.bytes_used + size <= state.bytes_max
        end)

      case :ets.lookup(state.table, key) do
        [] ->
          value_to_store = state.put_fn.(key, value)

          :ets.insert(state.table, {key, {size, value_to_store}})

          new_state = %{
            state
            | keys: [key | state.keys],
              bytes_used: state.bytes_used + size
          }

          {:noreply, new_state}

        [{^key, {old_size, old_value}}] ->
          # this is a replacement, we need to evict to update the bytes_used
          state.evict_fn.(key, old_value)
          value_to_store = state.put_fn.(key, value)

          :ets.insert(state.table, {key, {size, value_to_store}})

          new_state = %{
            state
            | keys: state.keys |> move_front(key),
              bytes_used: state.bytes_used + size - old_size
          }

          {:noreply, new_state}
      end
    end
  end

  defp evict_until(state, predicate) do
    if predicate.(state) do
      state
    else
      case List.last(state.keys) do
        nil ->
          state

        oldest_key ->
          [{_, {size, oldest_value}}] = :ets.take(state.table, oldest_key)
          state.evict_fn.(oldest_key, oldest_value)

          evict_until(
            %{
              state
              | bytes_used: state.bytes_used - size,
                keys: List.delete(state.keys, oldest_key)
            },
            predicate
          )
      end
    end
  end

  defp move_front(list, item) do
    [item | List.delete(list, item)]
  end
end
