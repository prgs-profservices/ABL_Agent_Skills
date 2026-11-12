---
name: openedge-code-review
description: Review OpenEdge ABL code files for conformance to coding standards and best practices.
license: Apache-2.0
allowed-tools: Read, Grep, Glob
compatibility: Cross-platform, OpenEdge project (openedge-project.json)
---

<!--
openedge-code-review: Review OpenEdge ABL code files for conformance to coding standards and best practices.

Copyright 2026 Progress Software Corporation
SPDX-License-Identifier: Apache-2.0
-->

## Objective

Analyze OpenEdge ABL files (.cls, .p, .i, .w) and provide recommendations based on established coding standards and best practices.

**Important**: This skill performs read-only analysis and does not modify the code. Changes are only made if the user explicitly requests code updates after reviewing the recommendations.

## Prerequisites

- Access to the file to be reviewed
- The `rules.md` file in the same directory as this skill, containing the coding standards
- Optionally, a `problems.md` file in the same directory with additional problem patterns to check

## Steps

1. **Read the file to be reviewed**
   - Identify the file type (.cls, .p, .i, or .w)
   - Read the entire file contents

2. **Load the coding standards**
   - Read the `rules.md` file from the skill directory
   - If a `problems.md` file exists in the skill directory, read it as well
   - Understand the rules and problems that apply to the file type being reviewed

3. **Analyze the file**
   - Check each rule against the file contents
   - Note any violations or areas for improvement
   - Identify positive examples of good practices

4. **Generate recommendations**
   - List all issues found, categorized by severity (critical, warning, suggestion)
   - Provide specific line numbers or code examples where applicable
   - Suggest concrete fixes for each issue
   - Acknowledge what the code does well

## Output Format

Provide a structured review with:
- **Summary**: Overall assessment and key findings
- **Critical Issues**: Must-fix items that violate core standards
- **Warnings**: Should-fix items that affect code quality
- **Suggestions**: Nice-to-have improvements
- **Positive Observations**: What the code does well

For each issue, include:
- Rule reference from rules.md
- Specific location (line numbers)
- Current code example
- Recommended fix
- Rationale

## Usage Notes

- **Review only, no automatic changes**: This skill only analyzes and reports issues. It does not modify the code unless the user explicitly requests fixes after reviewing the recommendations.
- Be constructive and specific in feedback
- Prioritize issues that affect functionality or maintainability
- Consider the context and purpose of the code
- Balance strictness with pragmatism
