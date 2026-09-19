module c3pm;

import std::core::test;
import std::io::file;
import std::io::path;

struct FakeNixRunner (NixRunner)
{
	String[] paths;
	String[] manifests;
	int locks;
}

fn void nix_runner_supports_portable_and_direct_nix_test() @test
{
	PortableNixRunner portable = portable_nix_runner("/tmp/nix-portable");
	String[] wrapped = portable.command(tmem, { "build", ".#example" });
	test::eq(10, wrapped.len);
	test::eq("nix", wrapped[1]);
	test::eq("--option", wrapped[2]);
	test::eq(NIX_PORTABLE_CACHE, wrapped[4]);

	PortableNixRunner direct_runner = portable_nix_runner(
		"/tmp/.nix-portable/bin/nix", true, false);
	String[] direct = direct_runner.command(tmem, { "build", ".#example" });
	test::eq(3, direct.len);
	test::eq("build", direct[1]);
}

fn void nix_backend_config_round_trip_test() @test
{
	NixBackendConfig original = {
		.mode = "portable",
		.executable = `/tmp/a path/with"quote/nix-portable`,
	};
	String encoded = encode_nix_backend_config(tmem, original);
	NixBackendConfig parsed = parse_nix_backend_config(tmem, encoded)!!;
	test::eq("portable", parsed.mode);
	test::eq(original.executable, parsed.executable);
	test::@error(parse_nix_backend_config(tmem,
		`{"nix":{"mode":"unknown","path":"/tmp/nix"}}`), INVALID_NIX_CONFIG);
}

fn void executable_lookup_accepts_path_and_name_test() @test
{
	String shell = find_executable(tmem, "/bin/sh")!!;
	test::@check(shell.is_absolute_path()!!);
	test::@check(executable_file(shell));
	test::@error(find_executable(tmem, "c3pm-command-that-does-not-exist"), NOT_FOUND);
}

fn void? FakeNixRunner.lock(&self, String flake_dir) @dynamic
{
	self.locks++;
	file::save(string::format(tmem, "%s/flake.lock", flake_dir), "{}")!;
	return;
}

fn void? FakeNixRunner.update_input(&self, String flake_dir, String input_name) @dynamic
{
	return self.lock(flake_dir);
}

fn String? FakeNixRunner.eval_json(&self, Allocator allocator, String flake_dir,
	String expression) @dynamic => `"/nix/store/c3pm-test-shell.drv"`.copy(allocator);

fn String? FakeNixRunner.build(&self, Allocator allocator, String flake_ref) @dynamic
	=> "/nix/store/c3pm-test-libs".copy(allocator);

fn void? FakeNixRunner.bundle(&self, String installable,
	String output_link, String executable_name) @dynamic
{
	path::mkdir(string::format(tmem, "%s/bin", output_link), true)!;
	file::save(string::format(tmem, "%s/bin/%s", output_link, executable_name), "bundle")!;
	return;
}

fn int? FakeNixRunner.develop(&self, String flake_ref, String[] command) @dynamic
	=> 0;

fn void? FakeNixRunner.validate_package_attr(&self, String flake_dir,
	String system, String attr) @dynamic { return; }

fn String? FakeNixRunner.read_manifest(&self, Allocator allocator, String flake_dir,
	String input_name, String library_path) @dynamic
{
	foreach (i, path_value : self.paths)
	{
		if (path_value == library_path) return self.manifests[i].copy(allocator);
	}
	return NOT_FOUND~;
}

fn String? FakeNixRunner.read_source_json(&self, Allocator allocator, String flake_dir,
	String input_name, String relative_path) @dynamic
{
	foreach (i, path_value : self.paths)
	{
		if (path_value == relative_path) return self.manifests[i].copy(allocator);
	}
	return NOT_FOUND~;
}

