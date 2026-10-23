# Workspace Rules & Guidelines

## 1. Minimal Git Diff & No Unsolicited Formatting (STRICT)
- **DO NOT run formatters or linters automatically** (e.g., `pint`, `php-cs-fixer`, `prettier`, etc.) unless the user explicitly requests it.
- **Preserve existing code formatting**: When modifying an existing file, only touch the exact lines necessary for the task. Keep existing indentation, spacing, quotes, and structure of surrounding code unchanged.
- **Do not reformat untouched methods or files**: Avoid mass whitespace changes, import reordering, or cosmetic fixes across unaffected code.
- **No Unrelated Existing Method Changes**: Do not modify an existing method unless its behavior is directly required by the current task or the change is necessary to preserve correctness of an affected contract/call chain. Do not opportunistically refactor or clean up unrelated methods.
- **Protect Git Blame**: Keep diffs minimal, clean, and focused solely on the business requirement to avoid polluting version history and causing merge conflicts with team members.

## 2. Coding & Architecture Conventions
- Follow the existing project architecture: `Controller -> FormRequest -> Service -> Repository`.
- **Pure Read Delegation Exception**:
  - The default flow remains `Controller -> FormRequest -> Service -> Repository`.
  - A Service may be skipped when its method only forwards the same parameters to exactly one Repository method and returns the Repository result unchanged, with no validation, business rule, transformation, authorization, cache, side effect, or workflow coordination.
  - In that case, the Controller MUST inject and call the Repository **Interface** directly; it MUST NOT call a Model or query the database directly.
  - If the use case contains any business logic or orchestration, it MUST continue through the Service layer.
- **Repository Layer (Pure Data Access)**:
  - Repository ONLY accesses the database (queries, joins, filters, inserts, updates, deletes).
  - NEVER place business logic, conditional business branching rules, or `config()` checks inside Repositories.
  - All Repository interface-to-implementation bindings MUST be registered in `App\Providers\RepositoryServiceProvider`; DO NOT register Repository bindings in `AppServiceProvider`.
  - **Return Type Hint for Single Record Queries (`find` / `first`)**:
    - Tất cả các method tìm kiếm/truy vấn đơn bản ghi (như `find`, `first`, `firstByFilter`, `getLatestBy...`) trong Repository Contract và Repository Implementation PHẢI có return type hint là `?\Illuminate\Database\Eloquent\Model` (hoặc `?Model`), KHÔNG khai báo custom model trực tiếp (ví dụ: `?CandidateWelfareCheck`).
- **Named Query Methods for Stable Conditions**:
  - Khi một điều kiện query cố định có ý nghĩa nghiệp vụ và được sử dụng lặp lại, Repository Contract/Implementation PHẢI expose method có tên cụ thể thay vì để Service gọi trực tiếp `firstByFilter()` hoặc `getByFilter()`.
  - Dùng tiền tố `findBy...` cho lookup một bản ghi (semantics `first`) và `getBy...` cho lookup nhiều bản ghi (semantics collection).
  - `firstByFilter()`/`getByFilter()` chỉ dùng cho filter động hoặc use case không có điều kiện query ổn định; không dùng cho lookup cố định đã có thể đặt tên.
- **Service Layer (Business Logic)**:
  - Service holds 100% of the Business Logic (business rules, resolution priority, cache management, data transformation, HTML sanitization, workflow coordination).
  - Service MUST NOT inject another Service or `ServiceInterface`. Shared stateless technical helpers belong in `App\Utilities\*Utility`; Utilities MUST NOT query the database or contain business workflow. For cross-service business workflows, consolidate the workflow in one Service or use an appropriate event/job boundary.
- **No Magic Values (Use Constants)**:
  - DO NOT hardcode magic numbers or magic strings in queries, methods, or conditions.
  - All fixed types, statuses, categories, cache keys, TTL durations, and fixed identifiers must be declared as `public const` in the appropriate Model, Service, or Contract.
