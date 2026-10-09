# Pixel Agency Lite

A small macOS app for using **media engines**: pick an engine on your network, choose an operation, set its controls,
drop in an image, run it, and save the result. Lite is the reference client of the
[Media Engine Specification (MES)](../media-engine-spec): everything it does goes through the open MES SDKs, and every
control it shows comes from the engine's own descriptors.

> **Status:** L1 in progress.
> - **L1.1 done:** the run workflow's model (`PixelAgencyRun`) runs every Image operation of the MES mock engine end
>   to end, and passes the MES client conformance suite through `lite-run`.
> - **L1.2 done:** the workflow's views (`PixelAgencyRunUI`) and the sandboxed app. It was checked live against the mock:
>   onboarding, discovery, generate, save, use as input, upscale, select subject, the mask brush, and fill.
> - Next: the developer guide (L1.3). Nothing here is published yet.

![Pixel Agency Lite running Generate on the MES mock engine](docs/images/lite-generate.png)

## Contents

| Path | What |
|---|---|
| `Sources/PixelAgencyRun` | **The run workflow's model** (an open package that Pixel Agency Desktop embeds too):<br/>• engines: discovery, pairing, credentials;<br/>• a run: inputs, controls from the descriptor, progress, results and what happened;<br/>• the session list, the working folder, masks. |
| `Sources/PixelAgencyRunUI` | **The run workflow's views** (MESFormsUI and DesignScaffold):<br/>• engines, operations and this session's runs;<br/>• the canvas: input, progress and previews, results with Save, Share, Use as Input;<br/>• the controls from the descriptor, media slots, the mask brush with "select subject";<br/>• what happened;<br/>• working-folder onboarding. |
| `App/` | **Pixel Agency Lite.app:** a thin SwiftUI app around the workflow.<br/>• Sandboxed: user-selected files, app-scope bookmarks, network client only.<br/>• Declares the `_mes-engine._tcp` Bonjour service.<br/>• Settings: the working folder, and commercial-use only. |
| `Sources/LiteRun` | `lite-run`: the same workflow without a window, for the client conformance suite |
| `Tests/` | The L1 test, at the model level, against the mock engine |

## Building

The MES SDKs come from a sibling checkout of `media-engine-spec` until it's published.

```bash
swift test
```

The app (signed with your development team; see `App/Pixel Agency Lite.xcodeproj`):

```bash
xcodebuild -project "App/Pixel Agency Lite.xcodeproj" -scheme "Pixel Agency Lite" -derivedDataPath build/DerivedData build
```

To try it without a real engine, run the MES mock engine from the `media-engine-spec` checkout. Lite finds it on its own:

```bash
swift run --package-path ../media-engine-spec mes-mock-engine --delay-ms 250
```

## Licence

Apache-2.0 ([LICENSE](LICENSE)).