fn void github_source_parser_test() @test
{
	test::@check(valid_github_identifier("someone"));
	test::@check(valid_github_identifier("c3-libs"));
	test::@check(valid_git_ref("main"));
	validate_source_path("logging/logging.c3l")!!;
	PackageSource direct = { .kind = GITHUB, .location = "someone/c3-libs", .rev = "main", .subdir = "logging/logging.c3l" };
	direct.validate()!!;
	PackageSource source = parse_source(tmem, "github:someone/c3-libs", "main",
		"logging/logging.c3l", "")!!;
	test::eq("someone/c3-libs", source.location);
	test::eq("logging/logging.c3l", source.subdir);
	test::eq("main", source.rev);
}

fn void github_source_rejects_unsafe_paths_test() @test
{
	test::@error(parse_source(tmem, "github:someone/repo", "main", "../secret.c3l", ""), INVALID_SOURCE_PATH);
	test::@error(parse_source(tmem, "github:someone/repo", "main", "/foo.c3l", ""), INVALID_SOURCE_PATH);
	test::@error(parse_source(tmem, "github:someone/repo", "bad ref", "foo.c3l", ""), INVALID_SOURCE);
}

fn void source_identity_ignores_library_path_test() @test
{
	PackageSource one = parse_source(tmem, "github:u/repo", "v1", "foo.c3l", "")!!;
	PackageSource two = parse_source(tmem, "github:u/repo", "v1", "bar.c3l", "")!!;
	test::@check(source_identity_equal(one, two));
	test::eq(source_input_name(tmem, one), source_input_name(tmem, two));
}

fn void nix_attribute_validation_test() @test
{
	test::@check(valid_nix_attribute("openssl"));
	test::@check(valid_nix_attribute("llvmPackages.clang"));
	test::@check(valid_nix_attribute("xorg.libX11"));
	test::@check(!valid_nix_attribute("pkgs.openssl + evil"));
	test::@check(!valid_nix_attribute(".openssl"));
}

fn void jsonc_metadata_and_target_selection_test() @test
{
	String input =
	`{
  // Comments are valid in C3 project metadata.
  "provides": "logging",
  "dependencies": ["base"],
  "targets": {
    "linux-x64": { "dependencies": ["xxhash", "base"] },
    "linux-aarch64": { "dependencies": ["arm-only"] }
  },
  "vendor": { "c3pm": {
    "c3": { "dependencies": {
      "base": { "source": "github", "owner": "a", "repository": "base", "rev": "v1" },
      "xxhash": { "source": "github", "owner": "a", "repository": "xx", "rev": "main", "subdir": "xxhash.c3l" }
    } },
    "nix": {
      "nativeBuildInputs": ["pkg-config"],
      "buildInputs": ["openssl"]
    }
  } }
}`;
	Metadata metadata = parse_manifest(tmem, input, "linux-x64")!!;
	test::eq("logging", metadata.provides);
	test::eq(2, metadata.dependencies.len);
	test::eq("base", metadata.dependencies[0]);
	test::eq("xxhash", metadata.dependencies[1]);
	test::eq("pkg-config", metadata.nix.native_build_inputs[0]);
	test::eq("openssl", metadata.nix.build_inputs[0]);
	validate_metadata_sources(&metadata)!!;
}

fn void metadata_requires_each_dependency_source_test() @test
{
	Metadata metadata = parse_manifest(tmem,
		`{"provides":"logging","dependencies":["missing"]}`,
		"linux-x64")!!;
	test::@error(validate_metadata_sources(&metadata), MISSING_SOURCE);
}

fn void cycle_reports_complete_path_test() @test
{
	PackageSource source = { .kind = GITHUB, .location = "u/r", .rev = "v1" };
	GraphNode[] nodes = {
		{ .name = "foo", .source = source, .dependencies = { "bar" } },
		{ .name = "bar", .source = source, .dependencies = { "baz" } },
		{ .name = "baz", .source = source, .dependencies = { "foo" } },
	};
	Graph graph = { .nodes = nodes, .roots = { "foo" } };
	String[] cycle = find_cycle(tmem, &graph);
	test::eq(4, cycle.len);
	test::eq("foo", cycle[0]);
	test::eq("foo", cycle[3]);
	test::@error(validate_graph(&graph), DEPENDENCY_CYCLE);
}

