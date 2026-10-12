# SPEC: GAP-691 — Reuse Service-built data in Permanent sync Job

> **Trạng thái**: `DONE` — implementation/docs/tests PASS; deployment chưa thực hiện
> **Ngày tạo**: 2026-10-09
> **Author**: Codex
> **Related**: [007 — Implemented Permanent form/MM flow](007-backend-generated-permanent-form-in-mm-job.md), [008 — TestCommand](008-test-command-permanent-sync-job.md)
> **Nguồn**: Chuyển nguyên phạm vi chưa thực thi từ §22 của plan007 theo yêu cầu user. Không thay đổi quyết định thiết kế, trạng thái phê duyệt hoặc bằng chứng thực thi của các phần đã hoàn tất.

Status: DONE — user approved triển khai; docs-first, implementation, affected/full tests and self-check PASS (2026-10-09). This amendment supersedes §16/21's unconditional full worker-context rebuild and the MM current-profile data-origin rule only where submit has already supplied data.

## 1. Verified sources and intended handoff

Current submit builds PermanentCandidateIntakeContextData with Candidate, candidate-job, files, Address, existing Answers, PDF Questions, options, timing and immutable PDF snapshot. After persistence it dispatches PermanentCandidateSyncData containing only IDs and the PDF snapshot. buildExecutionData consequently selects the same Candidate/Address/Answers/files/question categories again. Reuse the available finalized data instead. Do not require submit to fetch every worker-only source just to make the queue DTO complete.

Queue a typed, scalar/value-only projection of the Service context after successful persistence, inside PermanentCandidateSyncData. Extend the existing DTO boundary with explicitly named prepared-data DTOs (`PreparedMatchMakerProfile`, `PreparedMatchMakerAnswer`) for Candidate profile, Address, Answers and Questions. MM identifiers/status remain live worker state and are not frozen in the prepared profile. Nested typed lists have explicit PHPDoc element types; no generic array data bag, FormRequest, Eloquent Model/Collection, query builder or injected Service in the queue payload.

Capture actual persisted values, not just raw Request values: retained phone country code, normalized middle name, first_applied_at, saved Address and final Answers. saveAnswer currently returns void and does not insert newly created records into context.answers. Change its directly affected call chain to capture repository write results/update the in-memory answer map, so both created and updated answers reach the Job without a reread. Preserve all pre-existing answers needed by MM, and preserve the different recruitment categories: submit/PDF WHERE_DID_YOU_HEAR_ABOUT_US_CANDIDATE_ANSWER versus MM WHERE_DID_YOU_HEAR_ABOUT_US. Do not substitute one for the other.

Keep the original PDF snapshot/fingerprint and display labels intact. Build the queued projection from the actual post-persistence Service context; snapshot serialization remains independent of MM profile projection. Queue dispatch remains Redis/default, direct Bus dispatch and HTTP202 pending.

CODE deviation found while tracing this plan:
- `buildIntakeData` now uses `request.files` although Symfony Request publicly defines files as FileBag. Restore `input('files')` for the JSON list and remove the contradictory `@property files` declaration.
- MatchMaker validators (`validatePermanentSyncData` / `validateStandalonePermanentData`) currently lack explicit precondition existence checks for `Candidate`, `Job`, and `Address` models compared to living spec. Ensure these are explicitly validated when adapting the boundary data sources.

## 1.1. DTO data overlap analysis and architectural redesign

### The constraint of nested Eloquent models in Queue Payload
The Job uses `SerializesModels` trait (`SyncPermanentCandidateToMatchMakerJob:L25`). However, `SerializesModels` only intercepts Eloquent models when they are **top-level properties** of the Job class. When models (`Candidate`, `CandidateAddress`) are nested deeply inside an object structure like `PermanentCandidateSyncData` or `PermanentCandidateIntakeContextData`, Laravel's serializer does not convert them to lightweight IDs. Instead, it serializes the **entire complex object** (including DB connections, Carbon instances, and relation closures). This causes massive Redis payload bloat and stale data on deserialization. Therefore, the queue payload MUST be strictly scalar/value-only.

### Why SnapshotData cannot be used directly for MatchMaker
Although `PermanentCandidateFormSnapshotData` contains all the scalar fields MatchMaker needs (name, email, phone, etc.), it represents the **pre-persistence Request state** used to stamp an immutable PDF. It does not reflect post-persistence fallbacks. For example, if `phoneNumberCountryCode` is null in the request, `SnapshotData` holds `null`, but `persistIntakeData` falls back to the candidate's existing database value. If MatchMaker uses the snapshot directly, it will receive the wrong data. 
Furthermore, standalone callers (like sync CV only) do not have a PDF snapshot. Forcing them to construct a fake 25-field `SnapshotData` just to satisfy a payload builder is anti-pattern.

