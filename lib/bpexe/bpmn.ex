defmodule BPEXE.BPMN do
  defmodule Handler do
    @callback add_process(term, Map.t()) :: {:ok, term} | {:error, term}
    @callback add_event(term, Map.t(), type :: atom) :: {:ok, term} | {:error, term}
    @callback add_signal_event_definition(term, Map.t()) :: {:ok, term} | {:error, term}
    @callback add_task(term, Map.t()) :: {:ok, term} | {:error, term}
    @callback add_task(term, Map.t(), type :: atom) :: {:ok, term} | {:error, term}
    @callback add_script(term, String.t()) :: {:ok, term} | {:error, term}
    @callback add_outgoing(term, name :: String.t()) :: {:ok, term} | {:error, term}
    @callback add_incoming(term, name :: String.t()) :: {:ok, term} | {:error, term}
    @callback add_sequence_flow(term, Map.t()) :: {:ok, term} | {:error, term}
    @callback add_parallel_gateway(term, Map.t()) :: {:ok, term} | {:error, term}
    @callback add_event_based_gateway(term, Map.t()) :: {:ok, term} | {:error, term}
    @callback complete(term) :: {:ok, term} | {:error, term}

    @behaviour Saxy.Handler

    defstruct ns: %{},
              handler: BPEXE.BPMN.Handler.Engine,
              current: [],
              characters: nil

    @bpmn_spec "http://www.omg.org/spec/BPMN/20100524/MODEL"

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
         handler: options[:handler] || BPEXE.BPMN.Handler.Engine,
         current: [options[:instance]]
       }}
    end

    # We don't know namespace mapping yet, get it from the root element
    def handle_event(:start_element, {root, args}, %__MODULE__{} = state)
        when map_size(state.ns) == 0 do
      namespaces =
        args
        |> Enum.filter(fn {k, _} -> String.contains?(k, "xmlns:") end)
        |> Map.new(fn {k, v} -> {v, String.replace(k, "xmlns:", "")} end)

      handle_event(:start_element, {root, args}, %{state | ns: namespaces})
    end

    # Transform arguments to a more digestible format:
    # 1. Split namespace and the element name
    # 2. Convert arguments to a Map
    # 2.1. Convert namespaced arguments to [ns, name]
    def handle_event(:start_element, {element, args}, %__MODULE__{ns: ns} = state)
        when is_binary(element) do
      handle_event(
        :start_element,
        {split_ns(element, ns),
         Map.new(
           args
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
          {{bpmn, "definitions"}, _args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}} = state
        ) do
      {:ok, state}
    end

    def handle_event(
          :start_element,
          {{bpmn, "process"}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [instance | _], handler: handler} =
            state
        )
        when not is_nil(instance) do
      handler.add_process(instance, args)
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
          {{bpmn, "parallelGateway"}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
        ) do
      handler.add_parallel_gateway(current, args)
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
          {{bpmn, "eventBasedGateway"}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
        ) do
      handler.add_event_based_gateway(current, args)
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
          {{bpmn, event}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [process | _]} = state
        )
        when event in @event_types do
      handler.add_event(process, args, String.to_atom(event))
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
          {{bpmn, "signalEventDefinition"}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [process | _]} = state
        ) do
      handler.add_signal_event_definition(process, args)
      |> Result.map(fn _ -> state end)
    end

    @task_types ~w(task serviceTask sendTask receiveTask userTask manualTask
    businessRuleTask scriptTask subProcess adHocSubProcess transaction callActivity)

    def handle_event(
          :start_element,
          {{bpmn, task}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [process | _]} = state
        )
        when task in @task_types do
      handler.add_task(process, args, String.to_atom(task))
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
          {{bpmn, "script"}, _args},
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
          {{bpmn, "outgoing"}, _args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
        ) do
      {:ok, %{state | characters: ""}}
    end

    def handle_event(
          :start_element,
          {{bpmn, "incoming"}, _args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, characters: nil} = state
        ) do
      {:ok, %{state | characters: ""}}
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
          {{bpmn, "sequenceFlow"}, args},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, handler: handler, current: [current | _]} = state
        ) do
      handler.add_sequence_flow(current, args)
      |> Result.map(fn flow -> %{state | current: [flow | state.current]} end)
    end

    def handle_event(
          :end_element,
          {bpmn, "sequenceFlow"},
          %__MODULE__{ns: %{@bpmn_spec => bpmn}, current: [_ | rest]} = state
        ) do
      {:ok, %{state | current: rest}}
    end

    def handle_event(:end_document, _, %__MODULE__{current: [instance], handler: handler}) do
      handler.complete(instance)
    end

    def handle_event(_event, _arg, state) do
      {:ok, state}
    end
  end

  def parse(string, options \\ []) when is_binary(string) do
    Saxy.parse_string(string, Handler, options)
  end

  def parse_stream(stream, options \\ []) do
    Saxy.parse_stream(stream, Handler, options)
  end
end
