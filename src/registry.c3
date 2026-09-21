module c3pm;

import libc;
import std::collections::list;
import std::collections::object;
import std::encoding::json;
import std::io;
import std::io::file;
import std::io::path;
import std::os::env;

const String DEFAULT_REGISTRY_NAME = "default";
const String DEFAULT_REGISTRY_SOURCE = "github:SMFloris/c3pm-registry";
const String DEFAULT_REGISTRY_REV = "master";

struct RegisteredPackageSource
{
	String registry;
	String id;
	String version;
	String provides;
	PackageSource source;
}

struct IndexedRegistryPackage
{
	RegistryConfig registry;
	SearchPackage package;
}

struct RegistryPackageDetails
{
	String id;
	String description;
	String homepage;
	String repository;
	String[] tags;
	String[] versions;
}

struct RegistryPackageSpec
{
	String query;
	String version;
}

fn Object*? parse_registry_json(Allocator allocator, String text)
{
	Object*? parsed = json::parse(allocator, text);
	if (catch parsed) return INVALID_REGISTRY~;
	return parsed;
}

fn String? required_string(Object* parent, String key)
{
	if (!parent.is_map() || !parent.has_key(key) || !parent.get(key)!.is_string())
	{
		return INVALID_REGISTRY~;
	}
	String value = parent.get_string(key)!;
	if (!value.len) return INVALID_REGISTRY~;
	return value;
}

fn String? registry_string(Object* parent, String key)
{
	if (!parent.is_map() || !parent.has_key(key) || !parent.get(key)!.is_string())
	{
		return INVALID_REGISTRY~;
	}
	return parent.get_string(key)!;
}

fn PackageSource? parse_registry_download(Allocator allocator, Object* download)
{
	if (!download.is_map()) return INVALID_REGISTRY~;
	if (download.has_key("source") || download.has_key("owner") ||
		download.has_key("repository") || download.has_key("rev") ||
		download.has_key("subdir")) return INVALID_REGISTRY~;
	String kind = required_string(download, "type")!;
	String url = required_string(download, "url")!;
	String hash = required_string(download, "sha256")!;
	if (!valid_sha256_sri(hash)) return INVALID_REGISTRY~;
	String[] fragments = url.tsplit("#");
	if (fragments.len > 2) return INVALID_REGISTRY~;
	if (kind == "git")
	{
		if (fragments.len != 2) return INVALID_REGISTRY~;
		if (!fragments[0].starts_with("git+https://") &&
			!fragments[0].starts_with("git+ssh://")) return INVALID_REGISTRY~;
		String[] parts = fragments[1].tsplit("/");
		if (parts.len < 2 || !full_git_commit(parts[0])) return INVALID_REGISTRY~;
		String subdir = fragments[1][parts[0].len + 1..];
		if (!subdir.len) return INVALID_REGISTRY~;
		PackageSource source = parse_source(allocator, fragments[0], parts[0], subdir, hash)!;
		return source;
	}
	else if (kind == "tar.gz" || kind == "zip")
	{
		String subdir = fragments.len == 2 ? fragments[1] : "";
		if (fragments.len == 2 && !subdir.len) return INVALID_REGISTRY~;
		PackageSource source = parse_source(allocator,
			string::format(tmem, "archive+%s", fragments[0]), "", subdir, hash)!;
		source.raw_archive = true;
		source.archive_type = kind.copy(allocator);
		source.validate()!;
		return source;
	}
	else { return INVALID_REGISTRY~; }
}

fn String[]? registry_string_array(Allocator allocator, Object* parent, String key,
	bool allow_empty = true)
{
	if (!parent.is_map() || !parent.has_key(key)) return INVALID_REGISTRY~;
	Object* array = parent.get(key)!;
	if (!array.is_array() || (!allow_empty && !array.len())) return INVALID_REGISTRY~;
	List{String} values;
	values.init(allocator, array.len());
	for (sz i = 0; i < array.len(); i++)
	{
		Object* item = array.get_at(i);
		if (!item.is_string() || !item.s.len) return INVALID_REGISTRY~;
		values.push(item.s.copy(allocator));
	}
	return values.to_array(allocator);
}

