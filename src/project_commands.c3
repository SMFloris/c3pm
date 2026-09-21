module c3pm;

import std::io;
import std::io::file;
import std::io::path;

struct SourceOptions
{
	String value;
	String rev;
	String sha256;
	String subdir;
	String name;
	String for_target;
}

fn bool option_value(String[] args, sz* index, String* destination)
{
	if (*index + 1 >= args.len || !args[*index + 1].len) return false;
	*destination = args[++*index];
	return true;
}

fn String? parse_list_target(String[] args, sz options_start)
{
	if (args.len == options_start) return "";
	if (args.len == options_start + 2 && args[options_start] == "--for-target" &&
		args[options_start + 1].len) return args[options_start + 1];
	return INVALID_ARGUMENTS~;
}

fn void? list_dependencies(Path root, String target)
{
	String project_json = (String)file::load(tmem,
		string::format(tmem, "%s/project.json", (String)root))!;
	Metadata project = parse_project(tmem, project_json, host_c3_target()!)!;
	sz target_object;
	JsonMember target_dependencies;
	if (target.len)
	{
		target_object = project_target_object(project_json, target)!;
		target_dependencies = find_json_member(project_json, target_object, "dependencies")!;
	}
	foreach (&source : project.sources)
	{
		if (target.len && (!target_dependencies.found ||
			!json_array_has_string(project_json, target_dependencies.value_start, source.name))) continue;
		io::printfn("%s\t%s:%s", source.name, source_kind_name(source.source.kind),
			source.source.location);
	}
}

fn void? list_links(Path root, String target)
{
	String json = (String)file::load(tmem,
		string::format(tmem, "%s/project.json", (String)root))!;
	Metadata project = parse_project(tmem, json, host_c3_target()!)!;
	foreach (&link : project.links)
	{
		if (target.len && link.for_target != target) continue;
		io::printfn("%s\t%s\t%s", link.name, link.c3c_target,
			link.passthrough ? "passthrough" : "runtime");
	}
}

fn int? run_list_command(String[] args, Path root)
{
	String target = parse_list_target(args, 2)!;
	io::printn("Dependencies:");
	list_dependencies(root, target)!;
	io::printn("\nLinks:");
	list_links(root, target)!;
	return 0;
}

fn SourceOptions? parse_dependency_options(String[] args, sz start)
{
	SourceOptions options;
	if (start >= args.len) return INVALID_ARGUMENTS~;
	options.value = args[start];
	for (sz i = start + 1; i < args.len; i++)
	{
		switch (args[i])
		{
			case "--rev": if (!option_value(args, &i, &options.rev)) return INVALID_ARGUMENTS~;
			case "--sha256": if (!option_value(args, &i, &options.sha256)) return INVALID_ARGUMENTS~;
			case "--subdir": if (!option_value(args, &i, &options.subdir)) return INVALID_ARGUMENTS~;
			case "--name": if (!option_value(args, &i, &options.name)) return INVALID_ARGUMENTS~;
			case "--for-target": if (!option_value(args, &i, &options.for_target)) return INVALID_ARGUMENTS~;
			default: return INVALID_ARGUMENTS~;
		}
	}
	return options;
}

fn void print_dep_help()
{
	io::printn(
		"Usage:\n"
		"  c3pm add SOURCE [options]  (alias for c3pm dep add)\n"
		"  c3pm remove NAME [--for-target TARGET]  (alias for c3pm dep remove)\n"
		"  c3pm dep add SOURCE|NAMESPACE/NAME [--rev REF] [--sha256 HASH] [--subdir PATH]\n"
		"                        [--name NAME] [--for-target TARGET]\n"
		"  c3pm dep remove NAME [--for-target TARGET]\n"
		"  c3pm dep list [--for-target TARGET]");
}

