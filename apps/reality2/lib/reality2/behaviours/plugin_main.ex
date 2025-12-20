defmodule Reality2.Plugin.Main do
  @moduledoc """
  Behaviour for Reality2 plugin main modules.

  Every plugin `Main` module must implement these functions so that the
  Reality2 runtime can create, delete, locate, and send messages to it.
  """

  @type sentant_id :: String.t()
  @type command :: map()
  @type details :: map()

  @doc """
  The create function is usually called when a Sentant is loaded so that there is a plugin available and registered.
  Many plugins have one child process per Sentant, but some don't need that.
  """
  @callback create(sentant_id, details) ::
              {:ok}
              | {:error, :existance}

  @doc """
  The opposite to the create function - when a Sentant is unloaded, this is called to do any cleanup required (eg remove database
  entries, kill processes etc)
  """
  @callback delete(sentant_id) ::
              {:ok}
              | {:error, :existance}

  @doc """
  Sometimes, the actual pID of the process for a specific Sentant plugin is required.  This returns it.  If there is only
  one process for all sentants, that is returned.  Mostly used internally.
  """
  @callback whereis(sentant_id | pid()) ::
              pid()
              | String.t()
              | nil

  @doc """
  Commands can be sent to the plugin for the named Sentant.  The command is a map consisting of two fields; command and parameters
  eg %{command: "add", parameters: %{param1: 3, param2: 5}}
  """
  @callback sendto(sentant_id, command) ::
              :ok
              | {:error, :command}
              | {:ok, any()}
              | {:error, :key}
end
