defmodule Reality2.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Reality2.Repo,
      # {DNSCluster, query: Application.get_env(:reality2, :dns_cluster_query) || :ignore},
      # {Phoenix.PubSub, name: Reality2.PubSub},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: Reality2.Sentants},
      %{id: :SentantNames, start: {Reality2.Metadata, :start_link, [:SentantNames]}},
      %{id: :SentantIDs, start: {Reality2.Metadata, :start_link, [:SentantIDs]}},
      {Finch, name: Reality2.HTTPClient, start: {Finch, :start_link, []}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