- **No Database Queries in Loops (STRICT - Avoid N+1 & Mass Operations)**:
  - NEVER execute database queries (`find`, `first`, `where`, `insert`, `update`, `delete`, etc.) inside `foreach`, `for`, `while`, or `Collection::each` loops.
  - Pre-fetch all necessary records in a single batch query before loops using `whereIn`, eager loading, or batch methods, and map/group data in-memory (e.g., using `groupBy`, `keyBy`, or `pluck`).
  - Perform bulk inserts/updates using batch methods (e.g., `insert`, `upsert`, or single multi-row queries) instead of individual queries per iteration.
- **Database Transactions (STRICT - Writes Only, No Read Queries)**:
  - Transactions (`DB::transaction`, `beginTransaction`) must ONLY wrap data-mutating operations (`insert`, `update`, `delete`) that require atomicity.
  - NEVER place read/GET queries (`find`, `first`, `get`, `getByFilter`, eager loading `load()`, relation checks) inside transactions. Perform all reads before or after the transaction block.
  - Keep transaction blocks as small and short-lived as possible to minimize connection hold times and avoid database lock contention.
- Match existing code styles and patterns in the repository rather than enforcing external preferences.
- **Custom Exceptions Only (No Generic Exceptions)**:
  - DO NOT throw default/generic PHP exceptions (`\Exception`, `\RuntimeException`, `\DomainException`, `\InvalidArgumentException`, etc.).
  - ALWAYS use custom-defined exceptions under `App\Exceptions` (e.g., `App\Exceptions\Api\...` such as `APIErrorException` with proper error codes, or appropriate service exceptions).
- **Internal Methods Must Be Private (Visibility Scoping)**:
  - Internal helper methods not defined in Service/Repository contracts and not intended for external calls MUST be declared as `private`.
  - DO NOT leave internal helper functions as `public`. Use `protected` only when specifically designed for subclass extension.
- **DRY / No Duplicate Business Logic**:
  - DO NOT copy-paste the same business logic across multiple methods or files.
  - When logic is repeated in two or more places, extract it into a shared helper or service with an appropriate scope; internal helpers MUST be `private`.
  - Only abstract logic that has the same business behavior; do not combine code that is merely structurally similar.
- **Exception Logging & Observability (STRICT - Always Include Exception Message)**:
  - Khi bọc `try ... catch (\Throwable $e)` để log lỗi hoặc xử lý fallback trong Services, Jobs, Commands, hoặc Controllers:
  - **TUYỆT ĐỐI KHÔNG CHỈ LOG MỖI TÊN CLASS NGOẠI LỆ** (ví dụ: `'exception' => $e::class` mà bỏ qua message). Việc chỉ log class name gây mù thông tin và khiến việc truy vết root cause khi debug trên môi trường Staging/Production trở nên bất khả thi.
  - **BẮT BUỘC PHẢI LOG KÈM THÔNG ĐIỆP LỖI** (`'message' => $e->getMessage()`) cùng các context liên quan (như ID, trạng thái, bước thực thi).
  - Nếu ngoại lệ có nguy cơ chứa dữ liệu nhạy cảm/PII/secret tokens (như trong query parameters hoặc connection string), hãy sanitize hoặc mask phần nhạy cảm; KHÔNG ĐƯỢC nuốt hoàn toàn thông điệp lỗi (`$e->getMessage()`).

## 3. Workflow & Planning Guidelines
- **Hard Pre-Implementation Gate (.md Plan Required - STRICT & UNCONDITIONAL)**:
  - For **ANY** request that requires creating, modifying, or deleting code, views, templates, configs, or migrations (regardless of size, whether a new feature, enhancement, bugfix, refactor, or simple 1-line edit):
  - You **MUST NEVER** execute code edits or write implementation files in the first turn.
  - You **MUST FIRST** create a plan `.md` file, present the design/approach, and **STOP IMMEDIATELY**.
  - Every new task plan `.md` file MUST be grouped under `.specs/<TASK-KEY>/` (normally `.specs/GAP-700/<task-slug>.md`), using `.specs/SPEC_TEMPLATE.md` when applicable. The filename MUST start with the next zero-padded three-digit sequence within that task directory (`001-<task-slug>.md`, `002-<task-slug>.md`, ...); inspect existing numbered plans and use the next highest number. If no numbered plan exists, start at `001`. Before creating a new plan, search existing plans for the same task, scope, or context and extend/merge into the existing plan instead of creating duplicate files. Create a separate plan only for an independently deliverable scope or when the user explicitly requests a separate plan; cross-link related plans when they must remain separate. Do NOT rename existing unnumbered plans retroactively unless explicitly requested. Do NOT create new task plans directly under `.specs/`, in the repository root, or in the old `specs/` path. If no task key is available, use `.specs/UNTRACKED/` until the task key is confirmed.
  - Wait for the user to review, provide feedback, and explicitly approve the plan before implementing any code modifications or running migrations.
