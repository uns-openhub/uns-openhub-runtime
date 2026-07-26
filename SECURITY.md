# Security

Do not open a public issue for a suspected vulnerability or include
credentials, tokens, keys, production configuration, customer data, registry
credentials, or exploit details in ordinary issue text.

Report security concerns privately to the repository maintainers or through a
private GitHub security advisory. Rotate any credential that may have been
exposed before sharing diagnostic evidence.

`uns runtime sync` may request an HTTPS Git token for a private runtime
repository. Use a fine-grained, expiring token restricted to read-only contents
access for this repository. The CLI supplies it only through the current Git
process environment; it does not add the token to the remote URL or Git
configuration.

The same rule applies when a private GitHub Release asset is needed. The
public, minimal `uns-bootstrap` and runtime launchers first try an anonymous
download, then request a token with a hidden prompt. The token is supplied only
as an `Authorization` header to GitHub's documented release API and is not
written to the runtime checkout or cache. The public bootstrap contains no
runtime templates, credentials, or private release payloads.
Downloaded executables and controller artifacts are rejected unless their
SHA-256 value matches the release index committed with the runtime version.
`uns-bootstrap install` and `uns bootstrap` apply the same rule to the
immutable offline runtime archive, extract it through a link- and
traversal-safe reader, and publish it only after the runtime version, release
manifest, offline marker, and current-platform private CLI checksum agree. They
refuse an existing non-empty destination.
