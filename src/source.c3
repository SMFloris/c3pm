module c3pm;

import std::io::path;

fn bool valid_github_identifier(String value)
{
	if (!value.len || value == "." || value == "..") return false;
	foreach (char c : value)
	{
		if (!(c.is_alnum() || c == '-' || c == '_' || c == '.')) return false;
	}
	return true;
}

fn void? validate_source_path(String path)
{
	if (!path.len) return;
	if (path[0] == '/' || path.ends_with("/") || path.contains("\\")) return INVALID_SOURCE_PATH~;
	String[] parts = path.tsplit("/");
	foreach (part : parts)
	{
		if (!part.len || part == "." || part == "..") return INVALID_SOURCE_PATH~;
	}
	foreach (char c : path) if (c < 0x20 || c == '"') return INVALID_SOURCE_PATH~;
	return;
}

fn void? PackageSource.validate(&self)
{
	if (!self.location.len || self.location.trim() != self.location) return INVALID_SOURCE~;
	if (self.kind == GITHUB)
	{
		String[] parts = self.location.tsplit("/");
		if (parts.len != 2 || !valid_github_identifier(parts[0]) ||
			!valid_github_identifier(parts[1])) return INVALID_SOURCE~;
	}
	if (self.kind == GIT_HTTPS && !self.location.starts_with("https://")) return INVALID_SOURCE~;
	if (self.kind == GIT_SSH && !self.location.starts_with("ssh://")) return INVALID_SOURCE~;
	if (self.kind == ARCHIVE_HTTPS && !self.location.starts_with("https://")) return INVALID_SOURCE~;
	if ((self.kind == GIT_HTTPS || self.kind == GIT_SSH) &&
		(self.location.contains("?") || self.location.contains("#"))) return INVALID_SOURCE~;
	if ((self.kind == GITHUB || self.kind == GIT_HTTPS || self.kind == GIT_SSH) &&
		!valid_git_ref(self.rev)) return INVALID_SOURCE~;
	if (self.kind == ARCHIVE_HTTPS && !self.sha256.starts_with("sha256-")) return INVALID_SOURCE~;
	validate_source_path(self.subdir)!;
	return;
}

fn bool valid_git_ref(String rev)
{
	if (!rev.len || rev.trim() != rev || rev.starts_with("/") || rev.ends_with("/") ||
		rev.starts_with(".") || rev.ends_with(".") || rev.contains("..") ||
		rev.contains("@{") || rev.ends_with(".lock")) return false;
	foreach (char c : rev)
	{
		if (c <= 0x20 || c == 0x7f || c == '~' || c == '^' || c == ':' ||
			c == '?' || c == '*' || c == '[' || c == '\\' || c == '#') return false;
	}
	String[] parts = rev.tsplit("/");
	foreach (part : parts) if (!part.len || part.starts_with(".")) return false;
	return true;
}

// Stable FNV-1a is deliberately used only for generated Nix identifiers. It is
// not a source hash; Nix owns source hashing and records it in flake.lock.
fn PackageSource? parse_source(Allocator allocator, String value, String rev,
	String subdir, String sha256)
{
	foreach (char c : value) if (c < 0x20 || c == '"' || c == '\\') return INVALID_SOURCE~;
	PackageSource source = { .rev = rev.copy(allocator), .subdir = subdir.copy(allocator),
		.sha256 = sha256.copy(allocator) };
	if (value.starts_with("github:"))
	{
		source.kind = GITHUB;
		source.location = value[7..].copy(allocator);
	}
	else if (value.starts_with("git+https://"))
	{
		source.kind = GIT_HTTPS;
		source.location = value[4..].copy(allocator);
	}
	else if (value.starts_with("git+ssh://"))
	{
		source.kind = GIT_SSH;
		source.location = value[4..].copy(allocator);
	}
	else if (value.starts_with("archive+https://"))
	{
		source.kind = ARCHIVE_HTTPS;
		source.location = value[8..].copy(allocator);
	}
	else if (value.starts_with("path:"))
	{
		source.kind = FOLDER;
		source.location = value[5..].copy(allocator);
	}
	else { return INVALID_SOURCE~; }
	source.validate()!;
	return source;
}

