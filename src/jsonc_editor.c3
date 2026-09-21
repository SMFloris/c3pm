module c3pm;

struct JsonSpan
{
	sz start;
	sz end;
	bool found;
}

struct JsonMember
{
	sz start;
	sz value_start;
	sz value_end;
	sz object_end;
	bool found;
}

fn bool json_space(char c)
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

fn void skip_jsonc_trivia(String text, sz* cursor)
{
	while (*cursor < text.len)
	{
		if (json_space(text[*cursor])) { (*cursor)++; continue; }
		if (*cursor + 1 < text.len && text[*cursor] == '/' && text[*cursor + 1] == '/')
		{
			*cursor += 2;
			while (*cursor < text.len && text[*cursor] != '\n') (*cursor)++;
			continue;
		}
		if (*cursor + 1 < text.len && text[*cursor] == '/' && text[*cursor + 1] == '*')
		{
			*cursor += 2;
			while (*cursor + 1 < text.len && !(text[*cursor] == '*' && text[*cursor + 1] == '/')) (*cursor)++;
			if (*cursor + 1 < text.len) *cursor += 2;
			continue;
		}
		break;
	}
}

fn sz? scan_json_string(String text, sz start)
{
	if (start >= text.len || text[start] != '"') return INVALID_METADATA~;
	for (sz i = start + 1; i < text.len; i++)
	{
		if (text[i] == '\\') { i++; continue; }
		if (text[i] == '"') return i + 1;
	}
	return INVALID_METADATA~;
}

fn sz? scan_json_value(String text, sz start)
{
	if (start >= text.len) return INVALID_METADATA~;
	if (text[start] == '"') return scan_json_string(text, start);
	if (text[start] == '{' || text[start] == '[')
	{
		char open = text[start];
		char close = open == '{' ? '}' : ']';
		int depth = 1;
		for (sz i = start + 1; i < text.len; i++)
		{
			if (text[i] == '"') { i = scan_json_string(text, i)! - 1; continue; }
			if (i + 1 < text.len && text[i] == '/' && text[i + 1] == '/')
			{
				i += 2;
				while (i < text.len && text[i] != '\n') i++;
				continue;
			}
			if (i + 1 < text.len && text[i] == '/' && text[i + 1] == '*')
			{
				i += 2;
				while (i + 1 < text.len && !(text[i] == '*' && text[i + 1] == '/')) i++;
				i++;
				continue;
			}
			if (text[i] == open) depth++;
			if (text[i] == close && --depth == 0) return i + 1;
		}
		return INVALID_METADATA~;
	}
	sz end = start;
	while (end < text.len && text[end] != ',' && text[end] != '}' && text[end] != ']') end++;
	while (end > start && json_space(text[end - 1])) end--;
	return end;
}

fn JsonMember? find_json_member(String text, sz object_start, String key)
{
	if (object_start >= text.len || text[object_start] != '{') return INVALID_METADATA~;
	sz cursor = object_start + 1;
	while (true)
	{
		skip_jsonc_trivia(text, &cursor);
		if (cursor >= text.len) return INVALID_METADATA~;
		if (text[cursor] == '}') return { .object_end = cursor + 1 };
		if (text[cursor] == ',') { cursor++; continue; }
		sz member_start = cursor;
		sz key_end = scan_json_string(text, cursor)!;
		String actual = text[cursor + 1 .. key_end - 2];
		cursor = key_end;
		skip_jsonc_trivia(text, &cursor);
		if (cursor >= text.len || text[cursor] != ':') return INVALID_METADATA~;
		cursor++;
		skip_jsonc_trivia(text, &cursor);
		sz value_start = cursor;
		sz value_end = scan_json_value(text, value_start)!;
		if (actual == key)
		{
			return { .start = member_start, .value_start = value_start,
				.value_end = value_end, .found = true };
		}
		cursor = value_end;
	}
}

fn String replace_json_range(Allocator allocator, String text, sz start, sz end, String replacement)
{
	DString out = dstring::new_with_capacity(allocator, text.len + replacement.len);
	out.append(text[:start]);
	out.append(replacement);
	out.append(text[end..]);
	return out.str_view();
}

