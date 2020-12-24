defprotocol BPXE.Language do
  @spec eval(t, binary) :: {:ok, t | {any, t}} | {:error, term}
  def eval(model, code)

  @spec set(t, String.t(), Map.t()) :: t
  def set(model, name, variables)

  @spec get(t, String.t()) :: term
  def get(model, name)
end
