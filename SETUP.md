# Ambassadors Portal: setup guide

You get one page (`index.html`) that GitHub hosts for free, plus a free Supabase project that holds the data and the logins.
Nobody can see anything without logging in, and only people you invite can log in. Plan on about 30 minutes, once.

## Files
| File | What it is | Goes on GitHub? |
|---|---|---|
| `index.html` | The whole portal | Yes |
| `schema.sql` | Builds the database and the security rules | Yes (no secrets in it) |
| `groupme.sql` | Optional GroupMe posting + next-day reminders | Yes, but see step 7 (edit a copy, do not commit your bot ID) |
| `PRIVATE-import-data.sql` | Your roster + the 10 past events, everyone marked present | **NO. Never upload it.** It has real names. Run it once, then delete it. |

## 1. Make the Supabase project
1. Go to supabase.com, sign up (free), **New project**. Pick a strong database password and save it somewhere. Choose the region closest to you.
2. Wait for it to finish setting up.

## 2. Build the database
1. Left menu **SQL Editor** > **New query**. Paste all of `schema.sql`. Click **Run**. You should see "Success".
2. New query again. Paste all of `PRIVATE-import-data.sql`. **Run**. (It refuses to run twice, so you cannot duplicate people by accident.)

## 3. Authentication settings (important)
Left menu **Authentication**:
- **Sign In / Providers > Email**: turn **Confirm email OFF**. (Invited people create their login straight from their link, and Supabase's free email sender only allows about 2 emails an hour, so it cannot be used for confirmations.)
- Set the **minimum password length to 10**.
- **URL Configuration > Site URL**: your GitHub address from step 5, for example `https://YOURNAME.github.io/ambassadors-portal/`. This is where "forgot password" links send people.

Supabase renames menu items now and then; if a label is slightly different, search for it.
Note: anyone *can* create an account, but an account with no invite sees nothing at all. The database refuses them everything.

## 4. Connect the page to your project
1. In Supabase click **Connect** (top bar) or **Project Settings > API Keys**.
2. Copy the **Project URL** and the **publishable key** (starts with `sb_publishable_`). The publishable key is meant to be public. **Never use the secret / service_role key.**
3. Open `index.html` in any text editor. Near the top of the script, replace `PASTE_YOUR_PROJECT_URL_HERE` and `PASTE_YOUR_PUBLISHABLE_KEY_HERE`. Keep the quotes. Save.

## 5. Put it on GitHub
1. github.com > **New repository**, name it e.g. `ambassadors-portal`. (Public is fine on a free account; the data is not in the repo.)
2. **Add file > Upload files**: upload `index.html`, `schema.sql`, `SETUP.md`. **Not** `PRIVATE-import-data.sql`.
3. **Settings > Pages**: Source = *Deploy from a branch*, Branch = `main`, folder `/ (root)`, Save.
4. After a minute your link is `https://YOURNAME.github.io/ambassadors-portal/`. Put that in the Supabase Site URL (step 3).

## 6. Create the first officer login (you)
1. Make up a long random code, 20+ letters and numbers, e.g. `k7Qp2xVn9RtLw4Zs8Hd3Mc`.
2. SQL Editor > New query (change the name and the code, then Run):
```sql
insert into public.staff (name, role, invite_hash, invite_expires)
values ('Your Name', 'officer',
        encode(sha256(convert_to('k7Qp2xVn9RtLw4Zs8Hd3Mc', 'utf8')), 'hex'),
        now() + interval '2 days');
```
3. Open `https://YOURNAME.github.io/ambassadors-portal/#/join?code=k7Qp2xVn9RtLw4Zs8Hd3Mc`, enter your email and a password. You land on "Hello, Your Name".
4. From now on, inside the portal: **Users > Add a user** creates a one-time invite link for each other officer or moderator. Send the link yourself (text, GroupMe, email). It works once and expires in 7 days.

## 7. GroupMe (optional)
1. Go to dev.groupme.com > **Bots** > create a bot for your group. Copy its **Bot ID**.
2. Supabase **Database > Extensions**: enable `pg_net` (and `pg_cron` if you want automatic next-day reminders).
3. Edit a **copy** of `groupme.sql` on your computer: replace `PASTE_YOUR_GROUPME_BOT_ID_HERE` with the Bot ID. Run it in the SQL Editor. Do not upload this edited copy to GitHub.
4. For automatic reminders, run the `cron.schedule` line that is commented out at the bottom of `groupme.sql`. It posts at about 8-9 AM Central the day before every dated event.
5. Event pages now show **Post to GroupMe**. The Bot ID is stored in the database only and is never sent to the browser.

## Day to day
- Change anything: every event, member, category and attendance row is editable in the portal. Attendance starts as "present" for everyone; untick the box for anyone who was absent.
- 8 people on the sheets were not on your roster, so they are in as **Guests** (Gianni Bustillo, Patrick Dominique, Ethan Sepulveda, Lucas Gualdron, Dominick Slocum, Sean Hirstius, Harving Perez, Gary Hilton). Open a profile to change that, merge, or delete.
- Imported events have no dates. They sit under **Calendar > Needs a date**. Open each one and set it.
- Lost access? Another officer uses **Users > New link**. Forgot password works from the login page (free email is limited, so it can be slow).
- Backups: **Export** downloads CSVs any time. Free Supabase projects pause after a week with no use; just click Restore in Supabase if that happens.

## What I could and could not test
Tested here: the database rules on a real PostgreSQL (86 checks: logged-out people get nothing, non-staff get nothing, invite codes work once and expire, the log cannot be edited, the last officer cannot be locked out), and the whole page in a real browser against a stand-in for Supabase (including phone width). **Not tested:** your actual Supabase project, GitHub Pages, real GroupMe posting and `pg_net`/`pg_cron`. After setup, do a quick check: log in, add a test event, post a test GroupMe message, log out, and confirm that opening the link while logged out shows only the login page.