fn String? insert_json_container_value(Allocator allocator, String text, sz container_start,
	char closing, String formatted_value)
{
	sz end = scan_json_value(text, container_start)!;
	if (end == 0 || text[end - 1] != closing) return INVALID_METADATA~;
	sz close_at = end - 1;
	char last_significant;
	bool empty = true;
	for (sz cursor = container_start + 1; cursor < close_at; cursor++)
	{
		if (json_space(text[cursor])) continue;
		if (cursor + 1 < close_at && text[cursor] == '/' && text[cursor + 1] == '/')
		{
			cursor += 2;
			while (cursor < close_at && text[cursor] != '\n') cursor++;
			continue;
		}
		if (cursor + 1 < close_at && text[cursor] == '/' && text[cursor + 1] == '*')
		{
			cursor += 2;
			while (cursor + 1 < close_at && !(text[cursor] == '*' && text[cursor + 1] == '/')) cursor++;
			cursor++;
			continue;
		}
		empty = false;
		last_significant = text[cursor];
		if (text[cursor] == '"') cursor = scan_json_string(text, cursor)! - 1;
	}
	bool trailing_comma = !empty && last_significant == ',';
	DString insertion = dstring::new_with_capacity(tmem, formatted_value.len + 16);
	if (!empty && !trailing_comma) insertion.append(",");
	insertion.append("\n");
	insertion.append(formatted_value);
	insertion.append("\n");
	return replace_json_range(allocator, text, close_at, close_at, insertion.str_view());
}

fn JsonMember? find_member_path(String text, String[] path_parts)
{
	sz object_start;
	JsonMember member;
	foreach (i, part : path_parts)
	{
		member = find_json_member(text, object_start, part)!;
		if (!member.found) return member;
		if (i + 1 < path_parts.len)
		{
			if (text[member.value_start] != '{') return INVALID_METADATA~;
			object_start = member.value_start;
		}
	}
	return member;
}

fn bool json_array_has_string(String text, sz array_start, String wanted)
{
	sz cursor = array_start + 1;
	while (cursor < text.len)
	{
		skip_jsonc_trivia(text, &cursor);
		if (text[cursor] == ']') return false;
		if (text[cursor] == ',') { cursor++; continue; }
		sz end = scan_json_value(text, cursor)!!;
		if (text[cursor] == '"' && text[cursor + 1 .. end - 2] == wanted) return true;
		cursor = end;
	}
	return false;
}

fn String? add_array_string(Allocator allocator, String text, String key, String value)
{
	JsonMember member = find_json_member(text, 0, key)!;
	if (!member.found || text[member.value_start] != '[') return INVALID_METADATA~;
	if (json_array_has_string(text, member.value_start, value)) return text.copy(allocator);
	DString item = dstring::new_with_capacity(tmem, value.len + 8);
	item.append("    \""); item.append(value); item.append("\"");
	return insert_json_container_value(allocator, text, member.value_start, ']', item.str_view());
}

fn String? add_array_string_in_object(Allocator allocator, String text, sz object_start,
	String key, String value)
{
	JsonMember member = find_json_member(text, object_start, key)!;
	if (!member.found)
	{
		DString property = dstring::new_with_capacity(tmem, key.len + value.len + 24);
		property.appendf("      \"%s\": [ \"%s\" ]", key, value);
		return insert_json_container_value(allocator, text, object_start, '}', property.str_view());
	}
	if (text[member.value_start] != '[') return INVALID_METADATA~;
	if (json_array_has_string(text, member.value_start, value)) return text.copy(allocator);
	DString item = dstring::new_with_capacity(tmem, value.len + 12);
	item.appendf("        \"%s\"", value);
	return insert_json_container_value(allocator, text, member.value_start, ']', item.str_view());
}

