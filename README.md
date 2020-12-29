# BPXE (Business Process eXecution Engine)

[![Hex pm](http://img.shields.io/hexpm/v/bpxe.svg?style=flat)](https://hex.pm/packages/bpxe)

BPMN 2.0 based business process execution engine implemented in
[Elixir](https://elixir-lang.org). BPMN stands for **Business Process Model and
Notation**. BPMN's goal is to help stakeholders to have a shared understanding
of processes.

BPXE focuses on the execution aspect of such notation, effectively allowing the
processes described in BPMN to function as if they were programs. BPXE is not
the only such engine, as there are many commercially or community supported
ones. The motivation behind the creation of BPXE was to create an engine that
integrates natively with Erlang/Elixir systems, with a particular focus on
being lightweight (a great deal of processes should be able to operate even on
a single server concurrently) and resistant to failures so that workflows can
be resumed with little to no consideration when a failure happen.

# Usage

As BPXE is not really a standalone server in its own right, it's shipped as a
"library" Erlang application. Its [package](https://hex.pm/packages/bpxe) can
be included into an application by adding `bpxe` to
the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bpxe, "~> 0.3.0"}
  ]
end
```
