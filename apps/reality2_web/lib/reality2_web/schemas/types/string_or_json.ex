defmodule Reality2Web.Schema.Types.Custom.StringOrJSON do
  @moduledoc false
  # A string or JSON

  use Absinthe.Schema.Notation

  scalar :string_or_json, description: "String or JSON object" do
    parse(fn
      %Absinthe.Blueprint.Input.String{value: value} ->
        {:ok, value}

      %Absinthe.Blueprint.Input.Null{} ->
        {:ok, nil}

      %Absinthe.Blueprint.Input.Object{fields: fields} ->
        {:ok, Enum.into(fields, %{}, fn %{name: name, input_value: iv} -> {name, iv.value} end)}

      _ ->
        :error
    end)

    serialize(fn
      value -> value
    end)
  end
end
