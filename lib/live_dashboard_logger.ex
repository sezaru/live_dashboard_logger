defmodule LiveDashboardLogger.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Phoenix.LiveDashboard.PageBuilder

  def on_mount(:default, _params, _session, socket) do
    {:cont, PageBuilder.register_after_opening_head_tag(socket, &after_opening_head_tag/1)}
  end

  defp after_opening_head_tag(assigns) do
    ~H"""
    <script nonce={@csp_nonces[:script]}>
      const ANSI_COLORS = {
        30: '#4e4e4e', 31: '#ff5f57', 32: '#57bc6a', 33: '#f3be4c',
        34: '#648fff', 35: '#c57bdb', 36: '#5ecfcf', 37: '#d0d0d0',
        90: '#767676', 91: '#ff8c82', 92: '#7dd87d', 93: '#ffd580',
        94: '#82a9ff', 95: '#d98cff', 96: '#73e2e2', 97: '#ffffff'
      };
      const ANSI_BG = {
        40: '#4e4e4e', 41: '#ff5f57', 42: '#57bc6a', 43: '#f3be4c',
        44: '#648fff', 45: '#c57bdb', 46: '#5ecfcf', 47: '#d0d0d0',
        100: '#767676', 101: '#ff8c82', 102: '#7dd87d', 103: '#ffd580',
        104: '#82a9ff', 105: '#d98cff', 106: '#73e2e2', 107: '#ffffff'
      };

      function ansiToHtml(text) {
        let result = '';
        let openSpans = 0;
        const re = /\x1b\[([0-9;]*)m/g;
        let last = 0, match;
        let bold = false, fg = null, bg = null;

        const flush = (raw) => { result += raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); };
        const applyStyle = () => {
          const parts = [];
          if (bold) parts.push('font-weight:bold');
          if (fg) parts.push(`color:${fg}`);
          if (bg) parts.push(`background:${bg}`);
          if (parts.length) { result += `<span style="${parts.join(';')}">`;  openSpans++; }
        };

        while ((match = re.exec(text)) !== null) {
          flush(text.slice(last, match.index));
          last = match.index + match[0].length;
          const codes = match[1] === '' ? [0] : match[1].split(';').map(Number);
          let i = 0;
          while (i < codes.length) {
            const c = codes[i];
            if (c === 0) {
              for (let s = 0; s < openSpans; s++) result += '</span>';
              openSpans = 0; bold = false; fg = null; bg = null;
            } else if (c === 1) {
              bold = true;
            } else if (c >= 30 && c <= 37) {
              fg = ANSI_COLORS[c];
            } else if (c >= 40 && c <= 47) {
              bg = ANSI_BG[c];
            } else if (c >= 90 && c <= 97) {
              fg = ANSI_COLORS[c];
            } else if (c >= 100 && c <= 107) {
              bg = ANSI_BG[c];
            } else if ((c === 38 || c === 48) && codes[i+1] === 5 && codes[i+2] !== undefined) {
              i += 2;
            }
            i++;
          }
          applyStyle();
        }
        flush(text.slice(last));
        for (let s = 0; s < openSpans; s++) result += '</span>';
        return result;
      }

      function processLogEntry(el) {
        if (el.dataset.ansiProcessed) return;
        el.dataset.ansiProcessed = '1';
        el.innerHTML = ansiToHtml(el.textContent);
      }

      window.LiveDashboard.registerCustomHooks({
        ScrollHook: {
          mounted() {
            const messages = this.el.querySelector('#logger-messages');
            this._observer = new MutationObserver((mutations) => {
              for (const m of mutations) {
                for (const node of m.addedNodes) {
                  if (node.nodeType === 1) processLogEntry(node);
                }
              }
              if (this.el.querySelector('.logger-autoscroll-checkbox').checked) {
                messages.scrollTop = messages.scrollHeight;
              }
              if (this._applyFilters) this._applyFilters();
            });
            this._observer.observe(messages, { childList: true });

            const filter = this.el.querySelector('.logger-filter-input');
            const levelFilter = this.el.querySelector('.logger-level-filter');
            const applyFilters = () => {
              const text = filter ? filter.value.toLowerCase() : '';
              const level = levelFilter ? levelFilter.value : '';
              for (const pre of messages.querySelectorAll('pre')) {
                const matchText = !text || pre.textContent.toLowerCase().includes(text);
                const matchLevel = !level || pre.classList.contains(`log-level-${level}`);
                pre.style.display = (matchText && matchLevel) ? '' : 'none';
              }
            };
            if (filter) filter.addEventListener('input', applyFilters);
            if (levelFilter) levelFilter.addEventListener('change', applyFilters);
            this._applyFilters = applyFilters;
          },
          destroyed() {
            if (this._observer) this._observer.disconnect();
          }
        }
      })
    </script>
    <style>
      .logger-wrap pre { white-space: pre-wrap !important; }

      #logger-messages pre { margin: 0; font-size: 0.82rem; line-height: 1.4; background: transparent !important; }

      .log-level-debug   { color: #8fbcbb; }
      .log-level-info    { color: #a3be8c; }
      .log-level-warning { color: #ebcb8b; }
      .log-level-error   { color: #bf616a; }
      .log-level-notice  { color: #88c0d0; }
      .log-level-critical, .log-level-alert, .log-level-emergency {
        color: #ff5f57; font-weight: bold;
      }
    </style>
    """
  end
