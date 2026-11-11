# Real-world story matching evaluation — 11 November 2026

> Archived baseline for the earlier generative implementation. See [the replacement evidence evaluation](Story%20matching%20evidence%20evaluation.md) for current code and tests.

The current matcher is not reliable enough. These tests used actual BBC and Sky RSS headlines, summaries, publication dates and source identities, with the real on-device Apple Intelligence model. No model answers were mocked. Matching rules and model instructions were unchanged between runs.

## Results

| Run | Expected matches found | Unrelated pairs incorrectly stacked | Review failures |
| --- | --- | --- | --- |
| initial | 4/9 | 0/12 | 2 |
| repeat (incomplete) | 4/7 | 0/0 | 0 |
| hard-negatives | 0/0 | 1/2 | 0 |

The repeat was interrupted after the Russell Brand review stopped producing output for over a minute. Its counts cover only the seven completed pairs, not all 21 scheduled pairs.

The initial run rejected all twelve negative pairs during candidate filtering; it therefore did not test model discrimination on negative pairs. The separate hard-negative run deliberately sent two unrelated pairs with shared England/Australia title terms to the model. One was incorrectly classified as the same event.

## Expected matches from the initial run

| Event | Sources | Result |
| --- | --- | --- |
| Proposed Manchester United appointment | [BBC](https://www.bbc.co.uk/sport/football/articles/cqvg25pj36mvo?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/football/news/12040/13610949/mauricio-pochettino-man-utd-strike-agreement-with-michael-carricks-potential-successor) | Matched |
| Return to tennis at the United Cup | [BBC](https://www.bbc.co.uk/sport/tennis/articles/cmwyvgvlv2qwo?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/tennis/live-blog/12040/13525472/emma-raducanu-tennis-schedule-next-match-ranking-latest-results-video-and-how-to-watch-live-on-sky-sports-tennis) | Matched |
| Jones previews Japan’s England match | [BBC](https://www.bbc.co.uk/sport/rugby-union/articles/c60mdnld8gvzo?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/rugby-union/news/12040/13611167/eddie-jones-former-england-coach-says-japan-aiming-to-make-twickenham-sky-fall-in-on-steve-borthwicks-distracted-charges) | Model rejected match |
| Death of jockey Tom O’Brien | [BBC](https://www.bbc.co.uk/sport/horse-racing/articles/c3pw48qyjz2ko?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/racing/news/12040/13610855/tom-obrien-cheltenham-festival-winning-jockey-dies-aged-39) | Model rejected match |
| England cancels West Indies Test | [BBC](https://www.bbc.co.uk/sport/cricket/articles/c5zjrympwrlmo?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/cricket/news/12040/13611025/england-scrap-west-indies-test-match-with-red-ball-preparation-ahead-of-womens-ashes-to-take-place-at-home) | Model review failed: Response may contain sensitive or unsafe content |
| Bethell’s injury and tour withdrawal | [BBC](https://www.bbc.co.uk/sport/cricket/articles/ckvg25q0n61jo?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/cricket/news/12040/13610898/jacob-bethell-england-batter-out-of-australia-white-ball-tour-and-doubt-for-test-series-in-south-africa) | Model rejected match |
| Super League expansion vote | [BBC](https://www.bbc.co.uk/sport/rugby-league/articles/cm0l384nz4r6o?at_medium=RSS&at_campaign=rss) · [Sky](https://www.skysports.com/rugby-league/news/12040/13610912/super-league-clubs-vote-to-expand-league-to-15-teams-for-2027-season) | Matched |
| Police response to the Brand/Goldsmith incident | [BBC](https://www.bbc.co.uk/news/articles/cqde1yddwk17o?at_medium=RSS&at_campaign=rss) · [Sky](https://news.sky.com/story/police-made-russell-brand-leave-home-of-his-then-girlfriend-after-violent-incident-13610872) | Matched |
| School threat emails and hoaxes | [BBC](https://www.bbc.co.uk/news/articles/cwz0k79pr8z2o?at_medium=RSS&at_campaign=rss) · [Sky](https://news.sky.com/story/threatening-emails-sent-to-hundreds-of-schools-in-northern-ireland-and-scotland-treated-as-hoaxes-police-say-13610920) | Model review failed: Response may contain sensitive or unsafe content |

## False match and consistency problems

- The model incorrectly stacked [England’s wheelchair rugby win over Australia](https://www.bbc.co.uk/sport/rugby-league/videos/cm5ynyez127xo?at_medium=RSS&at_campaign=rss) with [Bethell’s cricket injury](https://www.skysports.com/cricket/news/12040/13610898/jacob-bethell-england-batter-out-of-australia-white-ball-tour-and-doubt-for-test-series-in-south-africa). Shared countries are insufficient evidence of a shared event, but the structured subject/event checks still accepted it.
- Pochettino matched in the initial run and was rejected in the repeat. O’Brien was rejected initially and matched in the repeat.
- The initial Ashes and school-hoax reviews failed with “Response may contain sensitive or unsafe content”; they fell back to close-headline matching and were missed. The Ashes review succeeded in the repeat.
- This small, manually labelled sample is a diagnostic, not a population accuracy estimate. The Pochettino pair was already included in the prompt and is not a held-out example. The other expected-match pairs were not used to tune the prompt.
- These tests exercise candidate selection and pair review. Existing deterministic regression tests separately check date/feed safeguards and stack anchoring. They do not test final UI rendering.

## Reproduce

The opt-in test deliberately fails on false matches, missed matches or model errors. Ordinary test runs skip live-model evaluation. The snapshot prevents changing feed contents from changing the benchmark. Results are attached as JSON to the Xcode test result bundle.

```sh
TEST_RUNNER_PRECIS_LIVE_STORY_TESTS=1 xcodebuild \
  -project Precis.xcodeproj -scheme Precis -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/PrecisDerivedData \
  CODE_SIGNING_ALLOWED=NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 120 \
  '-only-testing:PrecisTests/StoryMatchingRealWorldTests' test
```

Add `TEST_RUNNER_PRECIS_STORY_HARD_NEGATIVES_ONLY=1` to run only the two hard negatives. The live test class is in `Tests/PrecisDigestTests.swift`; input and recorded output are in `Tests/Fixtures/StoryMatchingRealWorld*.json`.

## Implication

Structured output and stricter instructions did not make this on-device model a dependable final judge. Before enabling broad semantic stacking, use this corpus to evaluate an alternative verifier and an independent subject/sport mismatch check. Keep conservative duplicate handling available as a fallback. Do not relax thresholds to conceal missed matches or treat these live-test failures as passes.
