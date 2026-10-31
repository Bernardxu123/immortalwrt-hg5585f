#
# OpenWrt package: honk (prebuilt upstream release)
#
# honk is an experimental eBPF transparent proxy engine written in Rust:
#   https://github.com/daeuniverse/honk
#
# This package intentionally ships the official upstream release binary instead
# of building the Rust workspace here:
#   * the aarch64 musl "stock-full" build is self-contained (no libstdcpp), and
#     the stock allocator has a lower RSS peak than mimalloc on small gateways;
#   * it avoids pulling rustup / nightly / bpf-linker into the firmware build;
#   * it pins the exact upstream tag and SHA-256, so the image is reproducible.
#
# "full" contains the Clash API, the native API and the embedded doona UI.
# BTF is provided by the running kernel (CONFIG_KERNEL_DEBUG_INFO_BTF=y);
# vmlinux-btf-builtin only satisfies the virtual +vmlinux-btf dependency.
#
# The values below are the reproducible fallback. CI's update-honk.py refreshes
# them to the newest upstream release (including betas) on manual builds.
#
# This file is free software, licensed under the GNU General Public License v3
# or later.
#

# $(CURDIR) is the buildroot root when this Makefile is included from the
# build system; resolve the package directory before the first include.
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_VERSION:=0.1.0_beta4
PKG_RELEASE:=1
PKGARCH:=aarch64_cortex-a53

PKG_SOURCE:=honk-core-v0.1.0-beta.4-aarch64-unknown-linux-musl-stock-full.tar.gz
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/v0.1.0-beta.4
PKG_HASH:=9b2e30d68b3be216ef7c959f6266ee39ff2291be83fb7b60beeb05254f4becc6

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=PonWrt contributors

HONK_EXTRACT_DIR:=honk-core-v0.1.0-beta.4-aarch64-unknown-linux-musl-stock-full

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=honk eBPF transparent proxy (prebuilt full with doona UI)
  URL:=https://github.com/daeuniverse/honk
  LICENSE:=GPL-3.0-only
  DEPENDS:=+kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +vmlinux-btf +v2ray-geoip +v2ray-geosite \
           +ca-bundle
endef

define Package/honk/description
 honk is an experimental eBPF transparent proxy engine. The honk-core binary
 embeds its eBPF object and the doona dashboard, and needs kernel BTF for CO-RE
 relocations. This package installs the official aarch64 musl stock-full
 release, a procd init script, UCI configuration and a minimal direct-only
 /etc/honk/config.dae. Enable the service only after adding nodes/subscriptions.
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/$(HONK_EXTRACT_DIR)/honk-core $(1)/usr/bin/honk-core
	$(INSTALL_DIR) $(1)/usr/share/licenses/honk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/$(HONK_EXTRACT_DIR)/LICENSE $(1)/usr/share/licenses/honk/LICENSE
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.init $(1)/etc/init.d/honk
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_DIR)/files/honk.config $(1)/etc/config/honk
	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) $(PKG_DIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_DIR) $(1)/usr/share/honk
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat
endef

$(eval $(call BuildPackage,honk))
