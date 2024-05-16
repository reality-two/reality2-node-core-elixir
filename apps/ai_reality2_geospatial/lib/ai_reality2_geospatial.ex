defmodule AiReality2Geospatial do
  @moduledoc """
  The Reality2 Node Plugin `ai.reality2.geospatial` as it is written in the Sentant description YAML files.

  Naming restrictions require that underscores are used in the App filenames, so in this case `ai_reality2_geospatial`.

  To create a Plugin App such as this for a Reality2 Node, follow the general instructions for creating a new App under an umbrella project.
  Make sure the app created is a supervised app, ie created using the `--sup` option.

  ```bash
  mix new apps/ai_reality2_geospatial --sup
  ```

  The app name should match the plugin name, ie `ai_reality2_geospatial` for the plugin `ai.reality2.geospatial`, which is then called AiReality2Geospatial as the App Alias used inside the code.

  By convention, we are using a reverse domain name hence: `ai.reality2.geospatial`.

  The plugin app must have `create`, `delete`, `whereis` and `sendto` functions in the `lib/<app_name>/main.ex` file, which are called to create and delete instances of the app for each Sentant,
  return a process ID for communication, and send a command and parameters to the App for the given Sentant.
  See the `AiReality2Geospatial.Main` module for more details.
  """
end