### Redesign Approach: The `PreparedMatchMakerProfile` Boundary

Instead of hacking `SnapshotData` or pushing models into the queue, we will introduce a dedicated, lightweight scalar boundary explicitly for MatchMaker data.

1. **Retain Top-Level IDs in SyncData**: Do NOT remove `cvFileId` or `agreementFileId` from the top level of `PermanentCandidateSyncData`. Standalone callers pass `snapshot = null`; removing these IDs would break their flows. Ensure the `PermanentCandidateSyncData` constructor retains `?PermanentCandidateFormSnapshotData $snapshot = null` (currently it is incorrectly non-nullable in the codebase).

2. **Introduce Prepared Scalar DTOs**:
   - `PreparedMatchMakerProfile`: Scalar DTO containing exactly the submitted MM payload fields: `title`, `first_name`, `middle_name`, `last_name`, `email`, `phone_number`, nullable `phone_number_country_code`, nullable `date_of_birth`, `building`, `street`, `town_city`, `county`, and `postcode`. It MUST NOT contain `is_permanent`; completion/skip decisions always use the live candidate state read under the worker lock.
   - `PreparedMatchMakerAnswer`: Scalar DTO containing `question_id` (int), nullable question definition fields (`question_category`, `question_type`, `question_options_data`) and `answer_values` (`list<string|list<array{label: string, value: string}>>`, preserving the existing Answer cast shape for select-single, select-multi, and free-text answers). A nullable definition is allowed only when the answer's question category is not part of the submit-time question batch; the worker fills that definition from the missing category query by `question_id`. The worker resolves labels from this serialized definition/value pair without querying the same loaded question or answer again.

3. **Update SyncData Payload**: Extend `PermanentCandidateSyncData` to optionally carry `?PreparedMatchMakerProfile $profile`, `array<PreparedMatchMakerAnswer> $answers`, and `array<string> $loadedQuestionCategories`. 
   - Tracking `$loadedQuestionCategories` is critical for missing-only hydration: if a category was loaded during Submit but the candidate provided no answer, the `$answers` array won't have an entry for it. Passing the loaded categories list tells the worker *not* to re-query that question definition. The worker must keep question-definition presence separate from answer presence: a loaded question with no answer produces the existing `No answer` result, while an unavailable required question still raises the existing question-missing error. The category list is only a load marker; each supplied answer retains its `question_id` so it cannot be matched by category or array position.

4. **Refactor MM Payload Builder**: Change `MatchMakerService::getPermanentCandidateRegistrationPayload` to accept `PreparedMatchMakerProfile` and `array<PreparedMatchMakerAnswer>`. 
   - **Submit Flow**: Constructs these DTOs in memory *after* DB persistence (capturing fallbacks) and queues them. The worker reads them directly, eliminating DB reads for profile, address, and submit-provided answers.
   - **Standalone Flow**: The standalone `buildPermanentSyncData` reads the Eloquent models from DB and maps them into these same DTOs before calling the payload builder. 
   Both flows converge on a clean, scalar boundary.

5. **Worker Execution Constraints**: The worker still requires the `Candidate` model for live-state guards (`is_permanent` check) and DB mutation (`match_maker_status` writes), and `File` models for Storage operations and uploads. These will be fetched by ID, while the heavy profile/address/answers data is hydrated from the queued prepared DTOs. The queued profile's values never decide whether processing is skipped or completed.

## 2. Missing-only hydration and required live state

Use explicit presence/load metadata for optional source groups and loaded question categories. A known null, empty string/list or known absent record is a loaded result, not permission to query again. IDs alone do not count as loaded profile/file/question data. DTOs remain data carriers; Service owns decisions and Repository owns pure named data access.

Worker initial preparation merges supplied prepared data with only missing sources. For the normal HTTP submit path:

