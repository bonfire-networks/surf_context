defmodule SurfContext.EngineTest do
  use ExUnit.Case, async: true

  test ".heex file on disk is spliced at compile and threads context" do
    tpl_path = Path.join(System.tmp_dir!(), "surf_context_engine_test.heex")
    File.write!(tpl_path, "<article><SurfContext.Test.Components.echo /></article>\n")
    on_exit(fn -> File.rm(tpl_path) end)

    # Emulate what Phoenix.Template does with an engine's compile/2 return:
    # it becomes the body of a template function in the embedding module.
    code = """
    defmodule SurfContext.EngineTest.Embed do
      use SurfContext.Component

      def from_file(var!(assigns)) do
        _ = var!(assigns)
        #{SurfContext.Engine.compile(tpl_path, "surf_context_engine_test") |> Macro.to_string()}
      end
    end
    """

    [{_, _} | _] = Code.compile_string(code)

    html =
      SurfContext.EngineTest.Embed.from_file(%{__context__: %{who: "disk"}, __changed__: nil})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "c:disk"
  after
    :code.purge(SurfContext.EngineTest.Embed)
    :code.delete(SurfContext.EngineTest.Embed)
  end

  test "embed_templates/2 compiles .heex files through the engine (drop-in for Phoenix.Component's)" do
    dir = Path.join(System.tmp_dir!(), "surf_context_embed_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "greeting.heex"), "<p><SurfContext.Test.Components.echo /></p>\n")
    on_exit(fn -> File.rm_rf(dir) end)

    code = """
    defmodule SurfContext.EngineTest.EmbedTemplates do
      use SurfContext.Component

      embed_templates "*", root: #{inspect(dir)}
    end
    """

    [{_, _} | _] = Code.compile_string(code)

    html =
      apply(SurfContext.EngineTest.EmbedTemplates, :greeting, [
        %{__context__: %{who: "embedded"}, __changed__: nil}
      ])
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "c:embedded"
  after
    :code.purge(SurfContext.EngineTest.EmbedTemplates)
    :code.delete(SurfContext.EngineTest.EmbedTemplates)
  end
end
