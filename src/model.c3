module c3pm;

faultdef INVALID_GITHUB_URI,
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
	NIX_FAILED,
	TRANSACTION_FAILED,
	UNKNOWN_TARGET,
	NON_EXECUTABLE_TARGET,
	AMBIGUOUS_TARGET,
	NO_EXECUTABLE_TARGET,
	BUNDLE_FAILED,
	BUNDLE_OUTPUT_MISSING;

struct ProjectTarget
{
	String name;
	String type;
}

struct FetchGithub
{
	String owner;
	String repo;
	String rev;
	String path;
}

struct DependencySpec
{
	String name;
	FetchGithub source;
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
	NixInputs nix;
	ProjectTarget[] targets;
}

struct GraphNode
{
	String name;
	FetchGithub source;
	String[] dependencies;
	NixInputs nix;
}

struct Graph
{
	GraphNode[] nodes;
	String[] roots;
}

fn bool source_equal(FetchGithub a, FetchGithub b)
{
	return a.owner == b.owner && a.repo == b.repo && a.rev == b.rev && a.path == b.path;
}

fn bool source_identity_equal(FetchGithub a, FetchGithub b)
{
	return a.owner == b.owner && a.repo == b.repo && a.rev == b.rev;
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
