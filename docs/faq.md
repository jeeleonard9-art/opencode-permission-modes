# 常见问题

## 按 `Ctrl + .` 没反应

1. 确认你用的是**桌面版**（TUI 的切换键是 `Tab`，取决于 `tui.json` 里的 `agent_cycle`）。
2. 确认至少有两个非 subagent 的 agent 可用。如果只剩一个，循环切换看起来就像「没反应」。
3. 快捷键冲突：在 设置 → 快捷键 → *Model and agent* 里重新绑一个。

## 想用 `Ctrl + Space`，但按了没用

Windows 上 `Ctrl + Space` 默认是中文输入法的中英切换，会被系统先截走，OpenCode 根本收不到。

解决办法任选其一：

- 在输入法设置里把中英切换改成别的键（例如 `Shift` 或 `Ctrl + Shift + Space`）；
- 干脆用默认的 `Ctrl + .`。

## 改了快捷键，但不生效

桌面版的快捷键在启动时读取。改完需要**重启 OpenCode**。

## 三档没有出现在 agent 选择器里

按顺序排查：

1. 文件真的在配置目录的 `agent/` 下吗？
   - Windows：`C:\Users\<你>\.config\opencode\agent\`
   - macOS / Linux：`~/.config/opencode/agent/`
2. frontmatter 里 `mode` 是不是 `primary`（或 `all`）？`subagent` 不会出现在主选择器里。
3. 有没有写成 `disable: true`？
4. 重启过应用了吗？（新文件只在启动时扫描）
5. 检查 YAML 缩进。`permission` 是嵌套对象，用空格不用 Tab。

## 新增/删除档位为什么要重启？

OpenCode 在**启动时**扫描配置目录的 `agent/`，把每个 `.md` 解析成 agent 注册进列表；运行期间不会再扫这个目录。所以：

| 操作 | 要重启吗 |
| --- | --- |
| 改已有档位的 `permission` | **不用**，下次工具调用就是新规则 |
| 改已有档位的 `description` / 提示词正文 | 不用（新会话生效） |
| 新增一个 `.md`、删掉一个 `.md`、改名 | **要**，否则列表里看不到变化 |
| 改快捷键、改 `model` | 要 |

**标准操作流**：日常调权限直接改文件，热生效；只有加减档位文件时才重启。右键托盘图标退出再开一次即可。

## agent 不向我提问，只会自己瞎猜

自定义 agent 的 `question` 权限默认是 `deny`。需要显式写：

```yaml
permission:
  question: allow
```

本仓库三档都写了。

## 为什么 `read-only` 直接把 `bash` 设成 deny，而不是 ask？

因为 `read-only` 的语义是「只看不改」。`ask` 意味着你随时可能点同意，然后一条命令就把文件改了——那它就不是 read-only 了。真要跑命令，切到 `auto-edit`。

## 为什么 `"*": deny` 之后还要一个个写 allow？

因为判定规则是「**最后一条命中者获胜**」，`"*"` 会命中一切。它必须写在最前面当兜底，后面再逐项放开：

```yaml
permission:
  "*": deny      # 兜底，写在最前
  read: allow    # 写在后面才能覆盖它
```

顺序反了的话，所有 allow 都会被 `"*": deny` 盖掉。

## 项目里的 `opencode.json` 也写了 `permission`，会冲突吗？

会合并，同名的键以项目级为准。如果你在两处都定义了同名的 agent，建议只保留一处，或者换个 agent 名字区分开。

## 能不能只禁止少数命令，其它都放行？

可以，用对象写法按 glob 匹配命令内容：

```yaml
permission:
  bash:
    "rm -rf *": deny
    "git push *": ask
    "*": allow
```

## 切换档位会不会变慢 / 多花 token？

不会。权限判定在本地进程内完成，不发网络请求。每个档位只多了一句「你现在处于 X 档」的提示词。

## 怎么卸载

**用脚本**：在仓库目录里跑 `uninstall.ps1`（Windows）或 `./uninstall.sh`（macOS / Linux）。它会按安装时留下的清单把三个 `.md` 还原成你的原始文件（有备份的话）或直接删除，并提示 `default_agent` 是否还指向已删掉的档位。`opencode.json` 它不会动。

**手动**：删除配置目录 `agent/` 下的那三个 `.md`，重启。如果你改过 `opencode.json`，把 `default_agent` 和 `agent.build/plan.disable` 删掉即可。

安装脚本会在配置目录写一个 `.opencode-permission-modes.manifest`（记录装过哪些文件、对应的备份是哪个）。卸载完它会自己删掉，手动删也无害。

## 支持哪些版本？

在 OpenCode Desktop 1.19.3（Windows）上验证。只用了公开配置字段，TUI 同样适用，但其他版本请自行验证——完整的验证矩阵和自查清单见 [compatibility.md](compatibility.md)，欢迎提 issue 反馈结果。
