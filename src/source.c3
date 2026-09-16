module c3pm;

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
	return;
}

fn void? FetchGithub.validate(&self)
{
	if (!valid_github_identifier(self.owner) || !valid_github_identifier(self.repo)) return INVALID_SOURCE~;
	if (!valid_git_ref(self.rev)) return INVALID_SOURCE~;
	validate_source_path(self.path)!;
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

fn FetchGithub? parse_github_uri(Allocator allocator, String uri)
{
	const String PREFIX = "github://";
	if (!uri.starts_with(PREFIX)) return INVALID_GITHUB_URI~;
	String rest = uri[PREFIX.len..];
	sz hash = rest.index_of("#")!;
	if (hash == 0 || hash + 1 >= rest.len || rest[hash + 1..].contains("#")) return INVALID_GITHUB_URI~;
	String locator = rest[:hash];
	String rev = rest[hash + 1..];
	sz at = locator.index_of("@")!;
	if (at == 0 || at + 1 >= locator.len || locator[at + 1..].contains("@")) return INVALID_GITHUB_URI~;
	String owner = locator[:at];
	String repo_and_path = locator[at + 1..];
	String repo;
	String path;
	if (try slash = repo_and_path.index_of("/"))
	{
		repo = repo_and_path[:slash];
		path = repo_and_path[slash + 1..];
	}
	else
	{
		repo = repo_and_path;
		path = "";
	}
	FetchGithub source = {
		.owner = owner.copy(allocator),
		.repo = repo.copy(allocator),
		.rev = rev.copy(allocator),
		.path = path.copy(allocator),
	};
	source.validate()!;
	return source;
}

// Stable FNV-1a is deliberately used only for generated Nix identifiers. It is
// not a source hash; Nix owns source hashing and records it in flake.lock.
fn ulong source_identity_hash(FetchGithub source)
{
	ulong hash = 14695981039346656037;
	String[] fields = { source.owner, source.repo, source.rev };
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

fn String source_input_name(Allocator allocator, FetchGithub source)
{
	@stack_mem(256; Allocator smem)
	{
		DString out = dstring::new_with_capacity(smem, 64);
		out.append("c3pm_src_");
		append_nix_identifier_part(&out, source.owner);
		out.append("_");
		append_nix_identifier_part(&out, source.repo);
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
	return;
}

fn String nix_import_relative_path(String import_path)
{
	return import_path.starts_with("./") ? import_path[2..] : import_path;
}
