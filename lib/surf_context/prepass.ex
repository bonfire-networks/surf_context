defmodule SurfContext.Prepass do
  @moduledoc """
  The compile-time pre-pass: inserts a context attribute into every component call site of a HEEx source string, so context flows through the tree with full change tracking, exactly as if the attribute had been written by hand.

  This is a token-guided source transform: the template is tokenized with LiveView's own tokenizer (`Phoenix.LiveView.TagEngine.Parser.tokenize/2`), insertion points are collected for component tags only, and the attribute text is spliced into the source bottom-up. The modified source is then compiled by the standard HEEx engine, the output is plain HEEx semantics.

  Not touched: HTML tags, slot entries (`<:name>`), HTML comments, script/style contents, tags that already carry the attribute, and tags on the skip list.

  > #### Internal API dependency {: .warning}
  > The tokenizer is `@moduledoc false` internal LiveView API. The test suite includes a canary test that fails loudly if an upgrade moves it.
  """

  @default_attr "__context__"
  # components that must not receive the attribute (Phoenix built-ins that declare attrs, would emit verifier warnings, and can't read context).
  # NOTE: live_component/dynamic_component are deliberately NOT skipped, their extra attrs pass through to the rendered component, which is precisely how stateful/dynamic components receive context.
  @default_skip ~w(link form input async_result focus_wrap intersperse)

  @doc """
  Splices ` \#{attr}={\#{expr}}` into every component tag of `source`.

  ## Options

    * `:attr` — attribute name to insert (default `"#{@default_attr}"`)
    * `:expr` — expression for the attribute value (derived from the attr — `"@<attr>"` — unless overridden)
    * `:skip` — component names to leave untouched. Entries match local component names (`"link"` for `<.link>`) or full remote tag names (`"Some.Module.render"`). Defaults to `config :surf_context, :skip` or a small list of Phoenix built-ins.
    * `:skip_modules` — modules whose components are all left untouched (e.g. `[MyAppWeb.CoreComponents]`). Matched against the module part of remote tags as written, by suffix segment, so it also matches aliased calls like `<CoreComponents.button>`. Defaults to `config :surf_context, :skip_modules` (`[]`).
    * `:tag_handler` — tag handler for classification (default `Phoenix.LiveView.HTMLEngine`)
  """
  def splice(source, opts \\ []) when is_binary(source) do
    attr = Keyword.get(opts, :attr, default_attr())
    # derived from the effective attr unless explicitly overridden
    expr = Keyword.get(opts, :expr, Application.get_env(:surf_context, :expr, "@" <> attr))
    skip = Keyword.get(opts, :skip, default_skip())
    skip_modules = Keyword.get(opts, :skip_modules, default_skip_modules()) |> normalize_modules()
    tag_handler = Keyword.get(opts, :tag_handler, Phoenix.LiveView.HTMLEngine)

    insertion = " #{attr}={#{expr}}"

    tokens =
      Phoenix.LiveView.TagEngine.Parser.tokenize(source, tag_handler: tag_handler)

    insertions =
      for token <- tokens,
          {name, attrs, meta} <- [component_token(token)],
          name != nil,
          name not in skip,
          not skip_module?(name, skip_modules),
          not has_attr?(attrs, attr) do
        {meta.line, meta.column}
      end

    apply_insertions(source, insertions, insertion)
  end

  def default_attr, do: Application.get_env(:surf_context, :attr, @default_attr)

  # derived from the attr name unless explicitly overridden, two independent
  # knobs would invite a silently-broken pair (attr "ctx" + expr "@__context__")
  def default_expr, do: Application.get_env(:surf_context, :expr, "@" <> default_attr())

  def default_skip, do: Application.get_env(:surf_context, :skip, @default_skip)

  def default_skip_modules, do: Application.get_env(:surf_context, :skip_modules, [])

  # entries may be modules or strings; matched against the module part of a
  # remote tag AS WRITTEN in the template — since templates usually use
  # aliases, matching is by suffix segment (`CoreComponents` matches both
  # `<CoreComponents.button>` and `<MyAppWeb.CoreComponents.button>`)
  defp normalize_modules(mods) do
    Enum.map(mods, fn
      m when is_atom(m) -> m |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
      m when is_binary(m) -> m
    end)
  end

  defp skip_module?(name, []) when is_binary(name), do: false

  defp skip_module?(name, skip_modules) do
    case name |> String.split(".") |> Enum.drop(-1) do
      [] ->
        false

      segments ->
        module_part = Enum.join(segments, ".")

        Enum.any?(skip_modules, fn m ->
          # bidirectional suffix match: the tag may be written with a SHORTER
          # alias than the configured module (`<CoreComponents.button>` vs
          # MyAppWeb.CoreComponents) or with MORE segments than a short entry
          module_part == m or
            String.ends_with?(module_part, "." <> m) or
            String.ends_with?(m, "." <> module_part)
        end)
    end
  end

  defp component_token({:local_component, name, attrs, meta}), do: {name, attrs, meta}
  defp component_token({:remote_component, name, attrs, meta}), do: {name, attrs, meta}
  defp component_token(_), do: {nil, nil, nil}

  defp has_attr?(attrs, attr) do
    Enum.any?(attrs, fn a -> elem(a, 0) == attr end)
  end

  # Insert right after the tag name. meta.column is 1-based and points at the
  # `<`; we scan past the tag name to find the insertion offset, then apply
  # insertions bottom-up so earlier positions stay valid.
  defp apply_insertions(source, insertions, insertion) do
    lines = String.split(source, "\n")

    insertions
    |> Enum.sort(:desc)
    |> Enum.reduce(lines, fn {line_no, col}, acc ->
      List.update_at(acc, line_no - 1, fn line ->
        {before, rest} = String.split_at(line, col - 1)
        # rest starts at "<"; the tag name runs until whitespace / ">" / "/"
        [tag_open | _] = String.split(rest, ~r/(?=[\s>\/])/, parts: 2)
        {head, tail} = String.split_at(rest, String.length(tag_open))
        before <> head <> insertion <> tail
      end)
    end)
    |> Enum.join("\n")
  end
end
