## 这个 PR 做了什么

<!-- 一两句话。新增档位的话，把 permission 草案贴在这里。 -->

## 怎么验证的

<!-- 例如：切到 read-only，让 agent 改文件 → 工具不可用；重启后选择器出现第 4 档。 -->

## 检查清单

- [ ] `python scripts/validate_config.py` 通过
- [ ] 没有引入插件、hook 或运行时依赖
- [ ] 没有改动 `agent/read-only.md` / `auto-edit.md` / `full-auto.md` 的权限语义
- [ ] 改了 `README.md` 的话，`README_EN.md` 已同步
- [ ] 改了档位/能力的话，更新了 README 的能力对照表
- [ ] 在真实环境验证过的话，更新了 `docs/compatibility.md`
