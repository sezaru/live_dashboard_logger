defmodule LiveDashboardLogger.Log do
  @moduledoc """
  Simple Log struct
  """

  defstruct [:id, :message, :timestamp, :level, :node, metadata: []]

  @type t :: %__MODULE__{
          message: String.t(),
          timestamp: timestamp(),
          level: Logger.level(),
          metadata: Keyword.t(),
          node: node()
        }

  @type timestamp :: {{1970..9999, 1..12, 1..31}, {0..23, 0..59, 0..59, 0..999}}

  def new(level, message, timestamp, metadata \\ [], node \\ node()) do
    log =
      %__MODULE__{
        id: nil,
        level: level,
        message: message,
        timestamp: timestamp,
        metadata: metadata,
        node: node
      }

    id = :erlang.phash2(log, 4_294_967_296)

    %__MODULE__{log | id: id}
  end

  def from_cloudwatch_event(%{"timestamp" => ts_ms, "message" => message}) do
    log =
      %__MODULE__{
        id: nil,
        level: parse_level(message),
        message: String.trim_trailing(message),
        timestamp: ms_to_timestamp(ts_ms),
        metadata: [],
        node: :cloudwatch
      }

    %__MODULE__{log | id: :erlang.phash2(log, 4_294_967_296)}
  end

  defp ms_to_timestamp(ms) do
    seconds = div(ms, 1000)
    ms_rem = rem(ms, 1000)
    {{year, month, day}, {hour, min, sec}} = :calendar.system_time_to_universal_time(seconds, :second)

    {{year, month, day}, {hour, min, sec, ms_rem}}
  end

  defp parse_level(message) do
    cond do
      message =~ "[emergency]" -> :emergency
      message =~ "[alert]" -> :alert
      message =~ "[critical]" -> :critical
      message =~ "[error]" -> :error
      message =~ "[warning]" -> :warning
      message =~ "[notice]" -> :notice
      message =~ "[info]" -> :info
      message =~ "[debug]" -> :debug
      true -> :info
    end
  end
end
