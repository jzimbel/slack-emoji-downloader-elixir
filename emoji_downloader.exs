Mix.install([{:jason, "~> 1.2"}, {:httpoison, "~> 1.8"}])

defmodule EmojiDownloader do
  def download(cwd, emoji_json_path) do
    output_path = Path.join(cwd, "output")

    prepare_output(output_path)

    {originals, aliases} =
      emoji_json_path
      |> get_emoji_map()
      |> split_originals_and_aliases()

    total = map_size(originals)

    IO.puts("Downloading images")

    failed =
      originals
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{name, url}, index} ->
        print_progress(index, total, name)

        case do_download(name, url, output_path) do
          :ok -> []
          _ -> [{name, url}]
        end
      end)

    IO.puts("\n\nCreating symlinks for aliases")

    aliases
    |> resolve_aliases(originals)
    |> Enum.map(&symlink_alias(&1, output_path))

    IO.puts(["\nDone. Images and aliases saved to ", output_path, "."])

    if not Enum.empty?(failed), do: record_failed_downloads(failed, cwd)
  end

  defp record_failed_downloads(failed, cwd) do
    path = Path.join(cwd, "failures.json")

    %{"emoji" => Map.new(failed)}
    |> Jason.encode_to_iodata!(pretty: true)
    |> then(fn json -> File.write!(path, json) end)

    IO.puts("\n#{length(failed)} images failed to download. These have been recorded in #{path}.")
    IO.puts("To retry these, rename the output directory to something else and then run:")
    IO.puts("elixir #{__ENV__.file} #{path}")
  end

  defp prepare_output(output_path) do
    File.rm_rf!(output_path)
    File.mkdir_p!(output_path)
  end

  defp get_emoji_map(emoji_json_path) do
    emoji_json_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("emoji")
  end

  defp split_originals_and_aliases(emoji_map) do
    Enum.reduce(emoji_map, {%{}, %{}}, fn
      {name, "alias:" <> url}, {originals, aliases} -> {originals, Map.put(aliases, name, url)}
      {name, url}, {originals, aliases} -> {Map.put(originals, name, url), aliases}
    end)
  end

  defp to_30_chars(s) do
    if String.length(s) > 30, do: String.slice(s, 0..26) <> "...", else: String.pad_leading(s, 30)
  end

  defp do_download(name, url, output_path) do
    path = Path.join(output_path, "#{name}.#{get_extension(url)}")

    case HTTPoison.get(url) do
      {:ok, %{status_code: 200, body: body}} -> File.write(path, body)
      _ -> :error
    end
  end

  defp resolve_aliases(aliases, originals) do
    Enum.flat_map(aliases, fn {name, ali} ->
      case resolve_alias(ali, aliases, originals) do
        nil -> []
        original -> [{name, original, originals[original]}]
      end
    end)
  end

  defp resolve_alias(ali, aliases, originals) do
    cond do
      Map.has_key?(originals, ali) -> ali
      Map.has_key?(aliases, ali) -> resolve_alias(aliases[ali], aliases, originals)
      true -> nil
    end
  end

  defp symlink_alias({source, target, url}, output_path) do
    extension = get_extension(url)

    source_path = Path.join(output_path, "#{source}.#{extension}")
    target_path = Path.join(output_path, "#{target}.#{extension}")

    if File.regular?(target_path) do
      File.ln_s!(target_path, source_path)
    else
      IO.puts("Tried to create an alias symlink to #{target_path}, but it doesn't exist")
    end
  end

  defp get_extension(url) do
    url
    |> String.split(".")
    |> List.last()
  end

  defp print_progress(index, total, name) do
    IO.write("\r#{String.pad_leading("#{index}", 6)} / #{total}\t#{to_30_chars(name)}")
  end
end

case System.argv() do
  [emoji_json_path] -> EmojiDownloader.download(File.cwd!(), emoji_json_path)
  _ -> IO.puts("No emoji JSON file supplied")
end
