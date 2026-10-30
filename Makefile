# Application Build Configuration metadata
PKG_NAME:=luci-app-devicediscovery
PKG_VERSION:=0.3.6
PKG_RELEASE:=1
PKG_ARCH:=all

BUILD_DIR:=build_dir
OUTPUT_IPK:=$(PKG_NAME)_$(PKG_VERSION)-$(PKG_RELEASE)_$(PKG_ARCH).ipk

.PHONY: all clean ipk

all: ipk

ipk:
	@echo "Building OpenWrt installation package layout..."
	@rm -rf $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/control $(BUILD_DIR)/data
	# 1. Replicate exact relative router target system path layouts
	@mkdir -p $(BUILD_DIR)/data/etc/init.d
	@mkdir -p $(BUILD_DIR)/data/usr/sbin
	@mkdir -p $(BUILD_DIR)/data/usr/share/rpcd/acl.d
	@mkdir -p $(BUILD_DIR)/data/www/luci-static/resources/view/status/include
	# 2. Map files explicitly into their true relative target root directory frames
	@cp files/etc/init.d/devicediscovery $(BUILD_DIR)/data/etc/init.d/ 2>/dev/null || true
	@cp files/usr/sbin/devicediscovery.uc $(BUILD_DIR)/data/usr/sbin/ 2>/dev/null || true
	@cp files/usr/share/rpcd/acl.d/luci-app-devicediscovery.json $(BUILD_DIR)/data/usr/share/rpcd/acl.d/ 2>/dev/null || true
	@cp files/www/luci-static/resources/view/status/include/95_devicediscovery.js $(BUILD_DIR)/data/www/luci-static/resources/view/status/include/ 2>/dev/null || true
	@chmod +x $(BUILD_DIR)/data/usr/sbin/devicediscovery.uc
	@chmod +x $(BUILD_DIR)/data/etc/init.d/devicediscovery
	# 3. Generate the package control instruction descriptor metadata
	@echo "Package: $(PKG_NAME)" > $(BUILD_DIR)/control/control
	@echo "Version: $(PKG_VERSION)-$(PKG_RELEASE)" >> $(BUILD_DIR)/control/control
	@echo "Depends: libc, luasocket, libuci-lua" >> $(BUILD_DIR)/control/control
	@echo "Architecture: $(PKG_ARCH)" >> $(BUILD_DIR)/control/control
	@echo "Maintainer: ppdar" >> $(BUILD_DIR)/control/control
	@echo "Description: Lightweight multicast device discovery service and status panel widget." >> $(BUILD_DIR)/control/control
	# 4. Compress data and control blocks into separate root-level archives side-by-side
	@cd $(BUILD_DIR)/data && tar -czf ../data.tar.gz .
	@cd $(BUILD_DIR)/control && tar -czf ../control.tar.gz control
	# 5. Generate binary package signature block
	@echo "2.0" > $(BUILD_DIR)/debian-binary
	# 6. Build the final .ipk containing debian-binary, control.tar.gz, AND data.tar.gz
	@cd $(BUILD_DIR) && tar -czf ../$(OUTPUT_IPK) debian-binary control.tar.gz data.tar.gz
	@rm -rf $(BUILD_DIR)
	@echo "Successfully generated package output: $(OUTPUT_IPK)"

clean:
	@rm -f *.ipk
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned build workspace metadata paths."
