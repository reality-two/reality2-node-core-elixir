defmodule TestSentants do
  use ExUnit.Case
  alias Reality2.Helpers.R2Process, as: R2Process

  # -------------------------------------------------------------------------------------------------------------------
  # Test functionality of Reality.Sentants
  # -------------------------------------------------------------------------------------------------------------------
  test "Test single sentant" do

    sentant_definition = """
    sentant:
      name: fred
      description: "This is a Sentant."
    """

    sentant_map = %{ name: "george" }

    {result, id} = Reality2.Sentants.create sentant_definition
    assert result == :ok
    assert id |> R2Process.whereis != nil

    result2 = Reality2.Sentants.sendto( %{ name: "fred" }, %{ command: "test", parameters: %{ } } )
    assert result2 == :ok

    {result3, id} = Reality2.Sentants.delete %{ name: "fred" }
    assert result3 == :ok
    assert id |> R2Process.whereis == nil

    {result4, id2} = Reality2.Sentants.create sentant_map
    assert result4 == :ok
    assert id2 |> R2Process.whereis != nil

    result5 = Reality2.Sentants.sendto( %{ id: id2 }, %{ command: "test", parameters: %{ } } )
    assert result5 == :ok

    {result6, id2} = Reality2.Sentants.delete %{ name: "george" }
    assert result6 == :ok
    assert id2 |> R2Process.whereis == nil

  end

  test "Test multiple sentants" do
    create_many_sentants("test", 20)

    process_array = Reality2.Sentants
    |> PartitionSupervisor.which_children
    |> count_processes

    assert check_non_zero(process_array)

    result =  Reality2.Sentants.sendto_all(%{:command => "test", :parameters => %{}})
    assert result == {:ok, 20}

    delete_many_sentants("test", 20)

    process_array = Reality2.Sentants
    |> PartitionSupervisor.which_children
    |> count_processes

    assert check_all_zero(process_array)
  end

  # -------------------------------------------------------------------------------------------------------------------



  # -------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -------------------------------------------------------------------------------------------------------------------
  # Check that that all the DynamicSupervisors have at least one child process.
  defp check_non_zero([]), do: true
  defp check_non_zero([{_, 0} | _]), do: false
  defp check_non_zero([{_, _} | tail]), do: check_non_zero(tail)

  # Check that that all the DynamicSupervisors have no child processes.
  defp check_all_zero([]), do: true
  defp check_all_zero([{_, 0} | _]), do: true
  defp check_all_zero([{_, _} | tail]), do: check_all_zero(tail)

  # Create the given number of Sentants with the given name.
  defp create_many_sentants(name, num) do
    Enum.each(1..num, fn x ->
      sentant_definition = """
      sentant:
        name: #{name <> Integer.to_string(x)}
      """
      Reality2.Sentants.create(sentant_definition)
    end)
  end

  # Returns a list of tuples containing the DynamicSupervisor index and the number of child processes on that DynamicSupervisor.
  defp count_processes([]), do: []
  defp count_processes([{id, pid, _, _} | tail]) do
    %{active: num_children} = DynamicSupervisor.count_children(pid)
    [{id, num_children} | count_processes(tail)]
  end

  # Delete the given number of Sentants with the given name.
  defp delete_many_sentants(name, num) do
    Enum.each(1..num, fn x ->
      Reality2.Sentants.delete(%{:name => name <> Integer.to_string(x)})
    end)
  end
  # -------------------------------------------------------------------------------------------------------------------
end
