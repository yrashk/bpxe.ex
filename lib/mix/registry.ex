defmodule Mix.Tasks.Bpxe.Registry do
  @shortdoc "Lists all BPXE registered names used"
  @moduledoc "List all uses of BPXEs registry names with non-constant values highlighted"
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    result =
      Enum.reduce(Path.wildcard("{lib,test}/**/*.ex*"), %{}, fn file, acc ->
        quoted = Code.string_to_quoted!(File.read!(file))

        names =
          Traverse.walk(quoted, %{aliases: [[:BPXE, :Registry]], names: []}, fn
            # aliasing Registry
            {:alias, _,
             [
               {:__aliases__, _, [:BPXE, :Registry]},
               [as: {:__aliases__, _, new_alias}]
             ]},
            acc ->
              %{acc | aliases: [new_alias | acc.aliases]}

            # aliasing Registry
            {:alias, _,
             [
               {:__aliases__, _, [:BPXE, :Registry]},
               []
             ]},
            acc ->
              %{acc | aliases: [[:Registry] | acc.aliases]}

            # registry-related call
            {{:., _, [{:__aliases__, _, module}, call]}, _,
             [
               name | _
             ]},
            acc
            when call in ~w(register unregister whereis)a ->
              if module in acc.aliases do
                %{acc | names: [process_registration_name(name) | acc.names]}
              else
                acc
              end

            _, acc ->
              acc
          end).names

        new_acc =
          for channel <- names, reduce: acc do
            acc -> update_in(acc[channel], &[file | &1 || []])
          end

        new_acc
      end)

    rows =
      result
      |> Enum.map(fn {channel, files} ->
        [
          Macro.to_string(channel)
          |> String.replace(~s|"<<<|, IO.ANSI.underline() <> IO.ANSI.cyan())
          |> String.replace(~s|>>>"|, IO.ANSI.reset())
          |> String.replace(~s|\\"|, ~s|"|),
          files |> Enum.uniq()
        ]
      end)

    alias TableRex.Table

    Table.new(rows, ["Name", "Files"])
    |> Table.put_column_meta(:all, align: :center)
    |> Table.render!(header_separator_symbol: "=", horizontal_style: :all)
    |> IO.puts()

    :ok
  end

  defp process_registration_name({:{}, _, items}) do
    Enum.map(items, &process_registration_name/1) |> List.to_tuple()
  end

  defp process_registration_name(tuple) when tuple_size(tuple) != 3 do
    Enum.map(tuple |> Tuple.to_list(), &process_registration_name/1) |> List.to_tuple()
  end

  defp process_registration_name({:__aliases__, _, _} = a) do
    {atom, _} = Code.eval_quoted(a)
    atom
  end

  defp process_registration_name({c, _, a}) do
    str = Macro.to_string({c, [], a})
    "<<<" <> str <> ">>>"
  end

  defp process_registration_name(item), do: item
end
