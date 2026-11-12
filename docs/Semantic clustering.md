# Apple-only story clustering

The clustering design now uses Apple's on-device services only. No model weights, tokenizers, trained classifiers, Core ML packages, training scripts, runtime model downloads or hosted inference services are included.

## Processing

- `StoryClusterService` persists article profiles and cluster memberships independently of UI filters. Feed ingestion queues work after saving articles; enriched article content is reconsidered when the library snapshot changes.
- macOS NaturalLanguage sentence embeddings, when already available, help retrieve semantic candidates. These are system-provided assets, not bundled models. Text/entity overlap supplies candidates when embeddings are unavailable.
- Apple Intelligence, through Foundation Models, reviews candidate reports using structured output, source quotes and an event comparison. Explicit conflicting developments remain separate. Generated positive answers also need supporting semantic or entity evidence.
- Up to 12 Apple Intelligence reviews run per update batch. When Apple Intelligence is unavailable, a request fails, or that budget is exhausted, conservative text/entity/event evidence determines whether to stack. Uncertain reports remain separate.
- Original, closest and latest cluster representatives constrain membership. Conservative evidence checks reconcile small neighbouring clusters without additional generative requests.
- Memberships survive restarts. Content changes can split an article from its old cluster. Cancellation preserves committed work, and ingestion batches are serialized. Feed deletion removes entries and prevents stale queued articles from recreating them.
- Saved profiles and assignments from the removed model-based pipeline are discarded when the new service loads; articles are classified again using the Apple-only policy.

The derived index is stored in the app's Application Support directory at `Precis/StoryClusters-v1.json`. English remains the supported language for automatic semantic stacks. The application's existing macOS 26+ Apple-silicon target is unchanged.

## Validation status

At the user's request, no further builds or tests were run after removing the bundled models. Test sources were updated to remove model-specific parity checks and to cover conservative fallback instead of the removed classifiers.

The earlier results in `docs/evaluations/semantic-clustering-results.json` are historical results for the superseded bundled-model implementation. They do **not** validate this Apple-only policy. Its recall and precision have not been measured.

Project references were regenerated with `xcodegen generate` after removing the model files. This regenerates project metadata; it does not build the app or run tests.
