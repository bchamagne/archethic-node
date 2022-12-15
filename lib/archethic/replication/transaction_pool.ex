defmodule Archethic.Replication.TransactionPool do
  @moduledoc false

  use GenServer

  require Logger

  alias Archethic.TransactionChain.Transaction

  def start_link(arg \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  def add_transaction(name \\ __MODULE__, tx = %Transaction{}) do
    GenServer.cast(name, {:add_transaction, tx})
  end

  def pop_transaction(name \\ __MODULE__, address) when is_binary(address) do
    GenServer.call(name, {:pop_transaction, address})
  end

  def init(arg) do
    clean_interval = Keyword.get(arg, :clean_interval, 5_000)
    timeout_duration = Keyword.get(arg, :timeout, 60_000)
    clean_ref = Process.send_after(self(), :clean, clean_interval)

    {:ok,
     %{
       timeout_duration: timeout_duration,
       clean_interval: clean_interval,
       clean_ref: clean_ref,
       transactions: %{}
     }}
  end

  def handle_cast(
        {:add_transaction, tx = %Transaction{address: address, type: type}},
        state = %{timeout_duration: timeout_duration}
      ) do
    timeout = DateTime.add(DateTime.utc_now(), timeout_duration, :millisecond)
    new_state = Map.update!(state, :transactions, &Map.put(&1, address, {tx, timeout}))

    Logger.info("Added in the transaction pool",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    {:noreply, new_state}
  end

  def handle_call({:pop_transaction, address}, _from, state = %{transactions: transactions}) do
    case Map.pop(transactions, address) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {{transaction, _}, rest_transactions} ->
        {:reply, {:ok, transaction}, %{state | transactions: rest_transactions}}
    end
  end

  def handle_info(:clean, state = %{clean_interval: clean_interval}) do
    clean_ref = Process.send_after(self(), :clean, clean_interval)

    new_state =
      state
      |> Map.update!(:transactions, fn transactions ->
        Enum.reject(transactions, fn {_, {_, timeout}} ->
          DateTime.compare(DateTime.utc_now(), timeout) in [:gt, :eq]
        end)
        |> Enum.into(%{})
      end)
      |> Map.put(:clean_ref, clean_ref)

    {:noreply, new_state}
  end
end