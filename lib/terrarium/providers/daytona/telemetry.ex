defmodule Terrarium.Providers.Daytona.Telemetry do
  @moduledoc """
  Telemetry events emitted by the Daytona provider.

  These events are specific to the Daytona provider implementation and
  complement the generic events emitted by `Terrarium.Telemetry`.

  ## Events

  ### `[:terrarium, :daytona, :api_request, :start]`

  Emitted before each Daytona API HTTP request.

  - Measurements: `%{system_time: integer}`
  - Metadata: `%{method: atom, url: String.t()}`

  ### `[:terrarium, :daytona, :api_request, :stop]`

  Emitted after a Daytona API HTTP request completes.

  - Measurements: `%{duration: integer}`
  - Metadata: `%{method: atom, url: String.t(), status: integer}` on success,
    or `%{method: atom, url: String.t(), error: term()}` on failure

  ### `[:terrarium, :daytona, :api_request, :exception]`

  Emitted when a Daytona API HTTP request raises an exception.

  - Measurements: `%{duration: integer}`
  - Metadata: `%{method: atom, url: String.t()}`

  ### `[:terrarium, :daytona, :poll]`

  Emitted on each poll iteration while waiting for a sandbox to start.

  - Measurements: `%{remaining_timeout: integer}`
  - Metadata: `%{sandbox_id: String.t(), poll_interval: integer}`

  ## Example

      :telemetry.attach_many(
        "daytona-logger",
        [
          [:terrarium, :daytona, :api_request, :stop],
          [:terrarium, :daytona, :poll]
        ],
        fn event, measurements, metadata, _config ->
          Logger.info("\#{inspect(event)}: \#{inspect(measurements)} \#{inspect(metadata)}")
        end,
        nil
      )
  """
end
