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

fn SourceKind? parse_source_kind(String value)
{
	if (value == "github") return GITHUB;
	if (value == "git+https") return GIT_HTTPS;
	if (value == "git+ssh") return GIT_SSH;
	if (value == "archive+https") return ARCHIVE_HTTPS;
	if (value == "path") return FOLDER;
	return INVALID_SOURCE~;
}

fn PackageSource? parse_source_object(Allocator allocator, Object* declaration)
{
	if (!declaration.is_map() || !declaration.has_key("source") ||
		!declaration.get("source")!.is_string()) return INVALID_METADATA~;
	if (declaration.has_key("hashMode") &&
		(!declaration.get("hashMode")!.is_string() ||
		declaration.get_string("hashMode")! != "file")) return INVALID_METADATA~;
	SourceKind kind = parse_source_kind(declaration.get_string("source")!)!;
	String location;
	switch (kind)
	{
		case GITHUB:
			location = string::format(allocator, "%s/%s",
				declaration.get_string("owner")!, declaration.get_string("repository")!);
		case GIT_HTTPS:
		case GIT_SSH:
		case ARCHIVE_HTTPS: location = declaration.get_string("url")!.copy(allocator);
		case FOLDER: location = declaration.get_string("path")!.copy(allocator);
	}
	PackageSource parsed = {
		.kind = kind,
		.location = location,
		.rev = declaration.has_key("rev") ? declaration.get_string("rev")!.copy(allocator) : "",
		.subdir = declaration.has_key("subdir") ? declaration.get_string("subdir")!.copy(allocator) : "",
		.sha256 = declaration.has_key("sha256") ? declaration.get_string("sha256")!.copy(allocator) : "",
		.raw_archive = declaration.has_key("hashMode") &&
			declaration.get_string("hashMode")! == "file",
		.archive_type = declaration.has_key("archiveType")
			? declaration.get_string("archiveType")!.copy(allocator) : "",
	};
	parsed.validate()!;
	return parsed;
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
		if (!name.len || !declaration.is_map()) return INVALID_METADATA~;
		PackageSource source = parse_source_object(allocator, declaration)!;
		specs.push({ .name = name.copy(allocator), .source = source });
	};
	return specs.to_array(allocator);
}

fn RegistryDependencySpec[]? parse_registry_dependencies(Allocator allocator, Object* c3pm)
{
	List{RegistryDependencySpec} specs;
	specs.init(allocator);
	if (!c3pm.has_key("registry")) return specs.to_array(allocator);
	Object* declarations = c3pm.get("registry")!;
	if (!declarations.is_map()) return INVALID_METADATA~;
	declarations.@each_entry(; String name, Object* declaration)
	{
		if (!valid_library_name(name) || !declaration.is_map() ||
			!declaration.has_key("registry") || !declaration.has_key("package") ||
			!declaration.has_key("version") ||
			!declaration.get("registry")!.is_string() ||
			!declaration.get("package")!.is_string() ||
			!declaration.get("version")!.is_string()) return INVALID_METADATA~;
		String registry = declaration.get_string("registry")!;
		String package_id = declaration.get_string("package")!;
		String version = declaration.get_string("version")!;
		if (!valid_library_name(registry) || !is_registry_package_id(package_id) ||
			!valid_registry_version(version)) return INVALID_METADATA~;
		specs.push({
			.name = name.copy(allocator),
			.registry = registry.copy(allocator),
			.package_id = package_id.copy(allocator),
			.version = version.copy(allocator),
		});
	};
	return specs.to_array(allocator);
}

