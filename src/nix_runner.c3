module c3pm;

import std::collections::list;
import std::os::process;

interface NixRunner
{
	fn void? lock(String flake_dir);
	fn void? update_input(String flake_dir, String input_name);
	fn String? eval_json(Allocator allocator, String flake_dir, String expression);
	fn String? build(Allocator allocator, String flake_ref);
	fn void? bundle(String installable, String output_link, String executable_name);
	fn int? develop(String flake_ref, String[] command);
	fn void? validate_package_attr(String flake_dir, String system, String attr);
	fn String? read_source_json(Allocator allocator, String flake_dir, String input_name, String relative_path);
	fn String? read_manifest(Allocator allocator, String flake_dir, String input_name, String library_path);
}

struct PortableNixRunner (NixRunner)
{
	String portable_executable;
	bool direct_nix;
	bool use_portable_cache;
}

const String NIX_PORTABLE_CACHE = "https://nix-portable.cachix.org";
const String NIX_PORTABLE_CACHE_KEY =
	"nix-portable.cachix.org-1:zb9EtPV/tW34g4BD6Vc4xtSPdgpz3EF6y3X/WaMnifg=";

fn PortableNixRunner portable_nix_runner(String executable = "nix-portable",
	bool direct_nix = false, bool use_portable_cache = true)
{
	return {
		.portable_executable = executable,
		.direct_nix = direct_nix,
		.use_portable_cache = use_portable_cache,
	};
}

fn String[] PortableNixRunner.command(&self, Allocator allocator, String[] args)
{
	List{String} command;
	command.init(allocator, args.len + (self.direct_nix ? 1 : 2) +
		(self.use_portable_cache ? 6 : 0));
	command.push(self.portable_executable);
	if (!self.direct_nix) command.push("nix");
	if (self.use_portable_cache)
	{
		command.push_all({
			"--option", "extra-substituters", NIX_PORTABLE_CACHE,
			"--option", "extra-trusted-public-keys", NIX_PORTABLE_CACHE_KEY,
		});
	}
	command.push_all(args);
	return command.to_array(allocator);
}

fn String? capture_nix_output(Allocator allocator, String[] command, sz capacity)
{
	process::Process child = process::spawn(command,
		process::SpawnOptions.INHERIT_ENV,
		out: process::CAPTURE, err: process::INHERIT)!;
	defer (void)child.destroy();
	int status = child.join()!;
	char[] buffer = alloc::alloc_array(tmem, char, capacity);
	sz length = child.read_stdout(buffer.ptr, buffer.len)!;
	if (status != 0) return NIX_FAILED~;
	return ((String)buffer[:length]).copy(allocator);
}

fn void? PortableNixRunner.lock(&self, String flake_dir) @dynamic
{
	@pool()
	{
		String flake_ref = string::format(tmem, "path:%s", flake_dir);
		String[] command = self.command(tmem, { "flake", "lock", flake_ref });
		int status = process::run(command, process::SpawnOptions.INHERIT_ENV,
			out: process::INHERIT, err: process::INHERIT)!;
		if (status != 0) return NIX_FAILED~;
	};
	return;
}

fn void? PortableNixRunner.update_input(&self, String flake_dir, String input_name) @dynamic
{
	@pool()
	{
		String flake_ref = string::format(tmem, "path:%s", flake_dir);
		String[] command = self.command(tmem, { "flake", "update", input_name, "--flake", flake_ref });
		int status = process::run(command, process::SpawnOptions.INHERIT_ENV,
			out: process::INHERIT, err: process::INHERIT)!;
		if (status != 0) return NIX_FAILED~;
	};
	return;
}

fn String? PortableNixRunner.eval_json(&self, Allocator allocator, String flake_dir,
	String expression) @dynamic
{
	@pool()
	{
		String[] command = self.command(tmem,
			{ "eval", "--json", "--impure", "--expr", expression });
		String output = capture_nix_output(tmem, command, 16 * 1024 * 1024)!;
		if (!output.len) return NIX_FAILED~;
		return output.copy(allocator);
	};
}

