module c3pm;

import std::collections::list;

fn void append_nix_attr(DString* out, String base, String attr)
{
	out.appendf("%s.%s", base, attr);
}

fn void append_nix_string(DString* out, String value)
{
	out.append("\"");
	foreach (i, char c : value)
	{
		switch (c)
		{
			case '\\': out.append("\\\\");
			case '"': out.append("\\\"");
			case '\n': out.append("\\n");
			case '\r': out.append("\\r");
			case '\t': out.append("\\t");
			case '$':
				if (i + 1 < value.len && value[i + 1] == '{') { out.append("\\$"); }
				else { out.append(c); }
			default: out.append(c);
		}
	}
	out.append("\"");
}

fn void append_attr_list(DString* out, String key, String[] attrs)
{
	out.appendf("  %s = [\n", key);
	foreach (attr : attrs) out.appendf("    pkgs.%s\n", attr);
	out.append("  ];\n\n");
}

fn void append_dependency_build_inputs(DString* out, GraphNode* node)
{
	out.append("  buildInputs = [\n");
	foreach (attr : node.nix.build_inputs) out.appendf("    pkgs.%s\n", attr);
	foreach (import_path : node.nix.imports)
	{
		String relative = node.source.path.len
			? string::format(tmem, "%s/%s", node.source.path, nix_import_relative_path(import_path))
			: nix_import_relative_path(import_path);
		out.append("    (pkgs.callPackage (sources.");
		append_nix_string(out, node.name);
		out.append(" + ");
		append_nix_string(out, string::format(tmem, "/%s", relative));
		out.append(") {})\n");
	}
	out.append("  ];\n\n");
}

fn void append_project_build_inputs(DString* out, NixInputs* inputs)
{
	out.append("  buildInputs = [\n");
	foreach (attr : inputs.build_inputs) out.appendf("    pkgs.%s\n", attr);
	foreach (import_path : inputs.imports)
	{
		out.append("    (pkgs.callPackage (./imports/project + ");
		append_nix_string(out, string::format(tmem, "/%s", nix_import_relative_path(import_path)));
		out.append(") {})\n");
	}
	out.append("  ];\n\n");
}

fn void append_dependency_list(DString* out, String[] dependencies)
{
	out.append("  dependencies = [\n");
	foreach (dependency : dependencies)
	{
		out.append("    deps.");
		append_nix_string(out, dependency);
		out.append("\n");
	}
	out.append("  ];\n\n");
}

fn String generate_dependency_nix(Allocator allocator, GraphNode* node)
{
	DString out = dstring::new_with_capacity(allocator, 512);
	out.append("{ pkgs, sources, deps }:\n\n{\n  name = ");
	append_nix_string(&out, node.name);
	out.append(";\n\n  c3lPath = sources.");
	append_nix_string(&out, node.name);
	if (node.source.path.len)
	{
		out.append(" + ");
		append_nix_string(&out, string::format(tmem, "/%s", node.source.path));
	}
	out.append(";\n\n");
	append_dependency_list(&out, node.dependencies);
	append_attr_list(&out, "nativeBuildInputs", node.nix.native_build_inputs);
	append_dependency_build_inputs(&out, node);
	append_attr_list(&out, "propagatedNativeBuildInputs", node.nix.propagated_native_build_inputs);
	append_attr_list(&out, "propagatedBuildInputs", node.nix.propagated_build_inputs);
	out.append("}\n");
	return out.str_view();
}

fn String generate_project_nix(Allocator allocator, Metadata* project)
{
	DString out = dstring::new_with_capacity(allocator, 512);
	out.append("{ pkgs, deps }:\n\n{\n  name = \"project\";\n  version = ");
	append_nix_string(&out, project.version);
	out.append(";\n\n");
	append_dependency_list(&out, project.dependencies);
	append_attr_list(&out, "nativeBuildInputs", project.nix.native_build_inputs);
	append_project_build_inputs(&out, &project.nix);
	append_attr_list(&out, "propagatedNativeBuildInputs", project.nix.propagated_native_build_inputs);
	append_attr_list(&out, "propagatedBuildInputs", project.nix.propagated_build_inputs);
	out.append("}\n");
	return out.str_view();
}

