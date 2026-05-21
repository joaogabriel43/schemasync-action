# SchemaSync GitHub Action

This composite GitHub action automatically analyzes modified `.sql` files in a Pull Request for breaking changes using your deployed SchemaSync API.

## Requirements
- `actions/checkout` must use `fetch-depth: 0` to ensure `git diff` works correctly to discover changed files in the Pull Request.

## Example Usage

```yaml
name: SchemaSync Analysis
on:
  pull_request:
    paths:
      - '**.sql'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Run SchemaSync
        uses: joaogabriel43/schemasync-action@v1
        with:
          schemasync-url: 'https://api.schemasync.example.com'
          schemasync-token: ${{ secrets.SCHEMASYNC_TOKEN }}
          project-id: '123e4567-e89b-12d3-a456-426614174000'
          fail-on: 'BREAKING'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```
