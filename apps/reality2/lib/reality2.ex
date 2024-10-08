defmodule Reality2 do
  @moduledoc """
  Reality2 Sentient Agent (Sentant) based Platform with plugin architecture for Intuitive Spatial Computing supporting Assistive Technologies.

  This is the main module for managing Sentants, Swarms and Plugins on a Node and in a Cluster.
  Primarily, this will not be accessed directly, but rather through the GraphQL API [Reality2.Web](../reality2_web/api-reference.html).

  **Plugins**
  - [ai.reality2.vars](../ai_reality2_vars/AiReality2Vars.html) - A plugin for managing variables on a Sentant.
  - [ai.reality2.geospatial](../ai_reality2_geospatial/AiReality2Geospatial.html) - A plugin for managing geospatial location and context on a Sentant.
  - [ai.reality2.backup](../ai_reality2_backup/AiReality2Backup.html) - A plugin for managing data storage to a disc.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  @doc false
  def test() do
    Mix.Task.run("test")
  end

  @doc false
  def test_one(test_name) do
    Mix.Task.run("test", ["test/tests/" <> test_name])
  end



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------


end
