# TerrariumDaytona

[![Hex.pm](https://img.shields.io/hexpm/v/terrarium_daytona.svg)](https://hex.pm/packages/terrarium_daytona)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/terrarium_daytona)
[![CI](https://github.com/pepicrft/terrarium_daytona/actions/workflows/terrarium_daytona.yml/badge.svg)](https://github.com/pepicrft/terrarium_daytona/actions/workflows/terrarium_daytona.yml)

A [Daytona](https://daytona.io) provider for [Terrarium](https://github.com/pepicrft/terrarium) sandbox environments.

## Installation

Add `terrarium_daytona` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:terrarium, "~> 0.7.3"},
    {:terrarium_daytona, "~> 0.4.0"}
  ]
end
```

## Configuration

```elixir
# config/runtime.exs
config :terrarium,
  default: :daytona,
  providers: [
    daytona: {Terrarium.Providers.Daytona,
      api_key: System.fetch_env!("DAYTONA_API_KEY")
    }
  ]
```

### Options

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
- `:name` - human-readable name for the sandbox (stored locally, not sent to Daytona)
- `:auto_stop_interval` - minutes before auto-stop (optional)
- `:poll_interval` - milliseconds between status polls during creation (default: `1000`)
- `:create_timeout` - maximum milliseconds to wait for sandbox to start (default: `120_000`)
- `:ssh_gateway_host` - SSH gateway hostname (default: `"ssh.app.daytona.io"`)
- `:ssh_gateway_port` - SSH gateway port (default: `2222`)
- `:ssh_token_expires` - SSH token expiry in minutes (default: `60`)

## Usage

```elixir
# Create a sandbox using the configured default
{:ok, sandbox} = Terrarium.create(image: "debian:12")

# Or specify the provider explicitly
{:ok, sandbox} = Terrarium.create(:daytona, snapshot: "ubuntu-4vcpu-8ram-100gb")

# Execute commands
{:ok, result} = Terrarium.exec(sandbox, "echo hello")
IO.puts(result.stdout)

# File operations
:ok = Terrarium.write_file(sandbox, "/home/daytona/hello.txt", "Hello from Terrarium!")
{:ok, content} = Terrarium.read_file(sandbox, "/home/daytona/hello.txt")

# Replicate the current BEAM app into the sandbox over SSH
{:ok, peer_pid, remote_node} = Terrarium.replicate(sandbox, name: :daytona_replica)

# Clean up
:ok = Terrarium.stop_replica(peer_pid)
:ok = Terrarium.destroy(sandbox)
```

## Telemetry

This provider emits the following [`:telemetry`](https://hex.pm/packages/telemetry) events, in addition to the generic events from `Terrarium.Telemetry`:

| Event | Measurements | Metadata |
|---|---|---|
| `[:terrarium, :daytona, :api_request, :start]` | `%{system_time: integer}` | `%{method: atom, url: String.t()}` |
| `[:terrarium, :daytona, :api_request, :stop]` | `%{duration: integer}` | `%{method: atom, url: String.t(), status: integer}` (success) or `%{method: atom, url: String.t(), error: term()}` (failure) |
| `[:terrarium, :daytona, :api_request, :exception]` | `%{duration: integer}` | `%{method: atom, url: String.t()}` |
| `[:terrarium, :daytona, :poll]` | `%{remaining_timeout: integer}` | `%{sandbox_id: String.t(), poll_interval: integer}` |

### Example

```elixir
:telemetry.attach_many(
  "daytona-logger",
  [
    [:terrarium, :daytona, :api_request, :stop],
    [:terrarium, :daytona, :poll]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info("#{inspect(event)}: #{inspect(measurements)} #{inspect(metadata)}")
  end,
  nil
)
```

## License

This project is licensed under the [MIT License](LICENSE).