fn sz? project_target_object(String text, String target)
{
	JsonMember targets = find_json_member(text, 0, "targets")!;
	if (!targets.found || text[targets.value_start] != '{') return UNKNOWN_TARGET~;
	JsonMember selected = find_json_member(text, targets.value_start, target)!;
	if (!selected.found || text[selected.value_start] != '{') return UNKNOWN_TARGET~;
	return selected.value_start;
}

fn String? add_array_string_at(Allocator allocator, String text, String key,
	String value, String target)
{
	if (!target.len)
	{
		JsonMember member = find_json_member(text, 0, key)!;
		if (member.found) return add_array_string(allocator, text, key, value);
		DString property = dstring::new_with_capacity(tmem, key.len + value.len + 20);
		property.appendf("  \"%s\": [ \"%s\" ]", key, value);
		return insert_json_container_value(allocator, text, 0, '}', property.str_view());
	}
	return add_array_string_in_object(allocator, text, project_target_object(text, target)!, key, value);
}

fn JsonSpan? find_array_string(String text, sz array_start, String wanted)
{
	sz cursor = array_start + 1;
	while (cursor < text.len)
	{
		skip_jsonc_trivia(text, &cursor);
		if (text[cursor] == ']') return {};
		if (text[cursor] == ',') { cursor++; continue; }
		sz start = cursor;
		sz end = scan_json_value(text, cursor)!;
		if (text[start] == '"' && text[start + 1 .. end - 2] == wanted)
		{
			return { .start = start, .end = end, .found = true };
		}
		cursor = end;
	}
	return {};
}

fn JsonSpan expand_removal(String text, JsonSpan span, sz container_start)
{
	sz after = span.end;
	skip_jsonc_trivia(text, &after);
	if (after < text.len && text[after] == ',') { span.end = after + 1; return span; }
	sz before = span.start;
	while (before > container_start + 1 && json_space(text[before - 1])) before--;
	if (before > container_start + 1 && text[before - 1] == ',') span.start = before - 1;
	return span;
}

fn String? remove_array_string(Allocator allocator, String text, String key, String value)
{
	JsonMember member = find_json_member(text, 0, key)!;
	if (!member.found || text[member.value_start] != '[') return INVALID_METADATA~;
	JsonSpan item = find_array_string(text, member.value_start, value)!;
	if (!item.found) return NOT_FOUND~;
	item = expand_removal(text, item, member.value_start);
	return replace_json_range(allocator, text, item.start, item.end, "");
}

fn String? remove_array_string_at(Allocator allocator, String text, String key,
	String value, String target)
{
	sz object_start = target.len ? project_target_object(text, target)! : 0;
	JsonMember member = find_json_member(text, object_start, key)!;
	if (!member.found || text[member.value_start] != '[') return NOT_FOUND~;
	JsonSpan item = find_array_string(text, member.value_start, value)!;
	if (!item.found) return NOT_FOUND~;
	item = expand_removal(text, item, member.value_start);
	return replace_json_range(allocator, text, item.start, item.end, "");
}

fn String? replace_array_string_at(Allocator allocator, String text, String key,
	String previous, String replacement, String target)
{
	if (previous == replacement) return text.copy(allocator);
	sz object_start = target.len ? project_target_object(text, target)! : 0;
	JsonMember member = find_json_member(text, object_start, key)!;
	if (!member.found) return text.copy(allocator);
	if (text[member.value_start] != '[') return INVALID_METADATA~;
	JsonSpan item = find_array_string(text, member.value_start, previous)!;
	if (!item.found) return text.copy(allocator);
	if (json_array_has_string(text, member.value_start, replacement)) return SOURCE_CONFLICT~;
	String quoted = string::format(tmem, "\"%s\"", replacement);
	return replace_json_range(allocator, text, item.start, item.end, quoted);
}

