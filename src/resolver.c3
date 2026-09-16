module c3pm;

import std::collections::list;
import std::io::file;
import std::io::path;

struct PendingNode
{
	String name;
	FetchGithub source;
	String[] dependencies;
	NixInputs nix;
	bool loaded;
}

fn sz? pending_index(List{PendingNode}* nodes, String name)
{
	foreach (i, &node : *nodes) if (node.name == name) return i;
	return NOT_FOUND~;
}

fn Graph pending_graph(Allocator allocator, List{PendingNode}* pending, String[] roots)
{
	List{GraphNode} nodes;
	nodes.init(allocator, pending.len());
	foreach (&item : *pending)
	{
		nodes.push({
			.name = item.name,
			.source = item.source,
			.dependencies = item.dependencies,
			.nix = item.nix,
		});
	}
	return { .nodes = nodes.to_array(allocator), .roots = roots };
}

fn void? add_pending(Allocator allocator, List{PendingNode}* pending,
	String name, FetchGithub source)
{
	if (try index = pending_index(pending, name))
	{
		if (!source_equal((*pending)[index].source, source)) return SOURCE_CONFLICT~;
		return;
	}
	pending.push({ .name = name.copy(allocator), .source = source });
	return;
}

fn Graph? resolve_graph(Allocator allocator, Metadata* project, String target,
	String discovery_dir, NixRunner runner)
{
	validate_metadata_sources(project)!;
	List{PendingNode} pending;
	pending.init(allocator);
	foreach (root : project.dependencies)
	{
		DependencySpec* declaration = project.find_source(root)!;
		add_pending(allocator, &pending, root, declaration.source)!;
	}
	path::mkdir(discovery_dir, true)!;
	while (true)
	{
		Graph discovery = pending_graph(tmem, &pending, project.dependencies);
		file::save(string::format(tmem, "%s/flake.nix", discovery_dir),
			generate_flake_nix(tmem, &discovery, project))!;
		runner.lock(discovery_dir)!;
		bool added;
		for (sz i = 0; i < pending.len(); i++)
		{
			if (pending[i].loaded) continue;
			PendingNode* node = &pending[i];
			String input_name = source_input_name(tmem, node.source);
			String manifest_json = runner.read_manifest(tmem, discovery_dir, input_name, node.source.path)!;
			Metadata manifest = parse_manifest(allocator, manifest_json, target)!;
			if (manifest.provides != node.name) return PROVIDES_MISMATCH~;
			validate_metadata_sources(&manifest)!;
			node.dependencies = manifest.dependencies;
			node.nix = manifest.nix;
			node.loaded = true;
			foreach (child : manifest.dependencies)
			{
				DependencySpec* declaration = manifest.find_source(child)!;
				if (catch pending_index(&pending, child)) added = true;
				add_pending(allocator, &pending, child, declaration.source)!;
			}
		}
		if (!added) break;
	}
	Graph graph = pending_graph(allocator, &pending, project.dependencies);
	validate_graph(&graph)!;
	return graph;
}
