USE_PKGBUILD=1
include /usr/local/share/luggage/luggage.make
# PB_EXTRA_ARGS+= --sign "Graham Pugh"
PB_EXTRA_ARGS+= --info "./PackageInfo"

TITLE=check-local-admin
PACKAGE_NAME=check-local-admin
REVERSE_DOMAIN=com.grahamrpugh
INSTALL_SCRIPTS = check_local_admin.sh com.grahamrpugh.checklocaladmin.plist
INSTALL_SCRIPTS_REPO = ./
PAYLOAD=\
  pack-server \
  pack-script-postinstall
  
pack-server:
	@sudo mkdir -p ${WORK_D}/Library/Management/checklocaladmin/
	$(foreach INSTALL_SCRIPT,$(INSTALL_SCRIPTS),sudo ${CP} $(INSTALL_SCRIPTS_REPO)/$(INSTALL_SCRIPT) ${WORK_D}/Library/Management/checklocaladmin/;)
	@sudo chown -R root:wheel ${WORK_D}/Library/Management/checklocaladmin/
	@sudo chmod 755 ${WORK_D}/Library/Management/checklocaladmin/*.sh
