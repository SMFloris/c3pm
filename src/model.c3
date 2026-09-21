module c3pm;

faultdef INVALID_ARGUMENTS,
	INVALID_SOURCE,
	INVALID_SOURCE_PATH,
	INVALID_NIX_ATTRIBUTE,
	INVALID_METADATA,
	MISSING_SOURCE,
	PROVIDES_MISMATCH,
	SOURCE_CONFLICT,
	DEPENDENCY_CYCLE,
	UNSUPPORTED_HOST,
	PROJECT_NOT_FOUND,
	NIX_NOT_CONFIGURED,
	INVALID_NIX_CONFIG,
	INVALID_REGISTRY,
	AMBIGUOUS_REGISTRY_PACKAGE,
	REGISTRY_VERSION_NOT_FOUND,
	AMBIGUOUS_DEPENDENCY_UPDATE,
	NIX_DOWNLOAD_FAILED,
	NIX_FAILED,
	TRANSACTION_FAILED,
	UNKNOWN_TARGET,
	NON_EXECUTABLE_TARGET,
	NON_LINKABLE_TARGET,
	AMBIGUOUS_TARGET,
	NO_EXECUTABLE_TARGET,
	BUNDLE_FAILED,
	BUNDLE_OUTPUT_MISSING,
	BUNDLE_FORMAT_UNSUPPORTED;

enum SourceKind : char
{
	GITHUB,
	GIT_HTTPS,
	GIT_SSH,
	ARCHIVE_HTTPS,
	FOLDER,
}

struct ProjectTarget
{
	String name;
	String type;
}

struct PackageSource
{
	SourceKind kind;
	String location;
	String rev;
	String subdir;
	String sha256;
	// Runtime-only base for relative folder sources; never serialized.
	String base;
}

struct DependencySpec
{
	String name;
	PackageSource source;
}

struct RegistryDependencySpec
{
	String name;
	String registry;
	String package_id;
	String version;
}

struct LinkSpec
{
	String name;
	PackageSource source;
	bool has_source;
	String c3c_target;
	String nix_package;
	bool passthrough;
	String for_target;
}

struct ToolchainConfig
{
	String c3c_version;
	String nixpkgs;
}

struct NixInputs
{
	String[] imports;
	String[] native_build_inputs;
	String[] build_inputs;
	String[] propagated_native_build_inputs;
	String[] propagated_build_inputs;
}

struct Metadata
{
	String provides;
	String version;
	String[] dependencies;
	DependencySpec[] sources;
	RegistryDependencySpec[] registry_dependencies;
	NixInputs nix;
	ProjectTarget[] targets;
	LinkSpec[] links;
	ToolchainConfig toolchain;
}

struct GraphNode
{
	String name;
	PackageSource source;
	String[] dependencies;
	NixInputs nix;
}

struct Graph
{
	GraphNode[] nodes;
	String[] roots;
}

fn bool source_equal(PackageSource a, PackageSource b)
{
	return a.kind == b.kind && a.location == b.location && a.rev == b.rev &&
		a.subdir == b.subdir && a.sha256 == b.sha256;
}

fn bool source_identity_equal(PackageSource a, PackageSource b)
{
	return a.kind == b.kind && a.location == b.location && a.rev == b.rev &&
		a.sha256 == b.sha256 && a.base == b.base;
}

fn GraphNode*? Graph.find(&self, String name)
{
	foreach (&node : self.nodes) if (node.name == name) return node;
	return NOT_FOUND~;
}

fn DependencySpec*? Metadata.find_source(&self, String name)
{
	foreach (&source : self.sources) if (source.name == name) return source;
	return NOT_FOUND~;
}
