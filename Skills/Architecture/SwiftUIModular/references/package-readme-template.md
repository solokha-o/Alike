# Package README template

Every package under `Packages/` has a `README.md` with this structure.
Copy the block below into `Packages/<Name>/README.md` and replace each placeholder.

Rules:

- Write the description in at most 5 lines.
- Use one category from `Docs/adr/0004-package-dependencies.md`: Feature, Foundation,
  Foundation with UI, or Utility | Tool.
- List only real `public` types from `Sources/`. Write at most 6. Confirm each with
  `grep -rn "public .* <Type>" Packages/<Name>/Sources`.
- Read "Depends on" from `Package.swift`: each `path: "../<Package>"` plus each remote
  package. Write `none` when the package has no dependencies.
- In "Does not do", name the package that does that work, when one exists.
- Update the README in the same commit that changes the public types or the dependencies.

```markdown
# <PackageName>

<One sentence: what the package is.>
<One or two sentences: the main jobs it does.>
<Optional: who uses it, or a product split.>

- **Category:** <Feature | Foundation | Foundation with UI | Utility | Tool> (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** <One sentence: the single reason this package exists.>
- **Main public types:** `<TypeA>`, `<TypeB>`, `<TypeC>`
- **Depends on:** <PackageX, PackageY; remote: `<package-url-name>`> | none
- **Does not do:** <Work that belongs to another package (name it).>
```