fn String? insert_c3pm_property(Allocator allocator, String text, String property)
{
	JsonMember vendor = find_json_member(text, 0, "vendor")!;
	if (!vendor.found)
	{
		DString nested = dstring::new_with_capacity(tmem, property.len + 64);
		nested.append("  \"vendor\": {\n    \"c3pm\": {\n");
		nested.append(property);
		nested.append("\n    }\n  }");
		return insert_json_container_value(allocator, text, 0, '}', nested.str_view());
	}
	if (text[vendor.value_start] != '{') return INVALID_METADATA~;
	JsonMember c3pm = find_json_member(text, vendor.value_start, "c3pm")!;
	if (!c3pm.found)
	{
		DString nested = dstring::new_with_capacity(tmem, property.len + 40);
		nested.append("    \"c3pm\": {\n"); nested.append(property); nested.append("\n    }");
		return insert_json_container_value(allocator, text, vendor.value_start, '}', nested.str_view());
	}
	if (text[c3pm.value_start] != '{') return INVALID_METADATA~;
	return insert_json_container_value(allocator, text, c3pm.value_start, '}', property);
}

fn String? set_toolchain_value(Allocator allocator, String text, String key, String value)
{
	JsonMember toolchain = find_member_path(text, { "vendor", "c3pm", "toolchain" })!;
	if (!toolchain.found)
	{
		DString property = dstring::new_with_capacity(tmem, key.len + value.len + 48);
		property.appendf("      \"toolchain\": { \"%s\": \"%s\" }", key, value);
		return insert_c3pm_property(allocator, text, property.str_view());
	}
	if (text[toolchain.value_start] != '{') return INVALID_METADATA~;
	JsonMember existing = find_json_member(text, toolchain.value_start, key)!;
	DString encoded = dstring::new_with_capacity(tmem, value.len + 2);
	encoded.appendf("\"%s\"", value);
	if (existing.found) return replace_json_range(allocator, text, existing.value_start,
		existing.value_end, encoded.str_view());
	DString property = dstring::new_with_capacity(tmem, value.len + key.len + 20);
	property.appendf("        \"%s\": \"%s\"", key, value);
	return insert_json_container_value(allocator, text, toolchain.value_start, '}', property.str_view());
}

fn String? remove_toolchain_value(Allocator allocator, String text, String key)
{
	JsonMember toolchain = find_member_path(text, { "vendor", "c3pm", "toolchain" })!;
	if (!toolchain.found) return NOT_FOUND~;
	JsonMember existing = find_json_member(text, toolchain.value_start, key)!;
	if (!existing.found) return NOT_FOUND~;
	JsonSpan span = { .start = existing.start, .end = existing.value_end, .found = true };
	span = expand_removal(text, span, toolchain.value_start);
	return replace_json_range(allocator, text, span.start, span.end, "");
}

fn String? add_source_declaration(Allocator allocator, String text, String name, PackageSource source)
{
	JsonMember dependencies = find_member_path(text, { "vendor", "c3pm", "c3", "dependencies" })!;
	DString declaration = dstring::new_with_capacity(tmem, 256);
	declaration.appendf("        \"%s\": {\n", name);
	append_source_metadata(&declaration, source, "          ");
	declaration.append("\n        }");
	if (dependencies.found)
	{
		if (text[dependencies.value_start] != '{') return INVALID_METADATA~;
		JsonMember existing = find_json_member(text, dependencies.value_start, name)!;
		if (existing.found) return SOURCE_CONFLICT~;
		return insert_json_container_value(allocator, text, dependencies.value_start, '}', declaration.str_view());
	}

	JsonMember vendor = find_json_member(text, 0, "vendor")!;
	if (!vendor.found)
	{
		DString full = dstring::new_with_capacity(tmem, declaration.len() + 128);
		full.append("  \"vendor\": {\n    \"c3pm\": {\n      \"c3\": {\n        \"dependencies\": {\n");
		full.append(declaration.str_view());
		full.append("\n        }\n      }\n    }\n  }");
		return insert_json_container_value(allocator, text, 0, '}', full.str_view());
	}
	if (text[vendor.value_start] != '{') return INVALID_METADATA~;
	JsonMember c3pm = find_json_member(text, vendor.value_start, "c3pm")!;
	if (!c3pm.found)
	{
		DString nested = dstring::new_with_capacity(tmem, declaration.len() + 112);
		nested.append("    \"c3pm\": {\n      \"c3\": {\n        \"dependencies\": {\n");
		nested.append(declaration.str_view());
		nested.append("\n        }\n      }\n    }");
		return insert_json_container_value(allocator, text, vendor.value_start, '}', nested.str_view());
	}
	if (text[c3pm.value_start] != '{') return INVALID_METADATA~;
	JsonMember c3 = find_json_member(text, c3pm.value_start, "c3")!;
	if (!c3.found)
	{
		DString nested = dstring::new_with_capacity(tmem, declaration.len() + 96);
		nested.append("      \"c3\": {\n        \"dependencies\": {\n");
		nested.append(declaration.str_view());
		nested.append("\n        }\n      }");
		return insert_json_container_value(allocator, text, c3pm.value_start, '}', nested.str_view());
	}
	if (text[c3.value_start] != '{') return INVALID_METADATA~;
	DString nested = dstring::new_with_capacity(tmem, declaration.len() + 64);
	nested.append("        \"dependencies\": {\n");
	nested.append(declaration.str_view());
	nested.append("\n        }");
	return insert_json_container_value(allocator, text, c3.value_start, '}', nested.str_view());
}

