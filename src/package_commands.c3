module c3pm;

import std::io::file;
import std::io::path;

fn String? fetch_added_manifest(Allocator allocator, Path project_root,
	PackageSource source, NixRunner runner)
{
	@pool()
	{
		String state = string::format(tmem, "%s/.c3pm", (String)project_root);
		String temporary = string::format(tmem, "%s/add.next", state);
		Path temp_path = temporary.to_tpath()!;
		if (path::exists(temp_path)) path::rmtree(temp_path)!;
		path::mkdir(temporary, true)!;
		defer if (path::exists(temp_path)) (void)path::rmtree(temp_path);
		copy_file_if_present(string::format(tmem, "%s/nix/flake.lock", state),
			string::format(tmem, "%s/flake.lock", temporary))!;
		GraphNode node = { .name = "c3pm-probe", .source = source };
		Graph graph = { .nodes = { node } };
		Metadata project;
		file::save(string::format(tmem, "%s/flake.nix", temporary),
			generate_flake_nix(tmem, &graph, &project))!;
		runner.lock(temporary)!;
		verify_locked_source_hash(runner, temporary, source)!;
		return runner.read_manifest(allocator, temporary,
			source_input_name(tmem, source), source.subdir);
	};
}

fn void? validate_linked_project_target(Allocator allocator, Path project_root,
	LinkSpec* link, NixRunner runner)
{
	@pool()
	{
		String state = string::format(tmem, "%s/.c3pm", (String)project_root);
		String temporary = string::format(tmem, "%s/link-probe.next", state);
		Path temp_path = temporary.to_tpath()!;
		if (path::exists(temp_path)) path::rmtree(temp_path)!;
		path::mkdir(temporary, true)!;
		defer if (path::exists(temp_path)) (void)path::rmtree(temp_path);
		Graph graph;
		Metadata probe;
		LinkSpec[] links = { *link };
		probe.links = links;
		file::save(string::format(tmem, "%s/flake.nix", temporary),
			generate_flake_nix(tmem, &graph, &probe))!;
		runner.lock(temporary)!;
		verify_locked_source_hash(runner, temporary, link.source)!;
		String relative = link.source.subdir.len
			? string::format(tmem, "%s/project.json", link.source.subdir) : "project.json";
		String json = runner.read_source_json(tmem, temporary,
			source_input_name(tmem, link.source), relative)!;
		Metadata linked = parse_project(tmem, json, host_c3_target()!)!;
		foreach (&target : linked.targets)
		{
			if (target.name != link.c3c_target) continue;
			if (target.type != "static-lib" && target.type != "dynamic-lib")
			{
				return NON_LINKABLE_TARGET~;
			}
			return;
		}
		return UNKNOWN_TARGET~;
	};
}

