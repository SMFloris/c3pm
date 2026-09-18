module c3pm;

import libc;
import std::collections::object;
import std::encoding::json;
import std::io;
import std::io::file;
import std::io::path;
import std::os::env;
import std::os::process;

const String NIX_PORTABLE_VERSION = "v012";

struct NixBackendConfig
{
	String mode;
	String executable;
}

fn String? xdg_config_path(Allocator allocator)
{
	String base = env::tget_var("XDG_CONFIG_HOME") ?? "";
	if (!base.len)
	{
		String home = env::tget_var("HOME")!;
		base = string::format(tmem, "%s/.config", home);
	}
	return string::format(allocator, "%s/c3pm/config.json", base);
}

fn String? xdg_portable_path(Allocator allocator)
{
	String base = env::tget_var("XDG_DATA_HOME") ?? "";
	if (!base.len)
	{
		String home = env::tget_var("HOME")!;
		base = string::format(tmem, "%s/.local/share", home);
	}
	return string::format(allocator, "%s/c3pm/nix-portable", base);
}

fn void append_json_string(DString* out, String value)
{
	out.append("\"");
	foreach (char c : value)
	{
		switch (c)
		{
			case '\\': out.append("\\\\");
			case '"': out.append("\\\"");
			case '\n': out.append("\\n");
			case '\r': out.append("\\r");
			case '\t': out.append("\\t");
			default: out.append(c);
		}
	}
	out.append("\"");
}

fn String encode_nix_backend_config(Allocator allocator, NixBackendConfig config)
{
	DString out = dstring::new_with_capacity(allocator, config.executable.len + 64);
	out.append("{\n  \"nix\": {\n    \"mode\": ");
	append_json_string(&out, config.mode);
	out.append(",\n    \"path\": ");
	append_json_string(&out, config.executable);
	out.append("\n  }\n}\n");
	return out.str_view();
}

fn NixBackendConfig? parse_nix_backend_config(Allocator allocator, String text)
{
	Object* root = json::parse(allocator, text)!;
	if (!root.is_map() || !root.has_key("nix")) return INVALID_NIX_CONFIG~;
	Object* nix = root.get("nix")!;
	if (!nix.is_map() || !nix.has_key("mode") || !nix.has_key("path"))
	{
		return INVALID_NIX_CONFIG~;
	}
	String mode = nix.get_string("mode")!;
	String executable = nix.get_string("path")!;
	if ((mode != "native" && mode != "portable") || !executable.len)
	{
		return INVALID_NIX_CONFIG~;
	}
	return { .mode = mode.copy(allocator), .executable = executable.copy(allocator) };
}

fn bool executable_file(String candidate)
{
	return file::is_file(candidate) && access(candidate.zstr_tcopy(), 1) == 0;
}

fn String? find_executable(Allocator allocator, String name)
{
	if (name.contains("/"))
	{
		Path absolute = name.to_absolute_path(allocator)!;
		String candidate = (String)absolute;
		if (!executable_file(candidate)) return NOT_FOUND~;
		return candidate;
	}
	String search = env::tget_var("PATH") ?? "";
	foreach (directory : search.tsplit(":"))
	{
		String candidate = directory.len
			? string::format(tmem, "%s/%s", directory, name)
			: name;
		if (!executable_file(candidate)) continue;
		return ((String)candidate.to_absolute_path(tmem)!).copy(allocator);
	}
	return NOT_FOUND~;
}

fn void? save_nix_backend_config(NixBackendConfig config)
{
	String destination = xdg_config_path(tmem)!;
	String parent = destination.path_tdirname()!;
	path::mkdir(parent, true)!;
	String temporary = string::format(tmem, "%s.tmp", destination);
	defer (void)file::delete(temporary);
	file::save(temporary, encode_nix_backend_config(tmem, config))!;
	if (chmod(temporary.zstr_tcopy(), 0o600) != 0) return TRANSACTION_FAILED~;
	if (libc::rename(temporary.zstr_tcopy(), destination.zstr_tcopy()) != 0)
	{
		return TRANSACTION_FAILED~;
	}
	return;
}

