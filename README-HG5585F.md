# PonWrt for FiberHome HG5585F

`pbs05/ponwrt` 的个人 fork，只针对 **烽火 HG5585F（Airoha AN7581，联通 10G-EPON 非对称）** 做收敛和预设。
上游默认编 12 个机型；这里只编 2 个（CU + CT），并预置了桥接拓扑与 PON 参数。

---

## 1. 上游链条

```
immortalwrt/immortalwrt            ← 底座（有 target/linux/airoha/an7581，但只有 EVB / Nokia / Quantum / Gemtek W1700K）
        │  pbs05 定期 merge（约每周 1-2 次）
        ▼
pbs05/ponwrt                       ← + 21 个 PON/AN7581 内核补丁 + 8 款整机 + 2 个 PON feed + configs/
        │  本仓库 = fork + 纯增量文件
        ▼
Bernardxu123/ponwrt-hg5585f        ← 本仓库
```

**为什么不能直接编 immortalwrt**：immortalwrt 上游的 `target/linux/airoha` 里**没有 FiberHome**，
也没有 `kmod-airoha-xpon` / `airoha-pond` / `luci-app-pon`（那两个 feed 在 `pbs05/` 下）。
编出来是给 Nokia XG-040G / Quantum Q1000K 用的镜像。

**本仓库相对上游的全部改动**（都是新增文件，不与上游任何被跟踪文件重名）：

```
configs/hg5585f-profile.config        12 个 device → 2 个
configs/hg5585f-build.config          ccache / 能力锚点 / offload 依赖
files/                                首启注入 + 看门狗 + 静态 config + banner
scripts/hg5585f/                      配置生成 / 断言 / 产物校验 / 本地干跑工具
.github/workflows/build.yml           只编 an7581 + HG5585F 两个 profile
README-HG5585F.md                     本文件
```

---

## 2. 产物

| 文件 | 用途 |
|---|---|
| `*hg5585f-cu*sysupgrade.itb` | 联通现役机（4 口全内部 PHY） |
| `*hg5585f-ct*sysupgrade.itb` | 试刀机（lan1 是 MaxLinear GPY211C 2.5G） |
| `*hg5585f-{cu,ct}*recovery.itb` | initramfs 救援镜像，U-Boot 可内存启动 |
| `profiles.json` / `config.buildinfo` / `config.full` | 复现依据 |
| `sha256sums.txt` | 校验和 |

**不编** `-usb-sfp` 变体（没有 USB/SFP 硬件；且 `SUPPORTED_DEVICES` 已互相包含，sysupgrade 不会拒绝）。

---

## 3. 编译

### 3.1 GitHub Actions（推荐）

```sh
# 手动触发（默认产出 recovery.itb）
gh workflow run build-hg5585f

# 或打 tag 触发 + 自动发 Release
git tag v2026.10.17-1 && git push origin v2026.10.17-1
```

跑完在 Actions 页面下载 `hg5585f-<commit>-<run_number>` artifact。

耗时参考：冷缓存约 180-230 分钟，ccache 命中后约 70-100 分钟。
若撞 350 分钟超时，用 `build_recovery=false` 关掉 recovery.itb 再跑。

### 3.2 本地

```sh
git clone --depth 1 https://github.com/Bernardxu123/ponwrt-hg5585f.git
cd ponwrt-hg5585f
./scripts/feeds update -a && ./scripts/feeds install -a
sh scripts/hg5585f/gen-config.sh          # 内含 make defconfig + 断言
make -j$(( $(nproc) + 1 ))
```

不需要编译也能验证配置层（Windows 下没有 perl 时用这个）：

```sh
python scripts/hg5585f/kmerge.py configs/an7581.config configs/release.config \
    configs/hg5585f-profile.config configs/hg5585f-build.config > /tmp/c.cfg
python scripts/hg5585f/kmerge.py --check /tmp/c.cfg
```

### 3.3 同步上游

```sh
git fetch upstream
git merge upstream/master     # 我们的改动全是新增文件，正常不会冲突
git push origin master
```

上游 merge 后**不要自动重编**：先看 `git log upstream/master` 里有没有内核/驱动的大改，
再手动 dispatch。出"正式"固件只认 tag。

