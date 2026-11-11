# Expanded story matching and world-news evaluation

11 November 2026. This supersedes [the previous evidence evaluation](Story%20matching%20evidence%20evaluation.md).

## Changes

- Added native lemmatisation, so inflected verbs and nouns such as “resigns” and “resignation” can support the same action. Explicit spelling aliases cover cases the lemmatiser leaves unresolved.
- Added evidence for institutions, named locations, officeholders and actions described across the headline and opening text. Names that occur only in the opening can corroborate a headline’s role/country description.
- Compare combined text, headline-to-headline and opening-to-opening embeddings. A supporting vector score still cannot override subject, action, sport or commentary conflicts.
- Expanded action handling for international news: resignations, talks, escapes, relocations, court decisions, arrests, accusations, bans and demonstrations. Headline actions outrank their causes; a relocation after threats is not classified as a threat report.
- Independent checks distinguish internal company investigations from criminal investigations, political demonstrations from memorial marches, acquittals from convictions, and death threats from death reports. Reporting sources such as “Trump says” are not automatically treated as the main person.
- Countries receive weak weight through a locale-derived country vocabulary. Geographic evidence needs corroborating action and topic/venue evidence; a country alone is not enough.
- Candidate features are cached and computed on the matching actor so the new language processing does not block the list’s main actor. Matching uses existing article text and installed NaturalLanguage assets; no hosted API is involved.

## Frozen articles and labels

The world-news corpus contains 44 actual RSS articles from BBC, Sky, The Guardian, Al Jazeera, NPR, Deutsche Welle and France 24. Sources, publication timestamps, original headlines/summaries and event labels are stored in `Tests/Fixtures/StoryMatchingWorldNews.json`.

All 808 cross-publisher comparisons are labelled: 26 expected matching pairs and 782 non-matching pairs. This represents 24 underlying event labels, 16 of which have reports from multiple publishers. Positive pairs are not independent events: four reports of one event produce six positive comparisons. The counts must not be described as 26 independent news stories.

## Measured results

| World-news run | Matching pairs found | False matches |
| --- | ---: | ---: |
| baseline | 1/26 | 2/782 |
| first-reserved-evaluation | 23/26 | 2/782 |
| final | 24/26 | 0/782 |

The final original sports/business benchmark also improved from 10/13 matching pairs to 12/13, with no false matches among its 329 negative pairs. Across both suites, 1,150 pair comparisons were exercised; some news events overlap between suites, so they are not 1,150 independent stories.

### Reserved-split limitations

The world corpus was split by event using fixed seed 7206 before baseline evaluation: 371 development comparisons with 17 positive pairs, and 437 reserved comparisons with nine positive pairs. The original matcher recognised 0/17 development positives and 1/9 reserved positives. One reserved event, the Nvidia FBI investigation, had already appeared in the earlier benchmark and therefore was not an unseen event.

The first reserved evaluation after general improvements found 6/9 positives but incorrectly joined a Polish nationalist march with a separate silent march for shooting victims. Those failures informed the memorial-purpose check and separate headline/opening embeddings. The final 7/9 reserved result is therefore a regression result, not a fresh blind estimate. The final development result is 17/17.

No acceptance thresholds or expected labels were relaxed after observing scores. The world acceptance targets were fixed beforehand at zero false matches, at least 75% total positive recall, and at least 70% reserved positive recall. The original suite continues to require all nine previously established development matches. Both suites now pass those criteria.

## Actual stacks, not only pairs

The tests also assemble stacks using the application’s primary-only grouping algorithm. The world articles produce 25 stacks for 24 event labels, with zero stacks containing different labelled events. One strike report stays separate, explaining the extra stack. The original corpus likewise produces one extra stack because the Claude/Anthropic pair remains unmatched.

The build, 20 focused regression tests, and both benchmark suites passed. The world benchmark including assembly took about 3.6 seconds on this machine, excluding app startup and build time. Pair decisions were unchanged between the refined and final world runs.

