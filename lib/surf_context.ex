defmodule SurfContext do
  @moduledoc """
  Implicit context for Phoenix LiveView components, with no prop drilling, no runtime magic, full change tracking, plain HEEx output.
  """

  @doc """
  Swaps the context-threading `~H` and `embed_templates` into a module where `Phoenix.Component` is already set up, via `use Phoenix.LiveView`, `use Phoenix.LiveComponent`, `use Phoenix.Component`, or a web-macro layer:

      use MyAppWeb, :live_view   # or anything that sets up Phoenix.Component
      use SurfContext

  For standalone component modules use `SurfContext.Component` instead, which does `use Phoenix.Component` for you and then this.
  """
  defmacro __using__(_opts) do
    quote do
      import Phoenix.Component, except: [sigil_H: 2, embed_templates: 1, embed_templates: 2]
      import SurfContext.Sigil

      import SurfContext.Component,
        only: [context_attr: 0, embed_templates: 1, embed_templates: 2]

      import SurfContext, only: [context: 2, context: 3]

      @before_compile SurfContext
    end
  end

  @doc false
  # Auto-declares the context attr (`attr :__context__, :map, default: nil`) on
  # EVERY function component of the module, zero per-component code.
  #
  # Mechanics: @before_compile hooks run in REGISTRATION order, and `use
  # SurfContext` always comes after `use Phoenix.Component` (directly or via
  # LiveView/web macros), so this runs AFTER Phoenix.Component.Declarative has
  # already generated `__components__/0` and the default-merging wrappers from
  # the unpatched declarations. So instead of patching the attribute up front,
  # we override what Declarative generated:
  #   1. redefine `__components__/0` with the patched map → the HEEx verifier
  #      sees the attr as declared (no "undefined attribute" warnings), and
  #   2. re-wrap each patched component with `Map.put_new(assigns, attr, nil)`
  #      → the nil default applies even for un-threaded callers.
  # Components that already declare the attr (e.g. via `context_attr()`) are
  # skipped; modules without Phoenix.Component set up are a no-op.
  defmacro __before_compile__(env) do
    attr_name = SurfContext.Prepass.default_attr() |> String.to_atom()
    components = Module.get_attribute(env.module, :__components__)

    if is_map(components) and map_size(components) > 0 do
      {patched, wrapped} =
        Enum.reduce(components, {%{}, []}, fn
          {name, %{attrs: attrs, kind: kind} = comp}, {acc, wrapped} ->
            cond do
              Enum.any?(attrs, &(&1.name == attr_name)) ->
                {Map.put(acc, name, comp), wrapped}

              # zero-declaration components are verifier-EXEMPT, declaring our
              # attr would activate undefined-attr checks for all their ad-hoc
              # attrs. Leave them exempt; the nil-default wrapper still applies.
              attrs == [] and comp[:slots] in [[], nil] ->
                {Map.put(acc, name, comp), [{name, kind} | wrapped]}

              true ->
                entry = %{
                  slot: nil,
                  name: attr_name,
                  type: :map,
                  required: false,
                  opts: [default: nil],
                  doc: false,
                  line: comp[:line] || env.line
                }

                {Map.put(acc, name, %{comp | attrs: attrs ++ [entry]}), [{name, kind} | wrapped]}
            end

          {name, comp}, {acc, wrapped} ->
            {Map.put(acc, name, comp), wrapped}
        end)

      # keep the attribute consistent for any later readers
      Module.put_attribute(env.module, :__components__, patched)

      components_override =
        if Module.defines?(env.module, {:__components__, 0}) do
          quote do
            defoverridable __components__: 0
            def __components__(), do: unquote(Macro.escape(patched))
          end
        end

      default_wrappers =
        for {name, kind} <- wrapped, Module.defines?(env.module, {name, 1}) do
          quote do
            defoverridable [{unquote(name), 1}]

            Kernel.unquote(kind)(unquote(name)(assigns)) do
              super(Map.put_new(assigns, unquote(attr_name), nil))
            end
          end
        end

      quote do
        unquote(components_override)
        unquote_splicing(default_wrappers)
      end
    else
      quote do
      end
    end
  end

  @doc """
  Merges `values` into the context assign of a socket, an assigns map, or a `Plug.Conn`. Later writes win. Marks the assign changed (sockets/assigns), so components re-render per normal change tracking.

  Works from anywhere, and flows down from there: at the top of the tree (LiveView `mount`, an `on_mount` hook, or a plug) the values reach the whole tree; inside a component (on its `assigns` before `~H`, or its socket in `update/2`) they reach only that component's subtree, every call site threads its caller's map, so siblings keep the outer context. Positional subtree scoping, for free:

      def themed_section(assigns) do
        assigns = SurfContext.put(assigns, theme: :dark)   # everything below is dark
        ~H\"\"\"
        <section><.card /><.button /></section>
        \"\"\"
      end
  """
  def put(socket_or_assigns_or_conn, values)

  def put(%Phoenix.LiveView.Socket{} = socket, values) do
    Phoenix.Component.assign(socket, attr_key(), merged(socket.assigns, values))
  end

  if Code.ensure_loaded?(Plug.Conn) do
    def put(%Plug.Conn{} = conn, values) do
      Plug.Conn.assign(conn, attr_key(), merged(conn.assigns, values))
    end
  end

  def put(%{__changed__: _} = assigns, values) do
    Phoenix.Component.assign(assigns, attr_key(), merged(assigns, values))
  end

  @doc """
  Reads `key` from the context of a socket, assigns map, conn, or a bare
  context map. Returns `default` when absent (including when no context was
  ever threaded — nil-safe).
  """
  def get(source, key, default \\ nil)

  def get(%Phoenix.LiveView.Socket{assigns: assigns}, key, default),
    do: get(assigns, key, default)

  if Code.ensure_loaded?(Plug.Conn) do
    def get(%Plug.Conn{assigns: assigns}, key, default), do: get(assigns, key, default)
  end

  def get(%{} = assigns_or_context, key, default) do
    context = Map.get(assigns_or_context, attr_key(), assigns_or_context)
    if is_map(context), do: Map.get(context, key, default), else: default
  end

  def get(_, _key, default), do: default

  @doc "Alias of `get/3` for template ergonomics: `context(@__context__, :key)`."
  def context(source, key, default \\ nil), do: get(source, key, default)

  defp merged(assigns, values) do
    Map.merge(Map.get(assigns, attr_key()) || %{}, Map.new(values))
  end

  defp attr_key, do: SurfContext.Prepass.default_attr() |> String.to_atom()
end
