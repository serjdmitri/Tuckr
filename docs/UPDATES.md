# How Tuckr updates itself, and how it stays safe

Tuckr uses [Sparkle](https://sparkle-project.org). Running copies of the app read the **feed**
(`updater/appcast.xml`, from this repository's `main` branch, over HTTPS), and when it lists a newer
version they offer it. Nothing happens silently unless the user switched on automatic downloads.

## Why a stolen GitHub account cannot push a bad update

Every update has to be signed with Tuckr's **private key**. The matching public key is built into the
app (`SUPublicEDKey` in `boringNotch/Info.plist`). The app refuses:

- a **download** whose signature does not match (checked before it is even unpacked:
  `SUVerifyUpdateBeforeExtraction`);
- a **feed** that is not signed with the key (`SURequireSignedFeed`), so the version, the link and the
  size cannot be changed by someone who only edits the repository.

The private key never leaves the owner's Mac (it is in the login keychain). It is not in the repository.

## Looking after the key

- **Back it up once**, somewhere safe and offline (a password manager's secure note, or an encrypted
  drive): `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x tuckr-update-key`, then
  store that file and delete it from the disk. Without the key, no update can ever be signed again, and
  everyone would have to download a new version by hand.
- **Never** put it in the repository, an email or a chat.
- If it is ever lost or leaked: make a new key, ship a new release by hand whose `SUPublicEDKey` is the
  new one, and tell people to install it from the website.
- Keep two-factor authentication on the GitHub account anyway.

## Making a release

```bash
scripts/release.sh 1.0.1 "What is new"
```

This raises the version and build number, builds, makes `Tuckr-1.0.1.dmg`, signs the feed, publishes
the GitHub release and then the feed. Only after the feed is pushed do running apps see the update.
The repository has to be public for the app to read the feed.