- **API Contract/API Docs Pre-Deployment Gate (STRICT)**:
  - Every API implementation/deployment plan MUST include a dedicated step to assess whether the change affects the API contract or API documentation, including routes, request/response schemas, examples, error contracts, and endpoint documentation.
  - **Mandatory Docs-First Phases**: If a task requires updating the API contract or API docs, its plan MUST be split into at least two execution phases, even when the user does not explicitly request phases. **Phase 1 MUST update API docs in `~/projects/crs-api-docs` before any implementation code is written**; Phase 2 and later implement and verify the approved behavior.
  - Phase 1 MUST define the affected endpoints, schemas, examples, error contracts, owned documentation files, dependencies, acceptance criteria, and documentation validation gate. Record the actual updated file paths/diff and validation result in the plan. Later code phases MUST NOT start until Phase 1 passes. Mark planned contracts as not yet deployed using the docs repository convention.
  - This docs-first rule takes precedence over the skeleton-first phase numbering and the requirement for two implementation phases below. A docs-only Phase 1 followed by one complete implementation/test Phase 2 is sufficient; do not add a skeleton phase unless explicitly requested. Changes to the documented contract during implementation require updating the plan and docs before dependent code continues.
  - When the API contract or API docs change, the corresponding files MUST be updated in `~/projects/crs-api-docs` within the same task.
  - **Mandatory API Docs Commit & Push**: After synchronizing API docs and passing documentation checks, commit the task's documentation changes in `~/projects/crs-api-docs` and push the commit to the remote `main` branch as part of the same synchronization workflow. This rule authorizes that docs commit/push without requesting separate user confirmation; it does not authorize committing/pushing backend code.
  - Stage only files belonging to the current task; preserve unrelated local changes. Use a normal push without force, resolve remote changes safely, and rerun affected documentation checks if integration changes the docs. Record the documentation commit SHA and successful push to remote `main` in the task plan. The docs synchronization phase is complete only after validation, commit, and push all succeed; otherwise report the blocker and do not mark the phase PASS.
  - This synchronization step MUST be completed and marked as passed BEFORE the code deployment step. The plan MUST record either the updated files/diff in `~/projects/crs-api-docs` or `N/A — no API contract/API docs change`.
  - If `~/projects/crs-api-docs` does not exist, cannot be written, or is not synchronized, STOP and report a blocker; do not proceed with or report code deployment as complete.
- **Data Origin & Call Chain Verification (STRICT - No Assumed Variables)**:
  - When modifying or using variables in Views, Blade templates, DTOs, Resources, Mail templates, or Services, **NEVER assume a variable or array key exists**.
  - You **MUST trace the call chain back to the caller/data source** (Controller, Service, Mailer) and verify that the data is actually provided at runtime.
  - Never write isolated unit tests with mock data that assume a variable exists without verifying the real production caller passes it.
- **Feature Development & Sequential Execution (STRICT)**:
  - When making ANY code change, you MUST first read the relevant skill `SKILL.md` file(s) from `.agents/skills/` before writing any code.
  - For feature/API/template development, follow the `backend-workflow` skill.
  - For debugging/bugfix, follow the `debug-workflow` skill.
  - For creating new files (Controller, Service, Repository, etc.), follow the `laravel-architecture` skill.
  - **NEVER skip steps or jump ahead**. Each step must be completed before moving to the next.
  - After all code is written, perform a Self-Check against the original plan.
