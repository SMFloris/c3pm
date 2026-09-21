module c3pm;

import std::collections::list;
import std::collections::object;
import std::io;
import std::io::file;

struct SearchPackage
{
	String registry;
	String id;
	String name;
	String namespace;
	String latest;
	String description;
	String[] tags;
	int score;
}

fn int token_score(SearchPackage* package, String token)
{
	String id = package.id.to_lower_tcopy();
	String name = package.name.to_lower_tcopy();
	String namespace = package.namespace.to_lower_tcopy();
	String description = package.description.to_lower_tcopy();
	if (id == token) return 1000;
	if (name == token) return 900;
	if (name.starts_with(token)) return 700;
	if (id.starts_with(token)) return 600;
	foreach (tag : package.tags) if (tag.compare_to_ignore_case(token) == 0) return 500;
	if (name.contains(token)) return 400;
	if (id.contains(token)) return 300;
	if (namespace.contains(token)) return 250;
	foreach (tag : package.tags) if (tag.to_lower_tcopy().contains(token)) return 200;
	if (description.contains(token)) return 100;
	return -1;
}

fn int search_score(SearchPackage* package, String[] tokens)
{
	int score;
	foreach (token : tokens)
	{
		int matched = token_score(package, token);
		if (matched < 0) return -1;
		score += matched;
	}
	return score;
}

fn bool package_has_tag(SearchPackage* package, String requested)
{
	if (!requested.len) return true;
	foreach (tag : package.tags)
	{
		if (tag.compare_to_ignore_case(requested) == 0) return true;
	}
	return false;
}

fn SearchPackage[]? load_search_packages(Allocator allocator, String registry_name,
	String index_text)
{
	Object* index = parse_registry_json(tmem, index_text)!;
	if (!index.is_map() || !index.has_key("packages") ||
		!index.get("packages")!.is_array()) return INVALID_REGISTRY~;
	Object* packages = index.get("packages")!;
	List{SearchPackage} result;
	result.init(allocator, packages.len());
	for (sz i = 0; i < packages.len(); i++)
	{
		Object* package = packages.get_at(i);
		result.push({
			.registry = registry_name.copy(allocator),
			.id = required_string(package, "id")!.copy(allocator),
			.name = required_string(package, "name")!.copy(allocator),
			.namespace = required_string(package, "namespace")!.copy(allocator),
			.latest = required_string(package, "latest")!.copy(allocator),
			.description = registry_string(package, "description")!.copy(allocator),
			.tags = registry_string_array(allocator, package, "tags")!,
		});
	}
	return result.to_array(allocator);
}

fn SearchPackage[] sort_search_results(Allocator allocator, SearchPackage[] results)
{
	SearchPackage[] sorted = alloc::alloc_array(allocator, SearchPackage, results.len);
	for (sz i = 0; i < results.len; i++) sorted[i] = results[i];
	for (sz i = 1; i < sorted.len; i++)
	{
		SearchPackage value = sorted[i];
		sz j = i;
		while (j > 0)
		{
			SearchPackage previous = sorted[j - 1];
			bool before = previous.score < value.score ||
				(previous.score == value.score && previous.registry.compare_to(value.registry) > 0) ||
				(previous.score == value.score && previous.registry == value.registry &&
					previous.id.compare_to(value.id) > 0);
			if (!before) break;
			sorted[j] = previous;
			j--;
		}
		sorted[j] = value;
	}
	return sorted;
}

fn String single_line(Allocator allocator, String value)
{
	DString out = dstring::new_with_capacity(allocator, value.len);
	foreach (char c : value) out.append(c == '\n' || c == '\r' || c == '\t' ? ' ' : c);
	return out.str_view();
}

fn void print_search_help()
{
	io::printn(
		"Usage: c3pm search [QUERY...] [--registry NAME] [--tag TAG]\n\n"
		"With no query, all indexed packages matching the filters are listed."
	);
}

fn int? run_search_command(String[] args)
{
	List{String} tokens;
	tokens.tinit();
	String registry_filter;
	String tag_filter;
	for (sz i = 2; i < args.len; i++)
	{
		if (args[i] == "--registry" || args[i] == "--tag")
		{
			if (i + 1 >= args.len) { print_search_help(); return 2; }
			if (args[i] == "--registry") { registry_filter = args[++i]; }
			else { tag_filter = args[++i]; }
			continue;
		}
		if (args[i].starts_with("--")) { print_search_help(); return 2; }
		String normalized = args[i].trim().to_lower_tcopy();
		if (normalized.len) tokens.push(normalized);
	}
	if (registry_filter.len && !valid_library_name(registry_filter)) return INVALID_ARGUMENTS~;

	UserConfig config = load_user_config(tmem)!;
	if (!config.registries.len) add_default_registry(&config)!;
	if (registry_filter.len)
	{
		RegistryConfig*? selected = config.find_registry(registry_filter);
		if (catch selected) return NOT_FOUND~;
	}
	List{SearchPackage} matches;
	matches.tinit();
	sz[] registries = sorted_registry_indices(tmem, config.registries);
	foreach (registry_index : registries)
	{
		RegistryConfig registry = config.registries[registry_index];
		if (registry_filter.len && registry.name != registry_filter) continue;
		String index_path = registry_index_path(tmem, registry.name)!;
		if (!file::is_file(index_path))
		{
			io::eprintfn("c3pm: registry '%s' is not indexed; run `c3pm registry update %s`.",
				registry.name, registry.name);
			continue;
		}
		String contents = (String)file::load(tmem, index_path)!;
		SearchPackage[] packages = load_search_packages(tmem, registry.name, contents)!;
		foreach (&package : packages)
		{
			if (!package_has_tag(package, tag_filter)) continue;
			package.score = search_score(package, tokens.array_view());
			if (package.score >= 0) matches.push(*package);
		}
	}

	SearchPackage[] sorted = sort_search_results(tmem, matches.array_view());
	io::printn("REGISTRY\tPACKAGE\tLATEST\tDESCRIPTION");
	foreach (package : sorted)
	{
		io::printfn("%s\t%s\t%s\t%s", package.registry, package.id, package.latest,
			single_line(tmem, package.description));
	}
	return 0;
}
