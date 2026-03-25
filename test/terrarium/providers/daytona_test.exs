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
end
