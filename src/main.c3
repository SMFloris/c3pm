module c3pm;

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
		io::printn("c3pm 0.1.0");
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
		if (args[1] == "nix") return run_nix_command(args);
		PortableNixRunner? selected = select_nix_runner(tmem);
		if (catch selected) return 1;
		PortableNixRunner portable = selected;
		NixRunner runner = (NixRunner)&portable;
		Path root = find_project_root(tmem, path::tcwd()!)!;
		switch (args[1])
		{
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
			case "add":
				if (args.len != 3) return INVALID_GITHUB_URI~;
				String added = add_dependency(tmem, root, args[2], runner)!;
				io::printfn("Added C3 dependency \"%s\"", added);
				return 0;
			case "remove":
				if (args.len != 3) return INVALID_METADATA~;
				remove_dependency(tmem, root, args[2], runner)!;
				io::printfn("Removed C3 dependency \"%s\"", args[2]);
				return 0;
			case "bundle":
				return run_bundle_command(args, root, runner);
			default:
				io::printfn("c3pm: unknown command '%s'", args[1]);
				return 2;
		}
	};
}

fn void print_help()
{
	io::printn(
		"Usage: c3pm <command> [options]\n"
		"\n"
		"Commands:\n"
		"  add github://OWNER@REPO[/PATH]#REF\n"
		"  remove NAME\n"
		"  install\n"
		"  shell [-- COMMAND...]\n"
		"  bundle [TARGET] [--output PATH]\n"
		"  nix status\n"
		"  nix use <system | portable | PATH>\n"
		"  nix reset\n"
	);
}
