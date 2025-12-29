#!/bin/bash

set -e

echo "🚀 开始构建 Legado.app..."

# 清理旧的构建
rm -rf Legado.app
rm -rf .build/release

# 构建 Release 版本
echo "📦 编译 Release 版本..."
swift build -c release

# 创建 App 包结构
echo "📁 创建 App 包结构..."
mkdir -p Legado.app/Contents/MacOS
mkdir -p Legado.app/Contents/Resources

# 复制可执行文件
echo "📋 复制可执行文件..."
cp .build/release/Legado Legado.app/Contents/MacOS/

# 复制 Info.plist
echo "📋 复制 Info.plist..."
cp Resources/Info.plist Legado.app/Contents/

# 生成 icns 文件
echo "🎨 生成应用图标..."
mkdir -p icon.iconset
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png icon.iconset/icon_16x16.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png icon.iconset/icon_16x16@2x.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png icon.iconset/icon_32x32.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png icon.iconset/icon_32x32@2x.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png icon.iconset/icon_128x128.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png icon.iconset/icon_128x128@2x.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png icon.iconset/icon_256x256.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png icon.iconset/icon_256x256@2x.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png icon.iconset/icon_512x512.png
cp Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png icon.iconset/icon_512x512@2x.png

iconutil -c icns icon.iconset -o Legado.app/Contents/Resources/AppIcon.icns
rm -rf icon.iconset

# 代码签名（简单保护）
echo "🔐 添加代码签名..."
codesign --force --deep --sign - Legado.app 2>/dev/null || echo "⚠️  代码签名失败（需要开发者证书），但 App 仍可运行"

# 设置可执行权限
chmod +x Legado.app/Contents/MacOS/Legado

# 验证 App 结构
echo "✅ 验证 App 结构..."
if [ -f "Legado.app/Contents/MacOS/Legado" ] && [ -f "Legado.app/Contents/Info.plist" ] && [ -f "Legado.app/Contents/Resources/AppIcon.icns" ]; then
    echo "✅ App 结构正确"
else
    echo "❌ App 结构不完整"
    exit 1
fi

# 显示 App 信息
echo ""
echo "🎉 构建完成！"
echo "📦 App 位置: $(pwd)/Legado.app"
echo "📊 App 大小: $(du -sh Legado.app | cut -f1)"
echo ""
echo "🚀 运行方式："
echo "   1. 双击 Legado.app 运行"
echo "   2. 或在终端运行: open Legado.app"
echo ""
echo "⚠️  首次运行可能需要在「系统偏好设置 > 隐私与安全性」中允许运行"
