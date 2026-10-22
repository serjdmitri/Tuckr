# Signing builds so permissions stick

macOS ties Accessibility, Input Monitoring and similar permissions to an app's
code signature. A build signed ad hoc gets a new signature every time it is
rebuilt, so every install asks for those permissions again. A local
self-signed certificate keeps the signature stable.

## Create the certificate (once, about a minute)

1. Open **Keychain Access** (Applications → Utilities).
2. Menu **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Name: `TheBoringCoucouify Local Signing`
4. Identity Type: **Self Signed Root**
5. Certificate Type: **Code Signing**
6. Tick **Let me override defaults**, continue to the validity screen, and set
   it to **3650** days. Keep clicking Continue; the keychain is **login**.
7. Finish.

Check it:

```bash
security find-identity -p codesigning
```

The list should show `TheBoringCoucouify Local Signing`.

## Use it

`scripts/install.sh` finds the certificate by name and signs with it. The first
build may show a keychain prompt asking whether `codesign` may use the key:
choose **Always Allow**. Grant Accessibility and Input Monitoring once after
the first signed install; later installs keep them.
