defmodule SurfContext.Test.Components do
  @moduledoc """
  Test components compiled through `use SurfContext.Component` — this module
  compiling AT ALL proves the `use Phoenix.Component` + import-except sigil
  swap works (the one wiring detail the original PoC didn't cover).

  None of the templates below hand-writes a context attr; every read relies
  on the pre-pass threading.
  """
  use SurfContext.Component

  context_attr()

  def echo(assigns) do
    ~H"""
    <span>c:{@__context__[:who]}</span>
    """
  end

  def parent(assigns) do
    ~H"""
    <div><.echo /></div>
    """
  end

  def root(assigns) do
    ~H"""
    <section><.parent /></section>
    """
  end

  context_attr()

  slot :item do
    attr(:label, :string)
  end

  def with_slots(assigns) do
    ~H|<ul><li :for={item <- @item}>{item[:label]} [{@__context__[:who]}] {render_slot(item)}</li></ul>|
  end

  def edge_root(assigns) do
    ~H"""
    <div>
      <%= if @cond do %><.echo /><% end %>
      <.echo
        multi="line"
      />
      <.with_slots>
        <:item label="a">A</:item>
        <:item label="b"><.echo /></:item>
      </.with_slots>
      <.echo :if={@cond} />
      <.echo :for={_i <- @list} />
    </div>
    """
  end

  # a MID-TREE put: children receive the augmented map, siblings don't
  def scoped_parent(assigns) do
    assigns = SurfContext.put(assigns, who: "inner")

    ~H"""
    <div><.echo /></div>
    """
  end

  def scoped_root(assigns) do
    ~H"""
    <main><.scoped_parent /><.echo /></main>
    """
  end

  def render_to_string(fun, assigns) do
    fun.(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