fn LinkSpec[]? parse_links(Allocator allocator, Object* c3pm)
{
	List{LinkSpec} links;
	links.init(allocator);
	if (!c3pm.has_key("links")) return links.to_array(allocator);
	Object* declarations = c3pm.get("links")!;
	if (!declarations.is_map()) return INVALID_METADATA~;
	declarations.@each_entry(; String name, Object* declaration)
	{
		if (!valid_library_name(name) || !declaration.is_map()) return INVALID_METADATA~;
		LinkSpec link = {
			.name = name.copy(allocator),
			.c3c_target = declaration.has_key("c3cTarget")
				? declaration.get_string("c3cTarget")!!.copy(allocator) : "none",
			.nix_package = declaration.has_key("nixPackage")
				? declaration.get_string("nixPackage")!!.copy(allocator) : "",
			.for_target = declaration.has_key("forTarget")
				? declaration.get_string("forTarget")!!.copy(allocator) : "",
		};
		if (declaration.has_key("mode"))
		{
			String mode = declaration.get_string("mode")!!;
			if (mode != "runtime" && mode != "passthrough") return INVALID_METADATA~;
			link.passthrough = mode == "passthrough";
		}
		if (declaration.has_key("source"))
		{
			link.source = parse_source_object(allocator, declaration)!;
			link.has_source = true;
		}
		if (link.c3c_target != "none" && !link.has_source) return MISSING_SOURCE~;
		if (link.nix_package.starts_with("path:"))
		{
			validate_nix_import_path(link.nix_package[5..])!;
		}
		else if (link.nix_package.len && !valid_nix_attribute(link.nix_package))
		{
			return INVALID_NIX_ATTRIBUTE~;
		}
		links.push(link);
	};
	return links.to_array(allocator);
}

fn ToolchainConfig? parse_toolchain(Allocator allocator, Object* c3pm)
{
	ToolchainConfig config = { .nixpkgs = "github:NixOS/nixpkgs/nixpkgs-unstable" };
	// nixpkgs 26.11 dropped x86_64-darwin. Its last supported stable branch
	// still needs a newer C3 than the version packaged there.
	$if env::DARWIN && env::X86_64:
	config.nixpkgs = "github:NixOS/nixpkgs/0c32f40fe3e2a9adfc427fd5abc061a31043ea44";
	config.c3c_version = "0.8.4";
	$endif
	if (!c3pm.has_key("toolchain")) return config;
	Object* declaration = c3pm.get("toolchain")!;
	if (!declaration.is_map()) return INVALID_METADATA~;
	if (declaration.has_key("c3c")) config.c3c_version = declaration.get_string("c3c")!.copy(allocator);
	if (declaration.has_key("nixpkgs")) config.nixpkgs = declaration.get_string("nixpkgs")!.copy(allocator);
	if (!config.nixpkgs.len) return INVALID_METADATA~;
	return config;
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
		result.registry_dependencies = parse_registry_dependencies(allocator, c3pm)!;
		result.nix = parse_nix_inputs(allocator, c3pm)!;
		result.links = parse_links(allocator, c3pm)!;
		result.toolchain = parse_toolchain(allocator, c3pm)!;
	}
	else
	{
		List{DependencySpec} empty_sources;
		empty_sources.init(allocator, 0);
		result.sources = empty_sources.to_array(allocator);
		Object* empty = object::new_obj(allocator);
		result.nix = parse_nix_inputs(allocator, empty)!;
		result.links = parse_links(allocator, empty)!;
		result.toolchain = parse_toolchain(allocator, empty)!;
	}
	return result;
}

fn Metadata? parse_project(Allocator allocator, String text, String target)
{
	Metadata project = parse_metadata(allocator, text, target, false)!;
	Object* root = json::parse(tmem, text, JSONC)!;
	if (!root.is_map()) return INVALID_METADATA~;
	project.targets = parse_project_targets(allocator, root)!;
	// Every project target must be reproducible from one generated environment.
	// Keep target selection in project.json, but resolve the union here.
	List{String} dependencies;
	dependencies.init(allocator);
	append_unique(&dependencies, allocator, parse_string_array(tmem, root, "dependencies")!);
	if (root.has_key("targets"))
	{
		Object* targets = root.get("targets")!;
		targets.@each_entry(; String name, Object* declaration)
		{
			if (!declaration.is_map()) return INVALID_METADATA~;
			append_unique(&dependencies, allocator,
				parse_string_array(tmem, declaration, "dependencies")!!);
		};
	}
	project.dependencies = dependencies.to_array(allocator);
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
