# PonWrt for FiberHome HG5585F

`pbs05/ponwrt` 的个人 fork，只针对 **烽火 HG5585F（Airoha AN7581，联通 10G-EPON 非对称）** 做收敛和预设。
上游默认编 12 个机型；这里只编 2 个（CU + CT），默认配置为 **PPPoE 主路由**（不是透明桥）。

---

## 1. 上游链条

```
immortalwrt/immortalwrt            ← 底座
        │  pbs05 定期 merge
        ▼
pbs05/ponwrt                       ← PON/AN7581 内核补丁 + 8 款整机 + PON feeds
        │  本仓库 = fork + 纯增量文件
        ▼
Bernardxu123/ponwrt-hg5585f
```

**为什么不能直接编 immortalwrt**：immortalwrt 上游的 `target/linux/airoha` 里没有 FiberHome，
也没有 `kmod-airoha-xpon` / `airoha-pond` / `luci-app-pon`（PON 的两个 feed 在 `pbs05/` 下）。

**本仓库相对上游的改动**：

```
configs/hg5585f-profile.config        12 个 device → 2 个
configs/hg5585f-build.config          ccache / 能力锚点 / 去掉 UPnP / zram / PON 栈
files/                                首启注入 + 看门狗 + 绑核/温度服务 + sysctl 调优 + 静态 config + banner
                                      （QWRT 逆向借鉴清单见《QWRT-分析/优化借鉴与落地.md》）
scripts/hg5585f/                      配置生成 / 断言 / 产物校验 / 本地干跑
.github/workflows/build.yml           只编 an7581 + HG5585F 两个 profile
README-HG5585F.md                     本文件
```

---

## 2. 产物

| 文件 | 用途 |
|---|---|
| `*hg5585f-cu*sysupgrade.itb` | 联通现役机（4 口全内部 PHY，4×1G） |
| `*hg5585f-ct*sysupgrade.itb` | 试刀机（lan1 是 MaxLinear GPY211C 2.5G） |
| `*hg5585f-{cu,ct}*recovery.itb` | initramfs 救援镜像，U-Boot 可内存启动 |
| `profiles.json` / `config.buildinfo` / `config.full` | 复现依据 |
| `sha256sums.txt` | 校验和 |

**不编** `-usb-sfp` 变体（没有 USB/SFP 硬件；`SUPPORTED_DEVICES` 已互相包含）。

---

## 3. 编译

### 3.1 GitHub Actions

```sh
gh workflow run build-hg5585f
# 或打 tag 触发 + 自动发 Release
git tag v2026.10.17-2 && git push origin v2026.10.17-2
```

**2026-10-17 构建失败记录（已修）**：`configs/release.config` 里的
`CONFIG_PACKAGE_luci-app-upnp=y` 拉起了 `miniupnpd`，而 ImmortalWrt packages feed
的 `020-descr-filter-fix.patch` 对 `miniupnpd 2.3.11` 已打不上（5/7 hunks 失败），
编译在最后的包阶段失败。现在 `configs/hg5585f-build.config` 作为最后一层显式关掉
`luci-app-upnp` / `miniupnpd-*`，并在 `scripts/hg5585f/assert-config.sh` 里加了断言。
代理出口本来也不该开 UPnP。

### 3.2 本地

```sh
git clone --depth 1 https://github.com/Bernardxu123/ponwrt-hg5585f.git
cd ponwrt-hg5585f
./scripts/feeds update -a && ./scripts/feeds install -a
sh scripts/hg5585f/gen-config.sh          # 内含 make defconfig + 断言
make -j$(( $(nproc) + 1 ))
```

不需要编译也能验证配置层：

```sh
python scripts/hg5585f/kmerge.py configs/an7581.config configs/release.config \
    configs/hg5585f-profile.config configs/hg5585f-build.config > /tmp/c.cfg
python scripts/hg5585f/kmerge.py --check /tmp/c.cfg
```

### 3.3 同步上游

```sh
git fetch upstream
git merge upstream/master     # 改动以新增文件为主
git push origin master
```

