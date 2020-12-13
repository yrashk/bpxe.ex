defprotocol BPEXE.Language do
  @spec eval(t, binary) :: {:ok, t | {any, t}} | {:error, term}
  def eval(instance, code)
end