fn bool string_array_contains(String[] values, String wanted)
{
	foreach (value : values) if (value == wanted) return true;
	return false;
}

fn bool valid_registry_version(String version)
{
	if (!version.len || version == "." || version == ".." || version[0] == '.') return false;
	foreach (char c : version)
	{
		if (!(c.is_alnum() || c == '-' || c == '_' || c == '.' || c == '+')) return false;
	}
	return true;
}

fn String registry_relative_path(Allocator allocator, PackageSource source, String relative)
{
	return source.subdir.len
		? string::format(allocator, "%s/%s", source.subdir, relative)
		: relative.copy(allocator);
}

fn String? read_registry_json(Allocator allocator, PackageSource source, NixRunner runner,
	String flake_dir, String input_name, String relative)
{
	String nested = registry_relative_path(tmem, source, relative);
	validate_source_path(nested)!;
	if (source.kind != FOLDER)
	{
		return runner.read_source_json(allocator, flake_dir, input_name, nested);
	}
	String filename = string::format(tmem, "%s/%s", source.location, nested);
	if (!file::is_file(filename)) return INVALID_REGISTRY~;
	return ((String)file::load(allocator, filename)!).copy(allocator);
}

fn String? validate_registry(Allocator allocator, PackageSource source, NixRunner runner,
	String flake_dir, String input_name)
{
	String registry_text = read_registry_json(tmem, source, runner, flake_dir, input_name,
		"registry.json")!;
	Object* registry = parse_registry_json(tmem, registry_text)!;
	(void)required_string(registry, "name")!;
	(void)required_string(registry, "generated")!;
	if (!registry.has_key("version") || !registry.get("version")!.is_int() ||
		registry.get("version")!.i != 1) return INVALID_REGISTRY~;

	String index_text = read_registry_json(tmem, source, runner, flake_dir, input_name,
		"index.json")!;
	Object* index = parse_registry_json(tmem, index_text)!;
	if (!index.is_map() || !index.has_key("packages") ||
		!index.get("packages")!.is_array()) return INVALID_REGISTRY~;
	Object* packages = index.get("packages")!;
	List{String} seen_ids;
	seen_ids.init(tmem, packages.len());
	for (sz i = 0; i < packages.len(); i++)
	{
		Object* indexed = packages.get_at(i);
		String id = required_string(indexed, "id")!;
		String name = required_string(indexed, "name")!;
		String namespace = required_string(indexed, "namespace")!;
		String latest = required_string(indexed, "latest")!;
		(void)registry_string(indexed, "description")!;
		(void)registry_string_array(tmem, indexed, "tags")!;
		if (!valid_library_name(namespace) || !valid_library_name(name) ||
			!valid_registry_version(latest) || id != string::format(tmem, "%s/%s", namespace, name) ||
			string_array_contains(seen_ids.array_view(), id)) return INVALID_REGISTRY~;
		seen_ids.push(id);

		String package_path = string::format(tmem, "packages/%s/%s/package.json", namespace, name);
		String package_text = read_registry_json(tmem, source, runner, flake_dir, input_name,
			package_path)!;
		Object* package = parse_registry_json(tmem, package_text)!;
		if (required_string(package, "id")! != id ||
			required_string(package, "name")! != name ||
			required_string(package, "namespace")! != namespace) return INVALID_REGISTRY~;
		(void)registry_string(package, "description")!;
		(void)registry_string(package, "homepage")!;
		(void)registry_string(package, "repository")!;
		(void)registry_string_array(tmem, package, "tags")!;
		String[] versions = registry_string_array(tmem, package, "versions", false)!;
		if (!string_array_contains(versions, latest)) return INVALID_REGISTRY~;

		foreach (position, version : versions)
		{
			if (!valid_registry_version(version)) return INVALID_REGISTRY~;
			for (sz j = 0; j < position; j++)
			{
				if (versions[j] == version) return INVALID_REGISTRY~;
			}
			String version_path = string::format(tmem, "packages/%s/%s/%s.json",
				namespace, name, version);
			String version_text = read_registry_json(tmem, source, runner, flake_dir,
				input_name, version_path)!;
			Object* release = parse_registry_json(tmem, version_text)!;
			if (required_string(release, "name")! != name ||
				required_string(release, "namespace")! != namespace ||
				required_string(release, "version")! != version) return INVALID_REGISTRY~;
			if (release.has_key("provides") || release.has_key("toolchain"))
			{
				return INVALID_REGISTRY~;
			}
			(void)required_string(release, "published")!;
			if (!release.has_key("download") || !release.get("download")!.is_map())
			{
				return INVALID_REGISTRY~;
			}
			PackageSource? download = parse_registry_download(tmem, release.get("download")!);
			if (catch download) return INVALID_REGISTRY~;
			(void)required_string(release, "c3_version")!;
		}
	}
	return index_text.copy(allocator);
}

