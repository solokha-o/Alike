#!/usr/bin/env python3
"""Check the local package graph against ADR-0004.

Decision record: Docs/adr/0004-package-dependencies.md

The check reads:
- `tools/package-categories`: the category of each package and App target;
- `tools/package-graph.allowlist`: the remote dependencies that ADR-0004 names,
  edges outside the matrix that an ADR accepts, and known imports of an
  undeclared local module in one file (debt), each with a reason;
- `Packages/*/Package.swift`: `.package(path: "../X")` edges, `.package(url:)`
  dependencies, and the product and target names (the module names);
- `Packages/*/Sources` and `Packages/*/Tests`: `import X` of a local module;
- `Alike/Alike.xcodeproj/project.pbxproj`: the package products of each App
  target (`packageProductDependencies` -> `XCSwiftPackageProductDependency`).

It fails on a package without a category, an Xcode target that links a
package product and has no category, a category line for a missing package,
a dependency form that it cannot read, an edge outside the matrix, a remote
dependency that is not in the allowlist, an import of a local module that the
package does not declare, a cycle, and an allowlist line that is a duplicate
or that no dependency uses. It prints the level of each
module: 0 when it has no local dependency, otherwise 1 more than its highest
dependency (ADR-0004, "Levels are computed").

An import of a module that is not a local module (Foundation, SwiftUI, Lottie,
and so on) is not checked. The check is about local modules only.

The Swift parsing is a set of regular expressions, not a Swift parser. It reads
the literal forms that the Package.swift files use: `.package(path: "...")`,
`.package(url: "...")`, `.library(name: "...")` and `.target(name: "...")`.
Any other `.package(` form fails, so that no dependency passes unchecked.
"""

from __future__ import annotations

import pathlib
import re
import sys
from dataclasses import dataclass, field

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_no_xctest_imports as swift_text  # noqa: E402

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
CATEGORIES_FILE = "tools/package-categories"
ALLOWLIST_FILE = "tools/package-graph.allowlist"
PBXPROJ_FILE = "Alike/Alike.xcodeproj/project.pbxproj"
ADR = "Docs/adr/0004-package-dependencies.md"

CATEGORIES = ("App", "Feature", "Foundation", "Utility", "Tool")
# Rows depend on columns. The SDK column is the allowlist (`sdk` lines).
MATRIX = {
    "App": {"Feature", "Foundation", "Utility"},
    "Feature": {"Foundation", "Utility"},
    "Foundation": {"Foundation", "Utility"},
    "Utility": {"Utility"},
    "Tool": {"Foundation", "Utility"},
}

LOCAL_EDGE = re.compile(r'\.package\(\s*(?:name:\s*"[^"]*"\s*,\s*)?path:\s*"\.\./([^"/]+)/?"')
REMOTE_EDGE = re.compile(r'\.package\(\s*(?:name:\s*"[^"]*"\s*,\s*)?url:\s*"([^"]+)"')
ANY_EDGE = re.compile(r"\.package\(")
MODULE_DECLARATION = re.compile(r'\.(library|target|executableTarget|testTarget)\(\s*name:\s*"([^"]+)"')
IMPORT_STATEMENT = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?[ \t]+)*"
    r"(?:(?:public|package|internal|fileprivate|private)[ \t]+)?"
    r"import[ \t]+(?:(?:class|struct|enum|protocol|typealias|func|let|var)[ \t]+)?(\w+)"
)
NATIVE_TARGET = re.compile(
    r"^\t\t\w+ /\* ([^*]+?) \*/ = \{\n\t\t\tisa = PBXNativeTarget;\n(.*?)^\t\t\};",
    re.MULTILINE | re.DOTALL,
)
PRODUCT_LIST = re.compile(r"packageProductDependencies = \((.*?)\);", re.DOTALL)
PRODUCT_DEPENDENCY = re.compile(
    r"^\t\t(\w+) /\* [^*]+ \*/ = \{\n\t\t\tisa = XCSwiftPackageProductDependency;\n(.*?)^\t\t\};",
    re.MULTILINE | re.DOTALL,
)


