MATLAB Munki import method
=====================

**NOTE: This has not been looked at since 2015 and may not work anymore**

This is for network licensed Matlab, but you can further edit the `installer_input.txt` 
to suit standalone licenses. You wouldn't need a `network.lic` file in that case.

See [Install Noninteractively (Silent Installation)](http://uk.mathworks.com/help/install/ug/install-noninteractively-silent-installation.html) 
for more information on Matlab silent installation.

1. Clone this repo: `git clone https://github.com/grahampugh/osx-scripts.git; cd osx-scripts/matlab-munki`
or just copy `make-matlab-dmg.sh` into a new directory.
2. Copy/move your latest MATLAB installer ISO into this directory. In this case it is `R2015a-maci64.iso`
3. Edit or swap out your own `installer_input.txt` - enter your File Installation Key
4. Edit or swap out your own `network.lic`
5. `chmod +x make-matlab-dmg.sh`
6. Edit `make-matlab-dmg.sh` if your installer ISO is not `R2015a-maci64.iso`
6. `./make-matlab-dmg.sh`
7. `cp Matlab-R2015a-installer-files.dmg /path/to/munki_repo/pkgs/apps/matlab/`
8. `chmod 744 /path/to/munki_repo/pkgs/apps/matlab/Matlab-R2015a-installer-files.dmg`
9. `cp MATLAB-R2015a-8.5.0.plist /path/to/munki_repo/pkgsinfo/apps/matlab/MATLAB-R2015a-8.5.0.plist`
10. `chmod 644 /path/to/munki_repo/pkgsinfo/apps/matlab/MATLAB-R2015a-8.5.0.plist`
11. Edit `MATLAB-R2015a-8.5.0.plist` if you are using a different ISO, and/or to add your own metadata.
12. `makecatalogs`
