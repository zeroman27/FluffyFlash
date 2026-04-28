Dylibs for bundled CLI tools (aria2, wimlib, …). This folder lives OUTSIDE the Xcode synchronized "Wist" sources folder so Xcode does not add it to LIBRARY_SEARCH_PATHS and accidentally link the app against OpenSSL/wimlib.

Populated by Scripts/bundle-mac-cli-tools.sh and copied into the .app by the "Embed Tools dylibs" build phase.
