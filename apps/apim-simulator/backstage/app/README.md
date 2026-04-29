# APIM Simulator Backstage App

This is the local Backstage app used by the optional `apim-simulator`
developer portal compose overlay. It is intentionally limited to the software
catalog and API docs plugins; full internal developer platform features belong
in downstream Backstage installations such as `platform`.

From the repository root, run:

```sh
make up-backstage
```

The Backstage catalog imports the repository-owned `catalog-info.yaml`. It does
not define product API contracts for downstream applications; those stay owned
by the application repositories that publish them.
