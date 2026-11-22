# dmgbuild 配置：scripts/release.sh 调用，传入 -D app=<codedog.app 路径> -D background=<背景图路径>。
# 背景图由 scripts/dmg/make-background.swift 生成；改图标位置时两边一起改。
import os

app = defines["app"]  # noqa: F821  dmgbuild 注入

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821
window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

hide_extensions = [os.path.basename(app)]

icon_size = 112
text_size = 13
arrange_by = None
icon_locations = {
    os.path.basename(app): (170, 180),
    "Applications": (490, 180),
}
