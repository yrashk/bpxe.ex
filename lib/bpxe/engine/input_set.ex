defmodule BPXE.Engine.InputSet do
  defstruct attrs: %{},
            data_input_refs: [],
            optional_input_refs: [],
            while_executing_input_refs: [],
            output_set_refs: []

  use ExConstructor
end