fn String source_kind_name(SourceKind kind)
{
	switch (kind)
	{
		case GITHUB: return "github";
		case GIT_HTTPS: return "git+https";
		case GIT_SSH: return "git+ssh";
		case ARCHIVE_HTTPS: return "archive+https";
		case FOLDER: return "path";
	}
}

fn String source_url(Allocator allocator, PackageSource source)
{
	switch (source.kind)
	{
		case GITHUB: return string::format(allocator, "github:%s/%s", source.location, source.rev);
		case GIT_HTTPS: return string::format(allocator, "git+%s?ref=%s", source.location, source.rev);
		case GIT_SSH: return string::format(allocator, "git+%s?ref=%s", source.location, source.rev);
		case ARCHIVE_HTTPS: return string::format(allocator, "tarball+%s", source.location);
		case FOLDER:
			if (source.location.is_absolute_path()!!) { return string::format(allocator, "path:%s", source.location); }
			if (!source.base.len) { return string::format(allocator, "path:%s", source.location); }
			Path absolute = string::format(tmem, "%s/%s", source.base, source.location)
				.to_tpath()!!.to_absolute_path(tmem)!!;
			return string::format(allocator, "path:%s", (String)absolute);
	}
}

fn ulong source_identity_hash(PackageSource source)
{
	ulong hash = 14695981039346656037;
	String[] fields = { source_kind_name(source.kind), source.location, source.rev, source.sha256, source.base };
	foreach (field : fields)
	{
		foreach (char c : field)
		{
			hash ^= c;
			hash *= 1099511628211;
		}
		hash ^= 0xff;
		hash *= 1099511628211;
	}
	return hash;
}

fn String source_input_name(Allocator allocator, PackageSource source)
{
	@stack_mem(256; Allocator smem)
	{
		DString out = dstring::new_with_capacity(smem, 64);
		out.append("c3pm_src_");
		append_nix_identifier_part(&out, source_kind_name(source.kind));
		out.append("_");
		append_nix_identifier_part(&out, source.location);
		out.appendf("_%08x", (uint)source_identity_hash(source));
		return out.str_view().copy(allocator);
	};
}

fn void append_nix_identifier_part(DString* out, String value)
{
	foreach (char c : value)
	{
		out.append(c.is_alnum() || c == '_' ? c.to_lower() : '_');
	}
}

fn bool valid_nix_attribute(String attr)
{
	if (!attr.len || attr[0] == '.' || attr.ends_with(".")) return false;
	String[] parts = attr.tsplit(".");
	foreach (part : parts)
	{
		if (!part.len) return false;
		foreach (i, char c : part)
		{
			if (i == 0 && !(c.is_alpha() || c == '_')) return false;
			if (!(c.is_alnum() || c == '_' || c == '-' || c == '\'')) return false;
		}
	}
	return true;
}

fn void? validate_nix_import_path(String import_path)
{
	if (!import_path.len || import_path[0] == '/' || import_path.contains("\\") ||
		!import_path.ends_with(".nix")) return INVALID_SOURCE_PATH~;
	String normalized = import_path.starts_with("./") ? import_path[2..] : import_path;
	if (!normalized.len) return INVALID_SOURCE_PATH~;
	String[] parts = normalized.tsplit("/");
	foreach (part : parts)
	{
		if (!part.len || part == "." || part == "..") return INVALID_SOURCE_PATH~;
	}
	foreach (char c : import_path) if (c < 0x20 || c == '"') return INVALID_SOURCE_PATH~;
	return;
}

fn bool safe_metadata_value(String value)
{
	if (!value.len) return false;
	foreach (char c : value) if (c < 0x20 || c == '"' || c == '\\') return false;
	return true;
}

fn String nix_import_relative_path(String import_path)
{
	return import_path.starts_with("./") ? import_path[2..] : import_path;
}
