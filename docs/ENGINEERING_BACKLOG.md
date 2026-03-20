# Engineering Backlog

This backlog tracks architectural guardrails that are important for coach quality and reliability.

Status values:
- `next`: planned for the next implementation cycle
- `in_progress`: actively being implemented
- `done`: implemented and verified

## 1) Coach Output Schema Guardrail

- **Status:** `next`
- **Why:** Prevent schema drift between LLM response format and UI renderer expectations.
- **Scope:**
  - Define explicit response schema version (e.g., `schema_version`).
  - Validate LLM JSON against allowed section types and required fields before render.
  - Add safe fallback rendering for unknown section types.
- **Acceptance criteria:**
  - Invalid section shapes do not crash UI.
  - Unknown section type renders deterministic fallback card.
  - Prompt contract and renderer contract are documented in one place.

## 2) Async Data Freshness Guardrail (Coach Context)

- **Status:** `next`
- **Why:** Reduce inconsistent coaching caused by prompting before full activity details finish loading.
- **Scope:**
  - Introduce context freshness state for coach generation.
  - Gate "Generate feedback" until minimum context fields are loaded (or show explicit "use current cached data" option).
  - Add UI hint when context is still refreshing.
- **Acceptance criteria:**
  - User can see whether response is based on cached vs fresh data.
  - Race between background refresh and coach generation is observable and controlled.

## 3) History Window Policy Guardrail

- **Status:** `next`
- **Why:** Make intentional difference between stored history and prompt history transparent and maintainable.
- **Scope:**
  - Document and centralize history policy (`store_n`, `prompt_n`).
  - Optional rolling summary for older context beyond prompt window.
  - Expose lightweight debug info in dev mode.
- **Acceptance criteria:**
  - Policy is defined once and referenced by coach pipeline.
  - Engineers can explain why a prior turn was/was not included in prompt context.

## 4) Timezone and Day-Boundary Guardrail

- **Status:** `next`
- **Why:** Prevent "today/week" context errors across travel, DST, and local clock changes.
- **Scope:**
  - Normalize timestamps to UTC in storage logic.
  - Use a single explicit timezone policy for "today" and weekly grouping.
  - Add tests for midnight and DST boundary cases.
- **Acceptance criteria:**
  - "Today" activity grouping remains stable across timezone changes.
  - Week calculations match the chosen timezone policy and are test-covered.

