module c3pm;

import std::collections::list;

fn bool valid_library_name(String name)
{
	if (!name.len || name == "." || name == ".." || name[0] == '.') return false;
	foreach (char c : name)
	{
		if (!(c.is_alnum() || c == '-' || c == '_' || c == '.')) return false;
	}
	return true;
}

fn void? validate_metadata_sources(Metadata* metadata)
{
	foreach (dependency : metadata.dependencies)
	{
		if (!valid_library_name(dependency)) return INVALID_METADATA~;
		if (catch metadata.find_source(dependency)) return MISSING_SOURCE~;
	}
	return;
}

fn void? validate_graph(Graph* graph)
{
	foreach (i, &node : graph.nodes)
	{
		if (!valid_library_name(node.name)) return INVALID_METADATA~;
		node.source.validate()!;
		for (sz j = i + 1; j < graph.nodes.len; j++)
		{
			if (node.name != graph.nodes[j].name) continue;
			if (!source_equal(node.source, graph.nodes[j].source)) return SOURCE_CONFLICT~;
			return INVALID_METADATA~;
		}
		foreach (dependency : node.dependencies)
		{
			if (catch graph.find(dependency)) return MISSING_SOURCE~;
		}
	}
	foreach (root : graph.roots) if (catch graph.find(root)) return MISSING_SOURCE~;
	String[] cycle = find_cycle(tmem, graph);
	if (cycle.len) return DEPENDENCY_CYCLE~;
	return;
}

fn sz? node_index(Graph* graph, String name)
{
	foreach (i, &node : graph.nodes) if (node.name == name) return i;
	return NOT_FOUND~;
}

fn bool dfs_cycle(Allocator allocator, Graph* graph, sz index, int[] states,
	List{String}* stack, List{String}* cycle)
{
	states[index] = 1;
	stack.push(graph.nodes[index].name);
	foreach (dependency : graph.nodes[index].dependencies)
	{
		sz child = node_index(graph, dependency)!!;
		if (states[child] == 0 && dfs_cycle(allocator, graph, child, states, stack, cycle)) return true;
		if (states[child] == 1)
		{
			bool copying;
			foreach (name : *stack)
			{
				if (name == dependency) copying = true;
				if (copying) cycle.push(name.copy(allocator));
			}
			cycle.push(dependency.copy(allocator));
			return true;
		}
	}
	(void)stack.pop();
	states[index] = 2;
	return false;
}

// Empty means acyclic. A non-empty result repeats the first node at the end,
// e.g. [foo, bar, baz, foo], so diagnostics can print the complete cycle.
fn String[] find_cycle(Allocator allocator, Graph* graph)
{
	List{int} state_list;
	state_list.init(allocator, graph.nodes.len);
	for (sz i = 0; i < graph.nodes.len; i++) state_list.push(0);
	int[] states = state_list.array_view();
	List{String} stack;
	stack.init(allocator, graph.nodes.len);
	List{String} cycle;
	cycle.init(allocator);
	for (sz i = 0; i < graph.nodes.len; i++)
	{
		if (states[i] == 0 && dfs_cycle(allocator, graph, i, states, &stack, &cycle)) break;
	}
	return cycle.to_array(allocator);
}

fn GraphNode[]? dependency_closure(Allocator allocator, Graph* graph)
{
	validate_graph(graph)!;
	List{GraphNode} result;
	result.init(allocator, graph.nodes.len);
	List{String} pending;
	pending.init(allocator);
	foreach (root : graph.roots) pending.push(root);
	while (pending.len())
	{
		String name = pending.pop_first()!;
		bool seen;
		foreach (&existing : result) if (existing.name == name) { seen = true; break; }
		if (seen) continue;
		GraphNode* node = graph.find(name)!;
		result.push(*node);
		foreach (dependency : node.dependencies) pending.push(dependency);
	}
	return result.to_array(allocator);
}
