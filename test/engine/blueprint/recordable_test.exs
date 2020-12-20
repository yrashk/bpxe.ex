defmodule BPXETest.Engine.Blueprint.Recordable.Test do
  use GenServer
  use BPXE.Engine.Blueprint.Recordable, handle: ~w(add_one add_two)a

  defstruct blueprint: %{}

  def init(_) do
    {:ok, %__MODULE__{}}
  end

  def blueprint(pid) do
    call(pid, :blueprint)
  end

  def handle_call(:blueprint, _from, state) do
    {:reply, state.blueprint, state}
  end
end

defmodule BPXETest.Engine.Blueprint.Recordable do
  use ExUnit.Case
  import BPXE.Engine.Blueprint.Recordable, only: [call: 2]
  alias BPXETest.Engine.Blueprint.Recordable.Test
  alias BPXE.Engine.Base

  test "should handle recording calls" do
    {:ok, pid} = GenServer.start_link(Test, [])
    {:ok, one} = call(pid, {:add_one, "1"})
    {:ok, one_one} = call(pid, {:add_one, "1_1"})
    {:ok, two} = call(one, {:add_two, "2"})
    {:ok, three} = call(two, {:add_one, "3"})
    blueprint = Test.blueprint(pid)

    assert [
             ^one_one,
             ^one
           ] = blueprint[nil]

    assert [^two] = blueprint[one]
    assert [^three] = blueprint[two]
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
