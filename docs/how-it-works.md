# 它是怎么工作的

本文记录实现这三档权限时依赖的 OpenCode 行为，以及踩过的坑。基于 OpenCode Desktop **1.19.3**。

## 1. Agent 就是配置目录里的一个 Markdown 文件

OpenCode 启动时会扫描配置目录下的 `agent/` 与 `agents/`（递归、含子目录），每个 `.md` 文件变成一个 agent：

- YAML frontmatter → agent 配置
- 正文 → 该 agent 的 system prompt

agent 的名字取 frontmatter 里的 `name`，没有就用文件名。所以 `agent/read-only.md` 就是一个叫 `read-only` 的 agent。

配置目录（优先级从低到高）：

| 位置 | 说明 |
| --- | --- |
| `~/.config/opencode/` | 全局，所有项目共享 |
| `<项目>/.opencode/` | 项目级 |
| `<项目>/opencode.json` | 项目级 |

> Windows 上 `~` 就是 `C:\Users\<你>`。

**改动生效时机**：新增或删除 `.md` 文件需要重启；修改已有文件的 `permission` 无需重启（配置在会话中被重新读取）。如果不确定，重启总是安全的。

## 2. 三档之间只差了 `permission`

一个 primary agent 的常用字段：

```yaml
---
description: 显示在选择器里的说明
mode: primary        # primary | subagent | all
color: "#3b82f6"     # 指示点颜色，也可以是 primary/secondary/... 主题名
permission: { ... }  # 本文重点
model: provider/id   # 可选，给这一档单独指定模型
---
正文就是这一档的 prompt。
```

本仓库的三个文件都没有真正的 prompt（正文只有一句「你现在处于 X 档」）。**同样的模型、同样的能力，唯一的区别就是权限**——这正是「档位」该有的样子。

## 3. `permission` 的写法

权限值是三选一：`allow` / `ask` / `deny`。

大多数工具还能写成「按模式匹配」的对象，用 glob 匹配工具参数（比如命令的内容、文件的路径）：

```yaml
permission:
  edit: allow
  bash:
    "git *": allow       # git 开头的命令直接放行
    "rm *": deny         # 删除一律禁止
    "*": ask             # 其它一律询问
```

有两类工具的处理方式不同：

| 只接受单个动作字符串 | 接受动作或对象 |
| --- | --- |
| `question`, `todowrite`, `webfetch`, `websearch`, `doom_loop` | `bash`, `edit`, `read`, `glob`, `grep`, `list`, `task`, `lsp`, `skill`, `external_directory` |

另外可以写一个 `"*"` 作为兜底键，例如：

```yaml
permission:
  "*": deny        # 默认全部禁止，再逐个放开
```

## 4. 判定顺序：最后一条命中的规则获胜

这是最容易踩的坑。匹配不是「最具体的获胜」，而是**列表中最后一条匹配的规则获胜**。所以顺序 = 优先级，兜底规则要写在最上面：

```yaml
permission:
  "*": deny          # ① 先全禁
  read: allow        # ② 再把读放开（写在后面，才能盖住 ①）
  bash: ask          # ③
```

如果**没有任何规则命中**，默认动作是 `ask`——不是 `allow`。这是个安全的选择，但也意味着 `"*": deny` 之后必须显式列出你想放行的每一项。

## 5. `deny` 会让工具从模型眼前消失

`deny` 不是「调用了再拒绝」，而是在构造请求时就把该工具从工具列表里剔除。好处是模型不会浪费 token 去尝试一个注定失败的工具；代价是模型可能不知道这个能力存在——所以我们在正文里写了一句当前档位的说明。

## 6. 自定义 agent 的 `question` 默认是 `deny`

OpenCode 内置 agent 的权限基线是 `"*": allow`，而**自定义 agent 的 `question` 默认是 `deny`**。也就是说，如果你不显式写 `question: allow`，agent 就无法向你提问。

这就是三个文件里都能看到 `question: allow` 的原因。少了它，`read-only` 档会变得很难用：agent 既不能改东西，又没法问你问题，只能干瞪眼。

## 7. 为什么还留着 `doom_loop: ask`

`doom_loop` 是防止 agent 反复执行同一个动作、无限打转的保护。三档都设成 `ask` 是一个刻意的取舍：即使是 `full-auto`，当 agent 真的要陷入死循环时，我宁可被问一次。

## 8. `default_agent` 与禁用内置 agent

```jsonc
{
  "default_agent": "auto-edit",
  "agent": {
    "build": { "disable": true },
    "plan": { "disable": true }
  }
}
```

- `default_agent` 必须指向一个没有被隐藏的 primary agent；否则会回退到 `build`。
- `disable: true` 会把内置 agent 从选择器里移除，让列表只剩你的三档。
- 两者都是可选的。不加也能用，只是列表里会多出 `build` / `plan`。

## 9. 走过的弯路：为什么最终没有用插件

最初的实现是一个插件，通过 hook 拦截工具调用、按档位改写权限。它能跑，但：

1. 每个工具调用都要过一次 JS 分支判断，白白的运行时开销；
2. 依赖未公开的内部接口，OpenCode 升级时容易碎；
3. **界面上完全看不出当前处于哪一档**，得打开配置文件才知道。

换成 agent + `permission` 之后，这三个问题一起没了：判定是进程内查表，只用公开 schema，而且当前档位就明明白白写在 agent 选择器上。
