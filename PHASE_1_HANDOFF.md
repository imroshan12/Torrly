# Phase 1 Handoff: Add TorrDroid's search sites to Torrly

## Completed in Phase 1
- **Provider Updates**: Added `apibay.org`, `lovekat.org`, `knaben.org`, and `limetorrent.store` to `default-providers.json`.
- **Ordering**: Reordered providers to the B3EH+IA sequence, with `Internet Archive` as the final fallback.
- **Core Logic**: Updated `TypeValidation` in `ProviderDefinition.swift` to support multi-pattern matching (String or Array of Strings).
- **Apibay Rules**: Configured `apibay` to use the new multi-pattern validation for its numeric category codes.
- **Migration**: Implemented an idempotent migration in `AppModel.init` that reorders providers and disables known dead mirrors (`kattracker`, `tpb.vip`, `zooqle`, etc.) on first launch.

## Next Steps (Phase 2)
- **Fallback Pool**: Add the remaining mirrors (kattracker, 247prox, tpb.vip, tpb.world, pirateproxy.dev, 1337x.unblockit.link, zooqle, idope, torlock, limetorrents.lol, torrentz2/torrentz2k, bitsearch, torrentdownload.info, the punycode limetorrents, thepibay) to `default-providers.json` with `isEnabled: false`.
- **Rule Verification**: Write/verify rules for these sites based on public templates.
- **Docs & Polish**: Update `README.md` to include the new providers and verify the detail-fetch budget for LimeTorrents.
