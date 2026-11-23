# RBAC matrix — Yusal

Generated 2026-11-22 from the code on `refactor/feature-first` (app) and `master` @ `59606c5` (backend), and from test runs against a local API + MongoDB 8.0.4 (never `eqserver`).

Legend: **ALLOWED** — authorized action succeeds (passes the permission check) · **DENIED** — rejected server-side · **FAILED** — behaviour breaks the documented model · **BLOCKED** — could not be tested · **UNKNOWN** — the intended rule needs a decision.

## 1. The role model as built

There are **no tenants or organizations**. Every account is in one platform, so cross-tenant tests don't apply (N/A); isolation is per account.

Two independent axes:

**A. Back-office role** (`users.admin_role`, `backend/internal/module/client/user/role.go`). The role is read from the database **on every request**; it is never put in a token.

| Role | read | moderate | operate | team |
|---|---|---|---|---|
| `superadmin` | ✅ | ✅ | ✅ | ✅ |
| `moderator` | ✅ | ✅ | | |
| `operator` | ✅ | | ✅ | |
| `viewer` | ✅ | | | |
| *(none — ordinary user)* | | | | |

- read: open the back office, see numbers and lists
- moderate: decide on content and accounts (approve/reject, reports, appeals, verification, restrict, ban, hide, take down)
- operate: featured houses, broadcasts, banned words, push policy
- team: grant/revoke roles, delete accounts, CSV export

The first superadmin comes from `go run ./cmd/setadmin <id>`, or from the "Test Admin" dev persona when `DEV_LOGIN=true DEV_ADMIN=true`.

There is no inheritance chain beyond the table. Hierarchy rules enforced in code:
- Nobody changes, bans or deletes **themselves** (409).
- An account **holding any role** can't be restricted, banned or deleted until a superadmin revokes the role (409). So a moderator can't lock out a superadmin.
- A **restricted** account can't be given a role (409).
- Superadmins are **peers**: any superadmin may revoke any other (UNKNOWN whether intended; see report U-3).

**B. Account state and marketplace identity** (not roles, but they gate actions):

| State | Effect |
|---|---|
| active | normal |
| `restricted` | can sign in and read; can't publish houses/demands, quote, invite or start chats |
| `blocked` (banned) | every `/client/*` and `/admin/*` call → 403 `ACCOUNT_DISABLED`; refresh refused |
| `deleted` | same as blocked; name/email/logins wiped |
| owner / worker / contractor / engineer | marketplace profiles (`/client/profiles`); permissions are **ownership-based** (demand owner vs. quoting provider vs. cooperation partner), not role-based |

App side: `lib/features/shared/model/models.dart` `AdminRoles.perms` mirrors the table exactly, and `Account.can()` gates the UI (`lib/features/admin/page.dart`, `lib/features/me/page.dart:118`).

## 2. Back office: every `/admin` route × every caller

Source: `TestRBACAdminMatrix` (`backend/internal/router/rbac_test.go`), 34 routes × 15 callers = 510 server-side checks.
"Bad token ×7" = no token, garbage, wrong-secret signature, `alg:none`, expired, refresh token used as access token, token for a user ID that doesn't exist (all → 401).
"Disabled ×2" = a deleted account and a banned superadmin, each using a still-unexpired token (→ 403 `ACCOUNT_DISABLED`).
ALLOWED means the request got past authorization; with a fake `:id` it then returns 404/409, which is about the record, not permission.