- **Multi-Phase Skeleton-First Planning (WHEN USER REQUESTS PHASES)**:
  - Except for the mandatory docs-first phases above, plans MUST NOT be split into multiple implementation phases by default. Create a phased plan only when the user explicitly requests the work to be divided into phases.
  - When the user requests phases, the plan MUST contain at least two implementation phases. Planning/analysis is not counted as an implementation phase.
  - **Phase 1 — Skeleton / Integration Boundary** MUST create only the applicable layers for the scope and prepare compile-valid contracts, imports, dependency bindings, method signatures, return types, constants, and call-chain boundaries. For API features this normally includes Controller, FormRequest, Response/Resource/DTO, custom Exception, Service Contract/Implementation, and required Repository contracts/implementations.
  - Detailed business behavior that is not implemented in Phase 1 MUST be recorded with an explicit phase/owner TODO marker such as `// TODO[GAP-691-P2]: ...`; vague or ownerless TODOs are not allowed.
  - Phase 1 MUST NOT return fake success or mutate production state as if the feature were complete. An exposed incomplete route MUST use an approved safe behavior such as a feature gate or custom not-implemented response according to the existing project convention.
  - The plan MUST define phase input/output, file ownership, dependencies, acceptance criteria, and a test gate for every phase. Later phases may start only after the prior phase passes its gate.
  - Public Controller, Request, Response, Exception, and Service contracts established in Phase 1 are frozen for later phases; breaking changes require updating the plan and approval.
  - Apply a layer-applicability check: tasks limited to a Job, Repository, Command, or other layer MUST NOT create empty unrelated Controller/Request/Response files solely to satisfy the phase rule.
  - Required migrations, DTOs, external payloads, and seed data MUST be identified as data contracts before dependent business logic is implemented.
  - External integrations, queues, retries, idempotency, and rollout concerns SHOULD be isolated into later phases when present. Any retry phase MUST define post-state/idempotency checks before repeating side effects.
  - Each phase MUST be independently compileable/testable and reviewable/mergeable within its declared dependencies. After all phases, perform the existing test impact review, run affected suites, and run the full `./vendor/bin/phpunit` suite.
- **Multi-Agent Execution for Long Tasks**:
  - You MAY split a long task across multiple agents only when each part can be implemented independently and its dependencies, shared contracts, and file ownership are explicit.
  - Assign non-overlapping file ownership. A shared file MUST have one owner or be edited sequentially; agents MUST NOT overwrite or integrate changes outside their assigned scope.
  - Prefer isolated worktrees/branches for parallel work. If agents share a workspace, parallelize only work on disjoint files and coordinate before touching shared files.
  - If parts depend on each other or conflict-free ownership cannot be guaranteed, execute them sequentially.
  - The coordinating agent MUST integrate and review all changes, verify cross-part compatibility, and run the combined affected tests. Every agent MUST follow the existing plan approval, skill, and test requirements.
- **Mandatory Test Impact Review & Verification (STRICT - Test Audit After Code Changes)**:
  - Whenever code is created, modified, or refactored (especially data structures, contracts, facades, view templates, mailers, or helper methods):
  - You **MUST proactively identify and review all existing unit and feature test cases** that interact with or assert against the changed behavior/data structure to determine if test cases need updating.
  - You **MUST update existing test cases** to align with the new contract/behavior and **add new Feature tests or Service unit tests** covering the newly introduced functionality, following the placement policy below.
  - You **MUST execute all affected test suites** (`./vendor/bin/phpunit`) and ensure 100% passing status before considering any task complete.
- **Test Placement Policy (STRICT — Feature Tests and Service Unit Tests Only)**:
  - Feature tests cover functional flows and integration behavior, including APIs, Jobs/queues, Commands, Events/Listeners, Repositories, DTOs, Utilities, and views/templates.
  - Unit tests MUST ONLY test Service business logic and MUST be placed under `tests/Unit/Services/`.
  - DO NOT add standalone unit tests for other layers or place non-Service unit tests under `tests/Unit/Services/` to bypass this rule. Cover those behaviors through Feature tests or through a Service unit test that exercises the actual Service call chain.
  - DO NOT add unit tests for Repository implementations or contracts. Cover repository behavior through appropriate Service or Feature tests instead.
  - **Exception — test-data/fixture-only Artisan commands**: Commands whose sole purpose is to generate temporary local/STG test data or fixtures, and which do not change production runtime behavior or implement a production business workflow, are exempt from adding unit/feature tests and running PHPUnit. The command must be explicitly documented as test-data-only; if it contains production business logic or changes shared runtime behavior, this exception does not apply.
