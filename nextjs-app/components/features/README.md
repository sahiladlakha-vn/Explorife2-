# components/features

Feature-specific components, grouped by domain (e.g. `trips/`, `itinerary/`,
`dashboard/`, `profile/`). These compose `components/ui` primitives and may
be Server or Client Components, but still hold no business logic of their
own — reads go through Server Components calling `lib/db.ts` (via
`lib/server/*`), and mutations go through Server Actions in `lib/server/*`
that call `lib/auth/permissions.ts` before touching Prisma.
