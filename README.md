# Charcoal Browser

An unofficial ARM64 build of Firefox for Android with an OLED-black interface, charcoal panels and a silver private-browsing mask. The application ID is `app.charcoal.browser`, so it can be installed alongside Firefox.

## Build

The source patch targets Mozilla’s Firefox for Android 160.0 release. Run `bash build.sh` on Ubuntu or WSL2 to build and sign locally, or `bash build.sh --unsigned` to sign separately. Keep your release key for in-place updates.