上游 merge 后不要自动重编：先看 `git log upstream/master` 有没有内核/驱动大改，再手动 dispatch。
出正式固件只认 tag。

---

## 4. 刷机前置（本仓库交付不了的部分）

| 前置 | 状态 | 缺了会怎样 |
|---|---|---|
| U-Boot（`firstblock.bin` + `bl31-u-boot.fip`） | 物料已有 | 原厂 boot 不认 `sysupgrade.itb` |
| root（TTL 串口 115200 8N1，3.3V） | 未执行 | 拿不到 `mtd13 factory` 备份 |
| **APONCAL 光模块校准（factory `0x0`，2 KB）** | **未取到** | **PON 完全起不来** |
| **MT7916 WiFi EEPROM（factory `0x1000`，4 KB）** | **未取到** | WiFi 起不来（默认关，影响可控） |
| 1 MiB `factory` 镜像写回 | 依赖上一条 | MAC / SN 错，OLT 拒绝注册 |
| LOID | 已知（不预置） | 不注册 |
| PPPoE 账号 | 已知（不预置） | 拨不上号 |
| 全分区备份（mtd0/2/5/6/9/13） | **未做** | 无法回滚 |

正确顺序：**串口 root → 全量备份 → 刷 U-Boot → 用 `fiberhome-factory` 把原厂 factory 转成 1 MiB → 刷 itb → 首启填 LOID / 上传 board data / 填 PPPoE**。

`factory-1m.bin` **每台设备唯一，不能借用别人的**。

---

## 5. 首启要做的 4 件事

登录 `http://192.168.31.1`（LAN 内）或 SSH，按顺序：

```sh
# 1) LOID
uci set pon.line0_oam.loid='<你的LOID>'
uci commit pon && /etc/init.d/pon reload

# 2) PON board data：LuCI → 网络 → PON → PON board data
#    上传本机 factory 转出来的 1 MiB 镜像

# 3) PPPoE 账号
uci set network.wan.username='<宽带账号>'
uci set network.wan.password='<宽带密码>'
uci commit network && /etc/init.d/network restart

# 4) 看状态
ifstatus wan
cat /sys/kernel/debug/airoha-xpon-pon0/line
cat /sys/kernel/debug/airoha-xpon-pon0/registration
logread -e pon-watchdog
```

注册成功的标志：`/etc/config/pon` 参数正确 + 日志出现 `EPON LLID0 registered: LLID=0x....` +
`lifecycle: operational` + `service_ready: 1` + `ifstatus wan` 有 IPv4 地址。

---

## 6. 网络拓扑（主路由模式）

```
联通 OLT ── 光纤 ── HG5585F（PPPoE + NAT + DHCP + 防火墙）
                         │
                         ├─ lan1 ── 小米 BE6500 Pro（AP）
                         ├─ lan2..4 ── PC / 平板 / 预留
                         └─ WiFi 默认关闭
```

HG5585F 侧：

```
pon0                 PON 口
pon0.995             802.1q VLAN 995 = 联通 INTERNET（WAN）
wan                  proto=pppoe / device=pon0.995 / MTU·MRU 1492
wan6                 @wan / dhcpv6（联通 IPv6）
br-lan               lan1 lan2 lan3 lan4（不含 pon0.995）
lan                  192.168.31.1/24 + DHCP/RA
DHCP 静态租约         默认不预置；刷完在 LuCI/DHCP 里按需添加（不要提交设备 MAC）
WiFi                 radio 默认 disabled
管理                 http://192.168.31.1（LAN 内）
```

**为什么 `pon0.995` 不进 br-lan**：PPPoE 要在 WAN 上终结，`pon0.995` 是 WAN 的
802.1q 设备；把它桥进 LAN 就退回透明桥了。主路由模式下 LAN 与运营商二层隔离，
`ont.py` / `光猫通道开关` 这套开通道工具不再需要。

