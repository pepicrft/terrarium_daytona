defmodule Terrarium.Providers.Daytona do
  @moduledoc """
  A Terrarium provider for [Daytona](https://daytona.io) sandbox environments.

  Creates and manages sandboxes using Daytona's REST API. Each sandbox is a
  containerized environment that supports command execution and file operations.

  ## Configuration

      config :terrarium,
        providers: [
          daytona: {Terrarium.Providers.Daytona,
            api_key: System.fetch_env!("DAYTONA_API_KEY")
          }
        ]

  ## Options

  - `:api_key` - (required) Daytona API key
  - `:api_url` - base URL for the Daytona API (default: `"https://app.daytona.io/api"`)
  - `:toolbox_url` - base URL for the toolbox proxy (default: `"https://proxy.app.daytona.io/toolbox"`)
  - `:organization_id` - Daytona organization ID (optional)
  - `:target` - target region (optional)
  - `:snapshot` - base image or snapshot (optional)
  - `:class` - sandbox class (optional)
  - `:cpu` - number of vCPUs (optional)
  - `:memory` - memory in GB (optional)
  - `:disk` - disk in GB (optional)
  - `:user` - sandbox user (default: `"daytona"`)
  - `:env` - environment variables map (optional)
  - `:auto_stop_interval` - minutes before auto-stop (optional)
  - `:poll_interval` - milliseconds between status polls during creation (default: `1000`)
  - `:create_timeout` - maximum milliseconds to wait for sandbox to start (default: `120_000`)
  - `:ssh_gateway_host` - SSH gateway hostname (default: `"ssh.app.daytona.io"`)
  - `:ssh_gateway_port` - SSH gateway port (default: `2222`)
  - `:ssh_token_expires` - SSH token expiry in minutes (default: `60`)
  """

  use Terrarium.Provider

  @telemetry_prefix [:terrarium, :daytona]

  @default_api_url "https://app.daytona.io/api"
  @default_toolbox_url "https://proxy.app.daytona.io/toolbox"
  @default_poll_interval 1_000
  @default_create_timeout 120_000
  @default_exec_timeout 120_000
  @default_ssh_gateway_host "ssh.app.daytona.io"
  @default_ssh_gateway_port 2222
  @default_ssh_token_expires 60

  @impl true
  def create(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    api_url = Keyword.get(opts, :api_url, @default_api_url)
    toolbox_url = Keyword.get(opts, :toolbox_url, @default_toolbox_url)
    organization_id = Keyword.get(opts, :organization_id)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    create_timeout = Keyword.get(opts, :create_timeout, @default_create_timeout)
    ssh_gateway_host = Keyword.get(opts, :ssh_gateway_host, @default_ssh_gateway_host)
    ssh_gateway_port = Keyword.get(opts, :ssh_gateway_port, @default_ssh_gateway_port)
    ssh_token_expires = Keyword.get(opts, :ssh_token_expires, @default_ssh_token_expires)

    body =
      %{}
      |> put_if(:snapshot, Keyword.get(opts, :snapshot))
      |> put_if(:target, Keyword.get(opts, :target))
      |> put_if(:class, Keyword.get(opts, :class))
      |> put_if(:cpu, Keyword.get(opts, :cpu))
      |> put_if(:memory, Keyword.get(opts, :memory))
      |> put_if(:disk, Keyword.get(opts, :disk))
      |> put_if(:user, Keyword.get(opts, :user))
      |> put_if(:env, Keyword.get(opts, :env))
      |> put_if(:autoStopInterval, Keyword.get(opts, :auto_stop_interval))

    case api_request(:post, "#{api_url}/sandbox", api_key, organization_id, json: body) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        sandbox_id = resp["id"]

        state = %{
          "api_key" => api_key,
          "api_url" => api_url,
          "toolbox_url" => toolbox_url,
          "organization_id" => organization_id,
          "sandbox_id" => sandbox_id,
          "ssh_gateway_host" => ssh_gateway_host,
          "ssh_gateway_port" => ssh_gateway_port,
          "ssh_token_expires" => ssh_token_expires
        }

        sandbox = %Terrarium.Sandbox{
          id: sandbox_id,
          provider: __MODULE__,
          state: state
        }

        wait_for_started(sandbox, poll_interval, create_timeout)

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def destroy(%Terrarium.Sandbox{state: state}) do
    %{"api_key" => api_key, "api_url" => api_url, "sandbox_id" => sandbox_id} = state
    organization_id = state["organization_id"]

    case api_request(:delete, "#{api_url}/sandbox/#{sandbox_id}", api_key, organization_id) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:api_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def status(%Terrarium.Sandbox{state: state}) do
    %{"api_key" => api_key, "api_url" => api_url, "sandbox_id" => sandbox_id} = state
    organization_id = state["organization_id"]

    case api_request(:get, "#{api_url}/sandbox/#{sandbox_id}", api_key, organization_id) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        map_status(resp["state"])

      _other ->
        :error
    end
  end

  @impl true
  def reconnect(%Terrarium.Sandbox{} = sandbox) do
    case status(sandbox) do
      :running -> {:ok, sandbox}
      :creating -> {:ok, sandbox}
      :stopped -> {:error, :stopped}
      :destroyed -> {:error, :not_found}
      :error -> {:error, :error}
    end
  end

  @impl true
  def exec(sandbox, command, opts \\ [])

  def exec(%Terrarium.Sandbox{state: state}, command, opts) do
    %{"api_key" => api_key, "toolbox_url" => toolbox_url, "sandbox_id" => sandbox_id} = state
    organization_id = state["organization_id"]

    timeout = Keyword.get(opts, :timeout, @default_exec_timeout)
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env, %{})

    body =
      %{command: command, timeout: div(timeout, 1000)}
      |> put_if(:cwd, cwd)
      |> then(fn b -> if env == %{}, do: b, else: Map.put(b, :env, env) end)

    url = "#{toolbox_url}/#{sandbox_id}/process/execute"

    case api_request(:post, url, api_key, organization_id, json: body, receive_timeout: timeout) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        {:ok,
         %Terrarium.Process.Result{
           exit_code: resp["exitCode"] || 0,
           stdout: resp["stdout"] || "",
           stderr: resp["stderr"] || ""
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def read_file(%Terrarium.Sandbox{state: state}, path) do
    %{"api_key" => api_key, "toolbox_url" => toolbox_url, "sandbox_id" => sandbox_id} = state
    organization_id = state["organization_id"]

    url = "#{toolbox_url}/#{sandbox_id}/files/download?path=#{URI.encode(path)}"

    case api_request(:get, url, api_key, organization_id, raw: true) do
      {:ok, %{status: status, body: content}} when status in 200..299 ->
        {:ok, content}

      {:ok, %{status: 404}} ->
        {:error, :enoent}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def write_file(%Terrarium.Sandbox{state: state}, path, content) do
    %{"api_key" => api_key, "toolbox_url" => toolbox_url, "sandbox_id" => sandbox_id} = state
    organization_id = state["organization_id"]

    url = "#{toolbox_url}/#{sandbox_id}/files/upload?path=#{URI.encode(path)}"

    case api_request(:post, url, api_key, organization_id, body: content) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:api_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def ls(%Terrarium.Sandbox{state: state}, path) do
    %{"api_key" => api_key, "toolbox_url" => toolbox_url, "sandbox_id" => sandbox_id} = state
    organization_id = state["organization_id"]

    url = "#{toolbox_url}/#{sandbox_id}/files?path=#{URI.encode(path)}"

    case api_request(:get, url, api_key, organization_id) do
      {:ok, %{status: status, body: entries}} when status in 200..299 and is_list(entries) ->
        names =
          entries
          |> Enum.map(& &1["name"])
          |> Enum.reject(&(&1 in [".", ".."]))
          |> Enum.sort()

        {:ok, names}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def ssh_opts(%Terrarium.Sandbox{state: state}) do
    %{
      "api_key" => api_key,
      "api_url" => api_url,
      "sandbox_id" => sandbox_id,
      "organization_id" => organization_id,
      "ssh_gateway_host" => host,
      "ssh_gateway_port" => port,
      "ssh_token_expires" => expires
    } = state

    url = "#{api_url}/sandbox/#{sandbox_id}/ssh-access?expiresInMinutes=#{expires}"

    case api_request(:post, url, api_key, organization_id) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        {:ok, [host: host, port: port, user: resp["token"], auth: nil]}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Private helpers -------------------------------------------------------

  defp api_request(method, url, api_key, organization_id, opts \\ []) do
    {raw, opts} = Keyword.pop(opts, :raw, false)

    headers = [{"authorization", "Bearer #{api_key}"}]
    headers = if organization_id, do: [{"x-daytona-organization-id", organization_id} | headers], else: headers

    req_opts =
      [method: method, url: url, headers: headers]
      |> then(fn base -> if raw, do: Keyword.put(base, :decode_body, false), else: base end)
      |> Keyword.merge(opts)

    metadata = %{method: method, url: url}

    :telemetry.span(@telemetry_prefix ++ [:api_request], metadata, fn ->
      result = Req.request(req_opts)

      stop_metadata =
        case result do
          {:ok, %{status: status}} -> %{status: status}
          {:error, reason} -> %{error: reason}
        end

      {result, Map.merge(metadata, stop_metadata)}
    end)
  end

  defp wait_for_started(sandbox, _poll_interval, timeout) when timeout <= 0 do
    destroy(sandbox)
    {:error, :create_timeout}
  end

  defp wait_for_started(sandbox, poll_interval, timeout) do
    :telemetry.execute(@telemetry_prefix ++ [:poll], %{remaining_timeout: timeout}, %{
      sandbox_id: sandbox.id,
      poll_interval: poll_interval
    })

    case status(sandbox) do
      :running ->
        {:ok, sandbox}

      :creating ->
        Process.sleep(poll_interval)
        wait_for_started(sandbox, poll_interval, timeout - poll_interval)

      :error ->
        destroy(sandbox)
        {:error, :sandbox_failed}

      other ->
        destroy(sandbox)
        {:error, {:unexpected_status, other}}
    end
  end

  defp map_status("started"), do: :running

  defp map_status(s) when s in ~w(creating starting restoring pulling_snapshot building_snapshot pending_build),
    do: :creating

  defp map_status(s) when s in ~w(stopped archived stopping archiving resizing), do: :stopped
  defp map_status(s) when s in ~w(destroyed destroying), do: :destroyed
  defp map_status(_), do: :error

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
