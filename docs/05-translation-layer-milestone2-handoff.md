# 翻译层：里程碑 2（Dalvik / DEX 执行）交接

## 给 Claude 的小结

我们已经实现了 Dalvik（DEX）字节码执行和核心 Android 框架 shim，以便在不于 QEMU 下运行 Android 的情况下，让 Flappy Bird（`FlappyBird_64bit.apk`）在 iOS/macOS 上原生运行。

第 0 帧成功地逐像素渲染进 540x960 的 ARGB8888 帧缓冲（标题画面带 `(c) .GEARS 2013`、城市天际线、地面和 logo）。

用户的反馈是：
> "只显示了一帧，然后就变成白屏了，也可能只是在加载，如果是在加载那也太慢了"

我们通过 `xcrun devicectl` 拉取的设备日志，以及彼此隔离的 macOS 测试脚手架，直接在两个问题上做了排查。下面是确切的诊断，以及接下来需要做的事。

---

## 1. 问题 1：性能 / 极度缓慢

### 根本原因
在 `src/translation-layer/husk-tl-dex.c` 中：
`tl_dex_invoke` 在每条操作码上都会调用 `dex_log("  pc=%d op=0x%02x", pc, opcode)`，这会执行 `dlsym(RTLD_DEFAULT, "tl_log_line")`、获取一个 `pthread_mutex`、重新分配日志缓冲区，并向 stderr 打印。单帧会产生 19,000 多行日志，使执行变慢 10,000 倍，并把数 MB 的日志文本灌进 SwiftUI。

### 进展
- 在提交 `b1aa706` 中，我们从 `husk-tl-dex.c` 里移除了所有逐操作码和逐调用的 `dex_log` 行。
- **注意**：绝**不要**在启动时急切地对 APK 中全部 9,182 个类运行 `<clinit>`。该 APK 包含数百个 Google Play Services 和 AndroidX 类，它们带有循环依赖或未经 shim 的原生钩子。类初始化必须是**按需（惰性）**的。

---

## 2. 问题 2：为什么第 2 帧会变白

### 根本原因
1. 第 0 帧时，标题画面以青色天空绘制（`fb[0] = 0xffcac04e`）。
2. 第 2 帧时，`fb[0]` 变成 `0xffffffff`（纯白），因为执行了带白色 paint 叠加的 `canvas_drawRect(0, 0, 540, 960, paint)`。
3. 这个白色矩形就是游戏的死亡/闪光叠加层：类 `c` 的字段 `aQ` 表示闪光透明度（`0..255`）。在第 2 帧，`aQ` 从 `0` 跳到了 `255`！
4. `aQ` 跳到 `255` 是在 `c.a` 内部（`c.doFrame` 调用的物理 tick），因为 `this.a`（游戏状态枚举 `com/flappybird/recreation/d`）是 `NULL`（`0x00000000`）。
5. 当 `this.a` 为 `NULL` 时，`this.a.ordinal()` 会失败/返回 0 或落入 default 分支，而 `c.a` 把它当作游戏结束/死亡，从而触发全屏白色闪光叠加层（`aQ = 255`）。
6. 为什么 `this.a` 是 NULL？因为 `this.a` 是通过 `sget-object` 从 `Lcom/flappybird/recreation/d;->a` 赋值的。但 `d.<clinit>` 从未执行，所以所有静态字段（`d.a`、`d.b`、`d.c`……）都保持 `NULL`。

---

## 3. 解决方案 / 接下来立即要做的事

### 第 1 步：实现按需的 `<clinit>`
在 `src/translation-layer/husk-tl-dex.c` 中：
增加一个在首次访问时初始化类的辅助函数：

```c
static void dex_ensure_class_initialized(tl_dex_context *ctx, tl_dex_class *clazz)
{
    if (!clazz || clazz->initialized) return;
    clazz->initialized = true; /* Guard against recursion */
    tl_dex_method *clinit = tl_dex_find_method(clazz, "<clinit>", "V");
    if (!clinit) clinit = tl_dex_find_method(clazz, "<clinit>", NULL);
    if (clinit) {
        tl_dex_invoke(ctx, clinit, NULL, 0, NULL);
    }
}
```

在下列位置调用 `dex_ensure_class_initialized(ctx, f->clazz);`：
- 访问静态字段时的 `sget` / `sput`（操作码 `0x60` .. `0x6d`）。
- `new-instance`（操作码 `0x22`）。
- `invoke-static`（操作码 `0x71`、`0x77`）。

### 第 2 步：核实 Flappy Bird 的状态转换
在 `c.doFrame` 中：
- 检查 `this.a` 是否被正确设置为 `d.a`（或者它一开始所在的那个标题/准备状态枚举常量）。
- 确保 `src/translation-layer/husk-tl-framework.c` 中的 `android.graphics.Rect.intersects(Rect, Rect)` 和 `Rect.set(...)` 已被 shim（目前记录为 `invoke ?->intersects (native=0x0)`）。
- 在 `intersects` 未被 shim 时，碰撞检测可能被错误地判定为与管道或地面发生了碰撞。

### 第 3 步：用 `dex-test.c` 在 macOS 上测试
运行：
```bash
clang -O2 tools/dex-test.c src/translation-layer/husk-tl-dex.c src/translation-layer/husk-tl-framework.c src/translation-layer/husk-tl-zip.c -Isrc/translation-layer -lz -framework CoreGraphics -framework ImageIO -framework CoreFoundation -o /tmp/dex-test && /tmp/dex-test
```
核实 `fb[0]` 在全部 60 帧中都保持青色（`0xffcac04e`），而**不**变白（`0xffffffff`）。

### 第 4 步：打包并提交
- 运行 `bash scripts/package_ipa.sh` 打包 `~/Desktop/Husk.ipa`。
- 直接提交到 `origin/main`，不加 co-author 标记。
