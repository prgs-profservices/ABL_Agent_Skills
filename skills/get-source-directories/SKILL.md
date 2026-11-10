---
name: get-source-directories
description: Identify all compilable source directories from openedge-project.json, respecting includes and excludes filters. Used by other skills when they need to enumerate ABL source files for analysis or compilation.
license: Apache-2.0
allowed-tools: Read, Grep, Glob
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
get-source-directories: Identify all compilable source directories from openedge-project.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Overview

This skill reads `openedge-project.json` and returns the set of directories (and optional glob filters) that contain compilable ABL source files. Other skills call this skill first whenever they need to know *where* source code lives before scanning, analyzing, or compiling it.

## Instructions

### Step 1: Locate openedge-project.json

Find `openedge-project.json` in the workspace root.

### Step 2: Find Source Entries in buildPath

Read the file and locate the `buildPath` array. Filter for entries where `"type"` equals `"source"`. Ignore all entries with other types (e.g. `"propath"`).

### Step 3: Interpret Each Source Entry

Each source entry has the following relevant fields:

| Field | Required | Meaning |
|---|---|---|
| `path` | Yes | Root directory for this source tree (relative to workspace root) |
| `includes` | No | Comma-separated glob patterns. **If present, only files matching these patterns are compiled.** |
| `excludes` | No | Comma-separated glob patterns. **If present, files matching these patterns are excluded from compilation.** |

Rules:
- If **no** `includes` is present → all files under `path` are in scope.
- If `includes` **is** present → only files matching those patterns (relative to `path`) are in scope.
- If `excludes` **is** present → remove any files that match those patterns from the in-scope set.
- Both `includes` and `excludes` can appear together; apply `includes` first, then subtract `excludes`.

### Step 4: Build the Result

Return a flat list of relative paths. The expansion rules are:

- If an entry has **no** `includes`: emit just the `path` value.
- If an entry has `includes`: emit one path per include pattern, formed by joining `path` + `/` + each glob pattern.
- If an entry has `excludes`: note the excluded patterns separately so callers can subtract them, but do not emit them as positive paths.

### Example

Given this excerpt from `openedge-project.json`:

```json
"buildPath": [
  { "type": "propath", "path": "obj/shared" },
  { "type": "source", "path": "src/core",    "includes": "ap/**,gl/**" },
  { "type": "source", "path": "src/custom",  "includes": "ap/**,gl/**,adm2/**" },
  { "type": "source", "path": "src/base",    "includes": "ap/**,gl/**,adm2/**,rules/**" },
  { "type": "source", "path": "src/override" }
]
```

The result is:

```
src/core/ap/**
src/core/gl/**
src/custom/ap/**
src/custom/gl/**
src/custom/adm2/**
src/base/ap/**
src/base/gl/**
src/base/adm2/**
src/base/rules/**
src/override
```

Note that `obj/shared` is **not** included because its type is `"propath"`, not `"source"`.
