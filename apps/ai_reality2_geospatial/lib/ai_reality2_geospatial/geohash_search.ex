defmodule AiReality2Geospatial.GeohashSearch do
  # *******************************************************************************************************************************************
  @moduledoc """
    An optimised search algorithm for reducing the search time amongst the geospatal locations based on GeoHash.

    Each level of the tree is a character of the Geohash and the tree is up to 6 levels deep.  The goal is to reduce the number of Sentants to
    then have to refine the search on with actual distance calculation.  The leaves store the Sentant IDs
  """
  # *******************************************************************************************************************************************

    @doc false
    use GenServer, restart: :transient
    alias Reality2.Helpers.R2Process, as: R2Process


    # -----------------------------------------------------------------------------------------------------------------------------------------
    # GenServer callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(_),                                    do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

    @doc false
    def init(state),                                      do: {:ok, state}
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # GenServer callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def handle_call(%{command: "search", location: location, radius: radius}, _from, state) do
      {:reply, find(state, location, radius), state}
    end

    def handle_call(%{command: "store", location: location, sentantid: sentantid}, _from, state) do
      {:reply, nil, store(state, location, sentantid)}
    end

    def handle_call(%{command: "delete", sentantid: sentantid}, _from, state) do
      {:reply, nil, remove(state, sentantid)}
    end

    def handle_call(_request, _from, state) do
      IO.puts("Unknown Command #{inspect(state, pretty: true)}")
      {:reply, {:error, :unknown_command}, state}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------


    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Private Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Store a Sentant in the quadtree using the Geohash, with the data stored at the leaves at the depth given
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp store(quadtree, %{:geohash => geohash}, sentantid, depth \\ 6) do
      # Remove the item from the quadtree if it exists.
      quadtree = remove(quadtree,  sentantid)

      # Convert the geohash to a list of characters of the desired length
      geohash_list = geohash
        |> String.slice(0..depth - 1)
        |> String.split("")
        |> Enum.filter(fn x -> x != "" end)

      # Add the data to the quadtree
      put(quadtree, geohash_list, sentantid)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Retrieve the data from the quadtree using the Geohash, with the data stored at the leaves at the depth given
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp retrieve(quadtree, %{:geohash => geohash}, depth) do
      # Convert the geohash to a list of characters of the desired length
      geohash_list = geohash
        |> String.slice(0..depth - 1)
        |> String.split("")
        |> Enum.filter(fn x -> x != "" end)

      # Retrieve the data from the quadtree
      get(quadtree, geohash_list)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Do the actual retrieval of the data from the quadtree
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp get(quadtree, []) do
      leaves(quadtree)
    end
    defp get(quadtree, [head | tail]) do
      if Map.has_key?(quadtree, head) do
        next = Map.get(quadtree, head)
        if is_map(next) do
          get(next, tail)
        else
          next
        end
      else
        leaves(quadtree)
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Given a part of the quadtree, extract all the data from the leaves into a flat list.
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp leaves(quadtree) do
      Enum.map(Map.keys(quadtree), fn key ->
        if is_map(Map.get(quadtree, key)) do
          leaves(Map.get(quadtree, key))
        else
          Map.get(quadtree, key)
        end
      end) |> List.flatten()
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Put an item into the quadtree
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp put(quadtree, [head | []], data) do
      # If the head is the last element, then add the data to the quadtree
      # if the tree already has an element called 'head', then add the data to the list of data at position 'head'
      if Map.has_key?(quadtree, head) do
        Map.put(quadtree, head, [data | Map.get(quadtree, head)])
      else
        # Otherwise, create a new list with the data
        Map.put(quadtree, head, [data])
      end
    end
    defp put(quadtree, [head | tail], data) do
      if Map.has_key?(quadtree, head) do
        if is_map(Map.get(quadtree, head)) do
          Map.put(quadtree, head, put(Map.get(quadtree, head), tail, data))
        else
          Map.put(quadtree, head, [Map.get(quadtree, head), put(%{}, tail, data)])
        end
      else
        Map.put(quadtree, head, put(%{}, tail, data))
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Remove an item from the quadtree (if it exists) (and also any processes no longer running)
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp remove(quadtree, sentantid) do
      Enum.reduce( Map.keys(quadtree), %{}, fn key, acc ->
        subtree = Map.get(quadtree, key)
        if is_map(subtree) do
          newsubtree = remove(subtree, sentantid)
          if newsubtree != %{} do
            Map.put(acc, key, newsubtree)
          else
            acc
          end
        else
          case Enum.filter(Map.get(quadtree, key), fn x -> (x != sentantid) and (R2Process.whereis(x, AiReality2Geospatial.Processes) != nil) end) do
            [] -> acc
            newleaves -> Map.put(acc, key, newleaves)
          end
        end
      end)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Find the Sentants within a given radius of a location (and return the PIDs)
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp find(quadtree, location, radius) do
      depth = cond do
        radius < 1220 -> 5
        radius < 4890 -> 4
        radius < 39100 -> 3
        radius < 156000 -> 2
        radius < 1250000 -> 1
        true -> 0
      end
      retrieve(quadtree, location, depth)
      |> Enum.map(fn sentantid -> AiReality2Geospatial.Main.whereis(sentantid) end)
      |> Enum.filter(fn pid -> is_pid(pid) end)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------

end
