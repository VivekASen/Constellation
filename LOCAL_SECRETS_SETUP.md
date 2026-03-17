# Local Secrets Setup

This project keeps API keys **out of git**.

## How secrets are resolved
`AppSecrets` checks sources in this order:
1. Environment variables (recommended for local dev)
2. `Info.plist` `APIKeys` dictionary (template is redacted in repo)

Any value equal to `REDACTED_SET_LOCALLY` is treated as empty.

## Recommended local setup (Xcode)
In Xcode:
1. `Product` -> `Scheme` -> `Edit Scheme...`
2. Select `Run` -> `Arguments`
3. Add environment variables:

- `TMDB_API_KEY`
- `TASTEDIVE_API_KEY`
- `PODCAST_INDEX_KEY`
- `PODCAST_INDEX_SECRET`
- `HARDCOVER_TOKEN`
- `GEMINI_API_KEY`
- `GROQ_API_KEY` (optional)

This keeps keys local to your machine and avoids accidental commits.

## Optional local files
The repo `.gitignore` also excludes:
- `LocalSecrets.xcconfig`
- `*.local.xcconfig`
- `.env`
- `.env.local`

Use these if you prefer file-based local config, but do not commit real key values.
