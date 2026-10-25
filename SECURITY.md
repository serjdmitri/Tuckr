# Security Policy

## Reporting a vulnerability

Please report security problems **privately** through GitHub: open the repository's **Security** tab and choose **Report a vulnerability** ([direct link](https://github.com/serjdmitri/Tuckr/security/advisories/new)). Please do not open a public issue for something that could be abused.

I will answer as soon as I can, tell you what happens next, and credit you in the fix if you like.

## What is worth reporting

- Anything that lets another app or person read what Tuckr shows (messages, notes, keys).
- Anything that lets someone push a bad update: updates are signed, and the app refuses an unsigned update or update list (see [docs/UPDATES.md](docs/UPDATES.md)).
- Anything that makes Tuckr run something it should not.

## Third-party code

Report problems in Boring Notch, Talkify, Coucou or a library to its own project (see [CREDITS.md](CREDITS.md)). If it also affects Tuckr, tell me too.
