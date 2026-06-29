#!/bin/bash
set -euo pipefail

# ============================================================
# setup-edge-cdp.sh
# 为 Microsoft Edge 创建带 CDP 远程调试的包装应用，并设为默认浏览器。
#
# 用法:
#   chmod +x setup-edge-cdp.sh && ./setup-edge-cdp.sh
#
# 选项:
#   --port PORT         CDP 调试端口（默认 9222）
#   --no-default        不设为默认浏览器
#   --name NAME         包装应用名称（默认 "Edge Debug"）
# ============================================================

PORT=9222
SET_DEFAULT=true
WRAPPER_NAME="Edge Debug"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --no-default) SET_DEFAULT=false; shift ;;
        --name) WRAPPER_NAME="$2"; shift 2 ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--port PORT] [--no-default] [--name NAME]"
            exit 1
            ;;
    esac
done

EDGE_PATH="/Applications/Microsoft Edge.app"
WRAPPER_PATH="/Applications/${WRAPPER_NAME}.app"
BUNDLE_ID="com.microsoft.edgedev.debug"
MACOS_DIR="${WRAPPER_PATH}/Contents/MacOS"
RESOURCES_DIR="${WRAPPER_PATH}/Contents/Resources"

# ── 检查前置条件 ──────────────────────────────────────────
if [[ ! -d "$EDGE_PATH" ]]; then
    echo "❌ 未找到 Microsoft Edge.app，请先安装 Edge。"
    exit 1
fi

# ── 1. 创建包装应用目录结构 ───────────────────────────────
echo "📦 创建包装应用: ${WRAPPER_NAME}.app"
rm -rf "$WRAPPER_PATH"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# ── 2. 写入启动脚本 ───────────────────────────────────────
cat > "${MACOS_DIR}/${WRAPPER_NAME}" << SCRIPT
#!/bin/bash
exec /usr/bin/arch -arm64 "${EDGE_PATH}/Contents/MacOS/Microsoft Edge" --remote-debugging-port=${PORT} "\$@"
SCRIPT
chmod +x "${MACOS_DIR}/${WRAPPER_NAME}"

# ── 3. 写入 Info.plist ─────────────────────────────────────
cat > "${WRAPPER_PATH}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${WRAPPER_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${WRAPPER_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>app.icns</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>Web site URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>http</string>
                <string>https</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# ── 4. 复制 Edge 图标 ─────────────────────────────────────
ICON_SRC="${EDGE_PATH}/Contents/Resources/app.icns"
cp "$ICON_SRC" "${RESOURCES_DIR}/app.icns"
echo "   ✅ 图标已复制"

# ── 5. 注册到 LaunchServices ───────────────────────────────
echo "📋 注册应用..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$WRAPPER_PATH" 2>/dev/null
echo "   ✅ 已注册"

# ── 6. 设为默认浏览器 ─────────────────────────────────────
if $SET_DEFAULT; then
    echo "🌐 设为默认浏览器..."

    # 用 Swift 调用正式 API
    SWIFT_SRC=$(mktemp /tmp/set_browser.XXXXXX.swift)
    SWIFT_BIN=$(mktemp /tmp/set_browser.XXXXXX)
    trap "rm -f $SWIFT_SRC $SWIFT_BIN 2>/dev/null" EXIT

    cat > "$SWIFT_SRC" << 'SWIFT'
import Cocoa

let bundleID = "com.microsoft.edgedev.debug" as CFString

// 确保已注册
if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.edgedev.debug") {
    print("App found: \(appURL.path)")
} else {
    let appURL = URL(fileURLWithPath: "/Applications/Edge Debug.app")
    let _ = LSRegisterURL(appURL as CFURL, true)
    print("Registered")
}

// 设置 http / https 处理器
var allOK = true
for scheme in ["http", "https"] {
    let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID)
    if status == 0 {
        print("✅ \(scheme) → Edge Debug")
    } else {
        print("⚠️  \(scheme) 设置失败 (err \(status))，请手动到 系统设置 → 桌面与程序坞 → 默认网页浏览器 中选择")
        allOK = false
    }
}
SWIFT

    swiftc -o "$SWIFT_BIN" "$SWIFT_SRC" 2>/dev/null && "$SWIFT_BIN" || {
        echo "   ⚠️  Swift 编译失败，使用 fallback 方式..."
        # Fallback: 直接写 plist
        defaults delete com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers 2>/dev/null || true
        for scheme in http https; do
            defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers \
                -array-add "<dict><key>LSHandlerURLScheme</key><string>${scheme}</string><key>LSHandlerRoleAll</key><string>${BUNDLE_ID}</string></dict>"
        done
    }
fi

# ── 7. 刷新 Finder / Dock ─────────────────────────────────
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
echo "🔄 Finder / Dock 已刷新"

# ── 8. 验证 ─────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  ✅ ${WRAPPER_NAME}.app 创建完成"
echo "============================================"
echo ""
echo "  📍 位置: ${WRAPPER_PATH}"
echo "  🔌 CDP 端口: ${PORT}"
echo "  🌐 默认浏览器: $($SET_DEFAULT && echo "已设置" || echo "未设置")"
echo ""
echo "  下一步:"
echo "  1. 把 ${WRAPPER_NAME} 拖到 Dock 上替换原 Edge"
echo "  2. 若默认浏览器未生效: 系统设置 → 桌面与程序坞 → 默认网页浏览器 → ${WRAPPER_NAME}"
echo "  3. 启动后验证: curl -s http://localhost:${PORT}/json/version"
echo ""
