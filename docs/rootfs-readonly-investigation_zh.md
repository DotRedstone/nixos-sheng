# sheng 根分区只读故障调查

## 现象

NixOS 正常运行一段时间后，`/`、`/home` 和 `/nix` 的写入统一返回
`Read-only file system`。`findmnt` 仍可能显示 `rw`，因为 ext4 在检测到错误后
从文件系统内部进入只读保护，挂载信息不一定立即反映这个状态。

2026-08-25 的复现日志为：

```text
EXT4-fs error (device sda30): ext4_readdir: inode #4988158:
path /nix/store/...-source/pkgs/by-name/tr/trace-cmd:
bad entry in directory: directory entry overrun
EXT4-fs: Detected aborted journal
EXT4-fs (sda30): Remounting filesystem read-only
```

离线 `e2fsck -fn` 同时确认该目录块损坏，并发现一批孤立 inode。重启后 stage-1
在挂载前完成修复，superblock 从 `clean with errors` 恢复为 `clean`。

## 根因

这不是 Android 主动把 `linux` 分区改成只读，也不是单纯缺少 `rw` 挂载参数。

1. 旧 rootfs 由 Mobile NixOS 默认的 Android `make_ext4fs` 生成，文件系统没有
   `metadata_csum`，目录和 inode 元数据缺少现代 ext4 的端到端校验。
2. 原 stage-1 每次运行 `e2fsck -p`，但一次非正常关机后，e2fsck 可以只回放
   journal 并把文件系统重新标记为 clean，不会强制遍历全部目录。
3. 强制重启或掉电留下的潜伏目录损坏因此可能在启动时未被发现，直到 Nix 读取
   对应 store 目录，ext4 才发现结构非法并按 `errors=remount-ro` 进入只读保护。

本次及相邻启动日志中没有 UFS、SCSI、block I/O、设备 reset 或 flush 失败，UFS
设备也报告支持 FUA。因此目前没有证据表明 Micron UFS 闪存或 Qualcomm UFS 驱动
是直接根因。`errors=remount-ro` 是正确的保护结果，不应通过强制 remount 来绕过。

## 修复

- stage-1 在挂载前读取 ext4 superblock。若存在 `needs_recovery` 或状态不是
  `clean`，改用 `e2fsck -fp` 完整扫描；自动修复失败时再使用 `e2fsck -fy`。
- 正常运行时将检查周期设为最多 12 次挂载或 14 天，避免长期潜伏损坏。
- 每 30 秒读取 `/sys/fs/ext4/<device>/errors_count`。若 ext4 已将根分区保护为
  只读，通知当前用户并正常重启，让 stage-1 离线修复，而不是留下半失效桌面。
- 新发布的 rootfs 改用当前 `mkfs.ext4`，启用 `metadata_csum`、`64bit`、
  `dir_index`、`flex_bg`、`extra_isize` 等特性，并保留 journal barrier、
  `data=ordered` 和 `errors=remount-ro`。

## 验证

运行：

```bash
sheng-rootfs-status
systemctl status sheng-rootfs-tune.service sheng-rootfs-health.timer
journalctl -b -u sheng-rootfs-tune -u sheng-rootfs-health
```

正常结果应包含：

```text
Filesystem state: clean
Errors behavior: Remount read-only
Maximum mount count: 12
Check interval: 1209600 (2 weeks)
errors_count: 0
```

新 rootfs 镜像还应确认：

```bash
dumpe2fs -h rootfs.img | grep 'Filesystem features'
```

输出中必须存在 `metadata_csum`、`64bit` 和 `dir_index`。
