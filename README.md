# Pixel Agency Lite

A small macOS app for using **media engines**: pick an engine on your network, choose an operation, set its controls,
drop in an image, run it, and save the result. Lite is the reference client of the
[Media Engine Specification (MES)](../media-engine-spec): everything it does goes through the open MES SDKs, and every
control it shows comes from the engine's own descriptors.

> **Status:** L1 in progress. **L1.1 done:** the run workflow's model (`PixelAgencyRun`) runs every Image operation of
> the MES mock engine end to end, and passes the MES client conformance suite through `lite-run`. Next: the app and
> its views (L1.2). Nothing here is published yet.

## Contents

| Path | What |
|---|---|
| `Sources/PixelAgencyRun` | **The run workflow's model** (an open package that Pixel Agency Desktop embeds too):<br/>• engines: discovery, pairing, credentials;<br/>• a run: inputs, controls from the descriptor, progress, results and what happened;<br/>• the session list, the working folder, masks. |
| `Sources/PixelAgencyRunUI` | The run workflow's views (L1.2) |
| `Sources/LiteRun` | `lite-run`: the same workflow without a window, for the client conformance suite |
| `Tests/` | The L1 test, at the model level, against the mock engine |

## Building

The MES SDKs come from a sibling checkout of `media-engine-spec` until it's published.

```bash
swift test
```

## Licence

Apache-2.0 ([LICENSE](LICENSE)).