@dataclass
class Package:
    name: str
    local: list[str] = field(default_factory=list)
    remote: list[str] = field(default_factory=list)
    modules: set[str] = field(default_factory=set)
    # Text of each `.package(` form that is neither a local `../X` path nor a URL.
    unsupported: list[str] = field(default_factory=list)


@dataclass
class Graph:
    categories: dict[str, str]
    packages: dict[str, Package]
    # App target -> package names, or None when the project file is missing.
    apps: dict[str, list[str]] | None
    errors: list[str]

    def edges(self):
        for package in self.packages.values():
            for dependency in package.local:
                yield package.name, dependency
        for app, dependencies in (self.apps or {}).items():
            for dependency in dependencies:
                yield app, dependency


def strip_comments(source):
    """Return the source with comments blanked and string literals kept."""
    kept = list(source)
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            line_end = source.find("\n", index)
            end = len(source) if line_end < 0 else line_end
        elif source.startswith("/*", index):
            end = swift_text.block_comment_end(source, index)
        else:
            string_open = swift_text.STRING_OPEN.match(source, index)
            if string_open is not None:
                index = swift_text.string_end(source, string_open.end(), string_open.group(1), string_open.group(2))
            else:
                index += 1
            continue
        for position in range(index, end):
            if kept[position] != "\n":
                kept[position] = " "
        index = end
    return "".join(kept)


def read_name_lines(path, errors):
    """Yield (line number, fields, comment) for each line that is not blank or a comment."""
    if not path.is_file():
        errors.append(f"{path.name}: file not found.")
        return
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        text, _, comment = raw.partition("#")
        fields = text.split()
        if fields:
            yield number, fields, comment.strip()


def read_categories(root, errors):
    categories = {}
    for number, fields, _ in read_name_lines(root / CATEGORIES_FILE, errors):
        where = f"{CATEGORIES_FILE}:{number}"
        if len(fields) != 2 or fields[1] not in CATEGORIES:
            errors.append(f"{where}: write `<Package> <Category>`; categories are {', '.join(CATEGORIES)}.")
        elif fields[0] in categories:
            errors.append(f"{where}: {fields[0]} has a second category line.")
        else:
            categories[fields[0]] = fields[1]
    return categories


def read_allowlist(root, errors):
    """Return {(kind, first, second): line number}.

    The keys are ("sdk", package, URL), ("edge", from, to), and
    ("import", file, module), where file is relative to the repository root.
    """
    entries = {}
    for number, fields, reason in read_name_lines(root / ALLOWLIST_FILE, errors):
        where = f"{ALLOWLIST_FILE}:{number}"
        if len(fields) != 3 or fields[0] not in ("sdk", "edge", "import"):
            errors.append(
                f"{where}: write `sdk <Package> <URL>`, `edge <From> <To>`, or `import <File> <Module>`,"
                " then `# reason`."
            )
        elif tuple(fields) in entries:
            errors.append(f"{where}: duplicate of line {entries[tuple(fields)]}.")
        elif not reason:
            errors.append(f"{where}: give the reason in a `#` comment on the same line.")
        else:
            entries[tuple(fields)] = number
    return entries


def read_package(directory):
    source = strip_comments((directory / "Package.swift").read_text(encoding="utf-8"))
    package = Package(directory.name)
    package.local = sorted(set(LOCAL_EDGE.findall(source)))
    package.remote = sorted(set(REMOTE_EDGE.findall(source)))
    for match in ANY_EDGE.finditer(source):
        if not (LOCAL_EDGE.match(source, match.start()) or REMOTE_EDGE.match(source, match.start())):
            closing = source.find(")", match.start())
            end = len(source) if closing < 0 else closing + 1
            package.unsupported.append(" ".join(source[match.start():end].split()))
    package.modules = {name for kind, name in MODULE_DECLARATION.findall(source) if kind != "testTarget"}
    package.modules.add(directory.name)
    return package


