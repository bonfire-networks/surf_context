defmodule SurfContext.Component do
  @moduledoc """
  `use SurfContext.Component` in a component module to get `Phoenix.Component` with the context-threading `~H` swapped in:

      defmodule MyApp.CardLive do
        use SurfContext.Component

        context_attr()
        attr :title, :string, required: true

        def render(assigns) do
          ~H\"\"\"
          <div>{@title} — seen by {current_user_name(@__context__)}</div>
          \"\"\"
        end
      end

  `context_attr()` declares `attr :__context__, :map, default: nil`, it silences the HEEx verifier warning on components that declare other attrs, and the nil default keeps the component safe when rendered from a template that wasn't compiled with the pre-pass (context reads return nil instead of raising).
  """

  defmacro __using__(opts) do
    quote do
      use Phoenix.Component, unquote(Keyword.take(opts, [:global_prefixes]))
      use SurfContext
    end
  end

  @doc """
  Declares the context attribute on the next function component definition.
  """
  defmacro context_attr do
    attr = SurfContext.Prepass.default_attr()

    quote do
      require Phoenix.Component
      Phoenix.Component.attr(unquote(attr), :map, default: nil)
    end
  end

  @doc """
  Drop-in for `Phoenix.Component.embed_templates/2` that compiles the `.heex` files through `SurfContext.Engine`, so their component call sites thread context. Same options (`:root`, `:suffix`), same generated functions, only the engine differs, and only for the templates YOU embed (dependencies are unaffected, unlike global engine registration).

      use SurfContext.Component
      embed_templates "page_html/*"
  """
  defmacro embed_templates(pattern, opts \\ []) do
    quote bind_quoted: [pattern: pattern, opts: opts] do
      require Phoenix.Template

      Phoenix.Template.compile_all(
        &Phoenix.Component.__embed__(&1, opts[:suffix]),
        Path.expand(opts[:root] || __DIR__, __DIR__),
        pattern,
        %{heex: SurfContext.Engine}
      )
    end
  end
end