fn String? add_dependency(Allocator allocator, Path project_root, PackageSource source,
	String requested_name, String for_target, NixRunner runner,
	RegisteredPackageSource registered = {})
{
	String project_path = string::format(tmem, "%s/project.json", (String)project_root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	String manifest_json = fetch_added_manifest(allocator, project_root, source, runner)!;
	Metadata manifest = parse_manifest(allocator, manifest_json, host_c3_target()!)!;
	String name = requested_name.len ? requested_name : manifest.provides;
	if (!valid_library_name(name) || (requested_name.len && manifest.provides != name))
	{
		return PROVIDES_MISMATCH~;
	}
	registered.provides = name;
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	bool declared;
	if (try existing = project.find_source(name))
	{
		if (!source_equal(existing.source, source)) return SOURCE_CONFLICT~;
		declared = true;
	}

	String edited = add_array_string_at(allocator, original, "dependencies", name, for_target)!;
	JsonMember search_paths = find_json_member(edited, 0, "dependency-search-paths")!;
	if (search_paths.found)
	{
		edited = add_array_string(allocator, edited, "dependency-search-paths", "lib")!;
	}
	else
	{
		edited = insert_json_container_value(allocator, edited, 0, '}',
			"  \"dependency-search-paths\": [ \"lib\" ]")!;
	}
	if (!declared) edited = add_source_declaration(allocator, edited, name, source)!;
	if (registered.id.len) edited = set_registry_dependency(allocator, edited, "", registered)!;
	file::save(project_path, edited)!;
	String? installed = install_project(allocator, project_root, runner);
	if (catch err = installed)
	{
		file::save(project_path, original)!;
		return err~;
	}
	return name;
}

fn RegistryDependencySpec? find_registered_dependency(Metadata* project, String query)
{
	RegistryDependencySpec found;
	bool qualified = is_registry_package_id(query);
	foreach (entry : project.registry_dependencies)
	{
		String[] parts = entry.package_id.tsplit("/");
		if (qualified ? entry.package_id != query : parts[1] != query) continue;
		if (found.name.len) return AMBIGUOUS_DEPENDENCY_UPDATE~;
		bool direct;
		foreach (name : project.dependencies)
		{
			if (name == entry.name) { direct = true; break; }
		}
		if (!direct) return INVALID_METADATA~;
		if (catch project.find_source(entry.name)) return INVALID_METADATA~;
		found = entry;
	}
	if (!found.name.len) return NOT_FOUND~;
	return found;
}

fn String? update_direct_dependency(Allocator allocator, Path project_root, String name,
	String rev, String sha256, NixRunner runner)
{
	if (!valid_library_name(name) || ((rev.len > 0) == (sha256.len > 0)))
	{
		return INVALID_ARGUMENTS~;
	}
	String project_path = string::format(tmem, "%s/project.json", (String)project_root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	bool direct;
	foreach (dependency : project.dependencies)
	{
		if (dependency == name) { direct = true; break; }
	}
	if (!direct) return NOT_FOUND~;
	foreach (reference : project.registry_dependencies)
	{
		if (reference.name == name) return INVALID_ARGUMENTS~;
	}
	DependencySpec* existing = project.find_source(name)!;
	PackageSource source = existing.source;
	if (rev.len)
	{
		if (source.kind != GITHUB && source.kind != GIT_HTTPS && source.kind != GIT_SSH)
		{
			return INVALID_ARGUMENTS~;
		}
		source.rev = rev;
	}
	else
	{
		if (source.kind != ARCHIVE_HTTPS) return INVALID_ARGUMENTS~;
		source.sha256 = sha256;
	}
	source.validate()!;
	if (source_equal(existing.source, source)) return name;
	String manifest_json = fetch_added_manifest(allocator, project_root, source, runner)!;
	Metadata manifest = parse_manifest(allocator, manifest_json, host_c3_target()!)!;
	if (manifest.provides != name) return PROVIDES_MISMATCH~;
	String edited = replace_source_declaration(allocator, original, name, name, source)!;
	file::save(project_path, edited)!;
	if (catch err = install_project(allocator, project_root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return name;
}

fn String? update_dependency(Allocator allocator, Path project_root, String previous,
	RegisteredPackageSource selected, NixRunner runner)
{
	String project_path = string::format(tmem, "%s/project.json", (String)project_root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	DependencySpec* existing = project.find_source(previous)!;
	String manifest_json = fetch_added_manifest(allocator, project_root, selected.source, runner)!;
	Metadata manifest = parse_manifest(allocator, manifest_json, host_c3_target()!)!;
	selected.provides = manifest.provides;
	foreach (dependency : project.sources)
	{
		if (previous != selected.provides && dependency.name == selected.provides)
		{
			return SOURCE_CONFLICT~;
		}
	}
	bool same_source = previous == selected.provides &&
		source_equal(existing.source, selected.source);
	if (same_source)
	{
		foreach (reference : project.registry_dependencies)
		{
			if (reference.name == previous && reference.registry == selected.registry &&
				reference.package_id == selected.id && reference.version == selected.version)
			{
				return previous;
			}
		}
	}
	String edited = original.copy(allocator);
	if (!same_source)
	{
		edited = replace_array_string_at(allocator, edited, "dependencies",
			previous, selected.provides, "")!;
		foreach (target : project.targets)
		{
			edited = replace_array_string_at(allocator, edited, "dependencies",
				previous, selected.provides, target.name)!;
		}
		edited = replace_source_declaration(allocator, edited, previous,
			selected.provides, selected.source)!;
	}
	edited = set_registry_dependency(allocator, edited, previous, selected)!;
	file::save(project_path, edited)!;
	if (catch err = install_project(allocator, project_root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return selected.provides;
}

fn void? remove_dependency(Allocator allocator, Path project_root, String name,
	String for_target, NixRunner runner)
{
	if (!valid_library_name(name)) return INVALID_METADATA~;
	String project_path = string::format(tmem, "%s/project.json", (String)project_root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	bool root_dependency;
	foreach (dependency : project.dependencies)
		if (dependency == name) { root_dependency = true; break; }
	if (!root_dependency) return NOT_FOUND~;
	String edited = remove_array_string_at(allocator, original, "dependencies", name, for_target)!;
	Metadata remaining = parse_project(tmem, edited, host_c3_target()!)!;
	bool still_used;
	foreach (dependency : remaining.dependencies)
		if (dependency == name) { still_used = true; break; }
	if (!still_used)
	{
		edited = remove_source_declaration(allocator, edited, name)!;
		edited = remove_registry_dependency(allocator, edited, name)!;
	}
	file::save(project_path, edited)!;
	if (catch err = install_project(allocator, project_root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return;
}