fn NixBackendConfig? load_nix_backend_config(Allocator allocator)
{
	String config_path = xdg_config_path(tmem)!;
	if (!file::is_file(config_path)) return NOT_FOUND~;
	String contents = (String)file::load(tmem, config_path)!;
	NixBackendConfig config = parse_nix_backend_config(allocator, contents)!;
	if (!executable_file(config.executable))
	{
		io::printfn("Configured Nix executable is unavailable:\n  %s\n\nSelect it again with `c3pm toolchain nix use`.",
			config.executable);
		return INVALID_NIX_CONFIG~;
	}
	return config;
}

fn String nix_portable_asset()
{
	$if env::LINUX && env::X86_64:
	return "nix-portable-x86_64";
	$else
	$if env::LINUX && env::AARCH64:
	return "nix-portable-aarch64";
	$else
	return "";
	$endif
	$endif
}

fn void? download_nix_portable(String destination)
{
	String asset = nix_portable_asset();
	if (!asset.len) return UNSUPPORTED_HOST~;
	String url = string::format(tmem,
		"https://github.com/DavHau/nix-portable/releases/download/%s/%s",
		NIX_PORTABLE_VERSION, asset);
	String parent = destination.path_tdirname()!;
	path::mkdir(parent, true)!;
	String temporary = string::format(tmem, "%s.download", destination);
	(void)file::delete(temporary);
	defer (void)file::delete(temporary);

	String[] command;
	if (try curl = find_executable(tmem, "curl"))
	{
		command = { curl, "--fail", "--location", "--retry", "3", "--output", temporary, url };
	}
	else if (try wget = find_executable(tmem, "wget"))
	{
		command = { wget, "--output-document", temporary, url };
	}
	else
	{
		io::printn("Downloading nix-portable requires curl or wget.");
		return NIX_DOWNLOAD_FAILED~;
	}
	io::printfn("Downloading nix-portable %s...", NIX_PORTABLE_VERSION);
	int status = process::run(command, process::SpawnOptions.INHERIT_ENV,
		out: process::INHERIT, err: process::INHERIT)!;
	if (status != 0 || !file::is_file(temporary)) return NIX_DOWNLOAD_FAILED~;
	if (chmod(temporary.zstr_tcopy(), 0o755) != 0) return TRANSACTION_FAILED~;
	if (libc::rename(temporary.zstr_tcopy(), destination.zstr_tcopy()) != 0)
	{
		return TRANSACTION_FAILED~;
	}
	return;
}

fn void print_missing_nix_backend()
{
	io::printn(
		"No Nix backend is available.\n\n"
		"Install Nix and ensure `nix` is on PATH, or use the managed portable backend:\n\n"
		"  c3pm toolchain nix use portable\n\n"
		"To inspect backend selection:\n\n"
		"  c3pm toolchain nix status"
	);
}

fn String nix_backend_version(String backend, String executable)
{
	PortableNixRunner runner = backend == "portable"
		? portable_nix_runner(executable, false, false)
		: portable_nix_runner(executable, true, false);
	String[] command = runner.command(tmem, { "--version" });
	String? detected = capture_nix_output(tmem, command, 4096);
	if (catch detected) return "unavailable";
	return detected.trim();
}

fn void print_nix_status(String backend, String executable, String source)
{
	io::printfn("Nix backend: %s\nExecutable:  %s\nVersion:     %s\nSource:      %s",
		backend, executable, nix_backend_version(backend, executable), source);
}