fn void diamond_closure_is_unique_test() @test
{
	PackageSource source = { .kind = GITHUB, .location = "u/r", .rev = "v1" };
	GraphNode[] nodes = {
		{ .name = "a", .source = source, .dependencies = { "shared" } },
		{ .name = "b", .source = source, .dependencies = { "shared" } },
		{ .name = "shared", .source = source },
	};
	Graph graph = { .nodes = nodes, .roots = { "a", "b" } };
	GraphNode[] closure = dependency_closure(tmem, &graph)!!;
	test::eq(3, closure.len);
}

fn void nix_generation_is_deterministic_and_deduplicates_sources_test() @test
{
	PackageSource shared = { .kind = GITHUB, .location = "someone/c3-libs", .rev = "main" };
	GraphNode[] nodes = {
		{ .name = "zeta", .source = shared, .dependencies = { "alpha" } },
		{ .name = "alpha", .source = { .kind = GITHUB, .location = "someone/c3-libs", .rev = "main", .subdir = "alpha.c3l" } },
	};
	Graph graph = { .nodes = nodes, .roots = { "zeta" } };
	Metadata project;
	String flake = generate_flake_nix(tmem, &graph, &project);
	String input_name = source_input_name(tmem, shared);
	test::@check(flake.contains(input_name));
	// The source identity occurs once in inputs even though both libraries use it.
	test::eq(flake.index_of(input_name)!!, flake.index_of(" = {\n      url")!! - input_name.len);
	String shell = generate_shell_nix(tmem, &graph, &project);
	test::@check(shell.index_of("\"alpha\" =")!! < shell.index_of("\"zeta\" =")!!);
}

fn void recursive_resolution_uses_nix_runner_test() @test
{
	Metadata project = parse_project(tmem,
	`{
  "dependencies": ["logging"],
  "vendor": { "c3pm": { "c3": { "dependencies": {
    "logging": {
      "source": "github", "owner": "someone", "repository": "c3-libs",
      "rev": "main", "subdir": "logging/logging.c3l"
    }
  } } } }
}`,
		"linux-x64")!!;
	FakeNixRunner fake = {
		.paths = { "logging/logging.c3l", "xxhash.c3l" },
		.manifests = {
			`{
  "provides": "logging", "dependencies": ["xxhash"],
  "vendor": { "c3pm": { "c3": { "dependencies": {
    "xxhash": {
      "source": "github", "owner": "someone", "repository": "xxhash.c3",
      "rev": "v1", "subdir": "xxhash.c3l"
    }
  } } } }
}`,
			`{"provides":"xxhash","dependencies":[]}`,
		},
	};
	String scratch = "/tmp/c3pm-v2-resolver-test";
	if (path::exists(scratch.to_tpath()!!)) (void)path::rmtree(scratch.to_tpath()!!);
	defer if (path::exists(scratch.to_tpath()!!)) (void)path::rmtree(scratch.to_tpath()!!);
	Graph graph = resolve_graph(tmem, &project, "linux-x64", scratch, (NixRunner)&fake)!!;
	test::eq(2, graph.nodes.len);
	test::@check(fake.locks >= 2);
	test::eq("xxhash", graph.find("logging")!!.dependencies[0]);
}

fn void empty_install_commits_complete_generated_state_test() @test
{
	String scratch = "/tmp/c3pm-v2-install-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	file::save(string::format(tmem, "%s/project.json", scratch),
		`{"dependencies":[],"dependency-search-paths":["lib"]}`)!!;
	FakeNixRunner fake;
	String tree = install_project(tmem, root, (NixRunner)&fake)!!;
	test::eq("/nix/store/c3pm-test-libs", tree);
	test::@check(file::is_file(string::format(tmem, "%s/.c3pm/nix/flake.nix", scratch)));
	test::@check(file::is_file(string::format(tmem, "%s/.c3pm/nix/flake.lock", scratch)));
	test::@check(file::is_file(string::format(tmem, "%s/.c3pm/nix/c3pm-lib.nix", scratch)));
	test::@check(!path::exists(string::format(tmem, "%s/.c3pm/nix.next", scratch).to_tpath()!!));
}