fn int? run_dep_command(String[] args, Path root, NixRunner runner)
{
	if (args.len >= 4 && args[2] == "add")
	{
		SourceOptions options = parse_dependency_options(args, 3)!;
		PackageSource source;
		String requested_name = options.name;
		if (is_registry_package_id(options.value))
		{
			if (options.rev.len || options.sha256.len || options.subdir.len)
			{
				return INVALID_ARGUMENTS~;
			}
			RegisteredPackageSource registered = resolve_registry_package(tmem,
				options.value, runner)!;
			if (requested_name.len && requested_name != registered.provides)
			{
				return PROVIDES_MISMATCH~;
			}
			requested_name = registered.provides;
			source = registered.source;
			io::printfn("Resolved %s@%s from registry '%s'", registered.id,
				registered.version, registered.registry);
		}
		else
		{
			source = parse_source(tmem, options.value, options.rev,
				options.subdir, options.sha256)!;
		}
		if (source.kind == FOLDER) { source.base = ((String)root).copy(tmem); }
		String added = add_dependency(tmem, root, source, requested_name,
			options.for_target, runner)!;
		io::printfn("Added C3 dependency \"%s\"", added);
		return 0;
	}
	if (args.len >= 4 && args[2] == "remove")
	{
		String for_target;
		if (args.len == 6 && args[4] == "--for-target") { for_target = args[5]; }
		else if (args.len != 4) { return INVALID_ARGUMENTS~; }
		remove_dependency(tmem, root, args[3], for_target, runner)!;
		io::printfn("Removed C3 dependency \"%s\"", args[3]);
		return 0;
	}
	if (args.len >= 3 && args[2] == "list")
	{
		String target = parse_list_target(args, 3)!;
		list_dependencies(root, target)!;
		return 0;
	}
	print_dep_help();
	return 2;
}

fn void print_link_help()
{
	io::printn(
		"Usage:\n"
		"  c3pm link add NAME [--source SOURCE] [--rev REF] [--sha256 HASH]\n"
		"                     [--subdir PATH] [--c3c-target none|TARGET]\n"
		"                     [--nix-package PACKAGE] [--runtime|--passthrough]\n"
		"                     [--for-target TARGET]\n"
		"  c3pm link remove NAME [--for-target TARGET]\n"
		"  c3pm link list [--for-target TARGET]");
}

fn LinkSpec? parse_link_options(String[] args)
{
	if (args.len < 4 || !valid_library_name(args[3])) return INVALID_ARGUMENTS~;
	LinkSpec link = { .name = args[3], .c3c_target = "none" };
	String source_value;
	String rev;
	String sha256;
	String subdir;
	bool mode_set;
	for (sz i = 4; i < args.len; i++)
	{
		switch (args[i])
		{
			case "--source": if (!option_value(args, &i, &source_value)) return INVALID_ARGUMENTS~;
			case "--rev": if (!option_value(args, &i, &rev)) return INVALID_ARGUMENTS~;
			case "--sha256": if (!option_value(args, &i, &sha256)) return INVALID_ARGUMENTS~;
			case "--subdir": if (!option_value(args, &i, &subdir)) return INVALID_ARGUMENTS~;
			case "--c3c-target": if (!option_value(args, &i, &link.c3c_target)) return INVALID_ARGUMENTS~;
			case "--nix-package": if (!option_value(args, &i, &link.nix_package)) return INVALID_ARGUMENTS~;
			case "--for-target": if (!option_value(args, &i, &link.for_target)) return INVALID_ARGUMENTS~;
			case "--runtime": if (mode_set) return INVALID_ARGUMENTS~; mode_set = true;
			case "--passthrough": if (mode_set) return INVALID_ARGUMENTS~; mode_set = true; link.passthrough = true;
			default: return INVALID_ARGUMENTS~;
		}
	}
	if (source_value.len)
	{
		link.source = parse_source(tmem, source_value, rev, subdir, sha256)!;
		link.has_source = true;
	}
	else if (rev.len || sha256.len || subdir.len) return INVALID_ARGUMENTS~;
	if (link.c3c_target != "none" && !link.has_source) return MISSING_SOURCE~;
	if (link.c3c_target != "none" && !valid_library_name(link.c3c_target)) return INVALID_ARGUMENTS~;
	if (link.for_target.len && !valid_library_name(link.for_target)) return INVALID_ARGUMENTS~;
	if (link.nix_package.starts_with("path:")) { validate_nix_import_path(link.nix_package[5..])!; }
	else if (link.nix_package.len && !valid_nix_attribute(link.nix_package)) { return INVALID_NIX_ATTRIBUTE~; }
	return link;
}