fn String? registry_index_path(Allocator allocator, String name)
{
	String base = env::tget_var("XDG_CACHE_HOME") ?? "";
	if (!base.len)
	{
		String home = env::tget_var("HOME")!;
		base = string::format(tmem, "%s/.cache", home);
	}
	return string::format(allocator, "%s/c3pm/registries/%s/index.json", base, name);
}

fn PackageSource? default_registry_source(Allocator allocator)
{
	return parse_source(allocator, DEFAULT_REGISTRY_SOURCE, DEFAULT_REGISTRY_REV, "", "");
}

fn void? add_default_registry(UserConfig* config)
{
	PackageSource source = default_registry_source(tmem)!;
	String index_json = validate_registry_source(source, DEFAULT_REGISTRY_NAME)!;
	set_registry_config(config, tmem, {
		.name = DEFAULT_REGISTRY_NAME,
		.source = source,
	})!;
	save_user_config(config)!;
	save_registry_index(DEFAULT_REGISTRY_NAME, index_json)!;
	io::eprintfn("c3pm: added default registry %s (%s, rev %s).",
		DEFAULT_REGISTRY_NAME, DEFAULT_REGISTRY_SOURCE, DEFAULT_REGISTRY_REV);
	return;
}

fn void? save_registry_index(String name, String contents)
{
	String destination = registry_index_path(tmem, name)!;
	path::mkdir(destination.path_tdirname()!, true)!;
	String temporary = string::format(tmem, "%s.tmp", destination);
	defer (void)file::delete(temporary);
	file::save(temporary, contents)!;
	if (libc::rename(temporary.zstr_tcopy(), destination.zstr_tcopy()) != 0)
	{
		return TRANSACTION_FAILED~;
	}
	return;
}

fn void? remove_registry_index(String name)
{
	String filename = registry_index_path(tmem, name)!;
	String directory = filename.path_tdirname()!;
	Path directory_path = directory.to_tpath()!;
	if (path::exists(directory_path)) path::rmtree(directory_path)!;
	return;
}

fn String registry_probe_path(Allocator allocator, String name)
{
	String config = xdg_config_path(tmem)!!;
	return string::format(allocator, "%s/registry-probe-%s", config.path_tdirname()!!, name);
}

fn String generate_registry_probe_flake(Allocator allocator, PackageSource source)
{
	DString out = dstring::new_with_capacity(allocator, 512);
	out.append("{\n  inputs = {\n");
	append_flake_source(&out, source);
	out.append("  };\n  outputs = { self, ... }: {};\n}\n");
	return out.str_view();
}

