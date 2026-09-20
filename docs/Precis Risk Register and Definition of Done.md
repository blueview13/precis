# Precis Risk Register and Definition of Done

## Implementation risks

### Summary layout is harder than expected
Mitigation: prototype the marginalia layout early and test at multiple widths.

### Feed parsing inconsistency across real feeds
Mitigation: normalize feed entries through a single parser abstraction and capture raw plus extracted content.

### CloudKit sync churn
Mitigation: keep the model layer small and ensure sync mapping is explicit and tested.

### App feels generic despite good functionality
Mitigation: use the design review gate and preserve a distinct visual identity throughout implementation.

## Definition of done
The project is ready to move beyond MVP when all of the following are true:
- feeds can be added and refreshed reliably
- article reading is smooth and readable
- summaries are generated locally and displayed with the marginalia treatment
- the app has a clear and distinct design identity
- Smart Folders and search work reliably
- CloudKit sync preserves feed and read-state data across Macs
- background tasks and notifications are stable
- the app passes App Sandbox and Mac App Store readiness checks
- screenshots convey the product clearly and distinctly
