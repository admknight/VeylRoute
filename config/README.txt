TorTunnel Universal v3.5.1 - Configuration
=======================================================

Normally manage app lists through START-HERE.cmd instead of editing them by hand.

bridges.txt
  obfs4 bridge lines used by Tor. Keep this file private and replace bridges if they stop working.

tor-apps.txt
  Apps that use Tor when SelectedAppsOnly is selected during Start.

excluded-apps.txt
  Apps that bypass Tor when SystemWide is selected during Start.

settings.json
  Advanced configuration. Routing mode is NOT stored here; Start asks every session.

Do not put passwords, account credentials, private keys, or authentication tokens in these files.
