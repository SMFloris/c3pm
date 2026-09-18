module c3pm;

import libc;
import std::collections::list;
import std::io::file;
import std::io::path;

extern fn CInt symlink(ZString target, ZString link_path) @cname("symlink") @feat(POSIX);

fn void? copy_file_if_present(String source, String destination)
{
	if (!file::is_file(source)) return;
	char[] contents = file::load(tmem, source)!;
	file::save(destination, contents)!;
}

fn void? copy_project_imports(String directory, Path project_root, String[] imports)
{
	foreach (import_path : imports)
	{
		String relative = nix_import_relative_path(import_path);
		String source = string::format(tmem, "%s/%s", (String)project_root, relative);
		if (!file::is_file(source)) return INVALID_SOURCE_PATH~;
		String destination = string::format(tmem, "%s/imports/project/%s", directory, relative);
		String parent = destination.path_tdirname()!;
		path::mkdir(parent, true)!;
		file::save(destination, file::load(tmem, source)!)!;
	}
	return;
}

fn void? copy_link_imports(String directory, Path project_root, LinkSpec[] links)
{
	foreach (&link : links)
	{
		if (link.has_source || !link.nix_package.starts_with("path:")) continue;
		String import_path = link.nix_package[5..];
		String relative = nix_import_relative_path(import_path);
		String source = string::format(tmem, "%s/%s", (String)project_root, relative);
		if (!file::is_file(source)) return INVALID_SOURCE_PATH~;
		String destination = string::format(tmem, "%s/imports/links/%s/%s",
			directory, link.name, relative);
		path::mkdir(destination.path_tdirname()!, true)!;
		file::save(destination, file::load(tmem, source)!)!;
	}
	return;
}

fn bool excluded_project_source_entry(String name)
{
	return name == ".c3pm" || name == ".git" || name == ".tools" ||
		name == "lib" || name == "build" || name == "dist";
}

fn void? copy_source_directory(String source, String destination, bool filter_root)
{
	path::mkdir(destination, true)!;
	PathList entries = path::ls(tmem, source.to_tpath()!, relative: true)!;
	foreach (entry : entries)
	{
		String relative = (String)entry;
		if (filter_root && excluded_project_source_entry(relative)) continue;
		String from = string::format(tmem, "%s/%s", source, relative);
		String to = string::format(tmem, "%s/%s", destination, relative);
		if (file::is_dir(from))
		{
			copy_source_directory(from, to, false)!;
		}
		else if (file::is_file(from))
		{
			copy_file_streaming(from, to)!;
		}
	}
	return;
}

fn void? copy_project_source(String directory, Path project_root)
{
	String destination = string::format(tmem, "%s/project-source", directory);
	copy_source_directory((String)project_root, destination, true)!;
	return;
}

fn void? write_generated_state(String directory, Path project_root, Metadata* project, Graph* graph)
{
	path::mkdir(string::format(tmem, "%s/deps", directory), true)!;
	copy_project_source(directory, project_root)!;
	copy_project_imports(directory, project_root, project.nix.imports)!;
	copy_link_imports(directory, project_root, project.links)!;
	file::save(string::format(tmem, "%s/flake.nix", directory), generate_flake_nix(tmem, graph, project))!;
	file::save(string::format(tmem, "%s/shell.nix", directory), generate_shell_nix(tmem, graph, project))!;
	file::save(string::format(tmem, "%s/project.nix", directory), generate_project_nix(tmem, project))!;
	file::save(string::format(tmem, "%s/c3pm-lib.nix", directory), C3PM_LIB_NIX)!;
	foreach (&node : graph.nodes)
	{
		file::save(string::format(tmem, "%s/deps/%s.nix", directory, node.name),
			generate_dependency_nix(tmem, node))!;
	}
	return;
}

fn void? validate_all_nix_inputs(NixRunner runner, String directory,
	String system, NixInputs* inputs)
{
	foreach (attr : inputs.native_build_inputs) runner.validate_package_attr(directory, system, attr)!;
	foreach (attr : inputs.build_inputs) runner.validate_package_attr(directory, system, attr)!;
	foreach (attr : inputs.propagated_native_build_inputs) runner.validate_package_attr(directory, system, attr)!;
	foreach (attr : inputs.propagated_build_inputs) runner.validate_package_attr(directory, system, attr)!;
	return;
}

fn void? validate_link_nix_inputs(NixRunner runner, String directory,
	String system, LinkSpec[] links)
{
	foreach (&link : links)
	{
		if (link.nix_package.len && !link.nix_package.starts_with("path:"))
		{
			runner.validate_package_attr(directory, system, link.nix_package)!;
		}
	}
	return;
}

fn void? validate_generated_shell(NixRunner runner, String directory, String system)
{
	@pool()
	{
		String expression = string::format(tmem,
			`let f = builtins.getFlake "path:%s"; in f.devShells."%s".default.drvPath`,
			directory, system);
		(void)runner.eval_json(tmem, directory, expression)!;
	};
	return;
}

