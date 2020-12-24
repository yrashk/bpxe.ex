defmodule BPXETest.Utils do
  alias BPXE.Engine.Model.Recordable.Ref

  def find_model(model, path) do
    find_model(model, nil, path)
  end

  def find_model(_, result, []), do: result

  def find_model(model, key, [head | tail]) do
    key1 =
      Enum.find_value(model[key], fn
        %Ref{payload: payload} = ref
        when is_tuple(payload) and tuple_size(payload) > 1 and is_tuple(head) and
               tuple_size(head) == 2 and elem(payload, 0) == elem(head, 0) and
               elem(payload, 1) == elem(head, 1) ->
          ref

        %Ref{payload: payload} = ref
        when is_tuple(payload) and tuple_size(payload) > 1 and elem(payload, 1) == head ->
          ref

        %Ref{payload: payload} = ref
        when is_tuple(payload) and tuple_size(payload) > 1 and elem(payload, 0) == head ->
          ref

        %Ref{payload: payload} = ref when payload == head ->
          ref

        _ ->
          false
      end)

    find_model(model, key1, tail)
  end
end

ExUnit.configure(assert_receive_timeout: 500, refute_receive_timeout: 500)
ExUnit.start()
