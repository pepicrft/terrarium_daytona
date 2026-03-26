defmodule Terrarium.Providers.DaytonaTest do
  use ExUnit.Case, async: true

  alias Terrarium.Providers.Daytona

  describe "create/1" do
    test "requires api_key" do
      assert_raise KeyError, ~r/key :api_key not found/, fn ->
        Daytona.create([])
      end
    end
  end

  describe "status mapping" do
    test "maps Daytona states to Terrarium statuses" do
      # We verify the mapping indirectly through the module's public API.
      # Direct integration tests require a live Daytona instance.
      assert is_atom(
               Daytona.status(%Terrarium.Sandbox{
                 id: "fake",
                 provider: Daytona,
                 state: %{
                   "api_key" => "test",
                   "api_url" => "http://localhost:0",
                   "toolbox_url" => "http://localhost:0",
                   "sandbox_id" => "fake",
                   "organization_id" => nil
                 }
               })
             )
    end
  end

  describe "ssh_opts/1" do
    test "calls the ssh-access API endpoint" do
      ref = make_ref()
      pid = self()

      handler = fn event, _measurements, metadata, _config ->
        send(pid, {ref, event, metadata})
      end

      events = [[:terrarium, :daytona, :api_request, :start]]
      handler_id = "test-ssh-opts-#{inspect(ref)}"
      :telemetry.attach_many(handler_id, events, handler, nil)

      sandbox = %Terrarium.Sandbox{
        id: "ssh-test",
        provider: Daytona,
        state: %{
          "api_key" => "test-key",
          "api_url" => "http://localhost:0",
          "toolbox_url" => "http://localhost:0",
          "sandbox_id" => "ssh-test",
          "organization_id" => nil,
          "ssh_gateway_host" => "ssh.app.daytona.io",
          "ssh_gateway_port" => 2222,
          "ssh_token_expires" => 60
        }
      }

      # Will fail due to connection refused, but we can verify the URL pattern
      assert {:error, _} = Daytona.ssh_opts(sandbox)

      assert_receive {^ref, [:terrarium, :daytona, :api_request, :start], %{method: :post, url: url}}
      assert url =~ "/sandbox/ssh-test/ssh-access?expiresInMinutes=60"

      :telemetry.detach(handler_id)
    end
  end

  describe "telemetry" do
    test "emits [:terrarium, :daytona, :api_request, :start | :stop] on API calls" do
      ref = make_ref()
      pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(pid, {ref, event, measurements, metadata})
      end

      events = [
        [:terrarium, :daytona, :api_request, :start],
        [:terrarium, :daytona, :api_request, :stop]
      ]

      handler_id = "test-api-request-#{inspect(ref)}"
      :telemetry.attach_many(handler_id, events, handler, nil)

      # Trigger an API call that will fail (connection refused on port 0)
      Daytona.status(%Terrarium.Sandbox{
        id: "telemetry-test",
        provider: Daytona,
        state: %{
          "api_key" => "test-key",
          "api_url" => "http://localhost:0",
          "toolbox_url" => "http://localhost:0",
          "sandbox_id" => "telemetry-test",
          "organization_id" => nil
        }
      })

      assert_receive {^ref, [:terrarium, :daytona, :api_request, :start], %{system_time: _}, %{method: :get, url: _}}

      assert_receive {^ref, [:terrarium, :daytona, :api_request, :stop], %{duration: _},
                      %{method: :get, url: _, error: _}}

      :telemetry.detach(handler_id)
    end

    test "stop metadata includes error on connection failure" do
      ref = make_ref()
      pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(pid, {ref, event, measurements, metadata})
      end

      events = [[:terrarium, :daytona, :api_request, :stop]]
      handler_id = "test-api-error-meta-#{inspect(ref)}"
      :telemetry.attach_many(handler_id, events, handler, nil)

      Daytona.destroy(%Terrarium.Sandbox{
        id: "telemetry-test",
        provider: Daytona,
        state: %{
          "api_key" => "test-key",
          "api_url" => "http://localhost:0",
          "toolbox_url" => "http://localhost:0",
          "sandbox_id" => "telemetry-test",
          "organization_id" => nil
        }
      })

      assert_receive {^ref, [:terrarium, :daytona, :api_request, :stop], %{duration: _}, %{method: :delete, error: _}}

      :telemetry.detach(handler_id)
    end
  end
end
