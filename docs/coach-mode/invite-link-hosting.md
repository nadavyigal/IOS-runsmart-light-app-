# Coach invite links — what to host

Story 1.4. This repo does not host the page or the association file. No migration.

The invite URL is `ExternalURLs.inviteBase` plus `/join/{CODE}`:

`https://www.runsmart-ai.com/join/{CODE}`

The host is that constant (`www.runsmart-ai.com`). Do not stand up a second host. The app target already has the Associated Domains entitlement `applinks:www.runsmart-ai.com` in `RunSmart.entitlements` (bundle id `com.runsmart.lite`, team id `8VC4R5M425`).

## apple-app-site-association

Host this JSON at `https://www.runsmart-ai.com/.well-known/apple-app-site-association` (no `.json` suffix). Serve it as `application/json` over HTTPS with no redirect.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["8VC4R5M425.com.runsmart.lite"],
        "components": [
          {
            "/": "/join/*",
            "comment": "Coach Mode invite codes"
          }
        ]
      }
    ]
  }
}
```

## Landing page

`https://www.runsmart-ai.com/join/{CODE}` is what opens when the app is not installed.

- Show a control titled **Get RunSmart**.
- On tap, copy `{CODE}` to the clipboard, then open the App Store listing `https://apps.apple.com/app/id6768297840` (`ExternalURLs.appStore`).
- Do not add a deferred-deep-link SDK. After install and sign-in, the join screen's Paste code control reads the clipboard only when the athlete taps it.

## How to test a link on a device

1. Host the file and the page above.
2. Install a build of this app. A Debug build opens the join screen only when launched with the argument `-enable-coach-mode`. Release leaves Coach Mode off, and an invite link must not open the join screen.
3. On a signed-in athlete, tap `https://www.runsmart-ai.com/join/{CODE}`. The app should open on Join a coach with the code filled in, then the consent screen.
4. Signed out: sign in. The same code should still be on the join screen.
5. A code that is the wrong shape, unknown, inactive, or looked up while offline lands on Join a coach with an empty field and the hint "Enter your coach's code". Typing a code still works.
6. Delete the app, tap the link, tap Get RunSmart, install, sign in, and tap Paste code. The field fills from the code or the full link. The app does not read the clipboard by itself.