fn String? add_link(Allocator allocator, Path root, LinkSpec link, NixRunner runner)
{
	if (link.has_source && link.source.kind == FOLDER)
	{
		link.source.base = ((String)root).copy(allocator);
	}
	String project_path = string::format(tmem, "%s/project.json", (String)root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	foreach (&existing : project.links) if (existing.name == link.name) return SOURCE_CONFLICT~;
	if (link.for_target.len) (void)project_target_object(original, link.for_target)!;
	if (link.c3c_target != "none") validate_linked_project_target(allocator, root, &link, runner)!;
	String edited = add_array_string_at(allocator, original, "linked-libraries",
		link.name, link.for_target)!;
	edited = add_link_declaration(allocator, edited, link)!;
	file::save(project_path, edited)!;
	if (catch err = install_project(allocator, root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return link.name;
}

fn void? remove_link(Allocator allocator, Path root, String name, String for_target,
	NixRunner runner)
{
	String project_path = string::format(tmem, "%s/project.json", (String)root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	bool found;
	foreach (&link : project.links)
	{
		if (link.name != name) continue;
		if (link.for_target != for_target) return NOT_FOUND~;
		found = true;
		break;
	}
	if (!found) return NOT_FOUND~;
	String edited = remove_array_string_at(allocator, original, "linked-libraries", name, for_target)!;
	edited = remove_link_declaration(allocator, edited, name)!;
	file::save(project_path, edited)!;
	if (catch err = install_project(allocator, root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return;
}

fn int? run_link_command(String[] args, Path root, NixRunner runner)
{
	if (args.len >= 4 && args[2] == "add")
	{
		LinkSpec link = parse_link_options(args)!;
		String added = add_link(tmem, root, link, runner)!;
		io::printfn("Added link \"%s\"", added);
		return 0;
	}
	if (args.len >= 4 && args[2] == "remove")
	{
		String for_target;
		if (args.len == 6 && args[4] == "--for-target") { for_target = args[5]; }
		else if (args.len != 4) { return INVALID_ARGUMENTS~; }
		remove_link(tmem, root, args[3], for_target, runner)!;
		io::printfn("Removed link \"%s\"", args[3]);
		return 0;
	}
	if (args.len >= 3 && args[2] == "list")
	{
		String target = parse_list_target(args, 3)!;
		list_links(root, target)!;
		return 0;
	}
	print_link_help();
	return 2;
}

fn int? set_toolchain_project_value(Path root, String key, String value,
	bool remove, NixRunner runner)
{
	if (!remove && !safe_metadata_value(value)) return INVALID_ARGUMENTS~;
	String project_path = string::format(tmem, "%s/project.json", (String)root);
	String original = ((String)file::load(tmem, project_path)!).copy(tmem);
	if (remove)
	{
		JsonMember toolchain = find_member_path(original, { "vendor", "c3pm", "toolchain" })!;
		if (!toolchain.found) return 0;
		JsonMember existing = find_json_member(original, toolchain.value_start, key)!;
		if (!existing.found) return 0;
	}
	String edited = remove ? remove_toolchain_value(tmem, original, key)!
		: set_toolchain_value(tmem, original, key, value)!;
	file::save(project_path, edited)!;
	if (catch err = install_project(tmem, root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return 0;
}

fn void print_toolchain_help()
{
	io::printn(
		"Usage:\n"
		"  c3pm toolchain show\n"
		"  c3pm toolchain c3c set VERSION\n"
		"  c3pm toolchain c3c reset\n"
		"  c3pm toolchain nixpkgs set REF\n"
		"  c3pm toolchain nixpkgs update\n"
		"  c3pm toolchain nixpkgs reset\n"
		"  c3pm toolchain nix status\n"
		"  c3pm toolchain nix use <system|portable|PATH>\n"
		"  c3pm toolchain nix reset");
}

fn int? show_toolchain(Path root)
{
	String json = (String)file::load(tmem,
		string::format(tmem, "%s/project.json", (String)root))!;
	Metadata project = parse_project(tmem, json, host_c3_target()!)!;
	io::printfn("Project toolchain:\n  c3c: %s\n  nixpkgs: %s",
		project.toolchain.c3c_version.len ? project.toolchain.c3c_version : "default",
		project.toolchain.nixpkgs);
	return run_nix_status_command();
}

fn int? run_toolchain_project_command(String[] args, Path root, NixRunner runner)
{
	if (args.len == 3 && args[2] == "show") return show_toolchain(root);
	if (args.len == 5 && args[2] == "c3c" && args[3] == "set")
	{
		return set_toolchain_project_value(root, "c3c", args[4], false, runner);
	}
	if (args.len == 4 && args[2] == "c3c" && args[3] == "reset")
	{
		return set_toolchain_project_value(root, "c3c", "", true, runner);
	}
	if (args.len == 5 && args[2] == "nixpkgs" && args[3] == "set")
	{
		return set_toolchain_project_value(root, "nixpkgs", args[4], false, runner);
	}
	if (args.len == 4 && args[2] == "nixpkgs" && args[3] == "reset")
	{
		return set_toolchain_project_value(root, "nixpkgs", "", true, runner);
	}
	if (args.len == 4 && args[2] == "nixpkgs" && args[3] == "update")
	{
		(void)install_project(tmem, root, runner, true)!;
		return 0;
	}
	print_toolchain_help();
	return 2;
}
