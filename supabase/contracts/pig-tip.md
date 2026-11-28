# The pig-tip function (app contract)

The written pig tips' server: `supabase/functions/pig-tip`.

- **The request body** is `pig-tip-request.json`.
- **The no-guilt filter** is `no-guilt.json`.

Every call sends:
- `apikey: <the project's publishable key>`, never in `Authorization`;
- `Authorization: Bearer <access token>` of an **anonymous** user, from `POST {base}/auth/v1/signup` with the body `{}`, after the person has agreed to the consent sheet;
- `x-region: <the project's region>`, so the function runs next to its database (see the region guard below).

Anything else gets **401**.

| Call | Body | Answers |
|---|---|---|
| `POST {base}/functions/v1/pig-tip` | the week, exactly as `pig-tip-request.json` allows | **200** `{"tip": "…", "sig": "…"}`, with headers `x-tip-model` and `x-tip-usage: in=<n>;out=<n>`<br>**204**: no tip today<br>**400** `{"code":"invalid_value"}`: the body breaks the contract |
| `POST {base}/functions/v1/pig-tip/report` | `{"tip": "<the text shown>", "reason": "unhelpful" \| "wrong" \| "upsetting" \| "advice" \| "other", "model": "<that tip's x-tip-model>", "sig": "<that tip's sig>"}` | **204**: kept<br>**400** `{"code":"invalid_value"}`: a bad body, or not a tip this server gave, word for word<br>**429** `{"code":"rate_limited"}`: over the day's report limits; not kept |
| `POST {base}/functions/v1/pig-tip/forget` | none | **204**: this anonymous user and their counters are deleted |

**The signature:** each tip comes with `sig`, the server's signature of that tip and its model. The app keeps it with the tip it shows, and sends it back with a report. A report is kept only when the signature matches the tip and the model exactly, so no one can make the server store text it never gave. For a 429, the app thanks the person anyway and doesn't send again.

When the model was asked but no tip went out, the 204 also carries `x-tip-model`, `x-tip-usage` and `x-tip-why`. `x-tip-why` is a short code such as `stop_refusal` or `filter_guilt`, never any text. The staging run reads these headers; the app ignores them.

A **204 from `/pig-tip`** happens when:
- tips are switched off;
- the settings name a region and the function ran anywhere else. The app pins the region with the `x-region` header to avoid it; this 204 carries `x-tip-why: region` and `x-tip-region` (where it ran, or `unknown`);
- the day's cap for everyone is reached;
- this person's tip for the day is used;
- the model declines or fails;
- the filter holds the tip back: over 160 characters; numbers or counts, in digits or words; money signs; the summary's own labels; guilt words; advice topics; or another language.

**503** means the server's own error, including a server without its signing key (then it gives no tips at all). For 204, 503, 429, any other 5xx or a timeout, the app shows its own tip for the day and asks again only the next local day.

**What the server keeps:**
- per anonymous user per UTC day, how many tips and reports they had, deleted after 30 days or with the user;
- the same two counts per day, for the daily limits, deleted after 30 days;
- reported tips (the tip's text, its model and the reason; no one's id), for 90 days.

A scheduled job deletes them daily, whatever the traffic. No week's summary is ever stored or logged, and no tip that was sent is stored, except a reported one as above; logs hold short codes only.
