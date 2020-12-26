defmodule BPXE.BPMN.Handler do
  @callback add_process(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_event(term, type :: atom, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_signal_event_definition(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_task(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_task(term, Map.t(), type :: atom) :: {:ok, term} | {:error, term}
  @callback add_script(term, String.t()) :: {:ok, term} | {:error, term}
  @callback add_outgoing(term, name :: String.t()) :: {:ok, term} | {:error, term}
  @callback add_incoming(term, name :: String.t()) :: {:ok, term} | {:error, term}
  @callback add_sequence_flow(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_condition_expression(term, Map.t(), String.t()) :: {:ok, term} | {:error, term}
  @callback add_parallel_gateway(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_inclusive_gateway(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_event_based_gateway(term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_extension_elements(term) :: {:ok, term} | {:error, term}
  @callback add_json(term, term) :: {:ok, term} | {:error, term}
  @callback add_standard_loop_characteristics(term, term, Map.t()) :: {:ok, term} | {:error, term}
  @callback add_loop_condition(term, term, Map.t(), String.t()) :: {:ok, term} | {:error, term}
  @callback complete(term) :: {:ok, term} | {:error, term}

  @behaviour Saxy.Handler

  defstruct ns: %{},
            handler: BPXE.BPMN.Handler.Engine,
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
       handler: options[:handler] || BPXE.BPMN.Handler.Engine,
       current: [options[:model]]
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

  def handle_event(
        :start_element,
        {{bpmn, "definitions"}, _attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      ) do
    {:ok, state}
  end

  def handle_event(
        :start_element,
        {{bpmn, "process"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [model | _], handler: handler} = state
      )
      when not is_nil(model) do
    handler.add_process(model, attrs)
    |> Result.map(fn process -> %{state | current: [process | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "process"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      ) do
    {:ok, %{state | current: tl(state.current)}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "parallelGateway"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
      ) do
    handler.add_parallel_gateway(current, attrs)
    |> Result.map(fn gateway -> %{state | current: [gateway | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "parallelGateway"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      ) do
    {:ok, %{state | current: tl(state.current)}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "inclusiveGateway"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
      ) do
    handler.add_inclusive_gateway(current, attrs)
    |> Result.map(fn gateway -> %{state | current: [gateway | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "inclusiveGateway"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      ) do
    {:ok, %{state | current: tl(state.current)}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "eventBasedGateway"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
      ) do
    handler.add_event_based_gateway(current, attrs)
    |> Result.map(fn gateway -> %{state | current: [gateway | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "eventBasedGateway"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      ) do
    {:ok, %{state | current: tl(state.current)}}
  end

  @event_types ~w(startEvent intermediateCatchEvent intermediateThrowEvent implicitThrowEvent boundaryEvent endEvent)

  def handle_event(
        :start_element,
        {{bpmn, event}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [process | _]} = state
      )
      when event in @event_types do
    handler.add_event(process, String.to_atom(event), attrs)
    |> Result.map(fn event -> %{state | current: [event | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, event},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      )
      when event in @event_types do
    {:ok, %{state | current: tl(state.current)}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "signalEventDefinition"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [process | _]} = state
      ) do
    handler.add_signal_event_definition(process, attrs)
    |> Result.map(fn _ -> state end)
  end

  @task_types ~w(task serviceTask sendTask receiveTask userTask manualTask
    businessRuleTask scriptTask subProcess adHocSubProcess transaction callActivity)

  def handle_event(
        :start_element,
        {{bpmn, task}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [process | _]} = state
      )
      when task in @task_types do
    handler.add_task(process, attrs, String.to_atom(task))
    |> Result.map(fn event -> %{state | current: [event | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, task},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
      )
      when task in @task_types do
    {:ok, %{state | current: tl(state.current)}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "script"}, _attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
      ) do
    {:ok, %{state | characters: ""}}
  end

  def handle_event(
        :end_element,
        {bpmn, "script"},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn},
          handler: handler,
          characters: characters,
          current: [current | _]
        } = state
      ) do
    handler.add_script(current, characters)
    |> Result.map(fn _ -> %{state | characters: nil, current: state.current} end)
  end

  def handle_event(
        :start_element,
        {{bpmn, "standardLoopCharacteristics"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [node | _] = current, handler: handler} =
          state
      ) do
    handler.add_standard_loop_characteristics(node, attrs["id"], attrs)
    |> Result.map(fn loop -> %{state | current: [loop | current]} end)
  end

  def handle_event(
        :start_element,
        {{bpmn, "loopCondition"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
      ) do
    {:ok, %{state | characters: "", attrs: attrs}}
  end

  def handle_event(
        :end_element,
        {bpmn, "loopCondition"},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn},
          handler: handler,
          characters: characters,
          current: [current | _]
        } = state
      ) do
    handler.add_loop_condition(current, state.attrs["id"], state.attrs, characters)
    |> Result.map(fn _ -> %{state | characters: nil, current: state.current, attrs: nil} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "standardLoopCharacteristics"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [_ | rest]} = state
      ) do
    %{state | current: rest}
  end

  def handle_event(
        :start_element,
        {{bpmn, "outgoing"}, _attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
      ) do
    {:ok, %{state | characters: ""}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "incoming"}, _attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
      ) do
    {:ok, %{state | characters: ""}}
  end

  def handle_event(
        :end_element,
        {bpmn, "outgoing"},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn},
          handler: handler,
          characters: outgoing,
          current: [event | _]
        } = state
      ) do
    handler.add_outgoing(event, outgoing)
    |> Result.map(fn _ -> %{state | characters: nil} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "incoming"},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn},
          handler: handler,
          characters: incoming,
          current: [event | _]
        } = state
      ) do
    handler.add_incoming(event, incoming)
    |> Result.map(fn _ -> %{state | characters: nil} end)
  end

  def handle_event(
        :start_element,
        {{bpmn, "sequenceFlow"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
      ) do
    handler.add_sequence_flow(current, attrs)
    |> Result.map(fn flow -> %{state | current: [flow | state.current]} end)
  end

  def handle_event(
        :end_element,
        {bpmn, "sequenceFlow"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [_ | rest]} = state
      ) do
    {:ok, %{state | current: rest}}
  end

  def handle_event(
        :start_element,
        {{bpmn, "conditionExpression"}, attrs},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
      ) do
    {:ok, %{state | characters: "", attrs: attrs}}
  end

  def handle_event(
        :end_element,
        {bpmn, "conditionExpression"},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn},
          handler: handler,
          characters: body,
          current: [flow | _],
          attrs: attrs
        } = state
      ) do
    handler.add_condition_expression(flow, attrs, body)
    |> Result.map(fn _ -> %{state | characters: nil, attrs: nil} end)
  end

  def handle_event(
        :start_element,
        {{bpmn, "extensionElements"}, _attrs},
        %__MODULE__{
          ns: %{@bpmn_spec => bpmn},
          handler: handler,
          current: [node | _] = current,
          extension: nil
        } = state
      ) do
    handler.add_extension_elements(node)
    |> Result.map(fn result ->
      %{state | extension: true, current: [result | current], extension_top: 0}
    end)
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
          handler: handler,
          current: [node | _],
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
      handler.add_json(node, json)
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
          current: [node | _],
          handler: handler
        } = state
      )
      when not is_nil(extension) do
    BPXE.BPMN.JSON.handle_event(:end_element, element, state.extension)
    |> Result.map(fn result ->
      if extension_top == 1 do
        handler.add_json(node, BPXE.BPMN.JSON.prepare(result))
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
        :end_element,
        {bpmn, "extensionElements"},
        %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [_ | rest]} = state
      ) do
    {:ok, %{state | extension: nil, extension_top: nil, current: rest}}
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

  def handle_event(:end_document, _, %__MODULE__{current: [model], handler: handler}) do
    handler.complete(model)
  end

  def handle_event(_event, _arg, state) do
    {:ok, state}
  end
end