fn void? commit_nix_transaction(String current, String next, String previous)
{
	Path current_path = current.to_tpath()!;
	Path previous_path = previous.to_tpath()!;
	if (path::exists(previous_path)) path::rmtree(previous_path)!;
	bool had_current = path::exists(current_path);
	if (had_current && libc::rename(current.zstr_tcopy(), previous.zstr_tcopy()) != 0)
	{
		return TRANSACTION_FAILED~;
	}
	if (libc::rename(next.zstr_tcopy(), current.zstr_tcopy()) != 0)
	{
		if (had_current) (void)libc::rename(previous.zstr_tcopy(), current.zstr_tcopy());
		return TRANSACTION_FAILED~;
	}
	if (had_current) path::rmtree(previous_path)!;
	return;
}

fn void? materialize_library_links(Path project_root, Graph* graph, String library_tree)
{
	String lib_dir = string::format(tmem, "%s/lib", (String)project_root);
	path::mkdir(lib_dir, true)!;
	foreach (&node : graph.nodes)
	{
		String target = string::format(tmem, "%s/%s.c3l", library_tree, node.name);
		String link_path = string::format(tmem, "%s/%s.c3l", lib_dir, node.name);
		String temporary = string::format(tmem, "%s.c3pm-next", link_path);
		(void)file::delete(temporary);
		if (symlink(target.zstr_tcopy(), temporary.zstr_tcopy()) != 0) return TRANSACTION_FAILED~;
		if (libc::rename(temporary.zstr_tcopy(), link_path.zstr_tcopy()) != 0)
		{
			(void)file::delete(temporary);
			return TRANSACTION_FAILED~;
		}
	}
	return;
}

fn String[] generated_dependency_names(Allocator allocator, String nix_directory)
{
	List{String} names;
	names.init(allocator);
	Path deps = string::format(tmem, "%s/deps", nix_directory).to_tpath()!!;
	if (!path::exists(deps)) return names.to_array(allocator);
	PathList entries = path::ls(tmem, deps, no_dirs: true, mask: "*.nix")!!;
	foreach (entry : entries)
	{
		String basename = entry.basename();
		if (basename.ends_with(".nix")) names.push(basename[:basename.len - 4].copy(allocator));
	}
	return names.to_array(allocator);
}

fn void remove_stale_library_links(Path project_root, Graph* graph, String[] old_names)
{
	foreach (name : old_names)
	{
		if (try graph.find(name)) continue;
		(void)file::delete(string::format(tmem, "%s/lib/%s.c3l", (String)project_root, name));
	}
}

fn String? install_project(Allocator allocator, Path project_root, NixRunner runner,
	bool update_nixpkgs = false)
{
	@pool()
	{
		String root = (String)project_root;
		String project_file = string::format(tmem, "%s/project.json", root);
		String project_json = (String)file::load(tmem, project_file)!;
		String target = host_c3_target()!;
		String system = host_nix_system()!;
		Metadata project = parse_project(allocator, project_json, target)!;
		foreach (&source : project.sources)
			if (source.source.kind == FOLDER) { source.source.base = root.copy(allocator); }
		foreach (&link : project.links)
			if (link.has_source && link.source.kind == FOLDER) { link.source.base = root.copy(allocator); }

		String state_parent = string::format(tmem, "%s/.c3pm", root);
		String current = string::format(tmem, "%s/nix", state_parent);
		String next = string::format(tmem, "%s/nix.next", state_parent);
		String previous = string::format(tmem, "%s/nix.previous", state_parent);
		path::mkdir(state_parent, true)!;
		String[] old_names = generated_dependency_names(allocator, current);
		Path next_path = next.to_tpath()!;
		if (path::exists(next_path)) path::rmtree(next_path)!;
		path::mkdir(next, true)!;
		defer if (path::exists(next_path)) (void)path::rmtree(next_path);
		copy_file_if_present(string::format(tmem, "%s/flake.lock", current),
			string::format(tmem, "%s/flake.lock", next))!;

		Graph graph = resolve_graph(allocator, &project, target, next, runner)!;
		write_generated_state(next, project_root, &project, &graph)!;
		if (update_nixpkgs) { runner.update_input(next, "nixpkgs")!; }
		else { runner.lock(next)!; }
		validate_all_nix_inputs(runner, next, system, &project.nix)!;
		validate_link_nix_inputs(runner, next, system, project.links)!;
		foreach (&node : graph.nodes) validate_all_nix_inputs(runner, next, system, &node.nix)!;
		validate_generated_shell(runner, next, system)!;
		String flake_ref = string::format(tmem, "path:%s#c3pmLibs", next);
		String library_tree = runner.build(allocator, flake_ref)!;
		commit_nix_transaction(current, next, previous)!;
		materialize_library_links(project_root, &graph, library_tree)!;
		remove_stale_library_links(project_root, &graph, old_names);
		return library_tree;
	};
}
