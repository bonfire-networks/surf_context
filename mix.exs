defmodule SurfContext.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/bonfire-networks/surf_context"

  def project do
    [
      app: :surf_context,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "SurfContext",
      source_url: @source_url,
      docs: [main: "readme", extras: ["README.md"]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.2"},
      {:plug, "~> 1.15", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Implicit context for Phoenix LiveView components — a compile-time pre-pass that threads a context assign through every component call site, with full change tracking. No prop drilling, no runtime magic, plain HEEx output."
  end

  defp package do
    [
      licenses: ["MPL-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