**为什么 DHCP 现在必须开**：HG5585F 是主路由，下游 AP/PC 需要地址。静态租约默认不预置
（公开仓库不写家里的设备 MAC）；小米 AP 和常用设备可以在 LuCI → DHCP/DNS 里按需固定。

### 桥接回退（不常用）

如果只是想把 HG5585F 当透明桥（下面再挂主路由），手工改：

```sh
# pon0.995 加回 br-lan，wan 退回 pon0/proto=none，关 DHCP
uci add_list network.br_lan.ports='pon0.995'
uci set network.wan.device='pon0'
uci set network.wan.proto='none'
uci set dhcp.lan.ignore='1'
uci commit network && uci commit dhcp
/etc/init.d/network restart && /etc/init.d/dnsmasq restart
```

注意：桥接模式下看门狗需要拆 `lan` 才能卸载 `pon0.995`，会短暂断管理面；本版默认的
`ifdown wan` 恢复逻辑是按主路由模式写的。

---

## 7. 针对本机做的优化

| 优化 | 做法 | 依据 |
|---|---|---|
| 编译收敛 | 12 个 device profile → 2 个 | `PER_DEVICE_ROOTFS=y` 下每个 device 独立内核链接 + 独立 rootfs |
| 二次构建加速 | `CONFIG_CCACHE=y` + CI 统一用 `$SRC/.ccache` | 改 overlay 后重编从 ~3h 降到 ~1h |
| **flow offload** | `flow_offloading=1` + `flow_offloading_hw=1` | 路由模式下 **inet flowtable + AN7581 PPE** 可以卸载 PPPoE（驱动支持 `TC_SETUP_FT` / `FLOW_ACTION_PPPOE_PUSH`）。**桥接模式下这条不命中 PPPoE**，所以现在是它真正有意义的形态 |
| 不装 br_netfilter | `kmod-br-netfilter` 保持 not set | 桥接帧进 iptables 的元凶；与 `nf_conntrack_bridge` 是两回事 |
| PON 参数预设 | `mode=epon-10g-1g`、`operator=ctc`、`ge_ports=4` | 原厂 `current_ponmode=EPON_10G`、`port_num=4` |
| WiFi 默认关 | radio `disabled=1` | 小米 BE6500 Pro 继续做 AP；避免同一空间双 AP 干扰 |
| zram | `zram-swap` | 512 MiB RAM，为后续 Passwall/OpenClash 留压缩交换 |
| 去 UPnP | `luci-app-upnp` / `miniupnpd-*` 关闭 | 代理出口不需要；同时规避 feed 补丁失效导致的构建失败 |
| 去 EN7572 | 只保留 `paged-bosa` | HG5585F 用 `airoha,paged-bosa`，EN7572 前端对它是多余驱动+固件 |

**关于硬件限制**：

- DTS 声明内存 **512 MiB**（`memory@80000000` 0x20000000）。实机若为 1 GiB，先 `free -m` 确认再考虑把重负载服务搬上来。
- CU 的 LAN 是 **4×1G**；如果宽带 >1000M，CU 当主路由会卡在 1G。CT 的 `lan1` 是 2.5G，可换 CT 当主路由。
- 当前内核 **没有 BTF**（`DEBUG_INFO_REDUCED=y`、无 `DEBUG_INFO_BTF`、`BPF_EVENTS` 关闭），所以 **daed 不能直接搬到 ONT**；本方案用 Passwall/OpenClash（tproxy/tun），不依赖 BTF。

---

## 8. `pon-watchdog`

