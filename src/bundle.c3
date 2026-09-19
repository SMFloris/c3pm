module c3pm;

import libc;
import std::io;
import std::io::file;
import std::io::path;

extern fn CInt chmod(ZString path, uint mode) @cname("chmod") @feat(POSIX);
extern fn CInt access(ZString path, CInt mode) @cname("access") @feat(POSIX);

fn ProjectTarget*? find_project_target(Metadata* project, String name)
{
	foreach (&target : project.targets) if (target.name == name) return target;
	return NOT_FOUND~;
}

fn String? select_bundle_target(Allocator allocator, Metadata* project, String requested)
{
	if (requested.len)
	{
		ProjectTarget*? selected = find_project_target(project, requested);
		if (catch selected)
		{
			io::printfn("Unknown project target \"%s\".", requested);
			return UNKNOWN_TARGET~;
		}
		if (selected.type != "executable")
		{
			io::printfn("Target \"%s\" is not executable and cannot be bundled.", requested);
			return NON_EXECUTABLE_TARGET~;
		}
		return selected.name.copy(allocator);
	}

	ProjectTarget* only;
	sz count;
	foreach (&target : project.targets)
	{
		if (target.type != "executable") continue;
		only = target;
		count++;
	}
	if (!count)
	{
		io::printn("No executable project targets are available.");
		return NO_EXECUTABLE_TARGET~;
	}
	if (count > 1)
	{
		io::printn("Multiple executable targets are available:\n");
		foreach (&target : project.targets)
			if (target.type == "executable") io::printfn("  %s", target.name);
		io::printn("\nSpecify one:\n\n  c3pm bundle <target>");
		return AMBIGUOUS_TARGET~;
	}
	return only.name.copy(allocator);
}

fn void? copy_file_streaming(String source, String destination)
{
	io::File input = file::open(source, "rb")!;
	defer (void)input.close();
	io::File output = file::open(destination, "wb")!;
	defer (void)output.close();
	char[64 * 1024] buffer;
	while (true)
	{
		sz count = input.read(buffer[..])!;
		if (!count) break;
		io::write_all(&output, buffer[:count])!;
	}
	return;
}

fn String? bundle_project(Allocator allocator, Path project_root, String requested,
	String output_override, NixRunner runner)
{
	@pool()
	{
		String root = (String)project_root;
		String project_json = (String)file::load(tmem,
			string::format(tmem, "%s/project.json", root))!;
		Metadata project = parse_project(tmem, project_json, host_c3_target()!)!;
		String target = select_bundle_target(tmem, &project, requested)!;

		if (catch err = install_project(tmem, project_root, runner))
		{
			io::printfn("Failed to prepare C3 target \"%s\".", target);
			return err~;
		}

		String flake_ref = string::format(tmem, "path:%s/.c3pm/nix", root);
		String system = host_nix_system()!;
		String installable = string::format(tmem, "%s#packages.%s.\"%s\"",
			flake_ref, system, target);
		io::printfn("Building %s...", target);
		if (catch err = runner.build(tmem, installable))
		{
			io::printfn("Failed to build C3 target \"%s\".", target);
			return err~;
		}

		String temporary = string::format(tmem, "%s/.c3pm/bundle.next", root);
		Path temporary_path = temporary.to_tpath()!;
		if (path::exists(temporary_path)) path::rmtree(temporary_path)!;
		path::mkdir(temporary, true)!;
		defer if (path::exists(temporary_path)) (void)path::rmtree(temporary_path);
		String result_link = string::format(tmem, "%s/result", temporary);
		io::printn("Bundling runtime closure...");
		if (catch err = runner.bundle(installable, result_link, target))
		{
			io::printfn("The Nix bundler failed for target \"%s\".", target);
			return err~;
		}

		String bundled_in_output = string::format(tmem, "%s/bin/%s", result_link, target);
		// Nix 2.20 makes --out-link point directly at lib.getExe's result,
		// while other versions preserve the bundler derivation directory.
		String bundled = file::is_file(bundled_in_output) ? bundled_in_output : result_link;
		// file::is_file intentionally reports false for symlinks. access(2)
		// follows the direct executable out-link produced by Nix 2.20.
		if (access(bundled.zstr_tcopy(), 0) != 0)
		{
			io::printfn("Bundler output does not contain expected executable:\nbin/%s", target);
			return BUNDLE_OUTPUT_MISSING~;
		}
		String destination = output_override.len
			? output_override
			: string::format(tmem, "%s/dist/%s", root, target);
		Path destination_path = destination.to_tpath()!;
		String basename = destination_path.basename();
		if (!basename.len || basename == "." || basename == "..") return INVALID_SOURCE_PATH~;
		String parent = destination.path_tdirname()!;
		path::mkdir(parent, true)!;
		String staged = string::format(tmem, "%s/.%s.tmp", parent, basename);
		(void)file::delete(staged);
		defer (void)file::delete(staged);
		copy_file_streaming(bundled, staged)!;
		if (chmod(staged.zstr_tcopy(), 0o755) != 0) return TRANSACTION_FAILED~;
		if (libc::rename(staged.zstr_tcopy(), destination.zstr_tcopy()) != 0)
		{
			return TRANSACTION_FAILED~;
		}
		io::printfn("Created %s", destination);
		return destination.copy(allocator);
	};
}

fn int? run_bundle_command(String[] args, Path project_root, NixRunner runner)
{
	String requested;
	String output;
	for (sz i = 2; i < args.len; i++)
	{
		if (args[i] == "--output")
		{
			if (output.len || i + 1 >= args.len || !args[i + 1].len) return INVALID_METADATA~;
			output = args[++i];
		}
		else
		{
			if (args[i].starts_with("-") || requested.len) return INVALID_METADATA~;
			requested = args[i];
		}
	}
	(void)bundle_project(tmem, project_root, requested, output, runner)!;
	return 0;
}