- Reuse finalized Candidate profile, Address, Answers, CV/Agreement metadata, question definitions/categories already loaded and immutable labels from the queue DTO.
- Load Job and then its Branch if absent; query required question categories minus the explicitly loaded categories in one batch. Recruitment category differences above mean the MM category may still need loading, while transport/distance must not be selected again.
- Generated PDF metadata/storage state is worker-only: look up by candidate/job/type/fingerprint for reuse, otherwise generate/upload/create and carry the returned File through MM and completion. Do not immediately fetch a created File by its ID again.
- Data only produced by MM registration/upload cannot exist at submit: capture external results in the same execution context and persist only the specific changed identifiers/status fields.

Separate the above missing-data hydration from necessary live execution guards. Under the existing candidate lock, use minimal named repository state/existence projections for current candidate existence/completed status and candidate-job ownership. Verify submitted file existence/current owner/type/job and Storage existence with one batched metadata check as required by the established fresh-attempt safety contract. This check must not be used to reload unchanged profile/address/answers/questions or replace their queued business values. Retain current MM identifiers/status needed for safe retries after partial external/local success; fetch only those live state fields and use their established precedence, not the full Candidate profile. Completed candidate exits before PDF/MM side effects. Missing ownership/records/files fail through existing custom exceptions. Document every intentional repeated read as a live state guard rather than claiming zero database reads in the worker.

Hydrate all remaining mandatory sources and live state once at the initial preparation boundary. Later processing uses the execution DTO; only genuinely newly available data (generated File, external results) may extend it. No SELECT in processing loops/transactions and no full-context prepare a second time inside MM/completion. Use named pure Repository methods for minimal projections/batched checks if existing methods cannot express this without full-row loading.

Preserve the independent scalar MM, typed CV-only Job, standalone PDF generator and fixture TestCommand entry points. When these callers omit prepared data, hydrate their missing groups once and run their existing independent validation; this is not old serialized-job compatibility. TestCommand may provide the same typed prepared boundary where applicable. No public skipValidation flag or old-payload adapter.

## 3. Data-origin decision, write safety and owned files

For data actually supplied by submit, MM will use the finalized submitted values even if profile/address/answers/question definitions change before execution. This is the intentional consequence of reuse and supersedes the earlier current-attempt profile rule. Missing groups use their value when first hydrated in that attempt. Safety/status/MM retry identifiers are explicitly live state; PDF remains the original submit snapshot. Do not describe the whole payload as either entirely live or entirely frozen.

Persist only workflow-owned MM identifiers/status and completion fields against the checked candidate identity. Never save all attributes of a reconstructed queued Candidate back to the DB, which could undo profile edits made after enqueue. Preserve custom write-result failure handling, lock release, retry deadline/error handling, deterministic PDF reuse and no completion after MM failure. Do not change retry/idempotency guarantees or add submissions tables/migrations.

Owned implementation files: PermanentCandidateSyncData (add $profile, $answers, $loadedQuestionCategories; restore `?snapshot = null`); new `PreparedMatchMakerProfile` and `PreparedMatchMakerAnswer` DTOs under app/Dto; PermanentCandidateExecutionData only where required for handoff; PermanentCandidateIntakeService and its contract; MatchMakerService/contract for the refactored `getPermanentCandidateRegistrationPayload` signature and its caller `processPermanentSyncData`; SyncPermanentCandidateToMatchMakerJob only for the typed handoff; affected Repository contracts/implementations for named minimal state reads/writes; PermanentCandidateIntakeRequest for the verified FileBag collision; TestCommand if its actual caller needs the new boundary. Preserve unrelated methods, formatting and user edits. Read backend-workflow and laravel-architecture before creating implementation files.

## 4. Phase 1 — Documentation first

Public endpoint routes, request/response schemas, examples and synchronous error contracts remain unchanged. Internal data-flow/queue documentation changes, so docs-first applies. Update ~/projects/crs-api-docs/docs/flows/permanent-intake.md with prepared queue projection, loaded/missing semantics, mixed data origins, minimal live retry guards and standalone fallback. Update docs/operations/queue-and-events.md only where its Permanent data-preparation description would conflict. Mark the behavior planned/not deployed using the docs convention. Dependencies: approved design in this plan and verified current source trace. Acceptance: documented boundaries match sections 1–3; no claim of zero worker reads or all-current MM profile data.

Gate: npm run build and git diff --check; stage only task-owned docs; commit and normal push remote main. Record actual paths/diff, validation log, commit SHA and push result below before Phase2 starts. Preserve unrelated docs work; no backend commit/push or deployment. If docs cannot be synchronized, report blocker and do not start dependent code.

## 5. Phase 2 — Implementation, test audit and living specification

