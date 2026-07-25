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
