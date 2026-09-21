module c3pm;

import std::core::test;
import std::io::file;
import std::io::path;

struct FakeNixRunner (NixRunner)
{
	String[] paths;
	String[] manifests;
	int locks;
	bool fail_build;
}

fn void native_host_targets_are_mapped_test() @test
{
	$if env::LINUX && env::X86_64:
	test::eq("linux-x64", host_c3_target()!!);
	test::eq("x86_64-linux", host_nix_system()!!);
	$endif
	$if env::LINUX && env::AARCH64:
	test::eq("linux-aarch64", host_c3_target()!!);
	test::eq("aarch64-linux", host_nix_system()!!);
	$endif
	$if env::DARWIN && env::AARCH64:
	test::eq("macos-aarch64", host_c3_target()!!);
	test::eq("aarch64-darwin", host_nix_system()!!);
	$endif
	$if env::DARWIN && env::X86_64:
	test::eq("macos-x64", host_c3_target()!!);
	test::eq("x86_64-darwin", host_nix_system()!!);
	$endif
}

fn void dependency_command_aliases_are_normalized_test() @test
{
	String[] normalized = normalize_command_aliases(tmem,
		{ "c3pm", "add", "github:someone/c3-libs", "--rev", "main", "--name", "sqlite3" });
	test::eq(8, normalized.len);
	test::eq("c3pm", normalized[0]);
	test::eq("dep", normalized[1]);
	test::eq("add", normalized[2]);
	test::eq("github:someone/c3-libs", normalized[3]);
	test::eq("--rev", normalized[4]);
	test::eq("main", normalized[5]);
	test::eq("--name", normalized[6]);
	test::eq("sqlite3", normalized[7]);

	String[] remove = normalize_command_aliases(tmem,
		{ "c3pm", "remove", "sqlite3", "--for-target", "server" });
	test::eq(6, remove.len);
	test::eq("c3pm", remove[0]);
	test::eq("dep", remove[1]);
	test::eq("remove", remove[2]);
	test::eq("sqlite3", remove[3]);
	test::eq("--for-target", remove[4]);
	test::eq("server", remove[5]);

	String[] unchanged = { "c3pm", "link", "add", "sqlite3" };
	test::eq(unchanged, normalize_command_aliases(tmem, unchanged));

	String[] show = normalize_command_aliases(tmem, { "c3pm", "show", "vendor/raylib" });
	test::eq(4, show.len);
	test::eq("dep", show[1]);
	test::eq("show", show[2]);
	test::eq("vendor/raylib", show[3]);
}

