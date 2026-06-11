# 霍尔传感器与 GNOME 自动旋转

本文档记录了 Xiaomi Pad 6S Pro 12.4 (sheng) 移植中，针对霍尔（磁吸盖板）传感器与 GNOME 自动旋转功能的调试过程与最终实现方案。

## 背景与问题

Sheng 设备包含一个物理霍尔传感器，通过 `gpio-keys` 子系统向输入层报告 `SW_LID` 事件（0=开盖，1=合盖）。

在默认的 GNOME / Mutter 环境下，存在以下两个冲突的默认行为：
1. **自动旋转阻断**：Mutter 的自动旋转逻辑规定，如果系统报告存在 `SW_LID`，则不论其实际状态如何，都会在开机早期将设备识别为笔记本，并可能**永久禁用自动旋转**，直到再次收到明确的 `SW_TABLET_MODE` 事件。
2. **电源管理挂起**：`systemd-logind` 监听到 `SW_LID=1` 会执行 `suspend`。但在当前内核状态下，Sheng 的 suspend 会导致 ADSP/CDSP 子系统响应超时并引发内核崩溃。

## 解决思路的演进

在适配过程中，我们尝试了多种方案：

### 方案 A：udev 屏蔽 + logind ignore（失败）
最初尝试通过 udev 规则隐藏 `gpio-keys` 的 `ID_INPUT_SWITCH`，同时将 logind 的 `HandleLidSwitch` 设为 `ignore`。
**结果**：解决了挂起崩溃问题，但 GNOME 仍然通过底层的 libinput 读取到了 `SW_LID` 导致旋转失效；而且系统完全丧失了合盖息屏的能力。

### 方案 B：虚拟 uinput 设备 + 事件透传（失败）
通过一个 Python 脚本 (`fake-tablet-mode`) 创建虚拟设备，同时暴露 `SW_TABLET_MODE` 和 `SW_LID`，拦截物理霍尔传感器事件后转发给虚拟设备，并将 logind 的处理交给 GNOME 的 `lid-close-ac-action="blank"` 机制。
**结果**：由于最初错误地进行了取反操作，且 Mutter 需要明确的 `SW_TABLET_MODE` 0 到 1 的状态跳变才能激活平板模式，导致自动旋转仍然极其不稳定，且容易在开机盖板状态下卡死。

### 方案 C：解耦机制（最终成功）
彻底将 GNOME 的盖板逻辑与实际的屏幕息屏控制解耦。

## 最终实现方案

### 1. 彻底对 GNOME 隐藏 SW_LID
为了保证 GNOME 永远认为这是一台可以自动旋转的平板电脑：
* 通过 udev 规则，给物理 `gpio-keys` 添加 libinput 忽略配置。
* `fake-tablet-mode` 创建的虚拟设备**只上报 `SW_TABLET_MODE`**，完全剥离 `SW_LID`。

### 2. 构建 0 到 1 的状态跳变
Mutter 需要明确看到设备进入平板模式的动作：
* 虚拟设备在启动时先上报 `SW_TABLET_MODE=0`。
* 延迟 20 秒（等待 GNOME 桌面加载完成）后，再上报 `SW_TABLET_MODE=1`。
这强制触发了 Mutter 的平板模式激活，解锁自动旋转和悬浮键盘。

### 3. D-Bus 接管合盖息屏
既然 GNOME 已经看不见 `SW_LID`，合盖息屏只能通过自定义脚本完成：
* `fake-tablet-mode` 监听底层的物理 `gpio-keys` 的 `SW_LID` 原始事件（0=开盖，1=合盖，极性本身是正确的）。
* 当检测到合盖/开盖时，脚本通过 `loginctl` 查找当前活跃的 GNOME 会话。
* 利用 `busctl` 向该用户的 `org.gnome.Mutter.DisplayConfig` 发送 D-Bus 指令，直接修改 `PowerSaveMode` 属性（0=亮屏，3=息屏）。

### 4. 禁用 logind 干扰
在 `configuration.nix` 中：
```nix
services.logind.settings.Login.HandleLidSwitch = "ignore";
```
彻底剥夺 `systemd-logind` 对盖板事件的控制权，避免了因为挂起引发的内核崩溃。

## 总结
这一方案成功实现了：
1. 完美的四向自动旋转。
2. 合理的合盖息屏与开盖亮屏。
3. 避免了系统挂起引发的死机崩溃。
