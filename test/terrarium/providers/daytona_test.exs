defmodule Terrarium.Providers.DaytonaTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Terrarium.Providers.Daytona

  defp sandbox(overrides \\ %{}) do
    %Terrarium.Sandbox{
      id: "test-sandbox",
      provider: Daytona,
      state:
        Map.merge(
          %{
            "api_key" => "test-key",
            "api_url" => "https://api.example.com",
            "toolbox_url" => "https://toolbox.example.com",
            "sandbox_id" => "test-sandbox",
            "organization_id" => nil,
            "ssh_gateway_host" => "ssh.app.daytona.io",
            "ssh_gateway_port" => 2222,
            "ssh_token_expires" => 60
          },
          overrides
        )
    }
  end

  describe "create/1" do
    test "requires api_key" do
      assert_raise KeyError, ~r/key :api_key not found/, fn ->
        Daytona.create([])
      end
    end

    test "creates a sandbox and polls until started" do
      Req
      |> expect(:request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] =~ "/sandbox"
        {:ok, %Req.Response{status: 200, body: %{"id" => "sb-123"}}}
      end)
      |> expect(:request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] =~ "/sandbox/sb-123"
        {:ok, %Req.Response{status: 200, body: %{"state" => "started"}}}
      end)

      assert {:ok, %Terrarium.Sandbox{id: "sb-123"}} = Daytona.create(api_key: "key")
    end

    test "returns error on API failure" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "internal"}}}
      end)

      assert {:error, {:api_error, 500, _}} = Daytona.create(api_key: "key")
    end
  end

  describe "destroy/1" do
    test "deletes the sandbox" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :delete
        assert opts[:url] =~ "/sandbox/test-sandbox"
        {:ok, %Req.Response{status: 204, body: ""}}
      end)

      assert :ok = Daytona.destroy(sandbox())
    end
  end

  describe "status/1" do
    test "maps Daytona started state to :running" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 200, body: %{"state" => "started"}}}
      end)

      assert :running = Daytona.status(sandbox())
    end

    test "maps creating states" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 200, body: %{"state" => "creating"}}}
      end)

      assert :creating = Daytona.status(sandbox())
    end

    test "returns :error on connection failure" do
      expect(Req, :request, fn _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      assert :error = Daytona.status(sandbox())
    end
  end

  describe "exec/3" do
    test "executes a command and returns the result" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] =~ "/process/execute"
        {:ok, %Req.Response{status: 200, body: %{"exitCode" => 0, "result" => "hello\n"}}}
      end)

      assert {:ok, %Terrarium.Process.Result{exit_code: 0, stdout: "hello\n"}} =
               Daytona.exec(sandbox(), "echo hello")
    end
  end

  describe "read_file/2" do
    test "reads file content" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] =~ "/files/download"
        {:ok, %Req.Response{status: 200, body: "file content"}}
      end)

      assert {:ok, "file content"} = Daytona.read_file(sandbox(), "/app/test.txt")
    end

    test "returns :enoent for missing files" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 404, body: ""}}
      end)

      assert {:error, :enoent} = Daytona.read_file(sandbox(), "/missing.txt")
    end
  end

  describe "write_file/3" do
    test "uploads file content as multipart" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] =~ "/files/upload"

        assert [{:file, {_content, [filename: "test.txt", content_type: "application/octet-stream"]}}] =
                 opts[:form_multipart]

        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :ok = Daytona.write_file(sandbox(), "/app/test.txt", "content")
    end
  end

  describe "ls/2" do
    test "lists directory entries" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] =~ "/files?"
        {:ok, %Req.Response{status: 200, body: [%{"name" => "b.txt"}, %{"name" => "a.txt"}]}}
      end)

      assert {:ok, ["a.txt", "b.txt"]} = Daytona.ls(sandbox(), "/app")
    end
  end

  describe "ssh_opts/1" do
    test "creates an SSH access token and returns connection params" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] =~ "/sandbox/test-sandbox/ssh-access?expiresInMinutes=60"
        {:ok, %Req.Response{status: 200, body: %{"token" => "ssh-token-abc"}}}
      end)

      assert {:ok, opts} = Daytona.ssh_opts(sandbox())
      assert opts[:host] == "ssh.app.daytona.io"
      assert opts[:port] == 2222
      assert opts[:user] == "ssh-token-abc"
      assert opts[:auth] == nil
    end

    test "uses custom gateway settings" do
      expect(Req, :request, fn opts ->
        assert opts[:url] =~ "expiresInMinutes=30"
        {:ok, %Req.Response{status: 200, body: %{"token" => "tok"}}}
      end)

      sb =
        sandbox(%{
          "ssh_gateway_host" => "ssh.self-hosted.io",
          "ssh_gateway_port" => 3333,
          "ssh_token_expires" => 30
        })

      assert {:ok, opts} = Daytona.ssh_opts(sb)
      assert opts[:host] == "ssh.self-hosted.io"
      assert opts[:port] == 3333
    end

    test "returns error on API failure" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 403, body: %{"error" => "forbidden"}}}
      end)

      assert {:error, {:api_error, 403, _}} = Daytona.ssh_opts(sandbox())
    end
  end

  describe "reconnect/1" do
    test "succeeds when sandbox is running" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 200, body: %{"state" => "started"}}}
      end)

      sb = sandbox()
      assert {:ok, ^sb} = Daytona.reconnect(sb)
    end

    test "returns error when sandbox is stopped" do
      expect(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 200, body: %{"state" => "stopped"}}}
      end)

      assert {:error, :stopped} = Daytona.reconnect(sandbox())
    end
  end
end
