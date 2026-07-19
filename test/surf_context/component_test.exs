defmodule SurfContext.ComponentTest do
  use ExUnit.Case, async: true

  # explicit context_attr() — still supported, must not double-declare with auto
  @declared_code ~S'''
  defmodule SurfContext.ComponentTest.Declared do
    use SurfContext.Component

    context_attr()
    attr :label, :string, default: "x"

    def tag(assigns) do
      ~H"""
      <i>{@label}:{@__context__[:who]}</i>
      """
    end

    def threaded(assigns) do
      ~H"""
      <.tag label="t" />
      """
    end
  end
  '''

  # NO manual context_attr(), the @before_compile auto-declaration must cover it
  @auto_code @declared_code
             |> String.replace("context_attr()", "")
             |> String.replace("Declared", "Auto")

  # positive control: callee compiled with PLAIN Phoenix.Component (no SurfContext, no auto-declaration), a threaded caller passing __context__ must still warn, proving the verifier check is real and the auto-declaration is what silences it
  @plain_callee_code ~S'''
  defmodule SurfContext.ComponentTest.PlainCallee do
    use Phoenix.Component

    attr :label, :string, default: "x"

    def tag(assigns) do
      ~H"""
      <i>{@label}</i>
      """
    end
  end
  '''

  @threaded_caller_code ~S'''
  defmodule SurfContext.ComponentTest.ThreadedCaller do
    use SurfContext.Component

    def call(assigns) do
      ~H"""
      <SurfContext.ComponentTest.PlainCallee.tag label="c" />
      """
    end
  end
  '''

  # an UNTHREADED caller: plain Phoenix ~H (no pre-pass), context not passed
  @unthreaded_code ~S'''
  defmodule SurfContext.ComponentTest.Unthreaded do
    use Phoenix.Component

    def call(assigns) do
      ~H"""
      <SurfContext.ComponentTest.Auto.tag label="u" />
      """
    end
  end
  '''

  # `use SurfContext` (imports-only) layered on an existing Phoenix.Component
  # setup — the html_helpers/web-macro pattern from the README
  @layered_code ~S'''
  defmodule SurfContext.ComponentTest.Layered do
    use Phoenix.Component
    use SurfContext

    def child(assigns) do
      ~H"""
      <b>l:{@__context__[:who]}</b>
      """
    end

    def caller(assigns) do
      ~H"""
      <.child />
      """
    end
  end
  '''

  defp undeclared_warning?(diags) do
    Enum.any?(diags, &(&1.message =~ ~s(undefined attribute "__context__")))
  end

  defp compile_quiet(code) do
    Code.with_diagnostics([log: false], fn -> Code.compile_string(code) end)
  end

  # apply/3 with runtime-resolved modules avoids compile-time warnings about
  # modules that only exist after Code.compile_string runs
  defp render(mod, fun, assigns) do
    apply(mod, fun, [assigns]) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  test "context attr is AUTO-declared on every component; explicit context_attr() doesn't double up; plain-Phoenix callees still warn (control)" do
    {_, declared_diags} = compile_quiet(@declared_code)
    refute undeclared_warning?(declared_diags), "explicit context_attr() should silence verifier"

    {_, auto_diags} = compile_quiet(@auto_code)

    refute undeclared_warning?(auto_diags),
           "auto-declaration should silence verifier without context_attr()"

    # no duplicate entry when both auto and explicit declaration are present
    declared_attrs = SurfContext.ComponentTest.Declared.__components__()[:tag].attrs
    assert Enum.count(declared_attrs, &(&1.name == :__context__)) == 1

    auto_attrs = SurfContext.ComponentTest.Auto.__components__()[:tag].attrs
    assert Enum.count(auto_attrs, &(&1.name == :__context__)) == 1

    # positive control: plain-Phoenix callee + threaded caller → the warning is real
    {_, _} = compile_quiet(@plain_callee_code)
    {_, control_diags} = compile_quiet(@threaded_caller_code)
    assert undeclared_warning?(control_diags), "plain callee should warn (else test is vacuous)"

    # threaded render works
    threaded =
      render(SurfContext.ComponentTest.Auto, :threaded, %{
        __context__: %{who: "z"},
        __changed__: nil
      })

    assert threaded =~ "t:z"

    # plain-~H caller: no context threaded → auto nil default → renders, no KeyError
    {_, _} = compile_quiet(@unthreaded_code)
    unthreaded = render(SurfContext.ComponentTest.Unthreaded, :call, %{__changed__: nil})
    assert unthreaded =~ "u"
  end

  test "use SurfContext layers onto an existing Phoenix.Component setup" do
    [{_, _} | _] = Code.compile_string(@layered_code)

    html =
      render(SurfContext.ComponentTest.Layered, :caller, %{
        __context__: %{who: "layered"},
        __changed__: nil
      })

    assert html =~ "l:layered"
  end
end