fn void jsonc_editor_preserves_comments_during_add_remove_test() @test
{
	String original =
	`{
  // Keep this project comment.
  "dependencies": [
    "existing", // and this dependency comment
  ],
  "dependency-search-paths": [ "vendor" ],
  "unrelated": { "answer": 42 },
}`;
	PackageSource source = {
		.kind = GITHUB, .location = "someone/c3-libs", .rev = "main",
		.subdir = "logging/logging.c3l",
	};
	String edited = add_array_string(tmem, original, "dependencies", "logging")!!;
	edited = add_array_string(tmem, edited, "dependency-search-paths", "lib")!!;
	edited = add_source_declaration(tmem, edited, "logging", source)!!;
	test::@check(edited.contains("// Keep this project comment."));
	test::@check(edited.contains("// and this dependency comment"));
	test::@check(edited.contains("\"unrelated\": { \"answer\": 42 }"));
	test::@check(edited.contains(`"source": "github"`));
	test::@check(edited.contains(`"owner": "someone"`));
	test::@check(edited.contains(`"repository": "c3-libs"`));
	test::@check(!edited.contains(`"location"`));
	Metadata project = parse_project(tmem, edited, "linux-x64")!!;
	test::eq(2, project.dependencies.len);
	test::eq("logging", project.dependencies[1]);
	test::eq("someone/c3-libs", project.find_source("logging")!!.source.location);

	String removed = remove_array_string(tmem, edited, "dependencies", "logging")!!;
	removed = remove_source_declaration(tmem, removed, "logging")!!;
	test::@check(removed.contains("// Keep this project comment."));
	Metadata after = parse_project(tmem, removed, "linux-x64")!!;
	test::eq(1, after.dependencies.len);
	test::@error(after.find_source("logging"));
}

fn void add_and_remove_are_transactional_and_preserve_jsonc_test() @test
{
	String scratch = "/tmp/c3pm-v2-package-command-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	String project_path = string::format(tmem, "%s/project.json", scratch);
	file::save(project_path,
	`{
  // This must survive package operations.
  "dependencies": [],
  "dependency-search-paths": [ "vendor" ],
  "unrelated": true,
}`)!!;
	FakeNixRunner fake = {
		.paths = { "logging/logging.c3l" },
		.manifests = { `{"provides":"logging","dependencies":[]}` },
	};
	PackageSource source = parse_source(tmem, "github:someone/c3-libs", "main",
		"logging/logging.c3l", "")!!;
	String name = add_dependency(tmem, root, source, "", "", (NixRunner)&fake)!!;
	test::eq("logging", name);
	String added = (String)file::load(tmem, project_path)!!;
	test::@check(added.contains("// This must survive package operations."));
	test::@check(added.contains("\"unrelated\": true"));
	Metadata with_dependency = parse_project(tmem, added, "linux-x64")!!;
	test::eq("logging", with_dependency.dependencies[0]);
	test::eq("someone/c3-libs", with_dependency.find_source("logging")!!.source.location);

	remove_dependency(tmem, root, "logging", "", (NixRunner)&fake)!!;
	String removed = (String)file::load(tmem, project_path)!!;
	test::@check(removed.contains("// This must survive package operations."));
	Metadata without_dependency = parse_project(tmem, removed, "linux-x64")!!;
	test::eq(0, without_dependency.dependencies.len);
}

