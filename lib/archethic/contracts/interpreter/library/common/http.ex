defmodule Archethic.Contracts.Interpreter.Library.Common.Http do
  @moduledoc """
  Http client for the Smart Contracts.
  Implements AEIP-20.

  Mint library is processless so in order to not mess with
  other processes, we use it from inside a Task.
  """

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.TaskSupervisor

  @behaviour Library
  @threshold 256 * 1024

  def fetch(uri) do
    task =
      Task.Supervisor.async_nolink(
        TaskSupervisor,
        fn -> do_fetch(uri) end
      )

    case Task.yield(task, 2_000) || Task.shutdown(task) do
      {:ok, {:ok, reply}} ->
        reply

      {:ok, {:error, :threshold_reached}} ->
        raise Library.Error, message: "Http.fetch/1 response is bigger than threshold"

      {:ok, {:error, _}} ->
        # Mint.HTTP.connect error
        # Mint.HTTP.stream error
        raise Library.Error, message: "Http.fetch/1 failed"

      {:ok, {:error, _, _}} ->
        # Mint.HTTP.request error
        raise Library.Error, message: "Http.fetch/1 failed"

      nil ->
        # Task.shutdown
        raise Library.Error, message: "Http.fetch/1 timed out for url: #{uri}"
    end
  end

  def fetch_many(uris) do
    uris_count = length(uris)

    if uris_count > 5 do
      raise Library.Error, message: "Http.fetch_many/1 was called with too many urls"
    else
      Task.Supervisor.async_stream_nolink(
        TaskSupervisor,
        uris,
        &fetch/1,
        ordered: true,
        max_concurrency: 5
      )
      |> Enum.to_list()
      # count the number of bytes to be able to send a error too large
      # this is sub optimal because miners might still download threshold N times before returning the error
      # TODO: improve this
      |> Enum.reduce({0, []}, fn
        {:exit, {e, _stacktrace}}, _ ->
          # if any fetch/1 raised, we raise
          raise Library.Error, message: e.message

        {:ok, map}, {bytes_acc, result_acc} ->
          bytes =
            case map["body"] do
              nil -> 0
              body -> byte_size(body)
            end

          {bytes_acc + bytes, result_acc ++ [map]}
      end)
      |> then(fn {bytes_total, result} ->
        if bytes_total > @threshold do
          raise Library.Error,
            message: "Http.fetch_many/1 sum of responses is bigger than threshold"
        else
          result
        end
      end)
    end
  end

  def check_types(:fetch, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(:fetch_many, [first]) do
    AST.is_list?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false

  defp do_fetch(url) do
    uri = URI.parse(url)

    # we use the transport_opts to be able to test (MIX_ENV=test) with self signed certificates
    conn_opts = [
      transport_opts:
        Application.get_env(:archethic, __MODULE__, [])
        |> Keyword.get(:transport_opts, [])
    ]

    with :ok <- check_scheme(uri.scheme),
         {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port, conn_opts),
         {:ok, conn, _} <- Mint.HTTP.request(conn, "GET", path(uri), [], nil),
         {:ok, %{body: body, status: status}} <- stream_response(conn) do
      {:ok, %{"status" => status, "body" => body}}
    end
  end

  defp check_scheme("https"), do: :ok
  defp check_scheme(_), do: {:error, :not_https}

  # copied over from Mint
  defp path(uri) do
    IO.iodata_to_binary([
      if(uri.path, do: uri.path, else: ["/"]),
      if(uri.query, do: ["?" | uri.query], else: []),
      if(uri.fragment, do: ["#" | uri.fragment], else: [])
    ])
  end

  defp stream_response(conn, acc0 \\ %{status: 0, data: [], done: false, bytes: 0}) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            acc2 =
              Enum.reduce(responses, acc0, fn
                {:status, _, status}, acc1 ->
                  %{acc1 | status: status}

                {:data, _, data}, acc1 ->
                  %{acc1 | data: acc1.data ++ [data], bytes: acc1.bytes + byte_size(data)}

                {:headers, _, _}, acc1 ->
                  acc1

                {:done, _}, acc1 ->
                  %{acc1 | done: true}
              end)

            cond do
              acc2.bytes > @threshold ->
                {:error, :threshold_reached}

              acc2.done ->
                {:ok, %{status: acc2.status, body: Enum.join(acc2.data)}}

              true ->
                stream_response(conn, acc2)
            end

          {:error, _, reason, _} ->
            {:error, reason}
        end
    end
  end
end