---

## 4. ⚠️ 刷机前置（本仓库交付不了的部分）

**有 itb 不等于能刷。** 下面这些是硬门槛，缺一项都别动手：

| 前置 | 状态 | 缺了会怎样 |
|---|---|---|
| U-Boot（`firstblock.bin` + `bl31-u-boot.fip`） | 物料已有 | 原厂 boot 不认 `sysupgrade.itb` |
| root（TTL 串口 115200 8N1，3.3V） | **未执行** | 拿不到 `mtd13 factory` 备份 |
| **APONCAL 光模块校准（factory `0x0`，2 KB）** | **未取到** | **PON 完全起不来**，`optical_signal` 恒 0，看门狗也救不了 |
| **MT7916 WiFi EEPROM（factory `0x1000`，4 KB）** | **未取到** | WiFi 起不来（本仓库默认关 WiFi，影响可控） |
| 1 MiB `factory` 镜像写回 | 依赖上一条 | MAC / SN 错，OLT 拒绝注册 |
| LOID | 已知（不预置进固件） | 不注册 |
| 全分区备份（mtd0/2/5/6/9/13） | **未做** | 无法回滚 |

正确顺序：**串口 root → 全量备份 → 刷 U-Boot → 用 `fiberhome-factory` 把原厂 factory 转成 1 MiB → 刷 itb → 首启填 LOID / 上传 board data**。

`factory-1m.bin` **每台设备唯一，不能借用别人的**（里面是光模块校准和 PON SN）。

---

## 5. 首启要做的三件事

登录后 `/etc/banner` 会提示，也可看 `/tmp/hg5585f-setup.log` 确认预设是否生效。

```sh
# 1) 填 LOID（身份数据刻意不预置进固件）
uci set pon.line0_oam.loid='<你的LOID>'
uci commit pon && /etc/init.d/pon reload

# 2) 上传 PON board data：LuCI → 网络 → PON → PON board data
#    （本机 factory 转出来的 1 MiB 镜像）

# 3) 看状态
cat /sys/kernel/debug/airoha-xpon-pon0/line     # lifecycle / service_ready / optical_signal
logread -e pon-watchdog
```

注册成功的标志：`/etc/config/pon` 参数正确 + 日志出现 `EPON LLID0 registered: LLID=0x....` +
`lifecycle: operational` + `service_ready: 1`。

---

## 6. 网络拓扑（预设结果）

```
联通 OLT ── 光纤 ── HG5585F ──LAN1── LibWrt(PPPoE 拨号) ── LAN 192.168.31.0/24

HG5585F 侧：
  pon0                     PON 口（netifd 通过 wan 接口打开，proto=none）
  pon0.995                 8021q VLAN 995 = 联通 INTERNET 业务（原厂 veip0.995 / bridge）
  br-lan                   lan1 lan2 lan3 lan4 + pon0.995
  lan 接口                 static 192.168.1.1/24，无网关、无 DNS、IPv6 关
  DHCP / RA                全部关闭
  WiFi                     radio 默认 disabled（驱动和固件都在）
```

### 为什么 DHCP 必须关（重要）

`br-lan` 桥到 `pon0.995`，意味着**本机发出的 DHCP / RA 会直接进联通接入网**。
OLT 侧普遍开 DHCP snooping + 端口绑定，ONT 口出现非授权 DHCP 服务器时：

- 轻则该 PON 口被置为 err-disable → **整户断网，需要运营商侧恢复**
- 重则 IP 冲突告警影响同一 PON 口的邻居

所以 `files/etc/config/dhcp` 里 `lan` 是 `ignore=1 + dhcpv4/dhcpv6/ra/ndp 全 disabled`，
并且特意保留了 `config odhcpd` 段——`/etc/uci-defaults/15_odhcpd` 检测到该段存在时会
直接退出，不会把 `dhcpv4` 重新设成 `server`。`99-hg5585f-setup` 里还有第三重强制 + 校验。

**刷完第一次上电，先别接光纤**，用 `tcpdump -i br-lan port 67 or port 68` 确认没有 DHCP 报文，
再接光纤。

### 管理地址的安全边界

