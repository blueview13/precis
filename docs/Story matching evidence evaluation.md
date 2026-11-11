# Story matching: evidence classifier evaluation

> Superseded by [the expanded world-news evaluation](Story%20matching%20world%20news%20evaluation.md).

11 November 2026. This supersedes the generative matcher described in [the baseline evaluation](Story%20matching%20real-world%20evaluation.md).

## Implementation

- Replaced generative yes/no judgments with an inspectable, native feature classifier. NaturalLanguage identifies people and organisations; sentence embeddings supply corroborating semantic similarity.
- Each article is profiled once per bounded content version. Profiles record headline terms, opening text, named subjects, the headline’s action, and publisher URL sport context. Existing extracted text is used when available; matching does not download article pages.
- Different known sports, different known developments, or different headline main people veto a match. Shared countries and generic sports terms receive little weight. A semantic vector score cannot create a stack on its own.
- Matching action and subject evidence must be supported by text similarity or strong independent lexical corroboration. Unknown cases remain separate. This is a conservative rule-based pair classifier, not a newly trained cross-encoder.
- Existing global library matching, content-keyed session caches, and primary-article anchoring remain in place. Updates are published in batches to avoid hundreds of list redraws.
- Identical titles now also require compatible sport context and publication dates within 72 hours. Canonical article URL identity remains definitive.

## Benchmark and acceptance criteria

The frozen benchmark contains 37 actual BBC/Sky RSS articles and all 342 cross-publisher pairs. Labels identify 13 same-development pairs and 329 unrelated pairs. No titles or summaries were invented. Article source URLs, timestamps, event labels and split assignments are stored in `Tests/Fixtures/StoryMatchingBenchmark.json`.

Four new business/general-news events were labelled before evaluating the new classifier. They were not used to change its scoring thresholds or action rules after their results were seen. They are a small holdout, not proof of broad news coverage. Every pair involving a fresh article is assigned to that split.

| Split | Pairs | Genuine matches found | False stacks |
| --- | ---: | ---: | ---: |
| development | 210 | 9/9 | 0/201 |
| holdout | 132 | 1/4 | 0/128 |

Across the full sample, the classifier found 10 of 13 genuine matches and made no false stacks among 329 unrelated pairs. Seventeen candidate pairs reached evidence review; the other 325 were rejected by candidate filtering. Only five of the reviewed pairs were negatives, so the large negative count must not be interpreted as a broad model-discrimination benchmark.

The first benchmark run failed its original perfect-recall assertion because it missed three holdout matches. That result is retained in `StoryMatchingEvidenceResults.json`. The test now explicitly checks the intended safety criteria: no false stacks and no lost established development-set matches. Holdout misses remain measured and reported; they were not relabelled, hidden or converted into successful matches.

Three successive evaluations produced identical pair decisions. The final run built successfully and passed 14 focused regression tests plus the precision/regression benchmark. The final benchmark test body took approximately half a second on this machine; this excludes app startup and compilation. No generative model was invoked by matching.

## Remaining misses

| Pair | Why it remained separate | Sources |
| --- | --- | --- |
| US allegations concerning RAF Fairford | Insufficient shared event evidence despite matching location | [BBC](https://www.bbc.co.uk/news/articles/c3rryrryk59zo?at_medium=RSS&at_campaign=rss) · [Sky](https://news.sky.com/story/us-charges-three-men-allegedly-linked-to-raf-fairford-incident-13610779) |
| Nvidia share-price decline | Different headline wording; title anchors did not meet the evidence gate | [BBC](https://www.bbc.co.uk/news/articles/c6zxjx01vyleo?at_medium=RSS&at_campaign=rss) · [Sky](https://news.sky.com/story/jensen-huang-nvidias-value-plummets-430bn-in-two-days-as-ceo-urged-to-quit-13610814) |
| Anthropic proposed listing | The short BBC text names Claude while Sky names Anthropic; insufficient shared candidate terms | [BBC](https://www.bbc.co.uk/news/articles/crpdgd723x2zo?at_medium=RSS&at_campaign=rss) · [Sky](https://news.sky.com/story/claude-maker-anthropic-seeks-14trn-valuation-amid-worry-over-ai-investment-13610628) |

The hard-negative wheelchair rugby/cricket injury pair now stays separate because its sports conflict. The held-out Nvidia investigation and Nvidia share-price stories also remain separate despite sharing a company and substantial vocabulary.

The holdout found only one of four positive matches. This implementation improves the known failures and avoids false stacks in this sample, but does not establish high recall on unfamiliar stories. A future learned same-event classifier or fuller opening-text extraction should be evaluated on a new untouched holdout, rather than tuned against these four pairs and described as independently validated.

## Reproduce

```sh
TEST_RUNNER_PRECIS_STORY_BENCHMARK=1 xcodebuild \
  -project Precis.xcodeproj -scheme Precis -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/PrecisDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  '-only-testing:PrecisTests/StoryMatchingRegressionTests' \
  '-only-testing:PrecisTests/StoryMatchingRealWorldTests' test
```

Pair decisions, explanations and semantic scores are attached to the Xcode test results as JSON. The benchmark is opt-in because it loads the installed NaturalLanguage embedding asset. Missing embeddings use stricter lexical corroboration, covered separately by a regression test. No external API or new model download is required.
