# 贡献指南

先说清楚这个仓库是什么：**一份纯配置 preset**。三个档位是三个 primary agent 的 Markdown 文件，能力全部来自 OpenCode 原生的 `permission` 字段。没有插件、没有 hook、没有运行时依赖，也不打算有。

这意味着两件事：

- 好的贡献通常很小——改几行 YAML、补一段文档、在某个平台上验证一次。
- 需要写运行时代码的提案，基本都会被拒绝（哪怕它能让功能更强）。

---

## 报告 bug

**先自查**（大多数 issue 卡在这里）：

1. 你的版本/平台在 [`docs/compatibility.md`](docs/compatibility.md) 里是什么状态？「未验证」的组合出问题很正常。
2. 快捷键、输入法、重启相关的问题，看 [`docs/faq.md`](docs/faq.md)。
3. 新增/删除档位后**重启过** OpenCode 吗？
4. 去掉本仓库的配置后还能复现吗？能的话，那是 [OpenCode 上游](https://github.com/anomalyco/opencode/issues)的问题。

**然后**开 [issue](https://github.com/jeeleonard9-art/opencode-permission-modes/issues/new/choose)，用 Bug report 模板。模板会要求填这几项，缺一项我就得多问一轮：

- OpenCode 版本（桌面版：设置 → 关于；TUI：`opencode --version`）
- 操作系统、形态（Desktop / TUI）
- 出问题的档位
- 实际行为 vs 预期行为（权限问题要写清是「被拒绝」「没弹确认」还是「弹了但点了没用」）
- 复现步骤
- 该档位的 frontmatter（**删掉敏感信息**）

不确定是不是 bug 的，去 [Discussions](https://github.com/jeeleonard9-art/opencode-permission-modes/discussions) 问，别开 issue。

## 提功能建议

用 Feature request 模板。提之前先接受这三条边界：

1. **纯配置**：只通过 `permission` 实现，不引入插件或运行时代码。
2. **向后兼容**：不改 `read-only` / `auto-edit` / `full-auto` 的既有语义。新能力以**新档位**或 `presets/` 片段的形式加。
3. **配置层够不到的东西做不了**：改 UI、加图标、改选择器排序，这些不是这个仓库能解决的。

新档位的提案请直接附上 `permission` 草案，比描述一堆场景有用得多。

## 提交代码

```bash
git clone https://github.com/jeeleonard9-art/opencode-permission-modes.git
cd opencode-permission-modes
python scripts/validate_config.py     # 必须 0 error
```

改完提 PR，描述里写清楚「改了什么、为什么、怎么验证的」。

### 硬性约束

| 约束 | 说明 |
| --- | --- |
| 纯配置 | 不新增插件、hook、运行时依赖。校验脚本只能放在 `scripts/` 或 `.github/`，且不会被安装脚本复制到用户配置目录 |
| 不改既有语义 | `agent/` 下三个文件的 `permission` 语义只允许「新增档位」的方式扩展 |
| 双语同步 | 改 `README.md` 必须同步改 `README_EN.md`，结构对齐 |
| 脚本双版本 | 安装/卸载脚本必须同时提供 PowerShell 与 bash 版本，风格一致（先备份、不覆盖已有配置、输出下一步提示） |
| CI 必须绿 | `validate` workflow 在 Ubuntu / macOS / Windows 上都要通过 |

### 新增一个档位

1. 复制 `agent/` 里最接近的一个文件，改 `description`、`color`、`permission` 和正文那一句说明。
2. 跑 `python scripts/validate_config.py`。
3. 在 README 的能力对照表里加一列（中英各一份）。
4. 在 `docs/compatibility.md` 里注明是否实测过。
5. 提 PR。

### 改安装/卸载脚本

除了保持双版本，注意这两点：

- **绝不覆盖**用户已有的 `opencode.json` / `opencode.jsonc`。
- 备份与还原要能对上：安装写 `.opencode-permission-modes.manifest`，卸载按它还原。改动这个格式要同时改 `install.ps1`、`install.sh`、`uninstall.ps1`、`uninstall.sh` 四处，并更新 CI 里的往返测试。

### 验证过新版本/新平台？

这是最有价值的贡献之一。把 `docs/compatibility.md` 里对应行从「未验证」改成「已验证」，填上验证方式，并在 PR 里贴一下你走的那套自查步骤（文档末尾有清单）。

## 行为

对事不对人。review 会直接说「这个不做」并给理由，不代表对你本人有意见。

## License

贡献的代码与文档按 [MIT](LICENSE) 授权。
