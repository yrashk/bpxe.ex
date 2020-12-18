defprotocol BPXE.Language do
  @spec eval(t, binary) :: {:ok, t | {any, t}} | {:error, term}
  def eval(instance, code)

  @spec set(t, String.t(), Map.t()) :: t
  def set(instance, name, variables)

  @spec get(t, String.t()) :: term
  def get(instance, name)
end