fn String? read_registry_file(Allocator allocator, RegistryConfig registry,
	String relative, NixRunner runner)
{
	if (registry.source.kind == FOLDER)
	{
		return read_registry_json(allocator, registry.source, runner, "", "", relative);
	}
	String temporary = registry_probe_path(tmem, registry.name);
	Path temporary_path = temporary.to_tpath()!;
	if (path::exists(temporary_path)) path::rmtree(temporary_path)!;
	path::mkdir(temporary, true)!;
	defer if (path::exists(temporary_path)) (void)path::rmtree(temporary_path);
	file::save(string::format(tmem, "%s/flake.nix", temporary),
		generate_registry_probe_flake(tmem, registry.source))!;
	runner.lock(temporary)!;
	return read_registry_json(allocator, registry.source, runner, temporary,
		source_input_name(tmem, registry.source), relative);
}

fn bool is_registry_package_id(String value)
{
	String[] parts = value.tsplit("/");
	return parts.len == 2 && valid_library_name(parts[0]) && valid_library_name(parts[1]);
}

fn bool is_registry_package_query(String value)
{
	return valid_library_name(value) || is_registry_package_id(value);
}

fn RegistryPackageSpec? parse_registry_package_spec(String value)
{
	if (is_registry_package_query(value)) return { .query = value };
	String[] parts = value.tsplit("@");
	if (parts.len < 2 || !is_registry_package_query(parts[0])) return {};
	if (parts.len != 2 || !valid_registry_version(parts[1])) return INVALID_ARGUMENTS~;
	return { .query = parts[0], .version = parts[1] };
}

fn String? select_registry_version(String latest, String[] versions, String requested)
{
	if (!requested.len) return latest;
	if (!string_array_contains(versions, requested)) return REGISTRY_VERSION_NOT_FOUND~;
	return requested;
}

fn IndexedRegistryPackage? find_indexed_registry_package(Allocator allocator, String query,
	String registry_filter = "")
{
	if (!is_registry_package_query(query)) return INVALID_ARGUMENTS~;
	bool qualified = is_registry_package_id(query);
	UserConfig config = load_user_config(allocator)!;
	if (!config.registries.len) add_default_registry(&config)!;
	IndexedRegistryPackage match;
	bool found;
	sz[] sorted = sorted_registry_indices(tmem, config.registries);
	foreach (registry_index : sorted)
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
		SearchPackage[] packages = load_search_packages(allocator, registry.name, contents)!;
		foreach (package : packages)
		{
			bool selected = qualified ? package.id == query : package.name == query;
			if (!selected) continue;
			if (found) return AMBIGUOUS_REGISTRY_PACKAGE~;
			found = true;
			match = { .registry = registry, .package = package };
		}
	}
	if (!found) return NOT_FOUND~;
	return match;
}

fn RegisteredPackageSource? parse_registered_release(Allocator allocator,
	RegistryConfig registry, String id, String version, String release_text)
{
	String[] parts = id.tsplit("/");
	if (parts.len != 2) return INVALID_REGISTRY~;
	Object* release = parse_registry_json(tmem, release_text)!;
	if (required_string(release, "namespace")! != parts[0] ||
		required_string(release, "name")! != parts[1] ||
		required_string(release, "version")! != version ||
		!release.has_key("download") || !release.get("download")!.is_map())
	{
		return INVALID_REGISTRY~;
	}
	if (release.has_key("provides") || release.has_key("toolchain")) return INVALID_REGISTRY~;
	(void)required_string(release, "c3_version")!;
	(void)required_string(release, "published")!;
	PackageSource? source = parse_registry_download(allocator, release.get("download")!);
	if (catch source) return INVALID_REGISTRY~;
	return {
		.registry = registry.name.copy(allocator),
		.id = id.copy(allocator),
		.version = version.copy(allocator),
		.source = source,
	};
}

fn RegisteredPackageSource? resolve_registry_package(Allocator allocator, String query,
	String requested_version, NixRunner runner)
{
	IndexedRegistryPackage indexed = find_indexed_registry_package(tmem, query)!;
	String version = indexed.package.latest;
	if (requested_version.len)
	{
		RegistryPackageDetails package = read_registry_package_details(tmem, indexed, runner)!;
		version = select_registry_version(version, package.versions, requested_version)!;
	}
	return read_registry_package_release(allocator, indexed, version, runner);
}

