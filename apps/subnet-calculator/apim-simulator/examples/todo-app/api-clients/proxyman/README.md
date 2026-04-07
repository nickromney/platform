# Proxyman Import

This directory contains a HAR capture of the APIM-backed todo flow.

Import `todo-through-apim.har` into Proxyman with `File -> Open` or by dragging
the file into the app window. Proxyman's import/export docs say HAR 1.2 files
are supported for inspection.

Regenerate the HAR against the currently running stack with:

```bash
make export-todo-har
```
