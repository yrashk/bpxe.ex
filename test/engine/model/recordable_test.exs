defmodule BPXETest.Engine.Model.Recordable.Test do
  use GenServer
  use BPXE.Engine.Model.Recordable, handle: ~w(add_one add_two)a

  defstruct model: %{}

  def init(_) do
    {:ok, %__MODULE__{}}
  end

  def model(pid) do
    call(pid, :model)
  end

  def handle_call(:model, _from, state) do
    {:reply, state.model, state}
  end
end

defmodule BPXETest.Engine.Model.Recordable do
  use ExUnit.Case, async: true
  import BPXE.Engine.Model.Recordable, only: [call: 2]
  alias BPXETest.Engine.Model.Recordable.Test
  alias BPXE.Engine.Base

  test "should handle recording calls" do
    {:ok, pid} = GenServer.start_link(Test, [])
    {:ok, one} = call(pid, {:add_one, "1"})
    {:ok, one_one} = call(pid, {:add_one, "1_1"})
    {:ok, two} = call(one, {:add_two, "2"})
    {:ok, three} = call(two, {:add_one, "3"})
    model = Test.model(pid)

    assert [
             ^one_one,
             ^one
           ] = model[nil]

    assert [^two] = model[one]
    assert [^three] = model[two]
  end

  test "should handle returning identifiers" do
    {:ok, pid} = GenServer.start_link(Test, [])
    {:ok, one} = call(pid, {:add_one, "1"})
    {:ok, one_one} = call(pid, {:add_one, "1_1"})
    {:ok, two} = call(one, {:add_two, "2"})
    {:ok, three} = call(two, {:add_one, "3"})
    assert Base.id(one) == "1"
    assert Base.id(one_one) == "1_1"
    assert Base.id(two) == "2"
    assert Base.id(three) == "3"
  end
end
