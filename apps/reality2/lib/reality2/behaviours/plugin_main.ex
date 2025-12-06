defmodule Reality2.Plugin.Main do
  @moduledoc """
  Behaviour for Reality2 plugin main modules.

  Every plugin `Main` module must implement these functions so that the
  Reality2 runtime can create, delete, locate, and send messages to it.
  """

  @type sentant_id :: String.t()
  @type command :: map()
  @type details :: map()

  @callback create(sentant_id, details) ::
              {:ok}
              | {:error, :existance}

  @callback delete(sentant_id) ::
              {:ok}
              | {:error, :existance}

  @callback whereis(sentant_id | pid()) ::
              pid()
              | String.t()
              | nil

  @callback sendto(sentant_id, command) ::
              :ok
              | {:error, :command}
              | {:ok, any()}
              | {:error, :key}
end