fn void nix_imports_are_parsed_validated_and_generated_test() @test
{
	Metadata manifest = parse_manifest(tmem,
	`{
  "provides": "custom",
  "vendor": { "c3pm": { "nix": {
    "imports": ["./package.nix"],
    "buildInputs": ["zlib"]
  } } }
}`,
		"linux-x64")!!;
	test::eq(1, manifest.nix.imports.len);
	test::eq("./package.nix", manifest.nix.imports[0]);
	GraphNode node = {
		.name = "custom",
		.source = { .kind = GITHUB, .location = "owner/repo", .rev = "main", .subdir = "libs/custom.c3l" },
		.nix = manifest.nix,
	};
	String generated = generate_dependency_nix(tmem, &node);
	test::@check(generated.contains("pkgs.zlib"));
	test::@check(generated.contains(
		`pkgs.callPackage (sources."custom" + "/libs/custom.c3l/package.nix") {}`));

	test::@error(parse_manifest(tmem,
		`{"provides":"bad","vendor":{"c3pm":{"nix":{"imports":["../escape.nix"]}}}}`,
		"linux-x64"), INVALID_SOURCE_PATH);
}

fn void project_nix_import_is_copied_into_generated_flake_test() @test
{
	String scratch = "/tmp/c3pm-v2-project-import-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	file::save(string::format(tmem, "%s/local-package.nix", scratch),
		`{ hello }: hello`)!!;
	file::save(string::format(tmem, "%s/project.json", scratch),
		`{
  "dependencies": [],
  "vendor": { "c3pm": { "nix": { "imports": ["./local-package.nix"] } } }
}`)!!;
	FakeNixRunner fake;
	(void)install_project(tmem, root, (NixRunner)&fake)!!;
	String copied = string::format(tmem,
		"%s/.c3pm/nix/imports/project/local-package.nix", scratch);
	test::@check(file::is_file(copied));
	String project_nix = (String)file::load(tmem,
		string::format(tmem, "%s/.c3pm/nix/project.nix", scratch))!!;
	test::@check(project_nix.contains(
		`pkgs.callPackage (./imports/project + "/local-package.nix") {}`));
}

fn void bundle_targets_and_flake_outputs_are_generated_test() @test
{
	Metadata project = parse_project(tmem,
	`{
  "version": "1.2.3",
  "targets": {
    "server": { "type": "executable" },
    "tool": { "type": "executable" },
    "library": { "type": "static-lib" }
  }
}`,
		"linux-x64")!!;
	test::eq(3, project.targets.len);
	test::eq("1.2.3", project.version);
	test::eq("server", select_bundle_target(tmem, &project, "server")!!);
	test::@error(select_bundle_target(tmem, &project, "library"), NON_EXECUTABLE_TARGET);
	test::@error(select_bundle_target(tmem, &project, "missing"), UNKNOWN_TARGET);
	test::@error(select_bundle_target(tmem, &project, ""), AMBIGUOUS_TARGET);
	Metadata single = parse_project(tmem,
		`{ "targets": { "server": { "type": "executable" } } }`, "linux-x64")!!;
	test::eq("server", select_bundle_target(tmem, &single, "")!!);
	Metadata none = parse_project(tmem,
		`{ "targets": { "library": { "type": "static-lib" } } }`, "linux-x64")!!;
	test::@error(select_bundle_target(tmem, &none, ""), NO_EXECUTABLE_TARGET);

	Graph graph;
	String flake = generate_flake_nix(tmem, &graph, &project);
	String shell = generate_shell_nix(tmem, &graph, &project);
	test::@check(!flake.contains(`nix-portable`));
	test::@check(!flake.contains(`c3c-source`));
	test::@check(!flake.contains(`c3c-binary`));
	test::@check(flake.contains(`self.packages.${system}."server"`));
	test::@check(!flake.contains(`self.packages.${system}."library"`));
	test::@check(shell.contains(`"server" = c3pm.c3ProjectBuilder`));
	test::@check(shell.contains(`target = "server"`));
	test::@check(!shell.contains(`"library" = c3pm.c3ProjectBuilder`));
	test::@check(C3PM_LIB_NIX.contains(
		`cp -R --no-preserve=mode,ownership "$src"/. source/`));
	test::@check(C3PM_LIB_NIX.contains(`export HOME="$TMPDIR/c3pm-home"`));
	test::@check(C3PM_LIB_NIX.contains(
		`PS1="\[\e[1;35m\](c3pm)\[\e[0m\] $PS1"`));
	String project_nix = generate_project_nix(tmem, &project);
	test::@check(project_nix.contains(`version = "1.2.3"`));
}

