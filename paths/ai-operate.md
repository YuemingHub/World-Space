# 我想让 AI 帮我操作电脑或网络

> 让 AI 自己浏览网页、填表、收集信息，或在你的电脑上执行任务。

---

## 你现在可以做到什么？

让 AI 像人一样操作浏览器：打开网页、点击、填表、截图、收集信息。或者在本地电脑上执行代码处理文件。

## 最推荐从哪里开始？

**Browser Use**（https://browser-use.com）

如果你想让 AI 在本地电脑上执行更广泛的任务，用 **Open Interpreter**（https://openinterpreter.com）。

## 为什么推荐它们？

### Browser Use
112K stars，目前最成熟的开源浏览器自动化 AI。有 Cloud 版本降低门槛。MIT 许可证。可以让 AI 自动完成网页上的重复操作。

### Open Interpreter
68K stars，让 AI 在你的电脑上执行代码和命令。不限浏览器，可以处理本地文件、批量操作。Apache-2.0 许可证。

## 难不难？

- Browser Use Cloud：中等，有界面操作
- Browser Use 自部署：中偏高，需要 Python 和 API Key
- Open Interpreter：中偏高，需要命令行和 API Key

⚠️ 这是 5 条路径里门槛最高的。如果你完全不想碰技术，建议先走前 4 条路径。

## 要钱吗？

- Browser Use：开源免费自部署；Cloud 有免费额度。需要 AI API Key
- Open Interpreter：开源免费。需要 AI API Key 或本地模型

## 第一步

### Browser Use Cloud
1. 打开 https://browser-use.com
2. 注册
3. 创建一个任务，用自然语言描述

第一句怎么说：
```
打开淘宝，搜索"羊毛混纺毛线"，把前 10 个结果的
名称、价格、店铺名整理成一个表格。
```

### Browser Use 自部署
1. 确保已安装 Python 3.11+
2. `pip install browser-use`
3. 设置 API Key：`export OPENAI_API_KEY=你的key`（或用 DeepSeek API）
4. 运行：
```python
from browser_use import Agent
agent = Agent(task="打开百度搜索'手工毛线价格'，截图第一页结果")
await agent.run()
```

## 做到什么算第一步成功？

AI 成功打开了一个网页，执行了你描述的操作，并返回了结果（截图/数据/完成通知）。

## 下一步怎么走？

1. 尝试更复杂的任务（多步操作）
2. 把常用的重复任务固定下来
3. 如果需要本地文件处理，了解 Open Interpreter

## 卡住了怎么办？

| 问题 | 解决 |
|---|---|
| Cloud 版免费额度用完了 | 可以自部署，或者减少使用频率 |
| 自部署安装失败 | 确认 Python 版本 ≥ 3.11，用虚拟环境隔离 |
| AI 操作网页不稳定 | 网页结构会变。给 AI 更明确的指令，比如"点击右上角蓝色的登录按钮" |
| 不确定要不要用 | 如果你的重复操作都在网页上，Browser Use 够了。如果涉及本地文件，看 Open Interpreter |
| 觉得太复杂 | 这条路径是进阶选项。先走"少做一些重复工作"路径，用 n8n 可能更简单 |
