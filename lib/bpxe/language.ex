defprotocol BPXE.Language do
  @spec eval(t, binary) :: {:ok, t | {any, t}} | {:error, term}
  def eval(blueprint, code)

  @spec set(t, String.t(), Map.t()) :: t
  def set(blueprint, name, variables)

  @spec get(t, String.t()) :: term
  def get(blueprint, name)
end