fn void bundle_materializes_regular_atomic_output_test() @test
{
	String scratch = "/tmp/c3pm-v2-bundle-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	file::save(string::format(tmem, "%s/project.json", scratch),
	`{
  "version": "1.0.0",
  "dependencies": [],
  "targets": { "server": { "type": "executable" } }
}`)!!;
	FakeNixRunner fake;
	String output = bundle_project(tmem, root, "", "", (NixRunner)&fake)!!;
	test::eq(string::format(tmem, "%s/dist/server", scratch), output);
	test::@check(file::is_file(output));
	test::eq("bundle", (String)file::load(tmem, output)!!);
	test::@check(!file::is_file(string::format(tmem, "%s/dist/.server.tmp", scratch)));
	test::@check(!path::exists(string::format(tmem, "%s/.c3pm/bundle.next", scratch).to_tpath()!!));
}

fn void generalized_source_syntax_test() @test
{
	PackageSource github = parse_source(tmem, "github:owner/repo", "v1", "lib/foo.c3l", "")!!;
	test::eq(SourceKind.GITHUB, github.kind);
	test::eq("owner/repo", github.location);
	test::eq("lib/foo.c3l", github.subdir);
	test::eq("github:owner/repo/v1", source_url(tmem, github));

	PackageSource https = parse_source(tmem, "git+https://example.com/a/repo.git",
		"main", "", "")!!;
	test::eq(SourceKind.GIT_HTTPS, https.kind);
	test::@check(source_url(tmem, https).starts_with("git+https://"));
	PackageSource ssh = parse_source(tmem, "git+ssh://git@example.com/a/repo.git",
		"deadbeef", "", "")!!;
	test::eq(SourceKind.GIT_SSH, ssh.kind);
	PackageSource archive = parse_source(tmem, "archive+https://example.com/a.tar.gz",
		"", "", "sha256-test")!!;
	test::eq(SourceKind.ARCHIVE_HTTPS, archive.kind);
	test::eq("tarball+https://example.com/a.tar.gz", source_url(tmem, archive));
	PackageSource folder = parse_source(tmem, "path:../local", "", "", "")!!;
	test::eq(SourceKind.FOLDER, folder.kind);
	test::@error(parse_source(tmem, "archive+https://example.com/a.tar.gz", "", "", ""),
		INVALID_SOURCE);
	Metadata flat = parse_project(tmem,
		`{"dependencies":["foo"],"vendor":{"c3pm":{"c3":{"dependencies":{"foo":{"source":"github","owner":"owner","repository":"repo","rev":"v1"}}}}}}`,
		"linux-x64")!!;
	test::eq("owner/repo", flat.find_source("foo")!!.source.location);
}

fn void superseded_metadata_shapes_are_rejected_test() @test
{
	test::@error(parse_project(tmem,
		`{"dependencies":["foo"],"vendor":{"c3pm":{"c3":{"dependencies":{"foo":{"fetchGithub":{"owner":"owner","repo":"repo","rev":"v1"}}}}}}}`,
		"linux-x64"), INVALID_METADATA);
	test::@error(parse_project(tmem,
		`{"dependencies":["foo"],"vendor":{"c3pm":{"c3":{"dependencies":{"foo":{"source":{"type":"github","location":"owner/repo","rev":"v1"}}}}}}}`,
		"linux-x64"), INVALID_METADATA);
	test::@error(parse_manifest(tmem,
		`{"provides":"foo","vendor":{"c3pm":{"nix":{"imports":"./package.nix"}}}}`,
		"linux-x64"), INVALID_METADATA);
}

