defmodule TestAutomations do
  use ExUnit.Case
  alias Reality2.Helpers.R2Process, as: R2Process

  # -------------------------------------------------------------------------------------------------------------------
  # Test functionality of Reality.Sentants
  # -------------------------------------------------------------------------------------------------------------------
  test "Test automations" do

    sentant_map = %{ name: "george", description: "This is a test sentant.", automations: [ %{ name: "test", description: "This is a test automation." } ] }

    {result4, id2} = Reality2.Sentants.create sentant_map
    assert result4 == :ok
    assert id2 |> R2Process.whereis != nil

    {result1, _id3} = Reality2.Automations.create(id2, %{ name: "test", description: "This is a test automation." })
    assert result1 == :ok

  end

  # -------------------------------------------------------------------------------------------------------------------



  # -------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -------------------------------------------------------------------------------------------------------------------

  # -------------------------------------------------------------------------------------------------------------------
end