fn String? PortableNixRunner.build(&self, Allocator allocator, String flake_ref) @dynamic
{
	@pool()
	{
		String[] command = self.command(tmem,
			{ "build", "--quiet", "--no-link", "--no-update-lock-file", "--print-out-paths", flake_ref });
		String output = capture_nix_output(tmem, command, 1024 * 1024)!;
		if (!output.len) return NIX_FAILED~;
		return output.trim().copy(allocator);
	};
}

fn void? PortableNixRunner.bundle(&self, String installable,
	String output_link, String executable_name) @dynamic
{
	@pool()
	{
		String nix_link = string::format(tmem, "%s.nix-link", output_link);
		String[] command = self.command(tmem, {
			"bundle", "--quiet", "--no-update-lock-file",
			"--out-link", nix_link,
			installable,
		});
		int status = process::run(command, process::SpawnOptions.INHERIT_ENV,
			out: process::INHERIT, err: process::INHERIT)!;
		if (status != 0) return BUNDLE_FAILED~;

		// nix-portable's store mount belongs to each invocation. Materialize
		// Nix's executable out-link while a second pinned flake environment
		// has that store mounted, leaving an ordinary file for the caller.
		sz fragment = installable.index_of("#")!;
		String flake_ref = installable[:fragment];
		String bundled_executable = string::format(tmem, "%s/bin/%s", nix_link,
			executable_name);
		if (access(bundled_executable.zstr_tcopy(), 0) != 0)
		{
			bundled_executable = nix_link;
		}
		String[] copy_command = self.command(tmem, {
			"develop", "--quiet", "--no-update-lock-file", flake_ref,
			"-c", "cp", "--dereference", bundled_executable, output_link,
		});
		status = process::run(copy_command, process::SpawnOptions.INHERIT_ENV,
			out: process::INHERIT, err: process::INHERIT)!;
		if (status != 0) return BUNDLE_FAILED~;
	};
	return;
}

fn int? PortableNixRunner.develop(&self, String flake_ref, String[] requested) @dynamic
{
	@pool()
	{
		List{String} args;
		args.tinit();
		args.push("develop");
		args.push(flake_ref);
		if (requested.len)
		{
			args.push("-c");
			args.push_all(requested);
		}
		String[] command = self.command(tmem, args.array_view());
		return process::run(command, process::SpawnOptions.INHERIT_ENV, in: process::INHERIT,
			out: process::INHERIT, err: process::INHERIT)!;
	};
}

fn void? PortableNixRunner.validate_package_attr(&self, String flake_dir,
	String system, String attr) @dynamic
{
	@pool()
	{
		String expression = string::format(tmem,
			`let f = builtins.getFlake "path:%s"; pkgs = import f.inputs.nixpkgs { system = "%s"; }; in pkgs.%s.outPath`,
			flake_dir, system, attr);
		(void)self.eval_json(tmem, flake_dir, expression)!;
	};
	return;
}

fn String? PortableNixRunner.read_manifest(&self, Allocator allocator, String flake_dir,
	String input_name, String library_path) @dynamic
{
	String relative = library_path.len
		? string::format(tmem, "%s/manifest.json", library_path)
		: "manifest.json";
	return self.read_source_json(allocator, flake_dir, input_name, relative);
}

fn String? PortableNixRunner.read_source_json(&self, Allocator allocator, String flake_dir,
	String input_name, String relative_path) @dynamic
{
	@pool()
	{
		validate_source_path(relative_path)!;
		String expression = string::format(tmem,
			`let f = builtins.getFlake "path:%s"; in builtins.fromJSON (builtins.readFile (f.inputs.%s + "/%s"))`,
			flake_dir, input_name, relative_path);
		return self.eval_json(allocator, flake_dir, expression);
	};
}
