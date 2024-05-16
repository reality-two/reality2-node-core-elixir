defmodule AiReality2Geospatial.Data do
# *******************************************************************************************************************************************
@moduledoc """
  Manage Geoloaction for Sentants.

  In this implementation, we just use a linear search for Sentants that have neighbouring Geohashes, but this could be optimised by using
  a database.
"""
# *******************************************************************************************************************************************

  @doc false
  use GenServer, restart: :transient

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(_, name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)

  @doc false
  def init(state),                                      do: {:ok, state}
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def handle_call(%{command: "get"}, _from, state),                                                 do: {:reply, {:ok, AiReality2Geospatial.Main.get(state, "location", %{latitude: 0.0, longitude: 0.0, altitude: 0.0, geohash: "", radius: 0.0})}, state}
  def handle_call(%{command: "all"}, _from, state),                                                 do: {:reply, {:ok, state}, state}
  def handle_call(%{command: "search", parameters: parameters}, _from, state),                      do: {:reply, {:ok, %{sentants: get_nearby_sentants(state, parameters)}}, state}
  def handle_call(_, _from, state),                                                                 do: {:reply, {:error, :unknown_command}, state}


  @doc false
  def handle_cast(%{command: "set", parameters: parameters}, state) do
    latitude = choose("latitude", state["location"], parameters, 0.0)
    longitude = choose("longitude", state["location"], parameters, 0.0)
    altitude = choose("altitude", state["location"], parameters, 0.0)
    radius = choose("radius", state["location"], parameters, 0.0)

    # latitude = AiReality2Geospatial.Main.get(parameters, "latitude", AiReality2Geospatial.Main.get(current_location, "latitude")) |> convert_string
    # longitude = AiReality2Geospatial.Main.get(parameters, "longitude", AiReality2Geospatial.Main.get(current_location, "longitude")) |> convert_string
    # altitude = AiReality2Geospatial.Main.get(parameters, "altitude", AiReality2Geospatial.Main.get(current_location, "altitude")) |> convert_string
    # radius = AiReality2Geospatial.Main.get(parameters, "radius", AiReality2Geospatial.Main.get(current_location, "radius")) |> convert_string
    case AiReality2Geospatial.Main.get(parameters, "geohash") do
      nil ->
        case is_nil(latitude) or is_nil(longitude) do
          true ->
            {:noreply, state}
          false ->
            {:noreply, Map.put(state, "location", %{geohash: Geohash.encode(latitude, longitude), latitude: latitude, longitude: longitude, altitude: altitude, radius: radius})}
        end
      geohash ->
        {lat, long} = Geohash.decode(geohash)
        {:noreply, Map.put(state, "location", %{geohash: geohash, latitude: lat, longitude: long, altitude: altitude, radius: radius})}
    end
  end
  def handle_cast(%{command: "delete"}, state),                                                     do: {:noreply, Map.delete(state, "location")}
  def handle_cast(%{command: "clear"}, _state),                                                     do: {:noreply, %{}}
  def handle_cast(_, state),                                                                        do: {:noreply, state}
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------
   defp choose(element, state, parameters, default) do
    state_element = AiReality2Geospatial.Main.get(state, element, default)
    param_element = AiReality2Geospatial.Main.get(parameters, element, nil)

    if (param_element == "" or param_element == nil) do
      state_element
    else
      param_element
    end |> convert_string
  end

  defp convert_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> 0
      _ ->
        case String.to_integer(value) do
          {:ok, integer} -> integer
          :error ->
            case String.to_float(value) do
              {:ok, float} -> float
              :error ->
                case String.downcase(value) do
                  "true" -> true
                  "false" -> false
                  _ -> value
                end
            end
        end
    end
  end
  defp convert_string(value), do: value

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get a list of Sentants that are within a certain radius of the Sentant with the given location.
  # At the moment, this is highly inefficient, amd could be improved by using an appropriate datastructure such as quadtrees.
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp get_nearby_sentants(state, parameters) do
    case AiReality2Geospatial.Main.get(state, "location") do
      nil -> []
      location ->
        radius = AiReality2Geospatial.Main.get(parameters, "radius", 10.0) # Radius in meters
        Enum.map(DynamicSupervisor.which_children(AiReality2Geospatial.Main), fn ({_, pid, _, _}) ->
          if (pid == self()) do
            nil
          else
            case GenServer.call(pid, %{command: "get"}) do
              {:error, _} -> nil
              {:ok, nil} -> nil
              {:ok, location2} ->
                lat1 = AiReality2Geospatial.Main.get(location, "latitude", 0.0)
                long1 = AiReality2Geospatial.Main.get(location, "longitude", 0.0)
                lat2 = AiReality2Geospatial.Main.get(location2, "latitude", 0.0)
                long2 = AiReality2Geospatial.Main.get(location2, "longitude", 0.0)
                sentant_radius = AiReality2Geospatial.Main.get(location2, "radius", 0.0)
                dist = distance(lat1, long1, lat2, long2)
                if ((dist <= radius) && (sentant_radius == 0.0)) || ((sentant_radius > 0.0) && (dist <= radius) && (dist <= sentant_radius)) do
                  case Process.info(pid, :registered_name) do
                    nil -> nil
                    {:registered_name, name} ->
                        name_str = Atom.to_string(name)
                        case (String.split(name_str, "|") |> List.first) do
                          nil -> nil
                          sentantid -> %{id: sentantid, distance: dist}
                        end
                  end
                end
            end
          end
        end) |> Enum.filter(fn x -> not is_nil(x) end)
    end
  end


  defp deg2rad(deg), do: :math.pi()*deg/180
  defp distance(lat1, long1, lat2, long2) do
    rlat1 = deg2rad(lat1)
    rlong1 = deg2rad(long1)
    rlat2 = deg2rad(lat2)
    rlong2 = deg2rad(long2)

    dlong = rlong2 - rlong1
    dlat = rlat2 - rlat1

    a = :math.pow(:math.sin(dlat/2), 2) + :math.cos(rlat1) * :math.cos(rlat2) * :math.pow(:math.sin(dlong/2), 2)

    c = 2 * :math.asin(:math.sqrt(a))

    # suppose radius of Earth is 6372.8 km
    6372800 * c
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------
end
