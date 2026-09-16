module c3pm;

import std::io::file;
import std::io::path;

fn String? host_c3_target()
{
	$if env::LINUX && env::X86_64:
	return "linux-x64";
	$else
	$if env::LINUX && env::AARCH64:
	return "linux-aarch64";
	$else
	return UNSUPPORTED_HOST~;
	$endif
	$endif
}

fn String? host_nix_system()
{
	$if env::LINUX && env::X86_64:
	return "x86_64-linux";
	$else
	$if env::LINUX && env::AARCH64:
	return "aarch64-linux";
	$else
	return UNSUPPORTED_HOST~;
	$endif
	$endif
}

fn Path? find_project_root(Allocator allocator, Path start)
{
	Path current = start.absolute(allocator)!;
	while (true)
	{
		Path candidate = current.tappend("project.json")!;
		if (file::is_file((String)candidate)) return current;
		Path parent = current.parent() ?? PROJECT_NOT_FOUND~!;
		if (parent == current) return PROJECT_NOT_FOUND~;
		current = parent;
	}
}