fn RegisteredPackageSource? read_registry_package_release(Allocator allocator,
	IndexedRegistryPackage indexed, String version, NixRunner runner)
{
	String id = indexed.package.id;
	String[] parts = id.tsplit("/");
	String relative = string::format(tmem, "packages/%s/%s/%s.json",
		parts[0], parts[1], version);
	String release_text = read_registry_file(tmem, indexed.registry, relative, runner)!;
	return parse_registered_release(allocator, indexed.registry, id, version, release_text);
}

fn RegisteredPackageSource[]? read_registry_package_releases(Allocator allocator,
	IndexedRegistryPackage indexed, RegistryPackageDetails package, NixRunner runner)
{
	List{RegisteredPackageSource} releases;
	releases.init(allocator, package.versions.len);
	foreach (version : package.versions)
	{
		releases.push(read_registry_package_release(allocator, indexed, version, runner)!);
	}
	return releases.to_array(allocator);
}

fn RegistryPackageDetails? read_registry_package_details(Allocator allocator,
	IndexedRegistryPackage indexed, NixRunner runner)
{
	String[] parts = indexed.package.id.tsplit("/");
	String relative = string::format(tmem, "packages/%s/%s/package.json", parts[0], parts[1]);
	String text = read_registry_file(tmem, indexed.registry, relative, runner)!;
	Object* package = parse_registry_json(tmem, text)!;
	if (required_string(package, "id")! != indexed.package.id ||
		required_string(package, "name")! != indexed.package.name ||
		required_string(package, "namespace")! != indexed.package.namespace)
	{
		return INVALID_REGISTRY~;
	}
	return {
		.id = indexed.package.id.copy(allocator),
		.description = registry_string(package, "description")!.copy(allocator),
		.homepage = registry_string(package, "homepage")!.copy(allocator),
		.repository = registry_string(package, "repository")!.copy(allocator),
		.tags = registry_string_array(allocator, package, "tags")!,
		.versions = registry_string_array(allocator, package, "versions", false)!,
	};
}

fn String? validate_registry_source(PackageSource source, String name)
{
	PortableNixRunner dummy = portable_nix_runner("", true, false);
	NixRunner reader = (NixRunner)&dummy;
	if (source.kind == FOLDER)
	{
		return validate_registry(tmem, source, reader, "", "");
	}

	PortableNixRunner selected = select_nix_runner(tmem)!;
	reader = (NixRunner)&selected;
	String temporary = registry_probe_path(tmem, name);
	Path temporary_path = temporary.to_tpath()!;
	if (path::exists(temporary_path)) path::rmtree(temporary_path)!;
	path::mkdir(temporary, true)!;
	defer if (path::exists(temporary_path)) (void)path::rmtree(temporary_path);
	file::save(string::format(tmem, "%s/flake.nix", temporary),
		generate_registry_probe_flake(tmem, source))!;
	reader.lock(temporary)!;
	verify_locked_source_hash(reader, temporary, source)!;
	return validate_registry(tmem, source, reader, temporary, source_input_name(tmem, source));
}

fn String source_cli_value(Allocator allocator, PackageSource source)
{
	switch (source.kind)
	{
		case GITHUB: return string::format(allocator, "github:%s", source.location);
		case GIT_HTTPS: return string::format(allocator, "git+%s", source.location);
		case GIT_SSH: return string::format(allocator, "git+%s", source.location);
		case ARCHIVE_HTTPS: return string::format(allocator, "archive+%s", source.location);
		case FOLDER: return string::format(allocator, "path:%s", source.location);
	}
}

fn void print_registry_help()
{
	io::printn(
		"Usage:\n"
		"  c3pm registry add NAME SOURCE [--rev REF] [--sha256 HASH] [--subdir PATH]\n"
		"  c3pm registry remove NAME\n"
		"  c3pm registry update [NAME]\n"
		"  c3pm registry list\n\n"
		"Sources: github:OWNER/REPO, git+https://URL, git+ssh://URL,\n"
		"         archive+https://URL, path:PATH"
	);
}

