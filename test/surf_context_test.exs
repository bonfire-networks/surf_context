defmodule SurfContextTest do
  use ExUnit.Case, async: true

  test "put/get on a LiveView socket: merge, later-wins, marks changed" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    socket =
      socket
      |> SurfContext.put(who: "sock", a: 1)
      |> SurfContext.put(a: 2)

    assert SurfContext.get(socket, :who) == "sock"
    assert SurfContext.get(socket, :a) == 2
    assert socket.assigns.__changed__[:__context__]
  end

  test "put/get on an assigns map" do
    assigns = SurfContext.put(%{__changed__: %{}}, a: 1)
    assert SurfContext.get(assigns, :a) == 1
    assert SurfContext.get(assigns, :missing, :fallback) == :fallback
  end

  test "put/get on a Plug.Conn" do
    conn = %Plug.Conn{}
    conn = SurfContext.put(conn, who: "conn")
    assert SurfContext.get(conn, :who) == "conn"
  end

  test "get on a bare context map (template ergonomics) and nil-safety" do
    assert SurfContext.context(%{who: "bare"}, :who) == "bare"
    assert SurfContext.get(nil, :anything, :default) == :default
    assert SurfContext.get(%{__context__: nil}, :anything, :default) == :default
  end
end