| Route | Needs | Bad token ×7 | Disabled ×2 | User | Restricted | Viewer | Operator | Moderator | SuperAdmin |
|---|---|---|---|---|---|---|---|---|---|
| `GET /admin/me` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/todo` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/dashboard` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/users` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/team` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/push-policy` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/review-queue` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/demands` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/reports` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/appeals` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/verifications` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/audit` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/accounts/:id` | ? | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/feedback` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/banned-words` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `GET /admin/trends` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/feedback/:id/handled` | read | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ❌ FAILED | ❌ FAILED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/demands/:id/approve` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/demands/:id/reject` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/demands/batch` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/reports/:id/resolve` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/appeals/:id/resolve` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/verifications/:id/resolve` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/accounts/:id/restriction` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/posts/:id/visibility` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/content/post/:id/takedown` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `POST /admin/accounts/:id/ban` | moderate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ✅ ALLOWED |
| `PUT /admin/push-policy` | operate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ⛔ DENIED | ✅ ALLOWED |
| `POST /admin/posts/:id/featured` | operate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ⛔ DENIED | ✅ ALLOWED |
| `POST /admin/broadcast` | operate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ⛔ DENIED | ✅ ALLOWED |
| `PUT /admin/banned-words` | operate | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED | ⛔ DENIED | ✅ ALLOWED |
| `PUT /admin/users/:id/role` | team | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED |
| `POST /admin/accounts/:id/delete` | team | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED |
| `GET /admin/export/users` | team | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ⛔ DENIED | ✅ ALLOWED |

The one FAILED cell: `POST /admin/feedback/:id/handled` needs only `read`, so a **viewer** (documented as read-only) can change state. For an operator it's UNKNOWN which permission feedback triage should need. See report F-5.

## 3. Client resources: ownership × action

Server-side results from `TestRBACCrossUserIsolation`, `TestRBACMassAssignment` and the existing router tests. "Other" = a signed-in account with no relation to the record.

