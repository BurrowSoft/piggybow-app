# The pig-tip function (app contract)

The written pig tips' server: `supabase/functions/pig-tip`.

- **The request body** is `pig-tip-request.json`.
- **The no-guilt filter** is `no-guilt.json`.

Every call sends:
- `apikey: <the project's anon key>`;
- `Authorization: Bearer <access token>` of an **anonymous** user, from `POST {base}/auth/v1/signup` with the body `{}`, after the person has agreed to the consent sheet.

Anything else gets **401**.

| Call | Body | Answers |
|---|---|---|
| `POST {base}/functions/v1/pig-tip` | the week, exactly as `pig-tip-request.json` allows | **200** `{"tip": "…"}`, with headers `x-tip-model` and `x-tip-usage: in=<n>;out=<n>`<br>**204**: no tip today<br>**400** `{"code":"invalid_value"}`: the body breaks the contract |
| `POST {base}/functions/v1/pig-tip/report` | `{"tip": "<the text shown>", "reason": "unhelpful" \| "wrong" \| "upsetting" \| "advice" \| "other", "model": "<that tip's x-tip-model>"}` | **204**<br>**400** `{"code":"invalid_value"}` |
| `POST {base}/functions/v1/pig-tip/forget` | none | **204**: this anonymous user and their counters are deleted |

When the model was asked but no tip went out, the 204 also carries `x-tip-model`, `x-tip-usage` and `x-tip-why`. `x-tip-why` is a short code such as `stop_refusal` or `filter_guilt`, never any text. The staging run reads these headers; the app ignores them.

A **204 from `/pig-tip`** happens when:
- tips are switched off;
- the day's cap for everyone is reached;
- this person's tip for the day is used;
- the model declines or fails;
- the filter holds the tip back: over 160 characters; numbers or counts, in digits or words; money signs; the summary's own labels; guilt words; advice topics; or another language.

**503** means the server's own error. For 204, 503, 429, any other 5xx or a timeout, the app shows its own tip for the day and asks again only the next local day.

**What the server keeps:**
- a counter per anonymous user per UTC day, deleted after 30 days or with the user;
- a counter per day;
- reported tips with their reason, for 90 days.

No request body and no tip that was sent is stored or logged.