fn sz[] sorted_node_indices(Allocator allocator, Graph* graph)
{
	List{sz} indices;
	indices.init(allocator, graph.nodes.len);
	for (sz i = 0; i < graph.nodes.len; i++) indices.push(i);
	sz[] result = indices.to_array(allocator);
	for (sz i = 1; i < result.len; i++)
	{
		sz value = result[i];
		sz j = i;
		while (j > 0 && graph.nodes[result[j - 1]].name.compare_to(graph.nodes[value].name) > 0)
		{
			result[j] = result[j - 1];
			j--;
		}
		result[j] = value;
	}
	return result;
}

fn bool source_seen_before(Graph* graph, sz[] sorted, sz position)
{
	FetchGithub source = graph.nodes[sorted[position]].source;
	for (sz i = 0; i < position; i++)
	{
		if (source_identity_equal(source, graph.nodes[sorted[i]].source)) return true;
	}
	return false;
}

fn String generate_flake_nix(Allocator allocator, Graph* graph, Metadata* project)
{
	DString out = dstring::new_with_capacity(allocator, 2048);
	sz[] sorted = sorted_node_indices(tmem, graph);
	out.append(
		"{\n  inputs = {\n"
		"    nixpkgs.url = \"github:NixOS/nixpkgs/nixpkgs-unstable\";\n"
		"    nix-portable.url = \"github:DavHau/nix-portable\";\n"
		"    nix-portable.inputs.defaultChannel.follows = \"nixpkgs\";\n\n");
	foreach (position, index : sorted)
	{
		if (source_seen_before(graph, sorted, position)) continue;
		FetchGithub source = graph.nodes[index].source;
		out.append("    ");
		out.append(source_input_name(tmem, source));
		out.append(" = {\n      url = ");
		append_nix_string(&out, string::format(tmem, "github:%s/%s/%s", source.owner, source.repo, source.rev));
		out.append(";\n      flake = false;\n    };\n\n");
	}
	out.append(
		"  };\n\n"
		"  outputs = inputs@{ self, nixpkgs, ... }:\n"
		"    let\n"
		"      systems = [ \"x86_64-linux\" \"aarch64-linux\" ];\n"
		"      forAllSystems = nixpkgs.lib.genAttrs systems;\n"
		"      evaluated = forAllSystems (system:\n"
		"        let pkgs = import nixpkgs { inherit system; };\n"
		"        in import ./shell.nix { inherit pkgs inputs; });\n"
		"    in {\n"
		"      devShells = forAllSystems (system: { default = evaluated.${system}.shell; });\n"
		"      packages = forAllSystems (system:\n"
		"        evaluated.${system}.packages // { c3pmLibs = evaluated.${system}.c3pmLibs; });\n"
		"      bundlers = forAllSystems (system:\n"
		"        let pkgs = import nixpkgs { inherit system; };\n"
		"        in {\n"
		"          c3pm = drv:\n"
		"            let\n"
		"              mainProgram = drv.meta.mainProgram or drv.pname;\n"
		"              payload = pkgs.runCommand \"${drv.name}-c3pm-bundle-payload\" {\n"
		"                meta.mainProgram = mainProgram;\n"
		"              } ''\n"
		"                mkdir -p $out/bin\n"
		"                ln -s ${nixpkgs.lib.getExe drv} $out/bin/${mainProgram}\n"
		"                # nix-portable currently expects this beside a hardcoded bundled executable.\n"
		"                ln -s ${pkgs.nix}/bin/nix $out/bin/nix\n"
		"                # Keep its first-run git dependency inside the embedded store closure.\n"
		"                mkdir -p $out/share/c3pm-runtime\n"
		"                ln -s ${pkgs.gitMinimal} $out/share/c3pm-runtime/git\n"
		"              '';\n"
		"            in inputs.nix-portable.bundlers.${system}.zstd-fast payload;\n"
		"        });\n"
	);
	out.append("      apps = forAllSystems (system: {\n");
	foreach (&target : project.targets)
	{
		if (target.type != "executable") continue;
		out.append("        ");
		append_nix_string(&out, target.name);
		out.append(" = { type = \"app\"; program = \"${self.packages.${system}.");
		append_nix_string(&out, target.name);
		out.append("}/bin/");
		out.append(target.name);
		out.append("\"; };\n");
	}
	out.append("      });\n    };\n}\n");
	return out.str_view();
}