## Examples covered

| Event | Matched pairs | Sources |
| --- | ---: | --- |
| spain strike | 4/6 | [guardianWorld](https://www.theguardian.com/world/2026/nov/11/spain-general-strike-housing-costs) · [nprWorld](https://www.npr.org/2026/11/11/nx-s1-6037314/spain-general-strike) · [aljazeera](https://www.aljazeera.com/video/newsfeed/2026/11/11/spain-faces-nationwide-protests-over-soaring-housing-costs?traffic_source=rss) · [france24](https://www.france24.com/en/general-strike-over-housing-brings-out-tens-of-thousands-in-spain) |
| ukraine talks | 6/6 | [bbcWorld](https://www.bbc.co.uk/news/articles/ck792we7zrz4o?at_medium=RSS&at_campaign=rss) · [guardianWorld](https://www.theguardian.com/world/2026/nov/11/ukraine-talks-in-abu-dhabi-bring-progress-on-prisoners-but-not-on-peace) · [nprWorld](https://www.npr.org/2026/11/11/g-s1-152954/russia-ukraine-war-talks) · [aljazeera](https://www.aljazeera.com/video/newsfeed/2026/11/11/russia-ukraine-talks-in-uae-secure-major-prisoner-exchange-deal?traffic_source=rss) |
| kenya ebola discharge | 1/1 | [bbcWorld](https://www.bbc.co.uk/news/articles/cwe9kzv0g0v7o?at_medium=RSS&at_campaign=rss) · [aljazeera](https://www.aljazeera.com/news/2026/11/11/kenya-discharges-last-ebola-patient?traffic_source=rss) |
| indonesia resignation | 1/1 | [bbcWorld](https://www.bbc.co.uk/news/articles/cmvgxgz87qqro?at_medium=RSS&at_campaign=rss) · [nprWorld](https://www.npr.org/2026/11/10/g-s1-152788/indonesias-vp-offers-resignation-as-questions-mount-over-his-eligibility) |
| argentina escape | 1/1 | [bbcWorld](https://www.bbc.co.uk/news/articles/c933gn6710lyo?at_medium=RSS&at_campaign=rss) · [guardianWorld](https://www.theguardian.com/world/2026/nov/11/red-brigades-leonardo-bertulazzi-escapes-house-arrest-argentina) |
| bessent relocation | 1/1 | [bbcWorld](https://www.bbc.co.uk/news/articles/cqr7gr0010r2o?at_medium=RSS&at_campaign=rss) · [guardianWorld](https://www.theguardian.com/us-news/2026/nov/11/us-treasury-chief-scott-bessent-moves-military-base-iran-threats) |
| gay law ruling | 1/1 | [skyWorld](https://news.sky.com/story/uk-court-overturns-trinidad-and-tobago-law-criminalising-homosexual-sex-13610702) · [dwWorld](https://www.dw.com/en/uk-privy-council-overrules-trinidad-and-tobago-gay-sex-law/a-79912163?maca=en-rss-en-world-4025-rdf) |
| meta election fine | 1/1 | [dwWorld](https://www.dw.com/en/brazil-electoral-court-fines-meta-sees-no-deliberate-election-bias/a-79920780?maca=en-rss-en-world-4025-rdf) · [france24](https://www.france24.com/en/brazil-electoral-court-fines-meta-1-3-mn-sees-no-deliberate-election-bias) |
| russia france bans | 1/1 | [aljazeera](https://www.aljazeera.com/news/2026/11/11/russia-bans-two-french-lawmakers-two-journalists-in-tit-for-tat-move?traffic_source=rss) · [france24](https://www.france24.com/en/europe/20261111-russia-bans-two-french-lawmakers-and-two-journalists-from-entry) |
| hegseth impeachment blocked | 1/1 | [bbcWorld](https://www.bbc.co.uk/news/articles/cxly4y5jzl0qo?at_medium=RSS&at_campaign=rss) · [france24](https://www.france24.com/en/us-house-votes-to-derail-impeachment-of-defense-secretary-hegseth) |
| poland nationalist march | 1/1 | [aljazeera](https://www.aljazeera.com/news/2026/11/11/tens-of-thousands-join-polands-nationalist-independence-day-march?traffic_source=rss) · [france24](https://www.france24.com/en/tens-of-thousands-attend-polish-nationalist-march-days-afer-shootings-1) |
| us soldier spying arrest | 1/1 | [dwWorld](https://www.dw.com/en/british-counterterrorism-police-arrest-us-soldier-accused-of-spying-on-behalf-of-russia/a-79913240?maca=en-rss-en-world-4025-rdf) · [bbcUK](https://www.bbc.co.uk/news/articles/c6d7q77xgw0vo?at_medium=RSS&at_campaign=rss) |
| cyprus soldier charged | 1/1 | [guardianWorld](https://www.theguardian.com/uk-news/2026/nov/11/scots-soldier-charged-with-of-army-servicewoman-in-cyprus) · [skyUK](https://news.sky.com/story/british-soldier-charged-with-rape-of-woman-in-cyprus-13611160) |
| nvidia company investigation | 1/1 | [guardianWorld](https://www.theguardian.com/us-news/2026/nov/08/nvidia-jensen-huang-investigation) · [bbcBusiness](https://www.bbc.co.uk/news/articles/ck1wvwwl3x0go?at_medium=RSS&at_campaign=rss) |
| nvidia fbi investigation | 1/1 | [skyWorld](https://news.sky.com/story/fbi-to-investigate-nvidia-ceo-over-affair-with-alleged-chinese-spy-trump-says-13610382) · [bbcBusiness](https://www.bbc.co.uk/news/articles/cqg7x7dpvym8o?at_medium=RSS&at_campaign=rss) |
| nvidia share price | 1/1 | [skyBusiness](https://news.sky.com/story/jensen-huang-nvidias-value-plummets-430bn-in-two-days-as-ceo-urged-to-quit-13610814) · [bbcBusiness](https://www.bbc.co.uk/news/articles/c6zxjx01vyleo?at_medium=RSS&at_campaign=rss) |

## Remaining gaps

- Two pair comparisons involving Al Jazeera’s report on Spain’s housing strike still lack enough corroborating evidence. The report remains a separate stack rather than weakening the general gate.
- The original business pair still misses a listing story whose short BBC text names the Claude product while Sky names its maker, Anthropic. Explicit entity linking or fuller article context would be needed to establish the relationship safely.
- This is a small, manually labelled, English-language sample. Most negatives are filtered before evidence scoring: 45 world pairs reached review, including 19 negatives. Strong population accuracy or reliability across all subjects is not established.
- The action vocabulary and subject/location extraction remain imperfect. New evaluations should reserve new events before scoring, rather than treating corrected regression fixtures as unseen validation.

## Reproduce

```sh
TEST_RUNNER_PRECIS_STORY_BENCHMARK=1 \
TEST_RUNNER_PRECIS_STORY_FIXTURE=StoryMatchingWorldNews.json \
TEST_RUNNER_PRECIS_STORY_RESULTS=/tmp/precis-world-results.json \
xcodebuild -project Precis.xcodeproj -scheme Precis \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/PrecisDerivedData CODE_SIGNING_ALLOWED=NO \
  '-only-testing:PrecisTests/StoryMatchingRegressionTests' \
  '-only-testing:PrecisTests/StoryMatchingRealWorldTests' test
```

Omit `TEST_RUNNER_PRECIS_STORY_FIXTURE` to rerun the original benchmark. The result path saves pair decisions and a sibling `.groups.json` file with actual stacks. JSON reports are also attached to the Xcode result bundle. Baseline errors, first-reserved errors and final decisions are preserved in `Tests/Fixtures/StoryMatchingExtendedResults.json`.