桥接模式下 `192.168.1.1` 和 `pon0.995` 在**同一个广播域**，OLT 侧理论上能访问它。
而且**无法按入端口过滤**——桥接帧的入端口信息只有 `br_netfilter` + `physdev` 才能看到，
而我们恰恰不装 `kmod-br-netfilter`；`nft` 的 `iifname` 在本机终止的流量里只看到 `br-lan`，
区分不出是 lan1 还是 pon0.995 进来的。

原厂固件也是这个拓扑，风险等级没变，但：**首登立刻设强口令**；若 OLT 侧出现
`192.168.1.0/24` 冲突就换管理网段。

---

## 7. 针对本机做的精准优化

| 优化 | 做法 | 依据 |
|---|---|---|
| 编译收敛 | 12 个 device profile → 2 个 | `PER_DEVICE_ROOTFS=y` 下每个 device 独立内核链接 + 独立 rootfs，10 个是纯浪费 |
| 二次构建加速 | `CONFIG_CCACHE=y`，目录 `$(TOPDIR)/.ccache` | 改 overlay 后重编从 ~3h 降到 ~1h |
| **桥接 flow offload** | 保留 `kmod-nf-conntrack-bridge` + `firewall.flow_offloading=1` + `flow_offloading_hw=1` | ponwrt 给 fw4 打了 `001-add-bridge-flowtable-support.patch`，专门为"防火墙 zone 之外的透明网桥"生成 `table bridge fw4 / flowtable fb`，并把 VLAN 桥端口（`pon0.995`）解析到物理 lower device（`pon0`）交给 PPE/L2B 硬件卸载。**这是本机型唯一能让桥接流量走硬件的通路** |
| 不装 br_netfilter | `kmod-br-netfilter` 保持 not set | 它才是"桥接帧进 iptables"的元凶，与 `nf_conntrack_bridge` 是两回事。装了纯增开销 |
| PON 参数预设 | `mode=epon-10g-1g`、`operator=ctc`、`ge_ports=4` | 原厂 `current_ponmode=EPON_10G`；`ge_ports` 上游默认 1，本机 4 口 |
| 路由能力保留 | firewall4 / dnsmasq-full / ppp / ppp-mod-pppoe / nftables 全留 | 随时能 `uci set network.wan.proto=pppoe` 顶替主路由 |
| WiFi 默认关 | radio `disabled=1`，驱动与固件保留 | 避免与主路由 SSID 冲突；更重要是 WiFi 桥进 br-lan 会把无线客户端的 DHCP 广播送进运营商二层域 |
| NTP | 阿里 / 腾讯 / cn.pool | 桥接模式无外网出口，切路由模式后生效 |
| 看门狗 | `pon-watchdog` 默认启用 | 见下节 |

### 关于 `kmod-nf-conntrack-bridge` 的排查记录

最初打算删掉它求"桥接零开销"，读源码后推翻：

1. 它的 `DEPENDS` 只有 `+kmod-nf-conntrack`，**不拉 `br_netfilter`**（那是独立包 `kmod-br-netfilter`）
2. 它装的是 `nf_conntrack_bridge.ko`
3. ponwrt 的 fw4 补丁依赖它才能生成 bridge flowtable
4. 删掉它 = 把桥接硬件卸载的唯一通路砍掉

结论：**保留**，真正的优化动作是打开 `flow_offloading`。

---

## 8. `pon-watchdog`

针对上游 Issue #42：**联通非对称 10G-EPON、LOID 认证、`epon-10g-1g`**，冷启动 5/5 卡在
`EPON MPCP timeout` 1 Hz 自循环，`service_ready` 恒 0，且不会自愈。

### 判据（为什么不用 `mpcp_state`）

形态 B 下 `mpcp_state` 每 1 秒会在 `registered` 窗口里露面几百毫秒，任何低频采样都会误判为正常。
这里用 `/sys/kernel/debug/airoha-xpon-pon0/line` 的：

- `lifecycle` 稳定在 `operational` 且 `service_ready=1` 才算健康
- 卡死时 `lifecycle` 停在 `wait-line-sync` / `error`，或 `rx_start_count` 以 ~1 Hz 增长

每 10 秒采样，连续 4 次（40 秒）满足条件才动手，开机有 120 秒宽限期。

