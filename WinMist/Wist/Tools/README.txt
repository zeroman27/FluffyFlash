Bundled CLI tools (optional but recommended for end users)

Place executables here so the app works without Homebrew:

  Tools/bin/aria2c
  Tools/bin/cabextract
  Tools/bin/wimlib-imagex
  Tools/bin/chntpw
  Tools/bin/mkisofs   (from Homebrew cdrtools; or genisoimage under the same name)

From the repository root:

  chmod +x Scripts/bundle-mac-cli-tools.sh
  ./Scripts/bundle-mac-cli-tools.sh

Dylibs are stored in ../../EmbeddedCLI/lib (not here) so Xcode does not auto-link the app against OpenSSL/wimlib. See EmbeddedCLI/README.txt.

Licensing: upstream tools are GPL or similar; see THIRD_PARTY.md. Distribution must comply.