fn void combined_list_target_filter_is_parsed_test() @test
{
	test::eq("", parse_list_target({ "c3pm", "list" }, 2)!!);
	test::eq("server", parse_list_target(
		{ "c3pm", "list", "--for-target", "server" }, 2)!!);
	test::@error(parse_list_target({ "c3pm", "list", "--unknown" }, 2), INVALID_ARGUMENTS);
	test::@error(parse_list_target(
		{ "c3pm", "list", "--for-target" }, 2), INVALID_ARGUMENTS);
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

fn void user_config_preserves_nix_and_registries_test() @test
{
	PackageSource local = parse_source(tmem, "path:/tmp/local registry", "", "catalog", "")!!;
	PackageSource github = parse_source(tmem, "github:acme/community", "main", "", "")!!;
	RegistryConfig[] registries = {
		{ .name = "local", .source = local },
		{ .name = "community", .source = github },
	};
	UserConfig original = {
		.has_nix = true,
		.nix = { .mode = "native", .executable = "/usr/bin/nix" },
		.registries = registries,
	};
	String encoded = encode_user_config(tmem, &original);
	UserConfig parsed = parse_user_config(tmem, encoded)!!;
	test::@check(parsed.has_nix);
	test::eq("/usr/bin/nix", parsed.nix.executable);
	test::eq(2, parsed.registries.len);
	test::eq("main", parsed.find_registry("community")!!.source.rev);
	test::eq("catalog", parsed.find_registry("local")!!.source.subdir);

	remove_registry_config(&parsed, tmem, "community")!!;
	test::@check(parsed.has_nix);
	test::eq(1, parsed.registries.len);
	test::@error(remove_registry_config(&parsed, tmem, "missing"), NOT_FOUND);
}

fn void registry_schema_is_validated_through_reader_test() @test
{
	String[] paths = {
		"registry.json",
		"index.json",
		"packages/vendor/raylib/package.json",
		"packages/vendor/raylib/5.5.json",
	};
	String[] documents = {
		`{"name":"C3 Vendor","version":1,"generated":"2026-09-21T00:00:00Z"}`,
		`{"packages":[{"id":"vendor/raylib","name":"raylib","namespace":"vendor","latest":"5.5","description":"Raylib bindings","tags":["graphics"]}]}`,
		`{"id":"vendor/raylib","name":"raylib","namespace":"vendor","description":"Raylib bindings","homepage":"https://raylib.com","repository":"https://github.com/raysan5/raylib","tags":["graphics"],"versions":["5.5"]}`,
		`{"name":"raylib","namespace":"vendor","version":"5.5","provides":"raylib","download":{"source":"github","owner":"SMFloris","repository":"c3c-vendor","rev":"main","subdir":"libraries/raylib.c3l"},"toolchain":{"c3c":">=0.8.1 <0.9.0"},"published":"2026-09-21T00:00:00Z"}`,
	};
	FakeNixRunner fake = { .paths = paths, .manifests = documents };
	NixRunner runner = (NixRunner)&fake;
	PackageSource source = parse_source(tmem, "github:acme/registry", "main", "", "")!!;
	validate_registry(tmem, source, runner, "/tmp/probe", "registry")!!;

	documents[1] = `{"packages":[{"id":"wrong/id","name":"raylib","namespace":"vendor","latest":"5.5","description":"","tags":[]}]}`;
	test::@error(validate_registry(tmem, source, runner, "/tmp/probe", "registry"),
		INVALID_REGISTRY);
}

fn void registry_search_matches_all_tokens_and_sorts_by_relevance_test() @test
{
	String index = `{"packages":[{"id":"vendor/raygui","name":"raygui","namespace":"vendor","latest":"4","description":"Immediate mode GUI","tags":["graphics"]},{"id":"vendor/raylib","name":"raylib","namespace":"vendor","latest":"6","description":"Graphics library","tags":["graphics","game"]}]}`;
	SearchPackage[] packages = load_search_packages(tmem, "vendor", index)!!;
	test::eq(2, packages.len);
	String[] exact = { "raylib" };
	String[] prefix = { "ray" };
	String[] multi = { "raylib", "graphics" };
	test::eq(900, search_score(&packages[1], exact));
	test::@check(search_score(&packages[0], prefix) > 0);
	test::@check(search_score(&packages[1], multi) > 0);
	test::eq(-1, search_score(&packages[0], multi));
	test::@check(package_has_tag(&packages[1], "GRAPHICS"));

	packages[0].score = search_score(&packages[0], exact);
	packages[1].score = search_score(&packages[1], exact);
	SearchPackage[] sorted = sort_search_results(tmem, packages);
	test::eq("vendor/raylib", sorted[0].id);
}

fn void default_registry_source_is_canonical_test() @test
{
	PackageSource source = default_registry_source(tmem)!!;
	test::eq(SourceKind.GITHUB, source.kind);
	test::eq("SMFloris/c3pm-registry", source.location);
	test::eq("master", source.rev);
	test::eq("default", DEFAULT_REGISTRY_NAME);
}

fn void registry_package_reference_resolves_download_source_test() @test
{
	test::@check(is_registry_package_id("vendor/raylib"));
	test::@check(is_registry_package_query("raylib"));
	test::@check(is_registry_package_query("vendor/raylib"));
	test::@check(!is_registry_package_id("raylib"));
	test::@check(!is_registry_package_id("github:owner/repo"));
	test::@check(!is_registry_package_query("vendor/raylib/6"));
	RegistryConfig registry = { .name = "default" };
	RegisteredPackageSource resolved = parse_registered_release(tmem, registry,
		"vendor/raylib", "6",
		`{"name":"raylib","namespace":"vendor","version":"6","provides":"raylib","download":{"source":"github","owner":"SMFloris","repository":"c3c-vendor","rev":"main","subdir":"libraries/raylib.c3l"}}`)!!;
	test::eq("default", resolved.registry);
	test::eq("raylib", resolved.provides);
	test::eq(SourceKind.GITHUB, resolved.source.kind);
	test::eq("SMFloris/c3c-vendor", resolved.source.location);
	test::eq("libraries/raylib.c3l", resolved.source.subdir);
	test::@error(parse_registered_release(tmem, registry, "vendor/raylib", "5.5",
		`{"name":"raylib","namespace":"vendor","version":"6","provides":"raylib","download":{"source":"github","owner":"a","repository":"b","rev":"main"}}`),
		INVALID_REGISTRY);
}

fn void registry_package_version_spec_selects_published_release_test() @test
{
	RegistryPackageSpec unqualified = parse_registry_package_spec("raylib@5.5")!!;
	test::eq("raylib", unqualified.query);
	test::eq("5.5", unqualified.version);
	RegistryPackageSpec qualified = parse_registry_package_spec("vendor/raylib@6")!!;
	test::eq("vendor/raylib", qualified.query);
	test::eq("6", qualified.version);
	test::eq("", parse_registry_package_spec("raylib")!!.version);
	test::eq("", parse_registry_package_spec("git+ssh://git@example.com/repo")!!.query);
	test::@error(parse_registry_package_spec("raylib@"), INVALID_ARGUMENTS);
	test::@error(parse_registry_package_spec("raylib@@5.5"), INVALID_ARGUMENTS);
	test::@error(parse_registry_package_spec("vendor/raylib@../5.5"), INVALID_ARGUMENTS);
	String[] versions = { "6", "5.5", "5" };
	test::eq("6", select_registry_version("6", versions, "")!!);
	test::eq("5.5", select_registry_version("6", versions, "5.5")!!);
	test::@error(select_registry_version("6", versions, "5.4"), REGISTRY_VERSION_NOT_FOUND);
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
{
	if (self.fail_build) return NIX_FAILED~;
	return "/nix/store/c3pm-test-libs".copy(allocator);
}

fn void? FakeNixRunner.bundle(&self, String installable,
	String output_link, String executable_name) @dynamic
{
	path::mkdir(string::format(tmem, "%s/bin", output_link), true)!;
	file::save(string::format(tmem, "%s/bin/%s", output_link, executable_name),
		string::format(tmem, `%sgo() {
  ( . ../env && exec ../run "$@" )
}
archive-data`, BUNDLE_PROLOGUE))!;
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

fn void registry_dependency_update_replaces_names_sources_and_rolls_back_test() @test
{
	String scratch = "/tmp/c3pm-v2-registry-update-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	String project_path = string::format(tmem, "%s/project.json", scratch);
	file::save(project_path,
	`{
  // Keep this comment when the binding name changes.
  "dependencies": [],
  "targets": { "server": { "type": "executable", "dependencies": [] } },
  "unrelated": true
}`)!!;
	FakeNixRunner fake = {
		.paths = { "libraries/raylib55.c3l", "libraries/raylib6.c3l" },
		.manifests = { `{"provides":"raylib55"}`, `{"provides":"raylib6"}` },
	};
	NixRunner runner = (NixRunner)&fake;
	PackageSource old_source = parse_source(tmem, "github:someone/c3-libs", "main",
		"libraries/raylib55.c3l", "")!!;
	PackageSource new_source = parse_source(tmem, "github:someone/c3-libs", "main",
		"libraries/raylib6.c3l", "")!!;
	RegisteredPackageSource[] releases = {
		{ .registry = "default", .id = "vendor/raylib", .version = "5.5", .provides = "raylib55", .source = old_source },
		{ .registry = "default", .id = "vendor/raylib", .version = "6", .provides = "raylib6", .source = new_source },
	};
	(void)add_dependency(tmem, root, old_source, "raylib55", "", runner, releases[0])!!;
	(void)add_dependency(tmem, root, old_source, "raylib55", "server", runner)!!;
	Metadata marked = parse_project(tmem, (String)file::load(tmem, project_path)!!,
		"linux-x64")!!;
	test::eq("5.5", find_registered_dependency(&marked, "raylib")!!.version);
	test::@error(update_direct_dependency(tmem, root, "raylib55", "v2", "", runner),
		INVALID_ARGUMENTS);
	test::eq("raylib6", update_dependency(tmem, root, "raylib55", releases[1], runner)!!);
	String updated = (String)file::load(tmem, project_path)!!;
	test::@check(updated.contains("// Keep this comment when the binding name changes."));
	test::@check(updated.contains("\"unrelated\": true"));
	test::@check(!updated.contains("raylib55"));
	test::@check(updated.contains("libraries/raylib6.c3l"));
	Metadata changed = parse_project(tmem, updated, "linux-x64")!!;
	test::eq("raylib6", changed.dependencies[0]);
	test::eq("raylib6", changed.find_source("raylib6")!!.name);
	test::eq(1, changed.registry_dependencies.len);
	test::eq("raylib6", find_registered_dependency(&changed, "raylib")!!.name);
	test::eq("6", find_registered_dependency(&changed, "vendor/raylib")!!.version);
	test::@check(json_array_has_string(updated,
		find_json_member(updated, project_target_object(updated, "server")!!,
			"dependencies")!!.value_start, "raylib6"));

	fake.fail_build = true;
	test::@error(update_dependency(tmem, root, "raylib6", releases[0], runner), NIX_FAILED);
	test::eq(updated, (String)file::load(tmem, project_path)!!);
}

fn void direct_dependency_update_requires_explicit_revision_or_hash_test() @test
{
	String scratch = "/tmp/c3pm-v2-direct-update-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	String project_path = string::format(tmem, "%s/project.json", scratch);
	file::save(project_path, `{"dependencies":[]}`)!!;
	FakeNixRunner fake = {
		.paths = { "libraries/sqlite3.c3l" },
		.manifests = { `{"provides":"sqlite3"}` },
	};
	NixRunner runner = (NixRunner)&fake;
	PackageSource source = parse_source(tmem, "github:someone/c3-libs", "v1",
		"libraries/sqlite3.c3l", "")!!;
	(void)add_dependency(tmem, root, source, "sqlite3", "", runner)!!;
	Metadata before = parse_project(tmem, (String)file::load(tmem, project_path)!!,
		"linux-x64")!!;
	test::eq(0, before.registry_dependencies.len);
	test::@error(find_registered_dependency(&before, "sqlite3"), NOT_FOUND);
	test::eq(1, run_dep_command({ "c3pm", "dep", "update", "sqlite3" }, root, runner)!!);
	test::eq(1, run_dep_command({ "c3pm", "dep", "update", "vendor/sqlite3" }, root, runner)!!);
	test::@error(update_direct_dependency(tmem, root, "sqlite3", "", "", runner),
		INVALID_ARGUMENTS);
	test::@error(update_direct_dependency(tmem, root, "sqlite3", "", "sha256-test", runner),
		INVALID_ARGUMENTS);
	test::@error(update_direct_dependency(tmem, root, "sqlite3", "bad ref", "", runner),
		INVALID_SOURCE);
	test::eq("sqlite3", update_direct_dependency(tmem, root, "sqlite3", "v2", "", runner)!!);
	String updated = (String)file::load(tmem, project_path)!!;
	Metadata changed = parse_project(tmem, updated, "linux-x64")!!;
	test::eq("v2", changed.find_source("sqlite3")!!.source.rev);
	test::eq("libraries/sqlite3.c3l", changed.find_source("sqlite3")!!.source.subdir);
	test::eq(0, changed.registry_dependencies.len);
	fake.fail_build = true;
	test::@error(update_direct_dependency(tmem, root, "sqlite3", "v3", "", runner),
		NIX_FAILED);
	test::eq(updated, (String)file::load(tmem, project_path)!!);
}

fn void direct_archive_update_changes_hash_only_test() @test
{
	String scratch = "/tmp/c3pm-v2-direct-archive-update-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	String project_path = string::format(tmem, "%s/project.json", scratch);
	file::save(project_path, `{"dependencies":[]}`)!!;
	FakeNixRunner fake = {
		.paths = { "binding.c3l" },
		.manifests = { `{"provides":"binding"}` },
	};
	NixRunner runner = (NixRunner)&fake;
	PackageSource source = parse_source(tmem,
		"archive+https://example.com/binding.tar.gz", "", "binding.c3l", "sha256-old")!!;
	(void)add_dependency(tmem, root, source, "binding", "", runner)!!;
	test::@error(update_direct_dependency(tmem, root, "binding", "v2", "", runner),
		INVALID_ARGUMENTS);
	test::@error(update_direct_dependency(tmem, root, "binding", "", "bad", runner),
		INVALID_SOURCE);
	test::eq("binding", update_direct_dependency(tmem, root, "binding", "",
		"sha256-new", runner)!!);
	Metadata changed = parse_project(tmem, (String)file::load(tmem, project_path)!!,
		"linux-x64")!!;
	PackageSource updated = changed.find_source("binding")!!.source;
	test::eq("https://example.com/binding.tar.gz", updated.location);
	test::eq("binding.c3l", updated.subdir);
	test::eq("sha256-new", updated.sha256);
}

fn void registry_add_records_reference_and_remove_clears_it_test() @test
{
	String scratch = "/tmp/c3pm-v2-registry-reference-test";
	Path root = scratch.to_tpath()!!;
	if (path::exists(root)) (void)path::rmtree(root);
	defer if (path::exists(root)) (void)path::rmtree(root);
	path::mkdir(root, true)!!;
	String project_path = string::format(tmem, "%s/project.json", scratch);
	file::save(project_path, `{"dependencies":[]}`)!!;
	FakeNixRunner fake = {
		.paths = { "libraries/raylib55.c3l" },
		.manifests = { `{"provides":"raylib55"}` },
	};
	PackageSource source = parse_source(tmem, "github:someone/c3-libs", "main",
		"libraries/raylib55.c3l", "")!!;
	RegisteredPackageSource release = {
		.registry = "default", .id = "vendor/raylib", .version = "5.5",
		.provides = "raylib55", .source = source,
	};
	NixRunner runner = (NixRunner)&fake;
	(void)add_dependency(tmem, root, source, "raylib55", "", runner, release)!!;
	Metadata added = parse_project(tmem, (String)file::load(tmem, project_path)!!,
		"linux-x64")!!;
	test::eq(1, added.registry_dependencies.len);
	test::eq("default", added.registry_dependencies[0].registry);
	test::eq("vendor/raylib", added.registry_dependencies[0].package_id);
	test::eq("5.5", added.registry_dependencies[0].version);
	remove_dependency(tmem, root, "raylib55", "", runner)!!;
	Metadata removed = parse_project(tmem, (String)file::load(tmem, project_path)!!,
		"linux-x64")!!;
	test::eq(0, removed.registry_dependencies.len);
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
	Metadata legacy = parse_manifest(tmem,
		`{"provides":"raylib55","vendor":{"c3pm":{"nix":{"imports":"./raylib.nix"}}}}`,
		"linux-x64")!!;
	test::eq(1, legacy.nix.imports.len);
	test::eq("./raylib.nix", legacy.nix.imports[0]);
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
	test::@error(parse_manifest(tmem,
		`{"provides":"bad","vendor":{"c3pm":{"nix":{"imports":"../escape.nix"}}}}`,
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
	String bundled = (String)file::load(tmem, output)!!;
	test::@check(bundled.starts_with(BUNDLE_PROLOGUE_WITH_CWD));
	test::@check(bundled.contains(BUNDLE_RUN_WITH_CWD));
	test::@check(bundled.ends_with("archive-data"));
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
		`{"provides":"foo","vendor":{"c3pm":{"nix":{"imports":42}}}}`,
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
	test::@check(flake.contains(`"x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"`));
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