| Resource | Action | Guest | Other user | Owner / party | Moderator+ | Result | Test |
|---|---|---|---|---|---|---|---|
| Account | read public view | ✅ (no email) | ✅ (no email) | ✅ full (`/auth/me`) | ✅ full + email (`/admin/accounts/:id`) | DENIED email to others | IDOR:public-account-email |
| Account | change own name/phone | — | — | ✅ | — | ALLOWED | existing |
| Account | set `admin_role`/`status`/`restricted`/`id` via `PATCH /auth/me` or register | — | ⛔ ignored | ⛔ ignored | — | DENIED | MASS:patch-me-admin_role, MASS:register-admin_role |
| Snapshot (design) | read unpublished | ⛔ | ⛔ 404 | ✅ | — | DENIED | IDOR:read-unpublished-snapshot |
| Snapshot | publish someone else's | — | ⛔ 403 | ✅ | — | DENIED | IDOR:publish-others-snapshot |
| House (post) | edit | — | ⛔ 403 | ✅ | — | DENIED | IDOR:edit-others-post |
| House | hide | — | ⛔ 403 | ✅ | ✅ via client route **(not audited)** | DENIED / FAILED audit | IDOR:hide-others-post, GAP-MOD-CLIENT-UNAUDITED |
| House | read hidden | ⛔ | ⛔ 404 | ✅ | ✅ | DENIED | IDOR:read-hidden-post, IDOR:hidden-in-account-list |
| House | set `featured`/`owner_id` in body | — | — | ⛔ ignored | operate only | DENIED | MASS:post-featured-owner |
| Comment | delete | — | ⛔ 403 | ✅ author or house owner | ✅ **(not audited)** | DENIED / FAILED audit | IDOR:delete-others-comment, IDOR:post-owner-deletes-comment |
| Comment | mark helpful | — | ⛔ 403 | ✅ house owner | — | DENIED | IDOR:mark-helpful-not-owner |
| Cloud backup | read/list/write | — | ⛔ 404 / own copy | ✅ | — | DENIED | `TestBackupsEndToEnd` |
| Conversation | read / send / share phone | — | ⛔ 403 | ✅ two members | — | DENIED | IDOR:read/post-into/share-phone-others-conversation |
| Notification | mark read | — | ⛔ no effect | ✅ | — | DENIED | IDOR:mark-others-notification-read |
| Profile (worker) | overwrite by sending its id | — | ⛔ unchanged | ✅ | — | DENIED | IDOR:overwrite-others-profile |
| Profile | request verification | — | ⛔ 404 | ✅ | resolve: moderate | DENIED | IDOR:verify-others-profile |
| Demand | read draft | ⛔ | ⛔ 404 | ✅ | ✅ read | DENIED | IDOR:read-others-draft-demand |
| Demand | exact address | ⛔ | ⛔ withheld | ✅ + confirmed partner | ✅ | DENIED | IDOR:exact-address-to-stranger |
| Demand | publish / pause / close / share-revoke | — | ⛔ 403 | ✅ | approve/reject: moderate | DENIED | IDOR:publish/pause/close/revoke-share-others-demand |
| Demand | close as the hired partner | — | — | ⛔ 403 | — | DENIED | IDOR:partner-closes-owners-demand |
| Demand | forged `owner_id` in body | — | ⛔ ignored | — | — | DENIED | MASS:demand-owner_id |
| Quote (application) | list on a demand | — | ⛔ 403 | ✅ demand owner | — | DENIED | IDOR:list-quotes-on-others-demand |
| Quote | read / withdraw / not-selected / invite | — | ⛔ 403/404 | ✅ provider or owner | — | DENIED | IDOR:read/withdraw/not-selected/invite… |
| Quote | submit with someone else's profile | — | ⛔ 403 | — | — | DENIED | IDOR:quote-with-others-profile |
| Cooperation | read / confirm / update / work log / review / end | — | ⛔ 403/404 | ✅ owner + provider | — | DENIED | IDOR:*-others-cooperation |
| Cooperation | list on someone else's demand | — | ✅ 200, own only (empty) | ✅ | — | DENIED (filtered) | IDOR:list-cooperations-others-demand |
| Appeal | about someone else's record | — | ⛔ 403 | ✅ own record | resolve: moderate | DENIED | IDOR:appeal-about-others-demand |
| Media (`/media/:id`) | read | ✅ public by 128-bit random URL | ✅ | ✅ | ✅ | UNKNOWN (bearer URL) | report U-1 |
| Feed / house / profile / public demand | read | ✅ | ✅ | ✅ | ✅ | ALLOWED | existing |
| Any write while `restricted` | publish / quote / invite / chat | — | ⛔ `RESTRICTED` | ⛔ | — | DENIED | SESS:restricted-cannot-post-demand, existing |

## 4. App UI vs. backend (Flutter, iOS simulator)

From `integration_test/rbac_roles_test.dart`: 62 checks, all passed. "UI" = what the screen shows; "API" = what the same signed-in app session gets back from the server.

| Check | User | Viewer | Operator | Moderator | SuperAdmin |
|---|---|---|---|---|---|
| UI: "管理后台" entry on Me tab | hidden | shown | shown | shown | shown |
| UI: open `AdminPage` directly (deep link) | lock screen | console | console | console | console |
| UI: More → 群发通知 (broadcast) | — | hidden | shown | hidden | shown |
| UI: More → 导出用户表 (export) | — | hidden | hidden | hidden | shown |
| UI: account → 限制账号 / 封禁 | — | hidden | hidden | shown | shown |
| UI: account → 设置后台角色 / 注销账号 | — | hidden | hidden | hidden | shown |
| API: `GET /admin/todo` | DENIED | ALLOWED | ALLOWED | ALLOWED | ALLOWED |
| API: `POST /admin/accounts/:id/ban` | DENIED | DENIED | DENIED | ALLOWED | ALLOWED |
| API: `GET /admin/export/users` | DENIED | DENIED | DENIED | DENIED | ALLOWED |
| API: `PUT /admin/users/:id/role` | DENIED | DENIED | DENIED | DENIED | ALLOWED |

Every place the UI hides a control, the backend also refuses the call. The UI never hides something the role is allowed to do.