fn String? remove_source_declaration(Allocator allocator, String text, String name)
{
	JsonMember dependencies = find_member_path(text, { "vendor", "c3pm", "c3", "dependencies" })!;
	if (!dependencies.found) return NOT_FOUND~;
	JsonMember member = find_json_member(text, dependencies.value_start, name)!;
	if (!member.found) return NOT_FOUND~;
	JsonSpan span = { .start = member.start, .end = member.value_end, .found = true };
	span = expand_removal(text, span, dependencies.value_start);
	return replace_json_range(allocator, text, span.start, span.end, "");
}

fn String? replace_source_declaration(Allocator allocator, String text,
	String previous, String replacement, PackageSource source)
{
	JsonMember dependencies = find_member_path(text, { "vendor", "c3pm", "c3", "dependencies" })!;
	if (!dependencies.found || text[dependencies.value_start] != '{') return NOT_FOUND~;
	JsonMember existing = find_json_member(text, dependencies.value_start, previous)!;
	if (!existing.found) return NOT_FOUND~;
	if (previous != replacement &&
		find_json_member(text, dependencies.value_start, replacement)!.found) return SOURCE_CONFLICT~;
	DString declaration = dstring::new_with_capacity(tmem, 256);
	declaration.appendf("\"%s\": {\n", replacement);
	append_source_metadata(&declaration, source, "          ");
	declaration.append("\n        }");
	return replace_json_range(allocator, text, existing.start, existing.value_end,
		declaration.str_view());
}

fn String? set_registry_dependency(Allocator allocator, String text,
	String previous, RegisteredPackageSource selected)
{
	JsonMember registry = find_member_path(text, { "vendor", "c3pm", "registry" })!;
	DString declaration = dstring::new_with_capacity(tmem, 160);
	declaration.appendf("      \"%s\": { \"registry\": \"%s\", \"package\": \"%s\", \"version\": \"%s\" }",
		selected.provides, selected.registry, selected.id, selected.version);
	if (registry.found)
	{
		if (text[registry.value_start] != '{') return INVALID_METADATA~;
		String key = previous.len ? previous : selected.provides;
		JsonMember existing = find_json_member(text, registry.value_start, key)!;
		if (key != selected.provides &&
			find_json_member(text, registry.value_start, selected.provides)!.found)
		{
			return SOURCE_CONFLICT~;
		}
		if (existing.found)
		{
			return replace_json_range(allocator, text, existing.start, existing.value_end,
				declaration.str_view().trim());
		}
		return insert_json_container_value(allocator, text, registry.value_start, '}',
			declaration.str_view());
	}
	DString property = dstring::new_with_capacity(tmem, declaration.len() + 48);
	property.append("      \"registry\": {\n");
	property.append(declaration.str_view());
	property.append("\n      }");
	return insert_c3pm_property(allocator, text, property.str_view());
}

