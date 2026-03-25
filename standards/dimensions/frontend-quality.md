# Frontend Quality

## Principle

Every UI state the user can encounter — loading, empty, error, populated — must be intentionally designed, not left as a scaffold.

## Criteria

- [ ] Every data-driven view handles all four states: loading, empty, error, populated
- [ ] Real data fetching with proper loading indicators — no static/placeholder data shipped as "done"
- [ ] State management follows a consistent pattern across the application
- [ ] Form validation with clear, inline error messages — not just console errors
- [ ] Pagination, filtering, and sorting for any list that could exceed a screenful
- [ ] Responsive layout that works on common viewport sizes — not just desktop
- [ ] Keyboard navigation works for all interactive elements
- [ ] Basic accessibility: semantic HTML, alt text, ARIA labels where needed, sufficient color contrast
- [ ] Error boundaries prevent full-page crashes from component failures
- [ ] No `JSON.stringify()` or raw data dumps in user-facing UI

## Common Violations

- Dashboard pages that are redirects or thin wrappers with no actual functionality
- `MetricsSummary` using `JSON.stringify()` to display complex objects
- Pages with no data fetching — static shells that look functional but do nothing
- No loading states — data appears or doesn't with no feedback
- No error states — API failures result in blank screens or cryptic messages
- No empty states — empty lists show nothing instead of helpful guidance
- Forms that submit without validation and show server errors as raw text
- Tables with hundreds of rows and no pagination

## Language-Specific Guidance

**React/TypeScript:**
- Use `Suspense` + `ErrorBoundary` for loading/error states
- Use `react-query`/`tanstack-query` or `SWR` for data fetching with built-in loading/error/empty handling
- Use a form library (`react-hook-form`, `formik`) with schema validation (Zod)
- Use semantic HTML elements (`<nav>`, `<main>`, `<section>`) not just `<div>`

**Vue:**
- Use `<Suspense>` for async components
- Use composables for reusable data fetching patterns
- Use `v-if`/`v-else` chains for state handling: loading → error → empty → populated

**General:**
- Design empty states as first-class UI — they're often the first thing a new user sees
- Use skeleton loaders over spinners for content-heavy pages
- Test with screen readers or accessibility audit tools (axe, Lighthouse)

## Opt-Out Justification

- Backend-only projects with no UI
- CLI tools
- Internal admin tools where UX polish is genuinely not required (but still need loading/error handling)
