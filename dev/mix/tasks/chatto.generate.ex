defmodule Mix.Tasks.Chatto.Generate do
  @shortdoc "Regenerates lib/chatto/generated from the pinned Chatto release"

  @moduledoc """
  Regenerates `lib/chatto/generated` from the Chatto release pinned in `flake.nix`
  (`lib.chatto`). Needs `buf`, `nix` and `protoc` on the path (`nix develop` provides them).

      mix chatto.generate
  """

  use Mix.Task

  @output_dir Path.join(["lib", "chatto", "generated"])

  # Operator APIs are internal to Chatto's CLI.
  @proto_packages ~W(chatto/admin chatto/api chatto/auth chatto/discovery chatto/realtime)

  @impl true
  def run(_args) do
    version = nix!(~W(eval --raw .#lib.chatto.version))
    source = ~W(eval --raw .#lib.chatto.src.outPath) |> nix!() |> Path.join("proto")
    temporary = Path.join(System.tmp_dir!(), "chatto-api-#{System.unique_integer([:positive])}")

    try do
      generate(version, source, temporary)
    after
      File.rm_rf!(temporary)
    end

    Mix.shell().info("Generated Chatto #{version} API in #{@output_dir}")
  end

  defp generate(version, source, temporary) do
    proto_dir = Path.join(temporary, "proto")
    image_path = Path.join(temporary, "image.json")
    paths = Enum.flat_map(@proto_packages, &["--path", Path.join(source, &1)])

    buf!(["export", source, "--output", proto_dir | paths])
    buf!(["build", proto_dir, "--output", image_path])

    proto_files = proto_dir |> Path.join("**/*.proto") |> Path.wildcard() |> Enum.sort()

    for file <- proto_files,
        file |> Path.relative_to(proto_dir) |> String.starts_with?("chatto/") do
      add_file_option(file)
    end

    File.rm_rf!(@output_dir)
    File.mkdir_p!(@output_dir)

    Mix.Task.run("protox.generate", [
      "--multiple-files",
      "--output-path=#{@output_dir}",
      "--include-path=#{proto_dir}" | proto_files
    ])

    # protovalidate rules are only enforced server-side, and they pull in descriptor.proto, so
    # keep only the modules Chatto messages reach (e.g. Timestamp and FieldMask).
    prune_unreachable()

    %{"file" => files} = image_path |> File.read!() |> JSON.decode!()
    modules = message_modules(files)

    for %{"package" => "chatto." <> _} = file <- files,
        {service, index} <- file |> Map.get("service", []) |> Enum.with_index() do
      module = "#{module_name(file["package"])}.#{service["name"]}"
      basename = module |> Macro.underscore() |> String.replace("/", "_")
      path = Path.join(@output_dir, "#{basename}.ex")

      File.write!(path, service_module(version, file, index, service, module, modules))
    end

    @output_dir |> Path.join("CHATTO_VERSION") |> File.write!("#{version}\n")
    Mix.Task.run("format", generated_files())
  end

  # Protox 2.1.0 drops every message from files without file options once descriptor.proto is
  # in the descriptor set (imported by protovalidate). SPEED is the default, so this is a no-op.
  defp add_file_option(path) do
    proto = File.read!(path)
    patched = Regex.replace(~r/^package [\w.]+;$/m, proto, "\\0\noption optimize_for = SPEED;")

    if patched == proto do
      Mix.raise("#{path} has no package declaration")
    end

    File.write!(path, patched)
  end

  # stderr goes to the terminal so warnings (e.g. a dirty Git tree) stay out of the output
  defp buf!(args) do
    result = System.cmd("buf", args, env: %{})
    output!(result, "buf", args)
  end

  defp nix!(args) do
    result = System.cmd("nix", args, env: %{})
    output!(result, "nix", args)
  end

  defp output!({output, 0}, _command, _args), do: String.trim(output)

  defp output!({_output, status}, command, args) do
    Mix.raise("#{command} #{Enum.join(args, " ")} exited with #{status}")
  end

  defp comment(file, path) do
    locations = get_in(file, ["sourceCodeInfo", "location"]) || []

    text =
      if location = Enum.find(locations, &(&1["path"] == path)) do
        (location["leadingComments"] || "")
        |> String.split("\n")
        |> Enum.map_join("\n", &(&1 |> String.replace_prefix(" ", "") |> String.trim_trailing()))
        |> String.trim()
      end

    if text && String.contains?(text, ~S|"""|) do
      Mix.raise(
        "#{file["name"]} comment at #{Enum.join(path, ".")} contains a heredoc terminator"
      )
    end

    if text != "", do: text
  end

  defp doc(_attribute, nil), do: ""

  defp doc(attribute, text) do
    body =
      text
      |> String.split("\n")
      |> Enum.map_join("\n", fn
        "" -> ""
        line -> "  #{line}"
      end)

    ~s|  @#{attribute} ~S"""\n#{body}\n  """\n|
  end

  defp message_modules(files) do
    for %{"package" => package} = file <- files,
        message <- Map.get(file, "messageType", []),
        entry <- message_entries(".#{package}", module_name(package), message),
        into: %{},
        do: entry
  end

  defp message_entries(prefix, module, %{"name" => name} = message) do
    type = "#{prefix}.#{name}"
    module = "#{module}.#{name}"
    nested = Map.get(message, "nestedType", [])
    [{type, module} | Enum.flat_map(nested, &message_entries(type, module, &1))]
  end

  defp generated_files do
    @output_dir |> Path.join("*.ex") |> Path.wildcard()
  end

  # Matches protox's camelization of protobuf package names.
  defp module_name(package) do
    package |> String.split(".") |> Enum.map_join(".", &Macro.camelize/1)
  end

  defp prune_unreachable do
    sources =
      Map.new(generated_files(), fn path ->
        text = File.read!(path)

        case Regex.run(~r/^defmodule ([\w.]+) do$/m, text) do
          [_, module] -> {module, %{path: path, text: text}}
          nil -> Mix.raise("#{path} defines no module")
        end
      end)

    roots = for {"Chatto." <> _ = module, _source} <- sources, do: module
    reachable = reach(roots, sources, MapSet.new(roots))

    for {module, %{path: path}} <- sources, not MapSet.member?(reachable, module) do
      File.rm!(path)
    end
  end

  defp reach([], _sources, reachable), do: reachable

  defp reach([module | pending], sources, reachable) do
    references =
      for [reference] <- Regex.scan(~r/\b[A-Z]\w*(?:\.[A-Z]\w*)+/, sources[module].text),
          Map.has_key?(sources, reference),
          not MapSet.member?(reachable, reference),
          uniq: true,
          do: reference

    reach(references ++ pending, sources, MapSet.union(reachable, MapSet.new(references)))
  end

  defp service_module(version, file, index, service, module, modules) do
    functions =
      service
      |> Map.get("method", [])
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {method, method_index} ->
        service_function(file, index, service, method, method_index, modules)
      end)

    [
      "# Code generated by mix chatto.generate from Chatto #{version}. Don't edit.\n",
      "# credo:disable-for-this-file\n",
      "defmodule #{module} do\n",
      doc("moduledoc", comment(file, [6, index])),
      functions,
      "end\n"
    ]
  end

  defp service_function(file, index, service, method, method_index, modules) do
    %{"inputType" => input_type, "name" => name, "outputType" => output_type} = method

    if method["clientStreaming"] || method["serverStreaming"] do
      Mix.raise("#{service["name"]}.#{name} streams; Chatto.Connect only supports unary")
    end

    function = Macro.underscore(name)
    input = Map.get(modules, input_type) || Mix.raise("No module for #{input_type}")
    output = Map.get(modules, output_type) || Mix.raise("No module for #{output_type}")
    procedure = "/#{file["package"]}.#{service["name"]}/#{name}"

    [
      doc("doc", comment(file, [6, index, 2, method_index])),
      "  @spec #{function}(Req.Request.t(), #{input}.t()) :: {:ok, #{output}.t()} | {:error, Chatto.Connect.Error.t()}\n",
      "  def #{function}(client, %#{input}{} = request) do\n",
      ~s|    Chatto.Connect.call(client, "#{procedure}", request, #{output})\n|,
      "  end\n"
    ]
  end
end
