defmodule BPXE.BPMN.Handler do
  @behaviour Saxy.Handler

  import BPXE.Helpers

  defstruct ns: %{},
            current: [],
            characters: nil,
            attrs: nil,
            extension: nil,
            extension_top: false

  @bpmn_spec "http://www.omg.org/spec/BPMN/20100524/MODEL"
  @json_spec "http://www.w3.org/2013/XSL/json"
  @bpxe_spec BPXE.BPMN.ext_spec()

  # Splits by namespace
  @spec split_ns(binary, Map.t()) :: binary() | {binary(), binary()}
  defp split_ns(string, namespaces) when is_binary(string) do
    case String.split(string, ":") do
      [name] -> name
      [ns, name] -> {namespaces[ns] || ns, name}
    end
  end

  def handle_event(:start_document, _prolog, options) when is_list(options) do
    {:ok,
     %__MODULE__{
       current: [{options[:model], nil}]
     }}
  end

  # We don't know namespace mapping yet, get it from the root element
  def handle_event(:start_element, {root, attrs}, %__MODULE__{} = state)
      when map_size(state.ns) == 0 do
    namespaces =
      attrs
      |> Enum.filter(fn {k, _} -> String.contains?(k, "xmlns:") end)
      |> Map.new(fn {k, v} -> {v, String.replace(k, "xmlns:", "")} end)

    handle_event(:start_element, {root, attrs}, %{state | ns: namespaces})
  end

  # Transform arguments to a more digestible format:
  # 1. Split namespace and the element name
  # 2. Convert arguments to a Map
  # 2.1. Convert namespaced arguments to [ns, name]
  def handle_event(:start_element, {element, attrs}, %__MODULE__{ns: ns} = state)
      when is_binary(element) do
    handle_event(
      :start_element,
      {split_ns(element, ns),
       Map.new(
         attrs
         |> Enum.map(fn {k, v} ->
           {split_ns(k, ns), v}
         end)
       )},
      state
    )
  end

  # Transform arguments to a more digestible format:
  # 1. Split namespace and the element name
  def handle_event(:end_element, element, %__MODULE__{ns: ns} = state)
      when is_binary(element) do
    handle_event(:end_element, split_ns(element, ns), state)
  end

  # Handle all elements from the specification
  for {element, _} <- BPXE.BPMN.Semantic.elements() do
    @element element
    element_spec =
      if element in Map.keys(BPXE.BPMN.Semantic.core_elements()) do
        @bpmn_spec
      else
        @bpxe_spec
      end

    @element_spec element_spec

    def handle_event(
          :start_element,
          {{ns, @element}, attrs},
          %__MODULE__{ns: %{@element_spec => ns}, current: [{handler, node} | _] = current} =
            state
        ) do
      attrs = update_in(attrs["id"], &(&1 || generate_id()))

      GenServer.call(handler, {:add_node, node, @element, attrs})
      |> result()
      |> Result.map(fn {handler_, node_} ->
        %{state | current: [{handler_, node_} | current], attrs: attrs, characters: ""}
      end)
      |> Result.and_then(fn state ->
        complete_event(:start_element, {{ns, @element}, attrs}, state)
      end)
    end

    def handle_event(
          :end_element,
          {ns, @element},
          %__MODULE__{
            ns: %{@element_spec => ns},
            current: [{handler, node} | rest],
            characters: characters
          } = state
        ) do
      GenServer.call(handler, {:complete_node, node, characters})
      |> result()
      |> Result.map(fn _ -> %{state | current: rest, characters: nil} end)
      |> Result.and_then(fn state ->
        complete_event(:end_element, {ns, @element}, state)
      end)
    end
  end

  def handle_event(
        :start_element,
        {{bpxe, "json"}, _},
        %__MODULE__{
          ns: %{@bpxe_spec => bpxe},
          extension: true
        } = state
      ) do
    {:ok, %{state | characters: ""}}
  end

  def handle_event(
        :end_element,
        {bpxe, "json"},
        %__MODULE__{
          ns: %{@bpxe_spec => bpxe},
          current: [{handler, node} | _],
          extension: true,
          characters: characters
        } = state
      ) do
    string = BPXE.BPMN.Interpolation.interpolate(characters)

    case string do
      string when is_binary(string) ->
        Jason.decode(characters)

      f when is_function(f) ->
        {:ok,
         fn cb ->
           f.(fn v -> {cb.(v), &Jason.encode/1} end) |> Jason.decode()
         end}

      other ->
        {:error, {:unexpected_interpolation, other}}
    end
    |> Result.and_then(fn json ->
      GenServer.call(handler, {:add_json, node, json})
    end)
    |> Result.map(fn _ ->
      %{state | characters: nil}
    end)
  end

  def handle_event(
        :start_element,
        {{json, _}, _} = element,
        %__MODULE__{
          ns: %{@json_spec => json},
          extension: true,
          extension_top: extension_top
        } = state
      ) do
    BPXE.BPMN.JSON.handle_event(:start_element, element, BPXE.BPMN.JSON.new([]))
    |> Result.map(fn result ->
      %{state | extension: result, extension_top: extension_top + 1}
    end)
  end

  def handle_event(
        :start_element,
        {{json, _}, _} = element,
        %__MODULE__{
          ns: %{@json_spec => json},
          extension: %BPXE.BPMN.JSON{} = extension,
          extension_top: extension_top
        } = state
      )
      when not is_nil(extension) do
    BPXE.BPMN.JSON.handle_event(:start_element, element, extension)
    |> Result.map(fn result ->
      %{state | extension: result, extension_top: extension_top + 1}
    end)
  end

  def handle_event(
        :end_element,
        {json, _} = element,
        %__MODULE__{
          ns: %{@json_spec => json},
          extension: extension,
          extension_top: extension_top,
          current: [{handler, node} | _]
        } = state
      )
      when not is_nil(extension) do
    BPXE.BPMN.JSON.handle_event(:end_element, element, state.extension)
    |> Result.map(fn result ->
      if extension_top == 1 do
        GenServer.call(handler, {:add_json, node, BPXE.BPMN.JSON.prepare(result)})
        true
      else
        result
      end
    end)
    |> Result.map(fn result ->
      %{state | extension: result, extension_top: extension_top - 1}
    end)
  end

  def handle_event(
        :characters,
        chars,
        %__MODULE__{extension: %BPXE.BPMN.JSON{} = json} = state
      )
      when not is_nil(chars) do
    BPXE.BPMN.JSON.handle_event(:characters, chars, json)
    |> Result.map(fn result -> %{state | extension: result} end)
  end

  def handle_event(
        :characters,
        chars,
        %__MODULE__{characters: characters} = state
      )
      when not is_nil(characters) do
    {:ok, %{state | characters: characters <> chars}}
  end

  def handle_event(
        :characters,
        _chars,
        state
      ) do
    {:ok, state}
  end

  def handle_event(_event, _arg, state) do
    {:ok, state}
  end

  def complete_event(
        :start_element,
        {{bpmn, "extensionElements"}, _attrs},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn}
        } = state
      ) do
    {:ok, %{state | extension: true, extension_top: 0}}
  end

  def complete_event(
        :end_element,
        {bpmn, "extensionElements"},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn}
        } = state
      ) do
    {:ok, %{state | extension: nil, extension_top: nil}}
  end

  def complete_event(_, _, state) do
    {:ok, state}
  end

  defp generate_id() do
    {m, f, a} = Application.get_env(:bpxe, :spec_id_generator)
    apply(m, f, a)
  end
end
