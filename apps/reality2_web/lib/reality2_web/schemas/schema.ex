defmodule Reality2Web.Schema do
  @moduledoc """
    Reality2 GraphQL Schema

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use Absinthe.Schema

  import_types(Reality2Web.Schema.Types.Custom.JSON)
  import_types(Reality2Web.Schema.Types.Custom.UUID4)
  import_types(Reality2Web.Schema.Types.Custom.StringOrJSON)
  import_types(Absinthe.Type.Custom)
  import_types(Reality2Web.Schema.Sentant)
  import_types(Reality2Web.Schema.Node)

  @desc """
  The Reality2 GraphQL queries
  """
  query do
    import_fields(:sentant_queries)
    import_fields(:node_queries)
  end

  mutation do
    import_fields(:sentant_mutations)
    import_fields(:node_mutations)
  end

  subscription do
    import_fields(:sentant_subscriptions)
    import_fields(:node_subscriptions)
  end
end
