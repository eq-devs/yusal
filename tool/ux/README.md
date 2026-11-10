# UX walkthroughs

Playwright scripts that drive the web build as a guest and as the demo owner
and save a screenshot of every screen. Used for the before / after sheets in
`docs/screenshots/ux-2026-11-09/`.

```sh
flutter build web --release
(cd build/web && python3 -m http.server 8765 --bind 127.0.0.1) &

mkdir -p /tmp/yusal-ux && cp tool/ux/*.mjs /tmp/yusal-ux && cd /tmp/yusal-ux
npm init -y && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i playwright   # uses the installed Chrome

node r1.mjs                      # tabs, My houses, Discover, a demand, a house, chat
THEME=night node r1.mjs          # the same at night
W=1280 H=800 node r1.mjs         # the same in a desktop window
node r2.mjs                      # publishing, a pro page, a quote
node sheet.mjs shots/r1-390-day 6 300   # contact sheet
node e2e.mjs                     # end-to-end checks with assertions; exits 1 on a failure
node e2e.mjs chat opinion        # only the flows whose name contains a word
```

`e2e.mjs` runs each flow in a fresh browser (a fresh demo backend) and checks
what is on screen after every step: a guest browsing and being asked to sign
in only when needed; sign-in, language and theme, sign-out; creating a design
by size; the example house and the editor pages; publishing a house; finding
builders from a design; a pro sending a quote; chat; writing an opinion; the
owner's workspace; and the desktop rail. `r1.mjs` and `r2.mjs` only take
screenshots.

`lib.mjs` turns on Flutter's web semantics and taps controls by their
accessibility label, so a control without a label cannot be reached — which
is itself a check. Labels are Russian (`lang: 'ru'` is the default).
