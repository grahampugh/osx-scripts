Check Local Admin
==========

This script runs at startup and syncs the members of AD group in the "Allow Administration By"
field with proper local admins on the Mac.  If no network is found, or it can't see AD,
it leaves everything as is.

If you just want to download the package:
https://raw.githubusercontent.com/grahampugh/osx-scripts/master/check_local_admin/check-local-admin.pkg

To recompile, first install the Luggage:
*  `cd`
*  `git clone https://github.com/unixorn/luggage.git`
*  If you don’t have Xcode command line tools installed, a popup will ask you to install them. Then, repeat previous step
*  `cd luggage`
*  `make bootstrap_files` (needs admin rights)

Then, if you haven't already: 
*  `cd`
*  `git clone https://github.com/grahampugh/osx-scripts.git`
*  `cd check_local_admin`
*  `make pkg`

If you want to recompile this with your own Developer ID, change Line 3 of the Makefile
to match your own Dev ID. If you don't have one, just comment out that line.

If you don't want to force a restart, comment out line 4 of the Makefile.

