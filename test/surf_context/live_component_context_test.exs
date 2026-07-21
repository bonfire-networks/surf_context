defmodule SurfContext.LiveComponentContextTest do
  @moduledoc """
  A live component threads `__context__` through `update/2`'s assigns (unlike
  function components, which get it on their `assigns` map). Surface's
  LiveComponent wrapper lifted `:__context__` onto the socket (via
  `move_private_assigns`) BEFORE the module's own `update/2`, so a custom
  `def update(_assigns, socket)` that ignores its assigns still had context at
  render. `use SurfContext` must reproduce that, or every converted stateful
  component with a custom update silently loses `@__context__`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defmodule IgnoringUpdateLC do
    use Phoenix.LiveComponent
    use SurfContext

    # the common Surface pattern: a custom update that recomputes its own state
    # and IGNORES the incoming assigns entirely
    def update(_assigns, socket), do: {:ok, socket}

    def render(assigns) do
      ~H"<span>who:{assigns[:__context__][:who]}</span>"
    end
  end

  test "custom update/2 that ignores assigns still gets __context__ onto the socket" do
    html = render_component(IgnoringUpdateLC, id: "x", __context__: %{who: "alice"})
    assert html =~ "who:alice"
  end
end