fn String generate_shell_nix(Allocator allocator, Graph* graph, Metadata* project)
{
	DString out = dstring::new_with_capacity(allocator, 4096);
	sz[] sorted = sorted_node_indices(tmem, graph);
	out.append("{ pkgs, inputs }:\n\nlet\n  c3pm = import ./c3pm-lib.nix { inherit pkgs; };\n\n  sources = {\n");
	foreach (index : sorted)
	{
		GraphNode* node = &graph.nodes[index];
		out.append("    ");
		append_nix_string(&out, node.name);
		out.append(" = inputs.");
		out.append(source_input_name(tmem, node.source));
		out.append(";\n");
	}
	out.append("  };\n\n  deps = pkgs.lib.fix (self: {\n");
	foreach (index : sorted)
	{
		GraphNode* node = &graph.nodes[index];
		out.append("    ");
		append_nix_string(&out, node.name);
		out.append(" = import ./deps/");
		out.append(node.name);
		out.append(".nix { inherit pkgs sources; deps = self; };\n");
	}
	out.append(
		"  });\n\n"
		"  project = import ./project.nix { inherit pkgs deps; };\n"
		"  graph = c3pm.closure project.dependencies;\n"
		"  c3pmLibs = c3pm.mkC3LibTree graph;\n"
		"  projectSource = ./project-source;\n"
		"in {\n"
		"  inherit c3pm project graph c3pmLibs projectSource;\n"
		"  shell = c3pm.mkShell { inherit project graph; };\n"
	);
	out.append("  packages = {\n");
	foreach (&target : project.targets)
	{
		if (target.type != "executable") continue;
		out.append("    ");
		append_nix_string(&out, target.name);
		out.append(" = c3pm.c3ProjectBuilder {\n      src = projectSource;\n      inherit project graph;\n      target = ");
		append_nix_string(&out, target.name);
		out.append(";\n    };\n");
	}
	out.append("  };\n}\n");
	return out.str_view();
}

const String C3PM_LIB_NIX =
`{ pkgs }:

let
  lib = pkgs.lib;

  closure = roots:
    let
      visit = seen: pending:
        if pending == [] then seen else
        let
          current = builtins.head pending;
          remaining = builtins.tail pending;
          alreadySeen = builtins.any (x: x.name == current.name) seen;
        in
          if alreadySeen then visit seen remaining
          else visit (seen ++ [ current ]) (current.dependencies ++ remaining);
    in visit [] roots;

  collectInputs = project: graph: {
    nativeBuildInputs = lib.unique (
      project.nativeBuildInputs ++ project.propagatedNativeBuildInputs ++
      lib.concatMap (dep: dep.nativeBuildInputs ++ dep.propagatedNativeBuildInputs) graph
    );
    buildInputs = lib.unique (
      project.buildInputs ++ project.propagatedBuildInputs ++
      lib.concatMap (dep: dep.buildInputs ++ dep.propagatedBuildInputs) graph
    );
  };

  mkC3LibTree = graph:
    pkgs.linkFarm "c3pm-libs" (map (dep: {
      name = "${dep.name}.c3l";
      path = dep.c3lPath;
    }) graph);

  mkShell = { project, graph }:
    let inputs = collectInputs project graph;
    in pkgs.mkShell {
      nativeBuildInputs = [ pkgs.c3c ] ++ inputs.nativeBuildInputs;
      buildInputs = inputs.buildInputs;
    };

  c3ProjectBuilder = { src, project, graph, target }:
    let
      inputs = collectInputs project graph;
      libs = mkC3LibTree graph;
    in pkgs.stdenv.mkDerivation {
      pname = target;
      version = project.version;
      meta.mainProgram = target;
      inherit src;
      nativeBuildInputs = [ pkgs.c3c ] ++ inputs.nativeBuildInputs;
      buildInputs = inputs.buildInputs;
      unpackPhase = ''
        runHook preUnpack
        mkdir source
        cp -R --no-preserve=mode,ownership "$src"/. source/
        chmod -R u+w source
        cd source
        runHook postUnpack
      '';
      buildPhase = ''
        runHook preBuild
        ln -s ${libs} lib
        c3c build ${lib.escapeShellArg target} --output-dir .c3pm-build-out
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp .c3pm-build-out/${lib.escapeShellArg target} $out/bin/${lib.escapeShellArg target}
        runHook postInstall
      '';
    };
in {
  inherit closure collectInputs mkC3LibTree mkShell c3ProjectBuilder;
}
`;