fn void toolchain_and_link_metadata_generation_test() @test
{
	String json =
	`{
  "dependencies": [],
  "targets": { "server": { "type": "executable" } }
}`;
	json = set_toolchain_value(tmem, json, "c3c", "0.8.3")!!;
	json = set_toolchain_value(tmem, json, "nixpkgs",
		"github:NixOS/nixpkgs/nixos-24.11")!!;
	LinkSpec native = {
		.name = "custom",
		.c3c_target = "none",
		.nix_package = "path:./nix/custom.nix",
	};
	json = add_array_string_at(tmem, json, "linked-libraries", "custom", "server")!!;
	json = add_link_declaration(tmem, json, native)!!;
	Metadata project = parse_project(tmem, json, "linux-x64")!!;
	test::eq("0.8.3", project.toolchain.c3c_version);
	test::eq("github:NixOS/nixpkgs/nixos-24.11", project.toolchain.nixpkgs);
	test::eq(1, project.links.len);
	test::eq("path:./nix/custom.nix", project.links[0].nix_package);
	Graph graph;
	String flake = generate_flake_nix(tmem, &graph, &project);
	String shell = generate_shell_nix(tmem, &graph, &project);
	String project_nix = generate_project_nix(tmem, &project);
	test::@check(flake.contains(`nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11"`));
	test::@check(flake.contains(`c3c-source = {`));
	test::@check(flake.contains(`url = "github:c3lang/c3c/v0.8.3"`));
	test::@check(flake.contains(`c3c-binary = {`));
	test::@check(flake.contains(
		`url = "https://github.com/c3lang/c3c/releases/download/v0.8.3/c3-linux-static.tar.gz"`));
	test::@check(flake.contains(`flake = false`));
	test::@check(shell.contains(`inputs.c3c-source`));
	test::@check(shell.contains(`inputs.c3c-binary`));
	test::@check(shell.contains(`inherit project graph c3cSource c3cBinary`));
	test::@check(C3PM_LIB_NIX.contains(`pkgs.c3c.overrideAttrs`));
	test::@check(C3PM_LIB_NIX.contains(`src = source`));
	test::@check(C3PM_LIB_NIX.contains(`pkgs.runCommand "c3c-${version}-binary"`));
	test::@check(project_nix.contains(`c3cVersion = "0.8.3"`));
	test::@check(project_nix.contains(
		`import (./imports/links/custom/nix/custom.nix) { inherit pkgs; }`));
	json = remove_array_string_at(tmem, json, "linked-libraries", "custom", "server")!!;
	json = remove_link_declaration(tmem, json, "custom")!!;
	project = parse_project(tmem, json, "linux-x64")!!;
	test::eq(0, project.links.len);
}

fn void linked_c3_project_generation_test() @test
{
	PackageSource source = parse_source(tmem, "git+ssh://git@example.com/acme/protocol.git",
		"v1", "project", "")!!;
	LinkSpec link = {
		.name = "protocol",
		.source = source,
		.has_source = true,
		.c3c_target = "protocol-static",
		.nix_package = "path:./package.nix",
		.passthrough = true,
		.for_target = "server",
	};
	LinkSpec[] links = { link };
	Metadata project = { .links = links, .toolchain = { .c3c_version = "0.8.3",
		.nixpkgs = "github:NixOS/nixpkgs/nixpkgs-unstable" } };
	Graph graph;
	String flake = generate_flake_nix(tmem, &graph, &project);
	String shell = generate_shell_nix(tmem, &graph, &project);
	String project_nix = generate_project_nix(tmem, &project);
	test::@check(flake.contains("git+ssh://git@example.com/acme/protocol.git?ref=v1"));
	test::@check(shell.contains(`target = "protocol-static"`));
	test::@check(shell.contains(`c3cVersion = "0.8.3"`));
	test::@check(shell.contains(`inherit c3cSource`));
	test::@check(project_nix.contains(`linkedProjects."protocol"`));
	test::@check(project_nix.contains(
		`import (sources."protocol" + "/project/package.nix") { inherit pkgs; }`));
}