Implement the typed handoff, finalized write-result capture and missing-only initial hydration after Phase1 PASS. Audit current call chains and queue serialization before adapting existing tests. Update the canonical .business-spec current-flow descriptions/data-origin statements and review route inventory/database relationship files for affected statements; no schema change expected.

Prefer extending existing Feature/Service cases and compact providers rather than adding duplicate tests. Feature coverage must trace real validated HTTP submit -> actual saved values -> serialized typed queue payload -> worker hydration -> MM/completion. Unit tests are only for actual Service business behavior; no Job/DTO/Repository unit suites.

Required acceptance coverage: supplied profile/address/answers/question categories are not reselected; each supplied answer is matched by `question_id`; select-single/select-multi/free-text payloads preserve existing label/value semantics; a loaded question with no answer remains `No answer` while a missing required question raises the existing error; only missing Job/Branch/categories are loaded once; known null/empty data does not trigger accidental fallback; newly created/updated Answers and phone-country fallback are carried after persistence; MM uses supplied values after later DB edits while live `is_permanent`, MM identifiers and status are honored; no queued profile value can bypass the live completion guard; metadata/storage/ownership deletion is still rejected; completed state skips effects; retry reuses generated PDF and does not revert unrelated profile edits; scalar/standalone callers hydrate absent data correctly; no queued Model/Request; no SELECT after initial preparation except a separately justified newly available source. Assert query sources/boundaries rather than one fragile global query count.

Run affected Feature/Service suites sequentially and full ./vendor/bin/phpunit with APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php. Record actual tests/assertions and logs; do not reuse historical PASS. Self-check against this plan: mapping/identity/error priority, source availability, minimal queries, no transaction reads/loop queries, pure Repository methods, specific local writes, standard queue serialization and preserved independent callers. No formatter, migration, live MM call, deployment, queue clear/drain, worker restart or backend commit/push.

## 6. Execution evidence and self-check (2026-10-09)

- User approved implementation with “triển khai”. Backend source was read against the three canonical `.business-spec` files before changes. No migration, new table, route, request rule, response schema or public error contract was added.
- Docs-first Phase 1 PASS: `~/projects/crs-api-docs/docs/flows/permanent-intake.md` and `docs/operations/queue-and-events.md` updated with scalar prepared MM data, missing-only hydration and mixed live/snapshot ownership. `npm run build` and `git diff --check` PASS. Task-only commit `52e268fc8f5f8c727f041957852150f393c444b1` pushed normally to `origin/main`; docs repository clean afterward.
- Implementation: added scalar `PreparedMatchMakerProfile` and `PreparedMatchMakerAnswer`; extended `PermanentCandidateSyncData` with optional prepared profile/answers/category markers while retaining top-level file IDs and nullable snapshot; captured created/updated answers after transaction; restored JSON `files` access through `input('files')`; worker reuses prepared values and queries only missing question categories when present; live candidate/job/ownership/file/branch/form guards remain; snapshot-null Job path retains independent scalar MM sync.
- MM payload mapping now consumes prepared profile/answer values, preserves raw select-single/select-multi/free-text shapes and question-id enrichment, and keeps legacy model-based answer mapping for non-Permanent flows. `is_permanent` and MM identifiers/status remain live; completion writes only workflow-owned fields. No queued Model/Request or runtime DTO.
- Affected gate PASS: 40 tests / 403 assertions. Full gate PASS: 632 tests / 9,516 assertions, `APP_CONFIG_CACHE=/private/tmp/gap691-no-config-cache.php ./vendor/bin/phpunit`, 02:38.111, 137MB; log `/private/tmp/gap691-009-full.log`. No skips introduced. `php -l` passed for all changed PHP implementation files; final `git diff --check` passed.
- Test impact audit PASS: Feature coverage verifies submitted profile/answer reuse after later Candidate/question changes, missing MM category hydration, zero address/answer reads in the prepared worker path, select mapping and standalone CV-only behavior. Service unit suites remain the only unit coverage; no Job/DTO/Repository unit suite was added.
- Self-check PASS: no database query in loops/transactions, no full queued Eloquent model, no post-build SELECT in prepared processing, Repository access remains data-only, helpers are private, custom exceptions and existing retry/lock/PDF identity semantics are preserved. Deployment, worker availability, storage assets and external MM delivery remain unverified.

Approval gate: [x] user approves this plan; [x] docs-first validation/commit/push PASS; [x] implementation and test-impact audit complete; [x] affected/full suites and self-check PASS.
