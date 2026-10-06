---
name: "personal-memory-os"
displayName: "Personal Memory OS"
description: >
  Full-stack context for building and extending the Personal Memory OS —
  an AWS-native Flutter application backed by Amazon Bedrock, AppSync,
  Lambda, Aurora PostgreSQL, EventBridge, and Bedrock Knowledge Bases.
  Loads architecture patterns, Flutter conventions, and AI safety rules
  automatically when you work on this project.
keywords:
  - personal memory
  - memory os
  - flutter aws
  - bedrock
  - appsync
  - eventbridge scheduler
  - aurora postgresql
  - cognito
  - flutter local notifications
  - knowledge base
  - opensearch serverless
  - capture pipeline
  - reminder engine
  - two-layer alarm
  - bedrock knowledge base
  - amazon nova
---

# Personal Memory OS — Kiro Power

This Power gives any developer working on the Personal Memory OS instant,
accurate context for the AWS architecture, Flutter code conventions, and
the project's AI safety rules — loaded on demand whenever the topics come up.

---

## What's inside

| File | Purpose |
|---|---|
| `POWER.md` | This file — entry point, activation keywords, onboarding |
| `mcp.json` | AWS Docs + CDK MCP servers via `uvx` |
| `steering/aws-architecture.md` | Full AWS service map, data flows, Lambda functions, queue names |
| `steering/flutter-patterns.md` | Dart conventions, folder structure, widget rules, AppColors/AppTextStyles |
| `steering/ai-principles.md` | AI safety rules — no Bedrock from Flutter, two-layer alarms, confirmation gates |

---

## Onboarding

### Step 1 — Prerequisites

- **Flutter SDK** (3.x+): `flutter --version`
- **AWS CLI** configured with a profile: `aws sts get-caller-identity`
- **Node.js / uvx**: the MCP servers run via `uvx` from the `uv` Python package manager.
  Install with `pip install uv` or see https://docs.astral.sh/uv/getting-started/installation/

### Step 2 — Install the Power

In Kiro, open the Powers panel → **Add power from GitHub** and paste the repo URL,
or **Add power from Local Path** for a local checkout.

Kiro auto-registers the MCP servers in `~/.kiro/settings/mcp.json` under namespaced
names (`power-personal-memory-os-aws-docs` and `power-personal-memory-os-aws-cdk`).

### Step 3 — Start building

Open the project in Kiro and mention any of the activation keywords — for example:
- "add a new Bedrock Lambda function"
- "fix the two-layer alarm registration"
- "create a new capture pipeline step"

The Power loads the right steering files automatically. No manual context needed.

---

## When to load each steering file

| Topic | Steering file |
|---|---|
| AWS service choices, data flows, Lambda functions, queues | `aws-architecture.md` |
| Flutter folder layout, widget rules, provider pattern, naming | `flutter-patterns.md` |
| AI model routing, confirmation gates, alarm strategy | `ai-principles.md` |

---

## Tool reference (MCP)

**aws-docs** — Search and read live AWS documentation
- Use when: choosing the right AWS service, checking API shapes, verifying CDK construct props

**aws-cdk** — CDK-aware assistance for the `infra/` stacks
- Use when: authoring or reviewing CDK stacks, checking L2/L3 construct availability, synth errors

---

## Project layout (quick reference)

```
lib/
  core/providers/       ChangeNotifier providers
  core/services/        Abstract interfaces + real/stub implementations
  core/models/          Reminder, Event, Capture, MemoryDocument, AiMessage
  core/theme/           AppColors, AppTextStyles
  features/             today/ reminders/ events/ capture/ memory/ auth/ settings/
  shared/widgets/       Cross-feature reusable widgets
backend/                Python Lambda functions (FastAPI)
infra/                  AWS CDK stacks (TypeScript) — 11 stacks
.kiro/
  specs/personal-memory-os/   requirements.md  design.md  tasks.md
  agents/memory-reviewer.md   Code review agent
  steering/                   Always-on project rules
```

---

## License

Apache-2.0 — see LICENSE in the repository root.

<!-- METADATA
maintainer: DHILIP-S-E
repository: https://github.com/DHILIP-S-E/memory-os
version: 1.0.0
-->