fn String? remove_registry_dependency(Allocator allocator, String text, String name)
{
	JsonMember registry = find_member_path(text, { "vendor", "c3pm", "registry" })!;
	if (!registry.found) return text.copy(allocator);
	if (text[registry.value_start] != '{') return INVALID_METADATA~;
	JsonMember existing = find_json_member(text, registry.value_start, name)!;
	if (!existing.found) return text.copy(allocator);
	JsonSpan span = { .start = existing.start, .end = existing.value_end, .found = true };
	span = expand_removal(text, span, registry.value_start);
	return replace_json_range(allocator, text, span.start, span.end, "");
}

fn void append_source_metadata(DString* out, PackageSource source, String indent)
{
	out.appendf("%s\"source\": \"%s\"", indent, source_kind_name(source.kind));
	switch (source.kind)
	{
		case GITHUB:
			String[] parts = source.location.tsplit("/");
			out.appendf(",\n%s\"owner\": \"%s\",\n%s\"repository\": \"%s\"",
				indent, parts[0], indent, parts[1]);
		case GIT_HTTPS:
		case GIT_SSH:
		case ARCHIVE_HTTPS: out.appendf(",\n%s\"url\": \"%s\"", indent, source.location);
		case FOLDER: out.appendf(",\n%s\"path\": \"%s\"", indent, source.location);
	}
	if (source.rev.len) out.appendf(",\n%s\"rev\": \"%s\"", indent, source.rev);
	if (source.subdir.len) out.appendf(",\n%s\"subdir\": \"%s\"", indent, source.subdir);
	if (source.sha256.len) out.appendf(",\n%s\"sha256\": \"%s\"", indent, source.sha256);
	if (source.raw_archive)
	{
		out.appendf(",\n%s\"hashMode\": \"file\"", indent);
		out.appendf(",\n%s\"archiveType\": \"%s\"", indent, source.archive_type);
	}
}

fn String? add_link_declaration(Allocator allocator, String text, LinkSpec link)
{
	JsonMember links = find_member_path(text, { "vendor", "c3pm", "links" })!;
	DString declaration = dstring::new_with_capacity(tmem, 512);
	declaration.appendf("        \"%s\": {\n", link.name);
	bool previous;
	if (link.has_source)
	{
		append_source_metadata(&declaration, link.source, "          ");
		previous = true;
	}
	if (previous) declaration.append(",\n");
	declaration.appendf("          \"c3cTarget\": \"%s\"", link.c3c_target);
	if (link.nix_package.len) declaration.appendf(",\n          \"nixPackage\": \"%s\"", link.nix_package);
	declaration.appendf(",\n          \"mode\": \"%s\"", link.passthrough ? "passthrough" : "runtime");
	if (link.for_target.len) declaration.appendf(",\n          \"forTarget\": \"%s\"", link.for_target);
	declaration.append("\n        }");
	if (links.found)
	{
		if (text[links.value_start] != '{') return INVALID_METADATA~;
		JsonMember existing = find_json_member(text, links.value_start, link.name)!;
		if (existing.found) return SOURCE_CONFLICT~;
		return insert_json_container_value(allocator, text, links.value_start, '}', declaration.str_view());
	}
	DString property = dstring::new_with_capacity(tmem, declaration.len() + 40);
	property.append("      \"links\": {\n");
	property.append(declaration.str_view());
	property.append("\n      }");
	return insert_c3pm_property(allocator, text, property.str_view());
}

fn String? remove_link_declaration(Allocator allocator, String text, String name)
{
	JsonMember links = find_member_path(text, { "vendor", "c3pm", "links" })!;
	if (!links.found) return NOT_FOUND~;
	JsonMember existing = find_json_member(text, links.value_start, name)!;
	if (!existing.found) return NOT_FOUND~;
	JsonSpan span = { .start = existing.start, .end = existing.value_end, .found = true };
	span = expand_removal(text, span, links.value_start);
	return replace_json_range(allocator, text, span.start, span.end, "");
}
