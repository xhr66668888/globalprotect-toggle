# GlobalProtect Toggle

一个简单的 macOS 菜单栏工具，用来开关 GlobalProtect，避免烦人的弹窗。

右键菜单只有三个选项：

- **On**：用 `launchctl load` 恢复现有 GlobalProtect。
- **Off**：用 `launchctl unload` 停止现有 GlobalProtect。
- **Quit**：退出小工具，保留最后一次的开关状态。

**[下载 Mac 程序](https://github.com/xhr66668888/globalprotect-toggle/releases/latest)**，解压后打开 `OU VPN.app` 即可。菜单栏使用 OU 标志。

需要 macOS 13+ 和已安装的 GlobalProtect。开启后，按原流程完成 Connect、登录及多重验证。

两个按钮分别只执行以下命令：

```sh
launchctl load /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*
launchctl unload /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*
```

图标状态通过只读查询获取。

## Build

安装 Xcode Command Line Tools，然后运行：

```sh
python3 scripts/build.py
open "dist/OU VPN.app"
```

运行检查：`python3 scripts/test.py`。

## License

源码采用 [MIT License](LICENSE)。OU 标志属于俄克拉荷马大学，不在 MIT 许可范围内，来源见 [NOTICE](NOTICE)。本项目是个人工具，与学校及 Palo Alto Networks 无隶属关系。
