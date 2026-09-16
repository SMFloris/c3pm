module c3pm;

import std::io::file;
import std::io::path;

fn String? fetch_added_manifest(Allocator allocator, Path project_root,
	FetchGithub source, NixRunner runner)
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
		return runner.read_manifest(allocator, temporary,
			source_input_name(tmem, source), source.path);
	};
}

fn String? add_dependency(Allocator allocator, Path project_root, String uri, NixRunner runner)
{
	String project_path = string::format(tmem, "%s/project.json", (String)project_root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	FetchGithub source = parse_github_uri(allocator, uri)!;
	String manifest_json = fetch_added_manifest(allocator, project_root, source, runner)!;
	Metadata manifest = parse_manifest(allocator, manifest_json, host_c3_target()!)!;
	if (!valid_library_name(manifest.provides)) return INVALID_METADATA~;
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	foreach (dependency : project.dependencies)
	{
		if (dependency == manifest.provides) return SOURCE_CONFLICT~;
	}

	String edited = add_array_string(allocator, original, "dependencies", manifest.provides)!;
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
	edited = add_source_declaration(allocator, edited, manifest.provides, source)!;
	file::save(project_path, edited)!;
	String? installed = install_project(allocator, project_root, runner);
	if (catch err = installed)
	{
		file::save(project_path, original)!;
		return err~;
	}
	return manifest.provides;
}

fn void? remove_dependency(Allocator allocator, Path project_root, String name, NixRunner runner)
{
	if (!valid_library_name(name)) return INVALID_METADATA~;
	String project_path = string::format(tmem, "%s/project.json", (String)project_root);
	String original = ((String)file::load(allocator, project_path)!).copy(allocator);
	Metadata project = parse_project(tmem, original, host_c3_target()!)!;
	bool root_dependency;
	foreach (dependency : project.dependencies)
		if (dependency == name) { root_dependency = true; break; }
	if (!root_dependency) return NOT_FOUND~;
	String edited = remove_array_string(allocator, original, "dependencies", name)!;
	edited = remove_source_declaration(allocator, edited, name)!;
	file::save(project_path, edited)!;
	if (catch err = install_project(allocator, project_root, runner))
	{
		file::save(project_path, original)!;
		return err~;
	}
	return;
}