end

defmodule LiveDashboardLogger do
  @moduledoc """
  Logs Page for Live Dashboard

  ## Add LiveDashboardLogger to Phoenix Live Dashboard

  To add LiveDashboardLogger to Phoenix Live Dashboard, simply include it in the `additional_pages`
  list of `live_dashboard` route macro.

  ### Example

  ```elixir
  live_dashboard "/dashboard",
    metrics: LoggertestWeb.Telemetry,
    additional_pages: [
      # Add this line
      live_logs: LiveDashboardLogger
    ],
    on_mount: [
      LiveDashboardLogger.Hooks
    ]
  ```

  ### CloudWatch support

  To enable the CloudWatch tab, configure the log group in your app config:

  ```elixir
  config :live_dashboard_logger, cloudwatch_log_group: "/my-app/production"
  ```

  Then the "Live Logs" menu item should appear in your dashboard.
  """
  use Phoenix.LiveDashboard.PageBuilder

  alias LiveDashboardLogger.CloudWatch
  alias LiveDashboardLogger.Log
  alias LiveDashboardLogger.PubSub

  @log_format Logger.Formatter.compile("$time [$level] $message")

  def render(assigns) do
    ~H"""
    <div class="logs-card" data-messages-present="true">
      <h5 class="card-title">Live Logs</h5>

      <div class="card mb-4" id="logger-messages-card" phx-hook="ScrollHook">
        <div class="card-body">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <div class="btn-group" role="group">
              <button
                phx-click="switch_source"
                phx-value-source="backend"
                class={"btn btn-sm #{if @source == :backend, do: "btn-primary", else: "btn-outline-secondary"}"}
              >
                Backend
              </button>
              <button
                phx-click="switch_source"
                phx-value-source="cloudwatch"
                class={"btn btn-sm #{if @source == :cloudwatch, do: "btn-primary", else: "btn-outline-secondary"}"}
                disabled={not @cloudwatch_configured}
                title={if not @cloudwatch_configured, do: "Set :live_dashboard_logger, :cloudwatch_log_group to enable"}
              >
                CloudWatch
              </button>
            </div>
            <%= if @source == :cloudwatch && @cw_loading do %>
              <small class="text-muted">Loading history...</small>
            <% end %>
          </div>
          <div class="d-flex gap-2 mb-2 align-items-center">
            <input
              type="text"
              class="form-control form-control-sm logger-filter-input"
              placeholder="Filter logs..."
              style="max-width: 320px;"
            />
            <select class="form-select form-select-sm logger-level-filter" style="max-width: 140px;">
              <option value="">All levels</option>
              <option value="debug">debug</option>
              <option value="info">info</option>
              <option value="notice">notice</option>
              <option value="warning">warning</option>
              <option value="error">error</option>
              <option value="critical">critical</option>
              <option value="alert">alert</option>
              <option value="emergency">emergency</option>
            </select>
          </div>
          <div
            id="logger-messages"
            style="height: calc(100vh - 500px); overflow-y: auto; background: #1e1e2e; padding: 0.5rem; border-radius: 4px;"
            class={if(@text_wrap_enabled, do: "logger-wrap")}
            phx-update="stream"
          >
            <%= for {id, %Log{level: level} = log} <- @streams.logs do %>
              <pre id={id} class={"log-level-#{level}"}>{format_log(log)}</pre>
            <% end %>
          </div>
          <div class="d-flex gap-3 justify-content-end mt-2">
            <label class="d-flex align-items-center gap-1 mb-0">
              Wrap
              <input phx-click="toggle_text_wrap" checked={@text_wrap_enabled} type="checkbox" />
            </label>
            <label class="d-flex align-items-center gap-1 mb-0">
              Autoscroll
              <input
                phx-click="toggle_autoscroll"
                checked={@autoscroll_enabled}
                class="logger-autoscroll-checkbox"
                type="checkbox"
              />
            </label>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    topic = Base.encode16(:rand.bytes(20))

    if connected?(socket) do
      endpoint = socket.endpoint
      pubsub_server = endpoint.config(:pubsub_server) || endpoint.__pubsub_server__()
      :ok = PubSub.subscribe_logs(pubsub_server, topic)

      LiveDashboardLogger.Backend.add_to_all_nodes(pubsub_server, topic)
    end

    socket =
      socket
      |> assign(
        autoscroll_enabled: true,
        text_wrap_enabled: true,
        topic: topic,
        source: :backend,
        cloudwatch_configured: CloudWatch.configured?(),
        cw_loading: false,
        cw_timer_ref: nil,
        cw_last_timestamp: nil
      )
      |> stream(:logs, [])

    {:ok, socket}
  end

  def handle_event("switch_source", %{"source" => "cloudwatch"}, socket) do
    start_time = System.os_time(:millisecond)
    pid = self()

    Task.start(fn -> send(pid, {:cloudwatch_history, CloudWatch.fetch_history()}) end)

    timer_ref = Process.send_after(self(), :poll_cloudwatch, CloudWatch.poll_interval())

    socket =
      socket
      |> stream(:logs, [], reset: true)
      |> assign(
        source: :cloudwatch,
        cw_loading: true,
        cw_timer_ref: timer_ref,
        cw_last_timestamp: start_time
      )

    {:noreply, socket}
  end

  def handle_event("switch_source", %{"source" => "backend"}, socket) do
    if socket.assigns.cw_timer_ref, do: Process.cancel_timer(socket.assigns.cw_timer_ref)

    socket =
      socket
      |> stream(:logs, [], reset: true)
      |> assign(source: :backend, cw_loading: false, cw_timer_ref: nil, cw_last_timestamp: nil)

    {:noreply, socket}
  end

  def handle_event("toggle_autoscroll", _params, socket) do
    {:noreply, assign(socket, :autoscroll_enabled, !socket.assigns.autoscroll_enabled)}
  end

  def handle_event("toggle_text_wrap", _params, socket) do
    {:noreply, assign(socket, :text_wrap_enabled, !socket.assigns.text_wrap_enabled)}
  end

  def handle_info({:cloudwatch_history, logs}, socket) do
    socket =
      logs
      |> Enum.reduce(socket, fn log, acc -> stream_insert(acc, :logs, log) end)
      |> assign(cw_loading: false)

    {:noreply, socket}
  end

  def handle_info({:cloudwatch_poll_result, logs, timestamp}, %{assigns: %{source: :cloudwatch}} = socket) do
    socket =
      logs
      |> Enum.reduce(socket, fn log, acc -> stream_insert(acc, :logs, log) end)
      |> assign(cw_last_timestamp: timestamp)

    {:noreply, socket}
  end

  def handle_info({:cloudwatch_poll_result, _logs, _timestamp}, socket), do: {:noreply, socket}

  def handle_info(:poll_cloudwatch, %{assigns: %{source: :cloudwatch}} = socket) do
    last_ts = socket.assigns.cw_last_timestamp
    now = System.os_time(:millisecond)
    pid = self()

    Task.start(fn -> send(pid, {:cloudwatch_poll_result, CloudWatch.fetch_since(last_ts), now}) end)

    timer_ref = Process.send_after(self(), :poll_cloudwatch, CloudWatch.poll_interval())

    {:noreply, assign(socket, cw_timer_ref: timer_ref)}
  end

  def handle_info(:poll_cloudwatch, socket), do: {:noreply, socket}

  def handle_info({:log, %Log{} = log}, %{assigns: %{source: :backend}} = socket) do
    {:noreply, stream_insert(socket, :logs, log)}
  end

  def handle_info({:log, %Log{}}, socket), do: {:noreply, socket}

  def menu_link(_, _) do
    {:ok, "Live Logs"}
  end

  defp format_log(%Log{node: :cloudwatch, message: message}), do: message

  defp format_log(%Log{} = log) do
    Logger.Formatter.format(@log_format, log.level, log.message, log.timestamp, log.metadata)
  end
end