def read_packages(root):
    packages_root = root / "Packages"
    if not packages_root.is_dir():
        return {}
    return {
        directory.name: read_package(directory)
        for directory in sorted(packages_root.iterdir())
        if (directory / "Package.swift").is_file()
    }


def read_app_products(root):
    """Return {native target: [product name]}, or None when there is no project file."""
    path = root / PBXPROJ_FILE
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    product_names = {}
    for identifier, body in PRODUCT_DEPENDENCY.findall(text):
        name = re.search(r"productName = \"?([^\";]+)\"?;", body)
        if name:
            product_names[identifier] = name.group(1)
    apps = {}
    for target, body in NATIVE_TARGET.findall(text):
        products = PRODUCT_LIST.search(body)
        identifiers = re.findall(r"^\s*(\w+)", products.group(1), re.MULTILINE) if products else []
        apps[target] = [product_names.get(identifier, identifier) for identifier in identifiers]
    return apps


def module_owners(packages):
    owners = {}
    for package in packages.values():
        for module in package.modules:
            owners[module] = package.name
    return owners


def load_graph(root):
    errors = []
    categories = read_categories(root, errors)
    packages = read_packages(root)
    owners = module_owners(packages)
    app_products = read_app_products(root)
    apps = None
    if app_products is not None:
        apps = {}
        for target, products in app_products.items():
            if target not in categories:
                if products:
                    errors.append(
                        f"{PBXPROJ_FILE}: target {target} links package products and has no line in {CATEGORIES_FILE}."
                    )
                continue
            if categories[target] != "App":
                continue
            dependencies = set()
            for product in products:
                if product in owners:
                    dependencies.add(owners[product])
                else:
                    errors.append(f"{PBXPROJ_FILE}: {target} uses product {product}, which no local package declares.")
            apps[target] = sorted(dependencies)
    return Graph(categories, packages, apps, errors)


def check_categories(graph):
    errors = []
    for name in graph.packages:
        if name not in graph.categories:
            errors.append(f"Packages/{name}: no line in {CATEGORIES_FILE}.")
    for name, category in graph.categories.items():
        if category == "App":
            if graph.apps is not None and name not in graph.apps:
                errors.append(f"{CATEGORIES_FILE}: App {name} is not a target in {PBXPROJ_FILE}.")
        elif name not in graph.packages:
            errors.append(f"{CATEGORIES_FILE}: {name} has no Packages/{name}/Package.swift.")
    return errors


def check_edges(graph, allowlist, used):
    errors = []
    for source, target in graph.edges():
        if target not in graph.packages:
            errors.append(f"{source} -> {target}: Packages/{target}/Package.swift does not exist.")
            continue
        source_category = graph.categories.get(source)
        target_category = graph.categories.get(target)
        if source_category is None or target_category is None:
            continue  # check_categories reports the missing line.
        if target_category in MATRIX[source_category]:
            continue
        key = ("edge", source, target)
        if key in allowlist:
            used.add(key)
            continue
        errors.append(
            f"{source} ({source_category}) -> {target} ({target_category}): the ADR-0004 matrix does not permit it."
        )
    for package in graph.packages.values():
        for text in package.unsupported:
            errors.append(
                f"Packages/{package.name}/Package.swift: cannot check `{text}`. "
                'Write `.package(path: "../<Package>")` or `.package(url: ...)`.'
            )
        for url in package.remote:
            key = ("sdk", package.name, url)
            if key in allowlist:
                used.add(key)
            else:
                errors.append(f"{package.name} -> {url}: a remote dependency that ADR-0004 does not name for {package.name}.")
    return errors


def swift_files(directory):
    for folder in ("Sources", "Tests"):
        base = directory / folder
        if base.is_dir():
            for path in sorted(base.rglob("*.swift")):
                if ".build" not in path.relative_to(directory).parts:
                    yield path


