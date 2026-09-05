# CareConnect Documentation Conversion

The generated 2025 HTML copies of the Programmer's Guide and Deployment and
Operations Guide were removed because they were no longer current.

The Markdown files under [`docs/guides/`](../guides/) are the current source
documents. Generate HTML or PDF from a reviewed Markdown source when a
published copy is needed; do not treat a generated artifact as an independent
source of operational truth.

For example, from the repository root:

```bash
pandoc docs/guides/DEPLOYMENT_AND_OPERATIONS_GUIDE.md \
  --standalone \
  --output docs/html/CareConnect_Deployment_Operations_Guide.html
```

Review generated output before publishing it and update it whenever the
underlying Markdown source changes.
