defmodule BPXETest.Service do
  use ExUnit.Case
  doctest BPXE.Service
  alias BPXE.Engine.Blueprint

  defmodule Service do
    use BPXE.Service
  end

  test "service should go down if blueprint is going down" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, service} = BPXE.Service.start_link(Service)
    Blueprint.register_service(pid, "service", service)

    Process.unlink(pid)
    Process.unlink(service)

    bp_ref = Process.monitor(pid)
    service_ref = Process.monitor(service)

    Process.exit(pid, :kill)

    assert_receive {:DOWN, ^bp_ref, :process, ^pid, _}
    assert_receive {:DOWN, ^service_ref, :process, ^service, _}
  end

  test "blueprint should not go down if service is going down" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, service} = BPXE.Service.start_link(Service)
    Blueprint.register_service(pid, "service", service)

    Process.unlink(pid)
    Process.unlink(service)

    bp_ref = Process.monitor(pid)
    service_ref = Process.monitor(service)

    Process.exit(service, :kill)

    assert_receive {:DOWN, ^service_ref, :process, ^service, _}
    refute_receive {:DOWN, ^bp_ref, :process, ^pid, _}
  end
end
