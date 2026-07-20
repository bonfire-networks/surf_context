# SurfContext

Implicit context assigns for Phoenix LiveView components, without prop drilling or runtime magic, with full change tracking and plain HEEx output.

Put values in once at the root LiveView or a parent component, and they *surf* through the component tree, passing through components that never mention them, and surfacing exactly wherever a component reads them. 

LiveView deliberately has [no context API](https://github.com/phoenixframework/phoenix_live_view/issues/2445). The usual workaround of putting one `@context` map assign and manually passing to every component works, but you have to remember to pass it through every intermediate component. 

SurfContext makes the passing invisible: a **compile-time pre-pass** inserts `__context__={@__context__}` into every component call site of your templates, exactly as if you had typed it. Because the output is plain HEEx, change tracking, slots, `:if`/`:for`, and the verifier all behave normally, there is nothing to learn and nothing to debug at runtime.

```elixir
# write once, at the top (mount, plug, wherever)
socket = SurfContext.put(socket, current_user: user, locale: "fr")
```

```heex
<%!-- any component, any depth, zero plumbing in between --%>
<span>{@__context__[:current_user].name}</span>
```

## Standing on the shoulders of Surface 🏄

The name is a homage to **[Surface](https://github.com/surface-ui/surface)**, which pioneered contexts for LiveView (along with much of what later became `attr`/`slot`/HEEx itself) and whose compiler threading `@__context__` into every component call site is the design this library recreates. SurfContext is that one idea: when [Bonfire](https://bonfirenetworks.org) prepared to migrate hundreds of components from Surface to plain LiveView, contexts were the single feature with no LiveView equivalent, so we kept Surface's semantics and reimplemented the threading as a small pre-pass over LiveView's own compiler. If you're leaving Surface too, your `Context.put`-style writes and `@__context__` reads carry over verbatim. Thank you, [Marlus Saraiva](https://github.com/msaraiva) and Surface contributors, for years of pushing LiveView's component model forward.


## What this is not

- Not name-scoped: no per-provider namespacing of keys (Surface deprecated its scope-aware contexts for diff-tracking reasons; we follow suit). Scoping by *position* works instead (see How it works below).
- Not a store: values live in assigns, nowhere else.
- Not a framework: ~300 lines over LiveView's own compiler.
- Not a runtime: **everything happens at compile time.** After compilation your templates are exactly what you'd have written by hand, with the injected attrs added as ordinary HEEx, and the only code that runs in production is `put`/`get` (a map merge and a map lookup). No processes, no ETS, no hooks into the render path.

## How it works

The template source is tokenized with LiveView's own tokenizer; ` __context__={@__context__}` is spliced into component tags (HTML tags, slot entries, comments, script/style contents, already-attributed tags, and a configurable skip-list are left untouched); the modified source is compiled by the standard HEEx engine. That's the whole trick: Surface's context feature over plain HEEx, with the option of pruning the threading per call site later (for finer re-render behavior), since the output is ordinary HEEx. `SurfContext.put/2` is just a map-merge into the `:__context__` assign (marking it changed, so tracking works), and reads are plain `@__context__[:key]`, or `SurfContext.context/3` for nil-safe access.

And `put` isn't root-only: since every call site threads its *caller's* map, a `put` inside any component flows down from there, only that component's subtree sees the change, siblings keep the outer map. Positional subtree scoping, for free:

```elixir
def themed_section(assigns) do
  assigns = SurfContext.put(assigns, theme: :dark)   # everything below is dark
  ~H"""
  <section><.card /><.button /></section>
  """
end
```

## Installation

```elixir
def deps do
  [
    {:surf_context, "~> 0.1.0"}
  ]
end
```

Then wire the pre-pass in where your templates get compiled. Find your situation:

**Standard Phoenix app** (where components have `use MyAppWeb, :html` / `:live_view` / `:live_component`): edit `lib/my_app_web.ex` and add ONE line to the shared helpers (the `html_helpers` private function in a default phx.new project), AFTER the existing `use`/`import Phoenix.Component`:

```elixir
defp html_helpers do
  quote do
    # ... existing uses/imports ...
    use SurfContext
  end
end
```

(`use SurfContext` swaps `~H` and `embed_templates` for the threading versions — keeping this a single line also means future versions of the library can extend the swap without you updating your web module.)

This covers BOTH template kinds everywhere the web module is used: every inline `~H` (the sigil swap) and every embedded `.heex` file — `Layouts`' `root/app.html.heex`, controller HTML modules' `embed_templates "page_html/*"` — because those calls now resolve to this library's drop-in `embed_templates` (same options, same generated functions, only the engine differs; your dependencies are unaffected, unlike global engine registration).

The context attr is **declared automatically** on every component in modules wired through SurfContext (a `@before_compile` hook adds `attr :__context__, :map, default: nil` for you — verifier-clean, and safe to render from un-threaded templates). One papercut remains for components in modules NOT wired through SurfContext (e.g. a plain-`Phoenix.Component` `CoreComponents`): threaded callers will trigger the HEEx verifier's undefined-attribute warning there. Fix per taste: add those component names to the `skip:` config (right for pure-UI components that never read context), wire the module through SurfContext too, or add the explicit `context_attr()` helper above specific components.

**App with its own web-macro layer**: same `use SurfContext` line, in whichever quoted context hands components their imports; if you have your own template-embedding macros, you can alternatively wire `SurfContext.Engine` into them directly (see that module's docs).

**Standalone component modules** (no web module): `use SurfContext.Component` instead of `use Phoenix.Component` — identical, with the threading `~H` and `embed_templates` swapped in (plus the optional `context_attr()` helper).

Last step, actually write some context with `SurfContext.put/2` whenever needed. Anywhere works: typically at the top of the tree (LiveView `mount` or `handle_params`, an `on_mount` hook, or a plug) for app-wide values like the current user, but a `put` inside any component scopes to just that component's subtree (see How it works). Reads work immediately everywhere below the write.

## Usage

```elixir
defmodule MyApp.CardLive do
  use SurfContext.Component   # Phoenix.Component with the pre-pass ~H swapped in
                              # (attr :__context__ is auto-declared on every component)
  attr :title, :string, required: true

  def render(assigns) do
    ~H"""
    <div>{@title} — {@__context__[:locale]}</div>
    """
  end
end
```

## Configuration

```elixir
config :surf_context,
  # attribute/assign name, an atom (the injected expression is derived: @<attr>)
  attr: :__context__,
  # component names never threaded (Phoenix built-ins that declare attrs and can't read context); override replaces the whole list.
  # live_component/dynamic_component ARE threaded: their extra attrs flow to the rendered component, that's how stateful components receive context
  skip: ~w(link form input async_result focus_wrap intersperse),
  # modules whose components are never threaded (alias-aware suffix match), e.g. [MyAppWeb.CoreComponents]
  skip_modules: []
```

Read at compile time (the pre-pass runs during template compilation), changing these requires recompiling the affected templates (`mix compile --force`, or touch the files).

## Status

The mechanism (splice fidelity, threading, change tracking, sigil, engine, verifier interplay) is covered by the test suite, which doubles as a canary against LiveView-internal API drift.
