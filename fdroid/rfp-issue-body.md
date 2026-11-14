* [x] The app complies with the [inclusion criteria](https://f-droid.org/docs/Inclusion_Policy/?title=Inclusion_Policy).
* [x] The app is not already listed in the repo or issue tracker (searched by `com.wetcorp.agysha`, "agysha" and "wetcorp": nothing).
* [x] The app has not already been requested (no RFP and no fdroiddata issue found by application ID or name).
* [x] The upstream app source repo contains the app metadata (summary/description/images/changelog) in a Fastlane folder structure: `fastlane/metadata/android/{en-US,ru,fr}/`.
* [x] The original app author has been notified and does not oppose the inclusion. I am the author and maintainer of the project.
* [ ] Optionally donated to support the maintenance of this app in F-Droid.

---------------------

#### APPLICATION ID:

com.wetcorp.agysha

```yaml
Categories:
 - Alarm Clock
 - Habit Tracker
 - Task

License: MIT

AuthorName: Wetidom

WebSite: https://github.com/wxstdo-boop/agysha
SourceCode: https://github.com/wxstdo-boop/agysha

IssueTracker: https://github.com/wxstdo-boop/agysha/issues

AutoName: Agysha

RepoType: git
Repo: https://github.com/wxstdo-boop/agysha.git
```

Why do you want this app added to F-Droid:

> Agysha is a fully offline, privacy-respecting alarm clock with tasks, habits and nutrition tracking. The only network-dependent feature is an optional AI assistant, which is disclosed below as an anti-feature. There is no account, no ads and no trackers. I already maintain a complete, locally validated build recipe (metadata YAML) and I am happy to open a merge request — I can provide the recipe on request.

Summary:

> Alarm clock that won't let you snooze back to sleep

Description:

> Agysha is a free and open-source alarm clock that will not let you go back to sleep. It bundles alarms, tasks, habits, nutrition tracking and a built-in AI assistant in one Material You app.
>
> ALARMS THAT ACTUALLY WORK
>
> * Exact alarms via SCHEDULE_EXACT_ALARM and a foreground service that keeps the process alive
> * Wake tasks: attach a task you must complete to switch the alarm off
> * Survives a reboot — alarms are rescheduled automatically
> * Full-screen intent so the alarm shows above the lock screen
> * Five built-in sounds: classic, default, digital, gentle, nature
>
> TASKS AND HABITS
>
> * Tasks with priority, due date and repeat rules
> * Habits with streaks and daily or total goals
> * Reality checks — an honest "are you lying to yourself?" prompt
> * Swipe to delete, drag to reorder, springy animations
>
> NUTRITION
>
> * Meals, macro goals and 30-day trends
> * Ring progress for every goal
>
> PRIVACY
>
> * PIN lock and an app lock screen
> * Export all your data as a single file
>
> ADA — THE AI ASSISTANT
>
> Ada understands plain speech: "set an alarm for 7 am on weekdays", "remind me tomorrow at 18:30 to buy milk", "count how many calories I ate". She creates, edits and deletes alarms, tasks, habits, checks and meals, and can undo her last action. Ada works in a small window above other apps, and can run on free public model providers with no account of your own. Your API key, if you add one, is stored only on the device.
>
> SYSTEM
>
> * In-app updates (not in the F-Droid build — F-Droid updates it)
> * Material You dynamic colours plus a dark theme
> * Localisation: English, Russian, French
>
> Agysha is MIT-licensed. It contains no ads, no trackers and no Google Play Services.
>
> Requires Android 8.0 (API 26) or newer.

### Anti-feature: NonFreeNet

The optional AI assistant Ada talks to third-party, free public OpenAI-compatible model providers (OpenRouter, Poolside and others). The assistant is off by default and the rest of the app works fully offline. This is disclosed as the `NonFreeNet` anti-feature in the recipe.

### Build notes

* Flutter app. The recipe uses `srclibs: flutter@3.47.5` and `ndk: 28.2.13676358`.
* The F-Droid build passes `--dart-define=AGYSHA_NO_SELF_UPDATE=true`, which disables the built-in GitHub-Releases updater (and hides its update pill), so there is no self-update in the F-Droid build.
* `prebuild` strips `REQUEST_INSTALL_PACKAGES` and `ENFORCE_UPDATE_OWNERSHIP` from the manifest, since they only served the self-updater.
* Two small plugin forks live in `third_party/` directly in the repository (not git submodules).
* I have already validated the recipe locally end to end: `fdroid readmeta` (zero diff from `rewritemeta`), `fdroid checkupdates` (matches tag `v1.6.170+45242`), `fdroid lint` (clean) and a full `fdroid build` step-by-step (unsigned APK ~70 MB, `versionCode=45242`, ABIs arm64-v8a + armeabi-v7a + x86_64).

---

_This request was created by an AI agent (OpenHands) on behalf of the upstream author._
