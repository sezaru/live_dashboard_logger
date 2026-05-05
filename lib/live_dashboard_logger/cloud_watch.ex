defmodule LiveDashboardLogger.CloudWatch do
  @moduledoc false

  alias LiveDashboardLogger.Log

  @poll_interval 5_000
  @history_minutes 30

  def poll_interval, do: @poll_interval

  def log_group, do: Application.get_env(:live_dashboard_logger, :cloudwatch_log_group)

  def configured?, do: not is_nil(log_group())

  def fetch_history do
    start_time = System.os_time(:millisecond) - @history_minutes * 60 * 1_000

    fetch_events(start_time: start_time)
  end

  def fetch_since(start_time_ms) do
    fetch_events(start_time: start_time_ms)
  end

  def fetch_range(from_ms, to_ms) do
    fetch_events(start_time: from_ms, end_time: to_ms)
  end

  defp fetch_events(opts) do
    result =
      log_group()
      |> ExAws.CloudWatchLogs.filter_log_events(opts)
      |> ExAws.request()

    case result do
      {:ok, %{"events" => events}} ->
        events
        |> Enum.sort_by(& &1["timestamp"])
        |> Enum.map(&Log.from_cloudwatch_event/1)

      {:ok, response} ->
        require Logger
        Logger.warning("[LiveDashboardLogger] Unexpected CloudWatch response: #{inspect(response)}")
        []

      {:error, reason} ->
        require Logger
        Logger.error("[LiveDashboardLogger] CloudWatch fetch failed: #{inspect(reason)}")
        []
    end
  end
end