fn int? run_nix_status_command()
{
	if (try executable = env::tget_var("C3PM_NIX") && executable.len)
	{
		print_nix_status("system", executable, "C3PM_NIX");
		return 0;
	}
	if (try executable = env::tget_var("C3PM_NIX_PORTABLE") && executable.len)
	{
		print_nix_status("portable", executable, "C3PM_NIX_PORTABLE");
		return 0;
	}

	String config_path = xdg_config_path(tmem)!;
	if (file::is_file(config_path))
	{
		NixBackendConfig? loaded = load_nix_backend_config(tmem);
		if (catch loaded)
		{
			io::printfn("Invalid c3pm Nix configuration:\n  %s\n\nSelect a backend again.",
				config_path);
			return 1;
		}
		NixBackendConfig config = loaded;
		print_nix_status(config.mode == "portable" ? "portable" : "system",
			config.executable, config_path);
		return 0;
	}
	if (try executable = find_executable(tmem, "nix"))
	{
		print_nix_status("system", executable, "PATH (automatic)");
		return 0;
	}
	print_missing_nix_backend();
	return 1;
}

fn int? use_system_nix()
{
	if (try executable = find_executable(tmem, "nix"))
	{
		save_nix_backend_config({ .mode = "native", .executable = executable })!;
		io::printfn("Using system Nix at %s", executable);
		return 0;
	}
	io::printn(
		"Nix was not found on PATH.\n\n"
		"Install Nix and try again, or use:\n\n"
		"  c3pm toolchain nix use portable"
	);
	return 1;
}

fn int? use_portable_nix()
{
	String executable = xdg_portable_path(tmem)!;
	if (!executable_file(executable)) download_nix_portable(executable)!;
	save_nix_backend_config({ .mode = "portable", .executable = executable })!;
	io::printfn("Using managed nix-portable at %s", executable);
	return 0;
}

fn int? use_nix_path(String requested)
{
	String? found = find_executable(tmem, requested);
	if (catch found)
	{
		io::printfn("Nix executable was not found or is not executable:\n  %s", requested);
		return 1;
	}
	String executable = found;
	save_nix_backend_config({ .mode = "native", .executable = executable })!;
	io::printfn("Using Nix at %s", executable);
	return 0;
}

fn int? reset_nix_backend()
{
	String config_path = xdg_config_path(tmem)!;
	if (file::is_file(config_path)) (void)file::delete(config_path);
	io::printn("Cleared the saved Nix backend. Nix will be discovered automatically.");
	return 0;
}

fn void print_nix_help()
{
	io::printn(
		"Usage:\n"
		"  c3pm toolchain nix status\n"
		"  c3pm toolchain nix use system\n"
		"  c3pm toolchain nix use portable\n"
		"  c3pm toolchain nix use PATH\n"
		"  c3pm toolchain nix reset"
	);
}

fn int? run_toolchain_nix_command(String[] args)
{
	if (args.len == 4 && args[3] == "status") return run_nix_status_command();
	if (args.len == 4 && args[3] == "reset") return reset_nix_backend();
	if (args.len == 5 && args[3] == "use")
	{
		if (args[4] == "system") return use_system_nix();
		if (args[4] == "portable") return use_portable_nix();
		return use_nix_path(args[4]);
	}
	print_nix_help();
	return 2;
}

fn PortableNixRunner? select_nix_runner(Allocator allocator)
{
	if (try configured = env::tget_var("C3PM_NIX"))
	{
		return portable_nix_runner(configured.copy(allocator), true, false);
	}
	if (try configured = env::tget_var("C3PM_NIX_PORTABLE"))
	{
		return portable_nix_runner(configured.copy(allocator));
	}

	String config_path = xdg_config_path(tmem)!;
	if (file::is_file(config_path))
	{
		NixBackendConfig? loaded = load_nix_backend_config(tmem);
		if (catch loaded)
		{
			io::printfn("Invalid c3pm Nix configuration:\n  %s\n\nSelect it again with `c3pm toolchain nix use`.",
				config_path);
			return INVALID_NIX_CONFIG~;
		}
		NixBackendConfig config = loaded;
		return config.mode == "portable"
			? portable_nix_runner(config.executable.copy(allocator))
			: portable_nix_runner(config.executable.copy(allocator), true, false);
	}
	if (try native_nix = find_executable(tmem, "nix"))
	{
		return portable_nix_runner(native_nix.copy(allocator), true, false);
	}

	print_missing_nix_backend();
	return NIX_NOT_CONFIGURED~;
}
