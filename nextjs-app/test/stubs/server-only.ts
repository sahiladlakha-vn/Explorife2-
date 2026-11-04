// Test-only stand-in for the "server-only" package. The real package's
// index.js unconditionally throws when actually executed (it relies on
// Next.js's webpack config aliasing it to an empty module for server
// bundles — see node_modules/server-only/index.js and package.json's
// `exports["."]`); under plain Node (vitest, no webpack), importing it
// directly would throw and break every test that imports a module gated by
// `import "server-only"`. vitest.config.ts aliases the "server-only"
// specifier to this empty file so those imports are a no-op in tests,
// mirroring what webpack does for real server bundles.
export {};
