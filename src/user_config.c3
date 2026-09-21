module c3pm;

import libc;
import std::collections::list;
import std::collections::object;
import std::encoding::json;
import std::io::file;
import std::io::path;

struct RegistryConfig
{
	String name;
	PackageSource source;
}

struct UserConfig
{
	bool has_nix;
	NixBackendConfig nix;
	RegistryConfig[] registries;
}

fn RegistryConfig*? UserConfig.find_registry(&self, String name)
{
	foreach (&registry : self.registries) if (registry.name == name) return registry;
	return NOT_FOUND~;
}

fn UserConfig? parse_user_config(Allocator allocator, String text)
{
	Object* root = json::parse(allocator, text)!;
	if (!root.is_map()) return INVALID_NIX_CONFIG~;
	UserConfig config;
	if (root.has_key("nix"))
	{
		Object* nix = root.get("nix")!;
		if (!nix.is_map() || !nix.has_key("mode") || !nix.has_key("path") ||
			!nix.get("mode")!.is_string() || !nix.get("path")!.is_string())
		{
			return INVALID_NIX_CONFIG~;
		}
		String mode = nix.get_string("mode")!;
		String executable = nix.get_string("path")!;
		if ((mode != "native" && mode != "portable") || !executable.len)
		{
			return INVALID_NIX_CONFIG~;
		}
		config.has_nix = true;
		config.nix = { .mode = mode.copy(allocator), .executable = executable.copy(allocator) };
	}

	List{RegistryConfig} registries;
	registries.init(allocator);
	if (root.has_key("registries"))
	{
		Object* declarations = root.get("registries")!;
		if (!declarations.is_map()) return INVALID_NIX_CONFIG~;
		declarations.@each_entry(; String name, Object* declaration)
		{
			if (!valid_library_name(name)) return INVALID_NIX_CONFIG~;
			PackageSource? parsed = parse_source_object(allocator, declaration);
			if (catch parsed) return INVALID_NIX_CONFIG~;
			registries.push({ .name = name.copy(allocator), .source = parsed });
		};
	}
	config.registries = registries.to_array(allocator);
	return config;
}

fn sz[] sorted_registry_indices(Allocator allocator, RegistryConfig[] registries)
{
	sz[] indices = alloc::alloc_array(allocator, sz, registries.len);
	for (sz i = 0; i < indices.len; i++) indices[i] = i;
	for (sz i = 1; i < indices.len; i++)
	{
		sz value = indices[i];
		sz j = i;
		while (j > 0 && registries[indices[j - 1]].name.compare_to(registries[value].name) > 0)
		{
			indices[j] = indices[j - 1];
			j--;
		}
		indices[j] = value;
	}
	return indices;
}

fn void append_config_field(DString* out, String indent, String key, String value,
	bool* previous)
{
	if (*previous) out.append(",\n");
	out.append(indent);
	append_json_string(out, key);
	out.append(": ");
	append_json_string(out, value);
	*previous = true;
}

fn void append_registry_source(DString* out, PackageSource source, String indent)
{
	bool previous;
	append_config_field(out, indent, "source", source_kind_name(source.kind), &previous);
	switch (source.kind)
	{
		case GITHUB:
			String[] parts = source.location.tsplit("/");
			append_config_field(out, indent, "owner", parts[0], &previous);
			append_config_field(out, indent, "repository", parts[1], &previous);
		case GIT_HTTPS:
		case GIT_SSH:
		case ARCHIVE_HTTPS: append_config_field(out, indent, "url", source.location, &previous);
		case FOLDER: append_config_field(out, indent, "path", source.location, &previous);
	}
	if (source.rev.len) append_config_field(out, indent, "rev", source.rev, &previous);
	if (source.subdir.len) append_config_field(out, indent, "subdir", source.subdir, &previous);
	if (source.sha256.len) append_config_field(out, indent, "sha256", source.sha256, &previous);
}

fn String encode_user_config(Allocator allocator, UserConfig* config)
{
	DString out = dstring::new_with_capacity(allocator, 512);
	out.append("{\n");
	bool previous;
	if (config.has_nix)
	{
		out.append("  \"nix\": {\n    \"mode\": ");
		append_json_string(&out, config.nix.mode);
		out.append(",\n    \"path\": ");
		append_json_string(&out, config.nix.executable);
		out.append("\n  }");
		previous = true;
	}
	if (config.registries.len)
	{
		if (previous) out.append(",\n");
		out.append("  \"registries\": {\n");
		sz[] sorted = sorted_registry_indices(tmem, config.registries);
		foreach (position, index : sorted)
		{
			RegistryConfig registry = config.registries[index];
			if (position) out.append(",\n");
			out.append("    "); append_json_string(&out, registry.name); out.append(": {\n");
			append_registry_source(&out, registry.source, "      ");
			out.append("\n    }");
		}
		out.append("\n  }");
	}
	out.append("\n}\n");
	return out.str_view();
}

fn UserConfig? load_user_config(Allocator allocator)
{
	String config_path = xdg_config_path(tmem)!;
	if (!file::is_file(config_path))
	{
		UserConfig empty;
		return empty;
	}
	String contents = (String)file::load(tmem, config_path)!;
	return parse_user_config(allocator, contents);
}

fn void? save_user_config(UserConfig* config)
{
	String destination = xdg_config_path(tmem)!;
	if (!config.has_nix && !config.registries.len)
	{
		if (file::is_file(destination)) file::delete(destination)!;
		return;
	}
	String parent = destination.path_tdirname()!;
	path::mkdir(parent, true)!;
	String temporary = string::format(tmem, "%s.tmp", destination);
	defer (void)file::delete(temporary);
	file::save(temporary, encode_user_config(tmem, config))!;
	if (chmod(temporary.zstr_tcopy(), 0o600) != 0) return TRANSACTION_FAILED~;
	if (libc::rename(temporary.zstr_tcopy(), destination.zstr_tcopy()) != 0)
	{
		return TRANSACTION_FAILED~;
	}
	return;
}

fn void? set_registry_config(UserConfig* config, Allocator allocator, RegistryConfig registry)
{
	foreach (&existing : config.registries)
	{
		if (existing.name != registry.name) continue;
		existing.source = registry.source;
		return;
	}
	List{RegistryConfig} entries;
	entries.init(allocator, config.registries.len + 1);
	entries.push_all(config.registries);
	entries.push(registry);
	config.registries = entries.to_array(allocator);
	return;
}

fn void? remove_registry_config(UserConfig* config, Allocator allocator, String name)
{
	bool found;
	List{RegistryConfig} entries;
	entries.init(allocator, config.registries.len);
	foreach (registry : config.registries)
	{
		if (registry.name == name) { found = true; continue; }
		entries.push(registry);
	}
	if (!found) return NOT_FOUND~;
	config.registries = entries.to_array(allocator);
	return;
}
