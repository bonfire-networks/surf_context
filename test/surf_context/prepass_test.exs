defmodule SurfContext.PrepassTest do
  use ExUnit.Case, async: true

  alias SurfContext.Prepass

  test "splices the attr into component tags only (fidelity fixture)" do
    fixture = """
    <div class="x">
      <.child />
      <.child some_attr={@foo}>inner</.child>
      <Some.Remote.child />
      <.child __context__={%{}} />
      <.link href="/">nope</.link>
    </div>
    """

    expected = """
    <div class="x">
      <.child __context__={@__context__} />
      <.child __context__={@__context__} some_attr={@foo}>inner</.child>
      <Some.Remote.child __context__={@__context__} />
      <.child __context__={%{}} />
      <.link href="/">nope</.link>
    </div>
    """

    assert Prepass.splice(fixture) == expected
  end

  test "edge cases: eex blocks, multi-line tags, slots, :if/:for, comments, script/style, unicode, skip-list" do
    fixture = """
    <div>
      <%= if @cond do %>
        <.child />
      <% end %>
      {@some_interpolation}
      <.child
        multi="line"
        attrs={@x}
      />
      <.with_slots>
        <:item label="a">slot body</:item>
        <:item label="b"><.child /></:item>
      </.with_slots>
      <.child :if={@cond} />
      <.child :for={i <- @list} idx={i} />
      <!-- <.child /> not real, inside comment -->
      <script>var x = "<.child />";</script>
      <style>.child::before { content: "<.child/>"; }</style>
      🔥🔥 café <.child unicode="before me" />
      <.live_component module={SomeMod} id="x" />
      <.link href="/">skip</.link>
    </div>
    """

    expected = """
    <div>
      <%= if @cond do %>
        <.child __context__={@__context__} />
      <% end %>
      {@some_interpolation}
      <.child __context__={@__context__}
        multi="line"
        attrs={@x}
      />
      <.with_slots __context__={@__context__}>
        <:item label="a">slot body</:item>
        <:item label="b"><.child __context__={@__context__} /></:item>
      </.with_slots>
      <.child __context__={@__context__} :if={@cond} />
      <.child __context__={@__context__} :for={i <- @list} idx={i} />
      <!-- <.child /> not real, inside comment -->
      <script>var x = "<.child />";</script>
      <style>.child::before { content: "<.child/>"; }</style>
      🔥🔥 café <.child __context__={@__context__} unicode="before me" />
      <.live_component __context__={@__context__} module={SomeMod} id="x" />
      <.link href="/">skip</.link>
    </div>
    """

    assert Prepass.splice(fixture) == expected
  end

  test "custom attr (expr derived), explicit expr override, and skip options" do
    # expr derives from attr when not given
    assert Prepass.splice("<.thing /><.other />", attr: "ctx", skip: ~w(other)) ==
             ~s(<.thing ctx={@ctx} /><.other />)

    # explicit expr still wins
    assert Prepass.splice("<.thing />", attr: "ctx", expr: "@my_ctx") ==
             ~s(<.thing ctx={@my_ctx} />)
  end

  test "skip_modules: skips all components of a module, alias-aware (suffix match)" do
    src =
      ~s(<MyAppWeb.CoreComponents.button /><CoreComponents.icon /><Other.Mod.render /><.local />)

    assert Prepass.splice(src, skip_modules: [MyAppWeb.CoreComponents]) ==
             ~s(<MyAppWeb.CoreComponents.button /><CoreComponents.icon /><Other.Mod.render __context__={@__context__} /><.local __context__={@__context__} />)

    # string entries work too
    assert Prepass.splice("<UI.Kit.badge />", skip_modules: ["UI.Kit"]) == "<UI.Kit.badge />"
  end

  # CANARY: the tokenizer is internal LiveView API (@moduledoc false).
  # If an LV upgrade moves or reshapes it, fail here loudly — before anything
  # else breaks confusingly.
  test "canary: LV internal tokenizer API shape" do
    tokens =
      Phoenix.LiveView.TagEngine.Parser.tokenize(
        ~s(<div><.local x="1" /><Some.Remote.render /><:slot_entry /></div>),
        tag_handler: Phoenix.LiveView.HTMLEngine
      )

    kinds = Enum.map(tokens, &elem(&1, 0))
    assert :local_component in kinds
    assert :remote_component in kinds
    assert :tag in kinds

    assert {:local_component, "local", [attr | _], %{line: 1, column: _}} =
             Enum.find(tokens, &(elem(&1, 0) == :local_component))

    assert elem(attr, 0) == "x"
  end
end
