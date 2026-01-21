# PolicyProgressDialogs.zsh

Launches a swiftDialog mini message window in the bottom right corner whenever a policy runs. This is achieved using a LaunchDaemon that watches for changes to `jamf.log`. Needs to be run as root.

Based on Bart Reardon's [jss-progress.sh](https://github.com/bartreardon/swiftDialog-scripts/blob/main/JamfSelfService/jss-progress.sh).

An icon can be specified using Parameter 4 in a Jamf Pro policy. This will be added to the LaunchDaemon as parameter 1 of the embedded script.

![progress dialog](progress_dialog.png)

## PolicyProgressDialogs-template.zsh

This is the script that is embedded into `PolicyProgressDialogs.zsh` - not designed to be run alone, just here to make editing easier.
