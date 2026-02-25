# AGENTS.md (web/frontend)

Scope: Next.js App Router frontend for clock view, settings, and backend API integration.

## Entry Points And Hotspots

- `src/app/layout.tsx`: app shell and global setup.
- `src/app/page.tsx`: main dashboard page (large client component, heavy state/render logic).
- `src/app/settings/color-schema/page.tsx`: schema editor with drag/reorder and async sync behavior.
- `src/app/globals.css`: shared styling and interaction visuals.

## Conventions

- Use `NEXT_PUBLIC_BACKEND_URL` as backend base URL (`BACKEND_URL` exists only as legacy fallback in some paths).
- Keep API interaction typed and centralized in local helpers (`fetchJson` pattern with timeout and error extraction).
- Prefer extracting reusable UI blocks/hooks when touching `page.tsx` or `settings/color-schema/page.tsx`.
- Preserve existing interaction details (drag indicator line, reorder animation, dynamic timing).

## Anti-Drift Rules

- If backend payload shape changes, update corresponding TypeScript interfaces immediately.
- Avoid introducing new duplicate contract definitions when an existing local interface can be reused.
- Keep user-visible status messaging minimal and aligned with existing UX behavior.

## Commands

- Install: `npm install`
- Dev: `NEXT_PUBLIC_BACKEND_URL=http://localhost:8000 npm run dev`
- Build gate: `npm run build`
- Lint: `npm run lint`

## Verification

- Always run `npm run build` after frontend edits.
- For clock/date navigation changes, verify `<`, `>`, `Today` flows in browser.
- For schema editor changes, verify drag reorder animation and color palette boundaries on desktop and mobile widths.
