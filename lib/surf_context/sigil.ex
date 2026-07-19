defmodule SurfContext.Sigil do
  @moduledoc """
  A drop-in `~H` that runs the context pre-pass before compilation.

  Mirrors `Phoenix.Component.sigil_H` exactly (including the `noformat` modifier), with `SurfContext.Prepass.splice/2` applied to the template literal first. Use via the import-except dance (done for you by `use SurfContext.Component`):

      import Phoenix.Component, except: [sigil_H: 2]
      import SurfContext.Sigil

  Developers keep writing standard `~H`; component call sites just happen to thread `@__context__`.
  """

  defmacro sigil_H({:<<>>, meta, [expr]}, modifiers)
           when modifiers == [] or modifiers == ~c"noformat" do
    if not Macro.Env.has_var?(__CALLER__, {:assigns, nil}) do
      raise "~H requires a variable named \"assigns\" to exist and be set to a map"
    end

    Phoenix.LiveView.TagEngine.compile(SurfContext.Prepass.splice(expr),
      file: __CALLER__.file,
      line: __CALLER__.line + 1,
      caller: __CALLER__,
      indentation: meta[:indentation] || 0,
      tag_handler: Phoenix.LiveView.HTMLEngine
    )
  end
end
