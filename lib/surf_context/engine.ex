defmodule SurfContext.Engine do
  @moduledoc """
  A `Phoenix.Template.Engine` for `.heex` files that runs the context pre-pass before compilation.

  Mirrors `Phoenix.LiveView.HTMLEngine`'s callback→macro pattern: the behaviour callback returns a quoted call to `compile/1`, which expands in the template module (gaining `__CALLER__`), reads the file, splices, and hands the result to the standard `Phoenix.LiveView.TagEngine`.

  Wire it through your own template-embedding macros (recommended, as global engine registration for `.heex` would also affect dependencies):

      quote do
        require SurfContext.Engine
        def render_template(var!(assigns)) do
          unquote(SurfContext.Engine.compile(path, name))
        end
      end
  """

  @behaviour Phoenix.Template.Engine

  @impl true
  def compile(path, _name) do
    quote do
      require SurfContext.Engine
      SurfContext.Engine.compile(unquote(path))
    end
  end

  @doc false
  defmacro compile(path) do
    trim = Application.get_env(:phoenix, :trim_on_html_eex_engine, true)
    source = path |> File.read!() |> SurfContext.Prepass.splice()

    Phoenix.LiveView.TagEngine.compile(source,
      engine: Phoenix.LiveView.Engine,
      file: path,
      line: 1,
      caller: __CALLER__,
      tag_handler: Phoenix.LiveView.HTMLEngine,
      trim: trim
    )
  end
end