def imported_modules(source):
    """Yield (line number, module) for each import statement in the code."""
    code = swift_text.code_only(source)
    for number, line in enumerate(code.splitlines(), start=1):
        for statement in line.split(";"):
            match = IMPORT_STATEMENT.match(statement)
            if match:
                yield number, match.group(1)


def check_imports(root, graph, allowlist, used):
    errors = []
    owners = module_owners(graph.packages)
    for package in graph.packages.values():
        permitted = {package.name, *package.local}
        directory = root / "Packages" / package.name
        for path in swift_files(directory):
            source = path.read_text(encoding="utf-8", errors="replace")
            for number, module in imported_modules(source):
                owner = owners.get(module)
                if owner is None or owner in permitted:
                    continue
                where = path.relative_to(root).as_posix()
                key = ("import", where, module)
                if key in allowlist:
                    used.add(key)
                else:
                    errors.append(f"{where}:{number}: imports {module} from {owner}, which Package.swift does not declare.")
    return errors


def adjacency(graph):
    nodes = {*graph.packages, *(graph.apps or {})}
    edges = {node: [] for node in nodes}
    for source, target in graph.edges():
        if target in nodes:
            edges[source].append(target)
    return {node: sorted(set(targets)) for node, targets in edges.items()}


def find_cycle(edges):
    """Return one cycle as a list of nodes, or None."""
    state = {}
    stack = []

    def visit(node):
        state[node] = "open"
        stack.append(node)
        for target in edges[node]:
            if state.get(target) == "open":
                return stack[stack.index(target):] + [target]
            if target not in state:
                cycle = visit(target)
                if cycle:
                    return cycle
        stack.pop()
        state[node] = "done"
        return None

    for node in sorted(edges):
        if node not in state:
            cycle = visit(node)
            if cycle:
                return cycle
    return None


def levels(edges):
    """Level 0 has no local dependency; otherwise 1 more than the highest dependency."""
    result = {}

    def level(node):
        if node not in result:
            result[node] = 1 + max((level(target) for target in edges[node]), default=-1)
        return result[node]

    for node in edges:
        level(node)
    return result


def check(root):
    """Return (errors, levels or None, notes)."""
    graph = load_graph(root)
    allowlist = read_allowlist(root, graph.errors)
    used = set()
    errors = list(graph.errors)
    errors += check_categories(graph)
    errors += check_edges(graph, allowlist, used)
    errors += check_imports(root, graph, allowlist, used)
    for key, number in sorted(allowlist.items(), key=lambda item: item[1]):
        if key not in used:
            errors.append(f"{ALLOWLIST_FILE}:{number}: no current dependency uses `{' '.join(key)}`. Remove the line.")
    notes = []
    if graph.apps is None:
        notes.append(f"{PBXPROJ_FILE} not found: App edges are not checked, and levels use packages only.")
    edges = adjacency(graph)
    cycle = find_cycle(edges)
    if cycle:
        errors.append(f"Cycle: {' -> '.join(cycle)}.")
        return errors, None, notes
    return errors, levels(edges), notes


def main(argv=None):
    root = pathlib.Path(argv[0]).resolve() if argv else REPOSITORY_ROOT
    errors, module_levels, notes = check(root)
    for note in notes:
        print(f"Note: {note}")
    if module_levels:
        print("Levels (0 = no local dependency):")
        for name, value in sorted(module_levels.items(), key=lambda item: (item[1], item[0])):
            print(f"  {value}  {name}")
    if not errors:
        print("Package graph follows ADR-0004.")
        return 0
    print()
    for error in errors:
        print(f"error: {error}")
    print(
        f"\nA new edge, SDK, package, or category needs an ADR ({ADR}). "
        f"Update {CATEGORIES_FILE} or {ALLOWLIST_FILE} in the same pull request."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