- **Code Review Protocol (GitHub Actions Claude Review Logic - STRICT)**:
  - Khi người dùng yêu cầu review code (review PR, review commit, review task, review code change hoặc review file):
  - Bắt buộc áp dụng và tuân thủ chặt chẽ logic review từ GitHub Actions workflow [`.github/workflows/claude-review.yml`](file:///Users/nexusfrontiertech/projects/gap-web-backend/.github/workflows/claude-review.yml):
    1. **Chỉ báo cáo lỗi mức độ High và Medium**:
       - **High**: Lỗi tính đúng đắn (correctness bugs), lỗ hổng bảo mật (auth, injection, rò rỉ secret, xử lý file không an toàn), giả mạo dữ liệu tuân thủ/pháp lý (compliance/consent fabrication), mất mát dữ liệu, phá vỡ boundary/multi-tenant.
       - **Medium**: Hành vi tiềm ẩn sai lệch (likely-incorrect behavior), thiếu xử lý ngoại lệ/lỗi tại các luồng quan trọng, race conditions, cấu hình gây chết ngầm/thất bại trong im lặng (silent failures).
    2. **Bỏ qua hoàn toàn (OMIT)**: Lỗi Low severity, nitpicks, style, formatting, naming conventions hoặc sở thích cá nhân. Nếu một vấn đề không rõ ràng là High hoặc Medium, tuyệt đối không đưa vào báo cáo.
    3. **Điều tra phạm vi ảnh hưởng (Blast Radius)**: Không chỉ nhìn vào từng hunk của diff; phải grep/đọc toàn bộ codebase liên quan để kiểm tra callers, consumers, database query impact, và call-chain.
    4. **Neo vị trí chính xác (Anchors)**: Mọi finding High/Medium PHẢI có file path, số dòng cụ thể ([`file://...#L...`](file:///Users/nexusfrontiertech/projects/gap-web-backend)) và đề xuất giải pháp sửa lỗi cụ thể (concrete fix).
    5. **Kết luận rõ ràng**: Nếu không phát hiện lỗi High hoặc Medium nào, phải ghi rõ ràng: *"No High or Medium severity issues found."*

## 4. Context & Session Management
- **Context Rot Prevention**:
  - Do NOT dump entire database schemas, full config files, or verbose logs into the conversation.
  - When referencing existing code, cite file paths and line numbers instead of copying large blocks.
  - When a task is complete (feature/API done), suggest the user commit and start a new session.
- **Error Log Handling (STRICT)**:
  - When user provides error logs, summarize to: `[ErrorType] at [File:Line] — [Root cause in 1 line]`.
  - Do NOT request or process raw log dumps longer than 50 lines. Ask user to filter first.
- **SPEC as Source of Truth**:
  - Do NOT rely on chat history as the "memory" of decisions. All architecture/API decisions must be recorded in plan `.md` files.
  - When there is ambiguity, refer back to the approved plan document, not previous chat messages.

## 5. Living Business Logic Specification (STRICT)
- The canonical living business-logic documentation is stored in the hidden `.business-spec/` folder, separate from task plans/specifications in `.specs/`.
- Before answering ANY user question about current business logic, workflow, API behavior, cron/job behavior, data flow, or a business-related bug, you MUST read all three canonical files below first:
  - `.business-spec/backend-business-flow-spec.md`
  - `.business-spec/backend-api-route-inventory.md`
  - `.business-spec/backend-database-relationship.md`
- After reading the three files, trace into the source code to verify the actual implementation. Treat the files as the business-flow baseline and explicitly report any `CODE`, `DATA`, `CONFIG`, `EXTERNAL`, or `INFRASTRUCTURE` deviation found during tracing.
- Do NOT use task-specific plan files in `.specs/` as a substitute for the living business logic specification. Task plans describe a requested change; `.business-spec/` describes the currently implemented business flow.
- Any new or updated documentation that records current APIs, cron schedules, jobs, business flows, external integrations, or database relationships MUST be created or updated under `.business-spec/`. Add a cross-link from `backend-business-flow-spec.md` when a new living-spec file is added.
- New task plans, approved implementation designs, and task-specific decision records MUST remain in `.specs/` (or the explicitly requested task-plan location) and MUST NOT be mixed into `.business-spec/`.
