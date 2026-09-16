module c3pm;

import std::collections::list;
import std::collections::object;
import std::encoding::json;

fn String[]? parse_string_array(Allocator allocator, Object* parent, String key)
{
	List{String} values;
	values.init(allocator);
	if (!parent.has_key(key)) return values.to_array(allocator);
	Object* array = parent.get(key)!;
	if (!array.is_array()) return INVALID_METADATA~;
	for (sz i = 0; i < array.len(); i++)
	{
		Object* item = array.get_at(i);
		if (!item.is_string() || !item.s.len) return INVALID_METADATA~;
		values.push(item.s.copy(allocator));
	}
	return values.to_array(allocator);
}

fn void append_unique(List{String}* list, Allocator allocator, String[] values)
{
	foreach (value : values)
	{
		bool found;
		foreach (existing : *list) if (existing == value) { found = true; break; }
		if (!found) list.push(value.copy(allocator));
	}
}

fn String[]? parse_dependencies(Allocator allocator, Object* root, String target)
{
	List{String} dependencies;
	dependencies.init(allocator);
	String[] direct = parse_string_array(allocator, root, "dependencies")!;
	append_unique(&dependencies, allocator, direct);
	if (target.len && root.has_key("targets"))
	{
		Object* targets = root.get("targets")!;
		if (!targets.is_map()) return INVALID_METADATA~;
		if (targets.has_key(target))
		{
			Object* selected = targets.get(target)!;
			if (!selected.is_map()) return INVALID_METADATA~;
			String[] extra = parse_string_array(allocator, selected, "dependencies")!;
			append_unique(&dependencies, allocator, extra);
		}
	}
	return dependencies.to_array(allocator);
}

fn Object*? c3pm_vendor(Object* root)
{
	if (!root.has_key("vendor")) return NOT_FOUND~;
	Object* vendor = root.get("vendor")!;
	if (!vendor.is_map() || !vendor.has_key("c3pm")) return NOT_FOUND~;
	Object* c3pm = vendor.get("c3pm")!;
	if (!c3pm.is_map()) return INVALID_METADATA~;
	return c3pm;
}

fn DependencySpec[]? parse_sources(Allocator allocator, Object* c3pm)
{
	List{DependencySpec} specs;
	specs.init(allocator);
	if (!c3pm.has_key("c3")) return specs.to_array(allocator);
	Object* c3 = c3pm.get("c3")!;
	if (!c3.is_map()) return INVALID_METADATA~;
	if (!c3.has_key("dependencies")) return specs.to_array(allocator);
	Object* dependencies = c3.get("dependencies")!;
	if (!dependencies.is_map()) return INVALID_METADATA~;
	dependencies.@each_entry(; String name, Object* declaration)
	{
		if (!name.len || !declaration.is_map() || !declaration.has_key("fetchGithub")) return INVALID_METADATA~;
		Object* github = declaration.get("fetchGithub")!!;
		if (!github.is_map()) return INVALID_METADATA~;
		FetchGithub source = {
			.owner = github.get_string("owner")!!.copy(allocator),
			.repo = github.get_string("repo")!!.copy(allocator),
			.rev = github.get_string("rev")!!.copy(allocator),
			.path = github.has_key("path") ? github.get_string("path")!!.copy(allocator) : "",
		};
		source.validate()!!;
		specs.push({ .name = name.copy(allocator), .source = source });
	};
	return specs.to_array(allocator);
}

fn String[]? parse_nix_class(Allocator allocator, Object* nix, String key)
{
	String[] attrs = parse_string_array(allocator, nix, key)!;
	foreach (attr : attrs) if (!valid_nix_attribute(attr)) return INVALID_NIX_ATTRIBUTE~;
	return attrs;
}

fn String[]? parse_nix_imports(Allocator allocator, Object* nix)
{
	List{String} imports;
	imports.init(allocator);
	if (!nix.has_key("imports")) return imports.to_array(allocator);
	Object* value = nix.get("imports")!;
	if (value.is_string())
	{
		validate_nix_import_path(value.s)!;
		imports.push(value.s.copy(allocator));
	}
	else if (value.is_array())
	{
		for (sz i = 0; i < value.len(); i++)
		{
			Object* item = value.get_at(i);
			if (!item.is_string()) return INVALID_METADATA~;
			validate_nix_import_path(item.s)!;
			imports.push(item.s.copy(allocator));
		}
	}
	else { return INVALID_METADATA~; }
	return imports.to_array(allocator);
}

fn NixInputs? parse_nix_inputs(Allocator allocator, Object* c3pm)
{
	Object* nix = null;
	if (c3pm.has_key("nix"))
	{
		nix = c3pm.get("nix")!;
		if (!nix.is_map()) return INVALID_METADATA~;
	}
	else
	{
		nix = object::new_obj(allocator);
	}
	return {
		.imports = parse_nix_imports(allocator, nix)!,
		.native_build_inputs = parse_nix_class(allocator, nix, "nativeBuildInputs")!,
		.build_inputs = parse_nix_class(allocator, nix, "buildInputs")!,
		.propagated_native_build_inputs = parse_nix_class(allocator, nix, "propagatedNativeBuildInputs")!,
		.propagated_build_inputs = parse_nix_class(allocator, nix, "propagatedBuildInputs")!,
	};
}

fn Metadata? parse_metadata(Allocator allocator, String text, String target, bool require_provides)
{
	Object* root = json::parse(allocator, text, JSONC)!;
	if (!root.is_map()) return INVALID_METADATA~;
	Metadata result;
	if (root.has_key("provides")) result.provides = root.get_string("provides")!.copy(allocator);
	result.version = root.has_key("version")
		? root.get_string("version")!.copy(allocator)
		: "0.0.0";
	if (require_provides && !result.provides.len) return INVALID_METADATA~;
	result.dependencies = parse_dependencies(allocator, root, target)!;
	if (try c3pm = c3pm_vendor(root))
	{
		result.sources = parse_sources(allocator, c3pm)!;
		result.nix = parse_nix_inputs(allocator, c3pm)!;
	}
	else
	{
		List{DependencySpec} empty_sources;
		empty_sources.init(allocator, 0);
		result.sources = empty_sources.to_array(allocator);
		Object* empty = object::new_obj(allocator);
		result.nix = parse_nix_inputs(allocator, empty)!;
	}
	return result;
}

fn Metadata? parse_project(Allocator allocator, String text, String target)
{
	Metadata project = parse_metadata(allocator, text, target, false)!;
	Object* root = json::parse(tmem, text, JSONC)!;
	if (!root.is_map()) return INVALID_METADATA~;
	project.targets = parse_project_targets(allocator, root)!;
	return project;
}

fn Metadata? parse_manifest(Allocator allocator, String text, String target)
{
	return parse_metadata(allocator, text, target, true);
}

fn ProjectTarget[]? parse_project_targets(Allocator allocator, Object* root)
{
	List{ProjectTarget} targets;
	targets.init(allocator);
	if (!root.has_key("targets")) return targets.to_array(allocator);
	Object* declarations = root.get("targets")!;
	if (!declarations.is_map()) return INVALID_METADATA~;
	declarations.@each_entry(; String name, Object* declaration)
	{
		if (!valid_library_name(name) || !declaration.is_map()) return INVALID_METADATA~;
		String target_type = declaration.has_key("type")
			? declaration.get_string("type")!!.copy(allocator)
			: "";
		targets.push({ .name = name.copy(allocator), .type = target_type });
	};
	return targets.to_array(allocator);
}
