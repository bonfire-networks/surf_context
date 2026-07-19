defmodule SurfContext.ThreadingTest do
  use ExUnit.Case, async: true

  alias SurfContext.Test.Components, as: C

  test "context reaches a component two levels deep with zero hand-written attrs" do
    html = C.render_to_string(&C.root/1, %{__context__: %{who: "world"}, __changed__: nil})
    assert html =~ "c:world"
  end

  test "change tracking: skipped when unchanged, re-executed fresh when changed" do
    skipped = C.root(%{__context__: %{who: "world"}, __changed__: %{}})
    changed = C.root(%{__context__: %{who: "moon"}, __changed__: %{__context__: true}})

    assert Enum.all?(skipped.dynamic.(true), &is_nil/1),
           "component call re-executed despite unchanged __context__"

    refute Enum.all?(changed.dynamic.(true), &is_nil/1),
           "component call skipped despite changed __context__"

    assert changed |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary() =~ "c:moon"
  end

  test "put anywhere: a mid-tree put flows down that subtree only" do
    html =
      C.render_to_string(&C.scoped_root/1, %{
        __context__: %{who: "outer"},
        __changed__: nil
      })

    # child inside scoped_parent sees the augmented map; the sibling echo does not
    assert html =~ "c:inner"
    assert html =~ "c:outer"
  end

  test "edge forms compile and render with implicit context" do
    html =
      C.render_to_string(&C.edge_root/1, %{
        __context__: %{who: "w"},
        cond: true,
        list: [1, 2],
        __changed__: nil
      })

    # if-block + multiline + slot-b child + :if + 2× :for = 6 context-reading echoes
    assert html |> String.split("c:w") |> length() == 7
    # with_slots itself reads context in both :for iterations
    assert html |> String.split("[w]") |> length() == 3
  end
end
