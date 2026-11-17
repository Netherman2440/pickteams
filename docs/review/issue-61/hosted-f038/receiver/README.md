# Real configured candidate: authenticated receiver and startup

The coordinator executed full receiver validation and then booted the real hosted, configured NONPROMOTABLE candidate at source `f0384d6e38673bf0f44423514e7749cb316c83d3`. Independent artifact review is pending; this is not production delivery, live Auth/API/schema validation, or new authenticated stars-data captures.

## Archive and complete payload

Real run `44100639905`, attempt 1; artifact `14336672484`; authenticated external/downloaded ZIP SHA256 `6987795f4ef31e7fbfdbe2f85a5c7c1d316d8755887d3ab10fe120e6bb28391e`. The ZIP was downloaded once. Strict receiver validates the authenticated archive, exact two-file envelope plus `web/`, detached manifest, canonical unique regular paths, all 48 payload file hashes/48,211,398 bytes, source graph and 812 physical source files, public-only compiler/metadata contracts, 14 source copies and 11 public asset references. All recorded synthetic receiver-negative probes rejected; no artifact code executed by receiver. See [receiver verdict](receiver-verdict.json), [manifest](verified-manifest.json), [payload hashes](payload-files.json), [archive authentication](archive-authentication.json), [probes](receiver-negative-probes.json), [verifier](verify_receiver.py), [actual execution](coordinator-receiver-after-worker-exit.log).

Manifest SHA256 `ed5388811156b2406124edb9c2a4c4c7e8e1027c90c8fe56f7426436a939b50b`; payload-tree SHA256 `c3bdd48f9e5d60c6fcdcfbb2705ffca86be8415212a53f6a41c88ced7f97243b`. Configuration commitment comes from reviewed trusted producer using the same validated in-process input for private0600 compiler JSON and sealing. Receiver does **not** recover/recompute configured client values or independently authenticate a backend project from them. Neither raw compiled client/config values nor browser headers appear in this evidence.

## Actual browser execution and frames

The [V3 driver](prove_configured_startup_v3.py) rechecks every extracted payload hash and serves only the verified web directory over loopback. Fresh Chromium 156 context, 390×1000, service workers blocked. It activates Flutter's built-in accessibility DOM control (at −1,−1; not application-state assignment), observes the real landing page, and clicks its visible `Zaloguj` button to reach the login/password form.

- [Actual configured landing frame](configured-unauthenticated-landing.png), SHA256 `4fe64363ab285b8ccacce1d9dde8b3c3cc0b8f67461dff998b713ecfb5cbea6e`.
- [Actual configured login frame](configured-unauthenticated-startup.png), SHA256 `7675c57b0d3ed8045bc512f83613e35770b9b558a280022cce461e89b8ea472d`.
- [Sanitized startup receipt](startup.json) and [actual successful execution](coordinator-configured-startup-v3.log).

Both frames were opened by the coordinator. Seven HTTPS GETs to source-declared public Google Fonts hosts were allowed; all other nonlocal/backend requests and mutations remained blocked. Six HEADs/one GET were deliberately blocked and produced seven expected sanitized console resource errors. There were **zero uncaught page errors**, not zero console messages. No credentials/session/config values/headers read or entered, no live rows or schema visibility probe; browser and owned server stopped. Hash-based URL routing explains path `/` with a fragment after login navigation; screenshot/control observations, not an HTTP status, establish the form appeared.

## Admission and failed-driver provenance

Every receiver/browser invocation used the immediate nonblocking validation lock and unchanged MemAvailable≥2,621,440 KiB gate. The original worker was denied at 2,525,140 KiB before Python ([receipt](worker-admission-denied.log)); do not attribute later verification to that worker. After worker completion, coordinator receiver admitted at 2,835,112 KiB and exited0. Browser attempts admitted at 2,804,472, 2,718,596, and 2,747,796 KiB; no denial retry/poll/helper or lowered gate.

The [first](coordinator-configured-startup.log) and [second](coordinator-configured-startup-v2.log) driver executions failed and are retained. Initial assumptions were wrong: router starts at the marketing landing page rather than directly at login, and Flutter's accessibility activation placeholder cannot receive a pointer click outside the viewport. Initial blanket remote blocking also prevented declared public fonts. Only private proof-driver logic changed: V3 uses the real accessibility control and navigation, and permits narrowly allowlisted public-font reads while preserving the production/data/mutation boundary. Product/artifact bytes were not edited or rebuilt.

## Remaining gates

Independent review must accept these actual bytes, producer/consumer contracts and browser proof. Schema has no existing agent-accessible admin route or prior stars-migration receipt; this is **not** column-absence proof. A separate reviewed stars-only operator step plus disposable SQL/RLS/rollback proof is required; no bulk dbpush, grant changes or old unrelated RPC migration package. Subsequent production acceptance requires a new matching WEB+ANDROID version/native artifact/signature/audit/configuration/provenance/public-download verification. Old release1.0.6/native568f remains immutable and does not contain stars. Current Vercel preview failure is separate from successful Main candidate validation and has no claimed diagnosed cause.
