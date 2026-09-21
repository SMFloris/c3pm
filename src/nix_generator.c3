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
		String relative = node.source.subdir.len
			? string::format(tmem, "%s/%s", node.source.subdir, nix_import_relative_path(import_path))
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

fn void append_link_package(DString* out, LinkSpec* link)
{
	if (!link.nix_package.len) return;
	if (!link.nix_package.starts_with("path:"))
	{
		out.appendf("    pkgs.%s\n", link.nix_package);
		return;
	}
	String relative = nix_import_relative_path(link.nix_package[5..]);
	out.append("    (import (");
	if (link.has_source)
	{
		out.append("sources."); append_nix_string(out, link.name); out.append(" + ");
		String combined = link.source.subdir.len
			? string::format(tmem, "/%s/%s", link.source.subdir, relative)
			: string::format(tmem, "/%s", relative);
		append_nix_string(out, combined);
	}
	else
	{
		out.append("./imports/links/"); out.append(link.name); out.append("/"); out.append(relative);
	}
	out.append(") { inherit pkgs; })\n");
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
	if (node.source.subdir.len)
	{
		out.append(" + ");
		append_nix_string(&out, string::format(tmem, "/%s", node.source.subdir));
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
	out.append("{ pkgs, deps, sources, linkedProjects }:\n\n{\n  name = \"project\";\n  version = ");
	append_nix_string(&out, project.version);
	out.append(";\n  c3cVersion = ");
	append_nix_string(&out, project.toolchain.c3c_version);
	out.append(";\n\n");
	append_dependency_list(&out, project.dependencies);
	append_attr_list(&out, "nativeBuildInputs", project.nix.native_build_inputs);
	out.append("  buildInputs = [\n");
	foreach (attr : project.nix.build_inputs) out.appendf("    pkgs.%s\n", attr);
	foreach (import_path : project.nix.imports)
	{
		out.append("    (pkgs.callPackage (./imports/project + ");
		append_nix_string(&out, string::format(tmem, "/%s", nix_import_relative_path(import_path)));
		out.append(") {})\n");
	}
	foreach (&link : project.links)
	{
		if (link.passthrough) continue;
		if (link.c3c_target != "none")
		{
			out.append("    linkedProjects."); append_nix_string(&out, link.name); out.append("\n");
		}
		append_link_package(&out, link);
	}
	out.append("  ];\n\n");
	append_attr_list(&out, "propagatedNativeBuildInputs", project.nix.propagated_native_build_inputs);
	out.append("  propagatedBuildInputs = [\n");
	foreach (attr : project.nix.propagated_build_inputs) out.appendf("    pkgs.%s\n", attr);
	foreach (&link : project.links)
	{
		if (!link.passthrough) continue;
		if (link.c3c_target != "none")
		{
			out.append("    linkedProjects."); append_nix_string(&out, link.name); out.append("\n");
		}
		append_link_package(&out, link);
	}
	out.append("  ];\n\n");
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
	PackageSource source = graph.nodes[sorted[position]].source;
	for (sz i = 0; i < position; i++)
	{
		if (source_identity_equal(source, graph.nodes[sorted[i]].source)) return true;
	}
	return false;
}

fn bool graph_has_source(Graph* graph, PackageSource source)
{
	foreach (&node : graph.nodes) if (source_identity_equal(node.source, source)) return true;
	return false;
}

fn bool link_source_seen_before(Metadata* project, sz position)
{
	if (!project.links[position].has_source) return true;
	for (sz i = 0; i < position; i++)
	{
		if (project.links[i].has_source &&
			source_identity_equal(project.links[i].source, project.links[position].source)) return true;
	}
	return false;
}

fn void append_flake_source(DString* out, PackageSource source)
{
	out.append("    "); out.append(source_input_name(tmem, source));
	out.append(" = {\n      url = "); append_nix_string(out, source_url(tmem, source));
	out.append(";\n      flake = false;\n");
	if (source.sha256.len)
	{
		out.append("      narHash = "); append_nix_string(out, source.sha256); out.append(";\n");
	}
	out.append("    };\n\n");
}

fn String generate_flake_nix(Allocator allocator, Graph* graph, Metadata* project)
{
	DString out = dstring::new_with_capacity(allocator, 2048);
	sz[] sorted = sorted_node_indices(tmem, graph);
	out.append(
		"{\n  inputs = {\n"
		"    nixpkgs.url = ");
	append_nix_string(&out, project.toolchain.nixpkgs.len
		? project.toolchain.nixpkgs : "github:NixOS/nixpkgs/nixpkgs-unstable");
	out.append(";\n");
	if (project.toolchain.c3c_version.len)
	{
		out.append("    c3c-source = {\n      url = ");
		append_nix_string(&out, string::format(tmem, "github:c3lang/c3c/v%s",
			project.toolchain.c3c_version));
		out.append(";\n      flake = false;\n    };\n\n");
		out.append("    c3c-binary = {\n      url = ");
		append_nix_string(&out, string::format(tmem,
			"https://github.com/c3lang/c3c/releases/download/v%s/c3-linux-static.tar.gz",
			project.toolchain.c3c_version));
		out.append(";\n      flake = false;\n    };\n\n");
	}
	foreach (position, index : sorted)
	{
		if (source_seen_before(graph, sorted, position)) continue;
		PackageSource source = graph.nodes[index].source;
		append_flake_source(&out, source);
	}
	foreach (i, &link : project.links)
	{
		if (!link.has_source || graph_has_source(graph, link.source) ||
			link_source_seen_before(project, i)) continue;
		append_flake_source(&out, link.source);
	}
	out.append(
		"  };\n\n"
		"  outputs = inputs@{ self, nixpkgs, ... }:\n"
		"    let\n"
		"      systems = [ \"x86_64-linux\" \"aarch64-linux\" \"aarch64-darwin\" \"x86_64-darwin\" ];\n"
		"      forAllSystems = nixpkgs.lib.genAttrs systems;\n"
		"      evaluated = forAllSystems (system:\n"
		"        let pkgs = import nixpkgs { inherit system; };\n"
		"        in import ./shell.nix { inherit pkgs inputs; });\n"
		"    in {\n"
		"      devShells = forAllSystems (system: { default = evaluated.${system}.shell; });\n"
		"      c3pmToolchains = forAllSystems (system: { c3c = evaluated.${system}.c3c; });\n"
		"      packages = forAllSystems (system:\n"
		"        evaluated.${system}.packages // { c3pmLibs = evaluated.${system}.c3pmLibs; });\n"
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
	out.append(
		"{ pkgs, inputs }:\n\n"
		"let\n"
		"  c3pm = import ./c3pm-lib.nix { inherit pkgs; };\n"
		"  c3cSource = if project.c3cVersion == \"\" then null else inputs.c3c-source;\n"
		"  c3cBinary = if project.c3cVersion == \"\" then null else inputs.c3c-binary;\n\n"
		"  sources = {\n");
	foreach (index : sorted)
	{
		GraphNode* node = &graph.nodes[index];
		out.append("    ");
		append_nix_string(&out, node.name);
		out.append(" = inputs.");
		out.append(source_input_name(tmem, node.source));
		out.append(";\n");
	}
	foreach (&link : project.links)
	{
		if (!link.has_source) continue;
		out.append("    "); append_nix_string(&out, link.name); out.append(" = inputs.");
		out.append(source_input_name(tmem, link.source)); out.append(";\n");
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
		"  linkedProjects = {\n");
	foreach (&link : project.links)
	{
		if (link.c3c_target == "none") continue;
		out.append("    "); append_nix_string(&out, link.name);
		out.append(" = c3pm.c3LinkedProjectBuilder { name = "); append_nix_string(&out, link.name);
		out.append("; src = sources."); append_nix_string(&out, link.name);
		if (link.source.subdir.len)
		{
			out.append(" + "); append_nix_string(&out, string::format(tmem, "/%s", link.source.subdir));
		}
		out.append("; target = "); append_nix_string(&out, link.c3c_target);
		out.append("; c3cVersion = "); append_nix_string(&out, project.toolchain.c3c_version);
		out.append("; inherit c3cSource c3cBinary; };\n");
	}
	out.append(
		"  };\n\n"
		"  project = import ./project.nix { inherit pkgs deps sources linkedProjects; };\n"
		"  graph = c3pm.closure project.dependencies;\n"
		"  c3pmLibs = c3pm.mkC3LibTree graph;\n"
		"  projectSource = ./project-source;\n"
		"in {\n"
		"  inherit c3pm project graph c3pmLibs projectSource;\n"
		"  c3c = c3pm.selectC3c project.c3cVersion c3cSource c3cBinary;\n"
		"  shell = c3pm.mkShell { inherit project graph c3cSource c3cBinary; };\n"
	);
	out.append("  packages = {\n");
	foreach (&target : project.targets)
	{
		if (target.type != "executable") continue;
		out.append("    ");
		append_nix_string(&out, target.name);
		out.append(" = c3pm.c3ProjectBuilder {\n      src = projectSource;\n      inherit project graph c3cSource c3cBinary;\n      target = ");
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

  selectC3c = version: source: binary:
    if version == "" then pkgs.c3c else
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
      pkgs.runCommand "c3c-${version}-binary" {} ''
        mkdir -p $out/bin
        ln -s ${binary}/c3c $out/bin/c3c
        ln -s ${binary}/c3fmt $out/bin/c3fmt
      ''
    else
      pkgs.c3c.overrideAttrs (_: {
        inherit version;
        src = source;
      });

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

  mkShell = { project, graph, c3cSource, c3cBinary }:
    let inputs = collectInputs project graph;
    in pkgs.mkShell {
      nativeBuildInputs = [ (selectC3c project.c3cVersion c3cSource c3cBinary) ] ++ inputs.nativeBuildInputs;
      buildInputs = inputs.buildInputs;
      shellHook = ''
        if [[ $- == *i* ]]; then
          PS1="\[\e[1;35m\](c3pm)\[\e[0m\] $PS1"
        fi
      '';
    };

  c3ProjectBuilder = { src, project, graph, target, c3cSource, c3cBinary }:
    let
      inputs = collectInputs project graph;
      libs = mkC3LibTree graph;
    in pkgs.stdenv.mkDerivation {
      pname = target;
      version = project.version;
      meta.mainProgram = target;
      inherit src;
      nativeBuildInputs = [ (selectC3c project.c3cVersion c3cSource c3cBinary) ] ++ inputs.nativeBuildInputs;
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
        export HOME="$TMPDIR/c3pm-home"
        export XDG_CACHE_HOME="$HOME/.cache"
        mkdir -p "$XDG_CACHE_HOME"
        ln -s ${libs} lib
        c3c build ${lib.escapeShellArg target} --output-dir .c3pm-build-out
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/libexec
        cp .c3pm-build-out/${lib.escapeShellArg target} $out/libexec/${lib.escapeShellArg target}
        cat > $out/bin/${lib.escapeShellArg target} <<EOF
#!${pkgs.runtimeShell}
if [ -n "\''${C3PM_BUNDLE_CWD:-}" ]; then
  cd -- "\''${C3PM_BUNDLE_CWD}" || exit 1
fi
exec "$out/libexec/${target}" "\$@"
EOF
        chmod +x $out/bin/${lib.escapeShellArg target}
        runHook postInstall
      '';
      };

  c3LinkedProjectBuilder = { name, src, target, c3cVersion, c3cSource, c3cBinary }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "0.0.0";
      inherit src;
      nativeBuildInputs = [ (selectC3c c3cVersion c3cSource c3cBinary) ];
      buildPhase = ''
        runHook preBuild
        export HOME="$TMPDIR/c3pm-home"
        export XDG_CACHE_HOME="$HOME/.cache"
        mkdir -p "$XDG_CACHE_HOME"
        c3c build ${lib.escapeShellArg target} --output-dir .c3pm-build-out
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib
        find .c3pm-build-out -maxdepth 1 -type f \( -name '*.a' -o -name '*.so' -o -name '*.so.*' -o -name '*.dylib' -o -name '*.lib' -o -name '*.dll' \) -exec cp -P {} $out/lib/ \;
        test -n "$(find $out/lib -maxdepth 1 -type f -print -quit)" || {
          echo "c3pm: linked C3 target produced no static or dynamic library" >&2
          exit 1
        }
        built="$(find $out/lib -maxdepth 1 -type f -print -quit)"
        case "$built" in
          *.a) ln -sf "$(basename "$built")" "$out/lib/lib${name}.a" ;;
          *.so|*.so.*) ln -sf "$(basename "$built")" "$out/lib/lib${name}.so" ;;
          *.dylib) ln -sf "$(basename "$built")" "$out/lib/lib${name}.dylib" ;;
          *.lib) ln -sf "$(basename "$built")" "$out/lib/${name}.lib" ;;
          *.dll) ln -sf "$(basename "$built")" "$out/lib/${name}.dll" ;;
        esac
        runHook postInstall
      '';
    };
in {
  inherit selectC3c closure collectInputs mkC3LibTree mkShell c3ProjectBuilder c3LinkedProjectBuilder;
}
`;