针对上游 [Issue #42](https://github.com/pbs05/ponwrt/issues/42)：10G-EPON 注册成功后
1 Hz MPCP timeout 自循环，`service_ready` 恒 0，不会自愈。

### 判据（按 Issue 实测修正）

Issue 的现场不是 `wait-line-sync`，而是：

```
lifecycle: operational
optical_signal: 1
service_ready: 0
mpcp_state: 4 (registered)
mpcp_timeouts: 1 Hz 增长
registered_lifetime_ms: 600~950
```

而且 `rx_start_count` **只在 `airoha_xpon_epon_start_rx()` 自增**，MPCP timeout
路径不自增，不能当判据。本版用：

- `lifecycle=operational && service_ready=1` → 健康
- `operational && service_ready=0 && mpcp_timeouts` 持续增长 → 判定卡死
- `wait-line-sync` / `error` → 判热
- `protocol-activating && mpcp_timeouts` 增长 → 判热

未配置 LOID 时 `mpcp_timeouts` 不会涨，所以不会在首启未填 LOID 时误恢复。

### 恢复序列（只拆 WAN）

```
ifdown wan → 删 pon0.995 → ip link set pon0 down → pond stop
→ modprobe -r airoha_xpon（校验确实卸载）
→ modprobe airoha_xpon → pon reload → pond start
→ ip link set pon0 up → ifup wan
```

**绝不 `ifdown lan`**：LAN 是管理面，也是下游 AP/PC 的出口。如果 `modprobe -r`
三次都失败，脚本会明确报错并只恢复 WAN，不再假装“已重新加载”。

### 永不自动 reboot

这个 bug 的触发条件就是冷启动，重启只会把状态机扔回同一个坑，还会让 OLT 侧看到频繁掉线。

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
| EPON OAM profile | `ctc` | `uci set pon.line0_oam.operator='ieee'` |
| 硬件 flow offload | `flow_offloading_hw=1` | 吞吐反而下降就 `uci set firewall.@defaults[0].flow_offloading_hw='0'` |
| IPv6 | 开 | `uci set network.wan.ipv6='0'; uci delete network.wan6` + `uci set network.lan.ipv6='0'` |
| WiFi | 关 | `uci set wireless.radio0.disabled='0'; uci set wireless.radio1.disabled='0'` + `wifi up` |
| zram | 开 | `uci set system.zram.enabled='0'` 或停用 `zram-swap` |
| 看门狗灵敏度 | 40s / mpcp_delta≥3 | 改 `files/usr/sbin/pon-watchdog` 头部常量 |

**待实测确认的假设**：

1. 联通 995 是否真是 `pon0` 上的 802.1q tag → `tcpdump -i pon0 -e -n vlan`
2. PPPoE 在 `pon0.995` 上能否拨通（MTU/MRU 1492）
3. `ifdown wan` + 删 `pon0.995` + 模块重载后，`ifup wan` 能否干净重建 VLAN
4. `mpcp_timeouts` 在正常注册与故障自循环下的实际斜率
5. `flow_offloading_hw` 在 AN7581 路由模式下是否真的带上 `flags offload`（`nft list flowtable inet fw4` / PPE debugfs）

**flow offload 与 tproxy 的关系**：硬件卸载（`flags offload`）会把被代理的流直接甩给
PPE，绕开 tproxy，表现为"部分站点直连、规则不生效"。所以 `99-hg5585f-setup` 在检测到
分流内核时**自动只保留软件 flowtable**（`flow_offloading=1` / `flow_offloading_hw=0`）；
没有分流内核时两者都开。若实测代理流量仍有异常：

```sh
uci set firewall.@defaults[0].flow_offloading='0'
uci commit firewall && /etc/init.d/firewall restart
```

### 分流内核：编译时三选一

由 workflow 的 `proxy` 输入决定，默认 **passwall**（512 MiB RAM 首选）：

```sh
gh workflow run build-hg5585f --repo Bernardxu123/ponwrt-hg5585f --ref master \
  -f proxy=passwall -f build_recovery=true
```

| proxy | 配置文件 | 取舍 |
|---|---|---|
| `passwall`（默认） | `configs/hg5585f-proxy-passwall.config` | Xray/SingBox/Hysteria/Simple-Obfs/Geoview；不拉 Rust，约 +30~40 分钟 |
| `openclash` | `configs/hg5585f-proxy-openclash.config` | Clash 订阅原生；DEPENDS 里有 `+ruby +ruby-yaml`，Ruby 源码编译约 +15~25 分钟，运行内存也更高 |
| `none` | 无 | 只做路由/桥接，验证链路用 |

两者互斥，断言会检查。**不开 Shadowsocks-Rust**：会把 Rust 工具链拉进构建
（`rust/host` 现编，ccache 覆盖不到），而实际节点是 VLESS/Reality/Hy2，用不上。

nikki（mihomo）不在选项里——它需要额外 feed（`nikkinikki-org/OpenWrt-nikki`），
本仓库没加。想要更轻的 Clash 方案可以自己加 feed 后照 `openclash` 的写法加一个层。

### 方案对比（参考 qwpianzhang/Actions-OpenWrt-HG5585F）

**Passwall 与 OpenClash 都在 ImmortalWrt feeds 里**，不需要额外 feed；
只有 **nikki（mihomo）** 要加 feed。

| 方案 | 来源 | 取舍 |
|---|---|---|
| Passwall | ImmortalWrt feeds 自带 | Xray/SingBox/Hysteria；比 OpenClash 轻；Clash 订阅需转换 |
| OpenClash | ImmortalWrt feeds 自带 | Clash 订阅/规则原生；参考仓注明 **Ruby/Rust 编译极慢** |
| nikki | 额外 feed `nikkinikki-org/OpenWrt-nikki` | mihomo 内核 + LuCI；Clash 订阅原生，比 OpenClash 轻 |

本版先不内置；确认基础固件能拨号、PON 注册、PPE 卸载、看门狗恢复后，再按选择
把对应 `CONFIG_PACKAGE_*` 打开。`configs/hg5585f-build.config` 末尾有备查块。

---

## 10. 排障速查

```sh
# 预设是否生效
cat /tmp/hg5585f-setup.log

# 桥成员 / VLAN
brctl show br-lan
ip -d link show pon0.995

# LAN 有没有 DHCP
logread -e dnsmasq
cat /tmp/dhcp.leases

# WAN 状态
ifstatus wan
ubus call network.interface.wan status
logread -e pppd

# flowtable
nft list flowtable inet fw4
conntrack -L -o | head
cat /proc/net/nf_conntrack | grep -i offload

# PON 全量状态
cat /sys/kernel/debug/airoha-xpon-pon0/line
cat /sys/kernel/debug/airoha-xpon-pon0/registration
ponctl --device pon0 status
```

---

## 11. 上游参考

- [pbs05/ponwrt](https://github.com/pbs05/ponwrt) · [Issue #42 10G-EPON 掉线](https://github.com/pbs05/ponwrt/issues/42) · [PR #34 HG5585F-CT PHY](https://github.com/pbs05/ponwrt/pull/34) · [PR #43 HG5585F-CU LED](https://github.com/pbs05/ponwrt/pull/43)
- [pbs05/uboot-an758x](https://github.com/pbs05/uboot-an758x) · [an758x-stock2ubi](https://github.com/pbs05/an758x-stock2ubi) · [fiberhome-factory](https://github.com/pbs05/fiberhome-factory)
- [openwrt-pon-drivers](https://github.com/pbs05/openwrt-pon-drivers) · [openwrt-pon-userspace](https://github.com/pbs05/openwrt-pon-userspace)
- [qwpianzhang/Actions-OpenWrt-HG5585F](https://github.com/qwpianzhang/Actions-OpenWrt-HG5585F)：同板型云编译参考；确认 passwall/openclash 来自 ImmortalWrt feeds、nikki feed、失败时保存 dl 缓存、files/ 可执行位处理
- [LeoooChen/PonWRT-TYFZA1](https://github.com/LeoooChen/PonWRT-TYFZA1)：不同 SoC（Realtek RTL9617CVW）的原生 PON 移植，代码不能直接抄；其 PPPoE/FE/flow offload 测试脚本可作为验证方法参考

> PonWrt 是研发性质的开源项目。刷机、改 PON 相关设置可能导致启动失败、配置或设备专属数据丢失、
> 或无法在 PON 网络注册。刷之前请务必备份原厂固件与设备数据。
> 不得用于未授权的网络接入、冒用/克隆他人设备身份，或干扰运营商网络。