### 恢复序列（照抄 Issue #42 会失败）

`pon0.995` 是 `br-lan` 成员，持有对 `pon0` 的引用，直接 `modprobe -r` 会 EBUSY。所以：

```
ifdown lan → ip link set pon0 down → pond stop
→ modprobe -r airoha_xpon（失败重试 3 次）→ modprobe airoha_xpon
→ pon reload → pond start → ip link set pon0 up → ifup lan
```

### 永不自动 reboot

这个 bug 的触发条件就是冷启动，重启只会把状态机扔回同一个坑，还会让 OLT 侧看到频繁掉线。
宁可保持"不 ready 但在线可 SSH 排查"。

```sh
logread -e pon-watchdog
cat /tmp/pon-watchdog.log
/etc/init.d/pon-watchdog stop          # 临时停用
/etc/init.d/pon-watchdog disable       # 永久停用
```

---

## 9. 需要实测 A/B 的开关

| 项 | 默认 | 切法 |
|---|---|---|
| EPON OAM profile | `ctc`（Issue #42 同型号真机实测注册成功） | `uci set pon.line0_oam.operator='ieee'` |
| 硬件 flow offload | `flow_offloading_hw=1` | 吞吐反而下降就 `uci set firewall.@defaults[0].flow_offloading_hw='0'` |
| WiFi | 关 | `uci set wireless.radio0.disabled='0'` + `radio1` → `uci commit wireless && wifi up` |
| 切路由模式 | 桥接 | `uci set network.wan.proto='pppoe'` + 填账号 + 开 `dhcp.lan.ignore=0` |
| 看门狗灵敏度 | 40s / delta≥20 | 改 `files/usr/sbin/pon-watchdog` 头部常量 |

**待实测确认的假设**（没实测前不要当结论）：

1. 联通 995 是否真是 `pon0` 上的 802.1q tag → `tcpdump -i pon0 -e -n vlan`
2. `ifdown lan` / `ifup lan` 能否让 netifd 干净重建 `pon0.995` 并挂回 `br-lan`
3. `modprobe -r airoha_xpon` 在 `pond` 停止 + `ifdown lan` 后是否仍 EBUSY
4. `rx_start_count` 在正常注册与故障自循环下的实际斜率（定 `delta≥20/40s` 阈值）
5. `flow_offloading_hw` 在 AN7581 桥接模式下是否真的带上 `flags offload`

---

## 10. 排障速查

```sh
# 预设是否生效
cat /tmp/hg5585f-setup.log

# 桥成员
brctl show br-lan
ip -d link show pon0.995

# 有没有 DHCP 泄漏（接光纤前跑）
tcpdump -i br-lan port 67 or port 68

# flowtable 是否生成
nft list flowtable bridge fw4

# PON 全量状态
cat /sys/kernel/debug/airoha-xpon-pon0/line
cat /sys/kernel/debug/airoha-xpon-pon0/registration
ponctl --device pon0 status

# 看门狗
logread -e pon-watchdog
```

---

## 11. 上游参考

- [pbs05/ponwrt](https://github.com/pbs05/ponwrt) · [Issue #42 10G-EPON 掉线](https://github.com/pbs05/ponwrt/issues/42) · [PR #34 HG5585F-CT PHY](https://github.com/pbs05/ponwrt/pull/34) · [PR #43 HG5585F-CU LED](https://github.com/pbs05/ponwrt/pull/43)
- [pbs05/uboot-an758x](https://github.com/pbs05/uboot-an758x) · [an758x-stock2ubi](https://github.com/pbs05/an758x-stock2ubi) · [fiberhome-factory](https://github.com/pbs05/fiberhome-factory)
- [openwrt-pon-drivers](https://github.com/pbs05/openwrt-pon-drivers) · [openwrt-pon-userspace](https://github.com/pbs05/openwrt-pon-userspace)

> PonWrt 是研发性质的开源项目。刷机、改 PON 相关设置可能导致启动失败、配置或设备专属数据丢失、
> 或无法在 PON 网络注册。刷之前请务必备份原厂固件与设备数据。
> 不得用于未授权的网络接入、冒用/克隆他人设备身份，或干扰运营商网络。
