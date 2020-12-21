defmodule BPXETest.Utils do
  alias BPXE.Engine.Blueprint.Recordable.Ref

  def find_blueprint(blueprint, path) do
    find_blueprint(blueprint, nil, path)
  end

  def find_blueprint(_, result, []), do: result

  def find_blueprint(blueprint, key, [head | tail]) do
    key1 =
      Enum.find_value(blueprint[key], fn
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

    find_blueprint(blueprint, key1, tail)
  end
end

ExUnit.configure(assert_receive_timeout: 500, refute_receive_timeout: 500)
ExUnit.start()
