module c3pm;

import std::collections::list;
import std::io;
import std::io::path;

fn int main(String[] args)
{
	if (args.len < 2 || args[1] == "--help" || args[1] == "-h")
	{
		print_help();
		return 0;
	}
	if (args[1] == "--version" || args[1] == "-V")
	{
		io::printfn("c3pm %s", C3PM_VERSION);
		return 0;
	}
	int? result = run_command(args);
	if (catch err = result)
	{
		if (args.len > 1 && args[1] == "bundle") return 1;
		io::printfn("c3pm: %s", err);
		return 1;
	}
	return result;
}

fn int? run_command(String[] args)
{
	@pool()
	{
		args = normalize_command_aliases(tmem, args);
		if (args[1] == "toolchain" && args.len >= 3 && args[2] == "nix")
		{
			return run_toolchain_nix_command(args);
		}
		PortableNixRunner? selected = select_nix_runner(tmem);
		if (catch selected) return 1;
		PortableNixRunner portable = selected;
		NixRunner runner = (NixRunner)&portable;
		Path root = find_project_root(tmem, path::tcwd()!)!;
		switch (args[1])
		{
			case "list": return run_list_command(args, root);
			case "dep": return run_dep_command(args, root, runner);
			case "link": return run_link_command(args, root, runner);
			case "toolchain": return run_toolchain_project_command(args, root, runner);
			case "install":
				if (args.len != 2) return INVALID_METADATA~;
				String tree = install_project(tmem, root, runner)!;
				io::printfn("Synchronized C3 dependencies (%s)", tree);
				return 0;
			case "shell":
				(void)install_project(tmem, root, runner)!;
				String[] command;
				if (args.len > 2)
				{
					if (args[2] != "--") return INVALID_METADATA~;
					if (args.len > 3) command = args[3..];
				}
				String flake_ref = string::format(tmem, "path:%s/.c3pm/nix", (String)root);
				return runner.develop(flake_ref, command)!;
			case "bundle":
				return run_bundle_command(args, root, runner);
			default:
				io::printfn("c3pm: unknown command '%s'", args[1]);
				return 2;
		}
	};
}

fn String[] normalize_command_aliases(Allocator allocator, String[] args)
{
	if (args.len < 2 || (args[1] != "add" && args[1] != "remove")) return args;
	List{String} normalized;
	normalized.init(allocator, args.len + 1);
	normalized.push(args[0]);
	normalized.push("dep");
	normalized.push(args[1]);
	if (args.len > 2) normalized.push_all(args[2..]);
	return normalized.to_array(allocator);
}

fn void print_help()
{
	io::printn(
		"Usage: c3pm <command> [options]\n"
		"\n"
		"Commands:\n"
		"  add SOURCE [options]           Alias for dep add\n"
		"  remove NAME [--for-target TARGET]  Alias for dep remove\n"
		"  list [--for-target TARGET]     List dependencies and links\n"
		"  dep add SOURCE [options]\n"
		"  dep remove NAME [--for-target TARGET]\n"
		"  dep list [--for-target TARGET]\n"
		"  link add NAME [options]\n"
		"  link remove NAME [--for-target TARGET]\n"
		"  link list [--for-target TARGET]\n"
		"  toolchain show\n"
		"  toolchain c3c <set VERSION|reset>\n"
		"  toolchain nixpkgs <set REF|update|reset>\n"
		"  toolchain nix <status|use VALUE|reset>\n"
		"  install\n"
		"  shell [-- COMMAND...]\n"
		"  bundle [TARGET] [--output PATH]\n"
	);
}