fn int? run_registry_add(String[] args)
{
	if (args.len < 5 || !valid_library_name(args[3])) { print_registry_help(); return 2; }
	String rev;
	String sha256;
	String subdir;
	for (sz i = 5; i < args.len; i += 2)
	{
		if (i + 1 >= args.len) { print_registry_help(); return 2; }
		switch (args[i])
		{
			case "--rev": rev = args[i + 1];
			case "--sha256": sha256 = args[i + 1];
			case "--subdir": subdir = args[i + 1];
			default: print_registry_help(); return 2;
		}
	}
	PackageSource source = parse_source(tmem, args[4], rev, subdir, sha256)!;
	if (source.kind == FOLDER)
	{
		Path absolute = source.location.to_tpath()!.to_absolute_path(tmem)!;
		source.location = ((String)absolute).copy(tmem);
		if (!path::exists(absolute)) return NOT_FOUND~;
	}
	String index_json = validate_registry_source(source, args[3])!;
	UserConfig config = load_user_config(tmem)!;
	bool replacing;
	foreach (registry : config.registries)
	{
		if (registry.name == args[3]) { replacing = true; break; }
	}
	set_registry_config(&config, tmem, { .name = args[3], .source = source })!;
	save_user_config(&config)!;
	save_registry_index(args[3], index_json)!;
	io::printfn("%s registry '%s'", replacing ? "Updated" : "Added", args[3]);
	return 0;
}

fn int? run_registry_remove(String[] args)
{
	if (args.len != 4 || !valid_library_name(args[3])) { print_registry_help(); return 2; }
	UserConfig config = load_user_config(tmem)!;
	remove_registry_config(&config, tmem, args[3])!;
	save_user_config(&config)!;
	remove_registry_index(args[3])!;
	io::printfn("Removed registry '%s'", args[3]);
	return 0;
}

fn int? run_registry_update(String[] args)
{
	if (args.len < 3 || args.len > 4 || (args.len == 4 && !valid_library_name(args[3])))
	{
		print_registry_help();
		return 2;
	}
	UserConfig config = load_user_config(tmem)!;
	if (args.len == 4)
	{
		RegistryConfig* registry = config.find_registry(args[3])!;
		String index_json = validate_registry_source(registry.source, registry.name)!;
		save_registry_index(registry.name, index_json)!;
		io::printfn("Updated registry '%s'", registry.name);
		return 0;
	}
	sz[] sorted = sorted_registry_indices(tmem, config.registries);
	foreach (index : sorted)
	{
		RegistryConfig registry = config.registries[index];
		String index_json = validate_registry_source(registry.source, registry.name)!;
		save_registry_index(registry.name, index_json)!;
		io::printfn("Updated registry '%s'", registry.name);
	}
	return 0;
}

fn int? run_registry_list(String[] args)
{
	if (args.len != 3) { print_registry_help(); return 2; }
	UserConfig config = load_user_config(tmem)!;
	sz[] sorted = sorted_registry_indices(tmem, config.registries);
	foreach (index : sorted)
	{
		RegistryConfig registry = config.registries[index];
		io::printf("%s\t%s", registry.name, source_cli_value(tmem, registry.source));
		if (registry.source.rev.len) io::printf(" --rev %s", registry.source.rev);
		if (registry.source.sha256.len) io::printf(" --sha256 %s", registry.source.sha256);
		if (registry.source.subdir.len) io::printf(" --subdir %s", registry.source.subdir);
		io::printn("");
	}
	return 0;
}

fn int? run_registry_command(String[] args)
{
	if (args.len < 3) { print_registry_help(); return 2; }
	switch (args[2])
	{
		case "add": return run_registry_add(args);
		case "remove": return run_registry_remove(args);
		case "update": return run_registry_update(args);
		case "list": return run_registry_list(args);
		default: print_registry_help(); return 2;
	}
}
