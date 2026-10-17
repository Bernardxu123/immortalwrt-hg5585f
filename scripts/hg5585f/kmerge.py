#!/usr/bin/env python3
"""本地干跑工具：等价于 scripts/kconfig.pl 的 `+` 合并语义。

为什么需要它
------------
OpenWrt 的 kconfig.pl 是 Perl 脚本，Windows 的 Git Bash 里没有 perl，
所以本地没法直接验证 config 分层是否按预期生效。这个脚本只复刻 `+`
（config_add with mod_plus=0）这一个操作：**按文件顺序，后者无条件覆盖
前者，包括 "# CONFIG_X is not set" 覆盖 "CONFIG_X=y"**。

CI 里仍然用上游的 ./scripts/kconfig.pl（单一真源），本脚本只用于本地
在推 tag 之前快速确认符号层没问题——避免白烧 3 小时 CI。

用法
----
    python scripts/hg5585f/kmerge.py configs/an7581.config \
        configs/release.config configs/hg5585f-profile.config \
        configs/hg5585f-build.config > .config.dryrun

    python scripts/hg5585f/kmerge.py --check .config.dryrun

注意：这不是 make defconfig 的替代品。它不做依赖求解，只做文本层合并。
"""

import re
import sys

RE_SET = re.compile(r"^CONFIG_(.+?)=(.+)$")
RE_UNSET = re.compile(r"^# CONFIG_(.+?) is not set$")


def load(path):
    cfg = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = RE_SET.match(line)
            if m:
                cfg[m.group(1)] = m.group(2)
                continue
            m = RE_UNSET.match(line)
            if m:
                cfg[m.group(1)] = "#undef"
                continue
            if line and not line.startswith("#"):
                print(f"WARNING: can't parse line in {path}: {line}", file=sys.stderr)
    return cfg


def merge(paths):
    cfg = {}
    for path in paths:
        cfg.update(load(path))  # 后者无条件覆盖前者，等价 kconfig.pl 的 `+`
    return cfg


def dump(cfg):
    for key in sorted(cfg):
        val = cfg[key]
        if val in ("#undef", "n"):
            print(f"# CONFIG_{key} is not set")
        else:
            print(f"CONFIG_{key}={val}")


# ---- 断言规则：与 scripts/hg5585f/assert-config.sh 保持一致 ----
WANT_Y = [
    "TARGET_MULTI_PROFILE",
    "TARGET_PER_DEVICE_ROOTFS",
    "TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-cu",
    "TARGET_DEVICE_airoha_an7581_DEVICE_fiberhome_hg5585f-ct",
    "PACKAGE_firewall4",
    "PACKAGE_dnsmasq-full",
    "PACKAGE_ppp-mod-pppoe",
    "PACKAGE_kmod-pppoe",
    "PACKAGE_odhcpd-ipv6only",
    "PACKAGE_ethtool-full",
    "PACKAGE_airoha-ponctl",
    "PACKAGE_airoha-pond",
    "PACKAGE_kmod-airoha-xpon",
    "PACKAGE_luci-app-pon",
    "PACKAGE_kmod-mt7915e",
    "PACKAGE_kmod-mt7916-firmware",
    # 桥接 flow offload 依赖链：conntrack-bridge 装 nf_conntrack_bridge.ko，
    # fw4 的 bridge-family flowtable（ponwrt 自带补丁）靠它才能卸载桥接流量
    "PACKAGE_kmod-nf-conntrack-bridge",
    "PACKAGE_kmod-nf-flow",
    "PACKAGE_kmod-nft-bridge",
    "PACKAGE_kmod-nft-offload",
    "TARGET_ROOTFS_INITRAMFS",
    "TARGET_ROOTFS_SQUASHFS",
    "CCACHE",
]
WANT_UNSET = [
    # 不装 br_netfilter：它才是"桥接帧进 iptables"的元凶，
    # 与 nf_conntrack_bridge（桥接 conntrack + flowtable）是两回事
    "PACKAGE_kmod-br-netfilter",
    "TARGET_airoha_an7583",
    "TARGET_airoha_en7523",
]
DEVICE_PREFIX = "TARGET_DEVICE_airoha_an7581_DEVICE_"
EXPECTED_DEVICES = 2


def check(path):
    cfg = load(path)
    errors = []

    got = sum(1 for k, v in cfg.items() if k.startswith(DEVICE_PREFIX) and v == "y")
    if got != EXPECTED_DEVICES:
        names = sorted(k[len(DEVICE_PREFIX):] for k, v in cfg.items()
                       if k.startswith(DEVICE_PREFIX) and v == "y")
        errors.append(f"device profile 数量 = {got}，期望 {EXPECTED_DEVICES}；实际 {names}")

    for key in WANT_Y:
        if cfg.get(key) != "y":
            errors.append(f"CONFIG_{key} 应为 y，实际 {cfg.get(key, '<缺失>')}")

    for key in WANT_UNSET:
        if cfg.get(key) not in ("#undef", "n", None):
            errors.append(f"CONFIG_{key} 应为 not set，实际 {cfg.get(key)}")

    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1
    print(f"OK: {EXPECTED_DEVICES} 个 device profile，关键包齐备，"
          f"br_netfilter 未启用", file=sys.stderr)
    return 0


def main(argv):
    if len(argv) >= 2 and argv[0] == "--check":
        return check(argv[1])
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    dump(merge(argv))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
