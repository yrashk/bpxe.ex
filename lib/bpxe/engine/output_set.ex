defmodule BPXE.Engine.OutputSet do
  defstruct attrs: %{},
            data_output_refs: [],
            optional_output_refs: [],
            while_executing_output_refs: [],
            input_set_refs: []

  use ExConstructor
end
