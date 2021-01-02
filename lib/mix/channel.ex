defmodule Mix.Tasks.Bpxe.Channel.List do
  @shortdoc "Lists all BPXE channels used"
  @moduledoc "List all uses of BPXEs channels with non-constant values highlighted"
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    result =
      Enum.reduce(Path.wildcard("{lib,test}/**/*.ex*"), %{}, fn file, acc ->
        quoted = Code.string_to_quoted!(File.read!(file))

        channels =
          Traverse.walk(quoted, %{aliases: [[:BPXE, :Channel]], channels: []}, fn
            # aliasing Channel
            {:alias, _,
             [
               {:__aliases__, _, [:BPXE, :Channel]},
               [as: {:__aliases__, _, new_alias}]
             ]},
            acc ->
              %{acc | aliases: [new_alias | acc.aliases]}

            # aliasing Channel
            {:alias, _,
             [
               {:__aliases__, _, [:BPXE, :Channel]},
               []
             ]},
            acc ->
              %{acc | aliases: [[:Channel] | acc.aliases]}

            # channel-related call
            {{:., _, [{:__aliases__, _, module}, call]}, _,
             [
               name | _
             ]},
            acc
            when call in ~w(join leave publish multi_call)a ->
              if module in acc.aliases do
                %{acc | channels: [process_channel_name(name) | acc.channels]}
              else
                acc
              end

            _, acc ->
              acc
          end).channels

        new_acc =
          for channel <- channels, reduce: acc do
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

    Table.new(rows, ["Channel", "Files"])
    |> Table.put_column_meta(:all, align: :center)
    |> Table.render!(header_separator_symbol: "=", horizontal_style: :all)
    |> IO.puts()

    :ok
  end

  defp process_channel_name({:{}, _, items}) do
    Enum.map(items, &process_channel_name/1) |> List.to_tuple()
  end

  defp process_channel_name(tuple) when tuple_size(tuple) != 3 do
    Enum.map(tuple |> Tuple.to_list(), &process_channel_name/1) |> List.to_tuple()
  end

  defp process_channel_name({:__aliases__, _, _} = a) do
    {atom, _} = Code.eval_quoted(a)
    atom
  end

  defp process_channel_name({c, _, a}) do
    str = Macro.to_string({c, [], a})
    "<<<" <> str <> ">>>"
  end

  defp process_channel_name(item), do: item
end
