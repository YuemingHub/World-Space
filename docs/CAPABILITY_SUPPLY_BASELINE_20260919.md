# Capability Supply Baseline — 2026-09-19

> **名字就是边界**：这是一份**供应侧基线**（今天世界上已经有什么），
> **不是**"普通人已经验证可达"。今晚真人数量仍然是 **`REAL HUMAN CASES = 0`**。
>
> 证据等级：本文全部为 **Machine / Operator Evidence**（官方文档、应用商店目录、仓库元数据、
> 本地 fixture 实跑）。任何一条都**不得**被引用为 `docs/CAPABILITY_REACH_LAB.md` 的 H1 / H2 结论。
> `checked_at` 一律 2026-09-19。

---

## 0. 方法（以及一个必须说清的缺陷）

四层供应侧核验，顺序固定：

```text
A 通用 AI 产品 → B Agent / Work 产品 → C 开源 → D 非 AI 现成能力
```

D 层强制检查，**不许偏爱 AI**：如果 Excel、微信、手机系统、普通 SaaS 更简单，它赢。

⚠️ **本轮已知缺陷（影响可达性结论，不掩盖）**：本轮网络出口位于**境外（美国西雅图）**，
因此所有关于"中国大陆能不能打开某个境外域名 / 境外 App 在国内商店是否在架"的判断，
只有商店目录与官方文档作为依据，**没有一次大陆真实网络环境下的实测**。
涉及境外托管站点可达性的句子一律记为 `unverified（大陆侧）`。要补这一格，需要一次
在中国大陆网络里的浏览器实测（本轮未做）。

---

## 1. 八条 Pressure Seeds 的逐条审判

### S1 · 每周把几个 Excel 合成一个

```text
Capability            多表合并成一个可用总表
现有最佳供应方式        电脑上表格软件自带的合并入口：Excel Power Query「从文件夹导入并合并」
                       （适用 2016/2019/2021/2024/365，要求各文件列结构一致），一次配好、以后每周点"刷新"；
                       WPS 表格亦有内置多表/多工作簿合并。AI 侧 Kimi Sheets 官方写明可上传多个
                       Excel→合并→下载 xlsx（Web+iOS+Android，会员 ¥49–699 共享额度池，免费额度未公示）
官方 / 实测证据        support.microsoft.com/zh-cn/excel/import-data-from-a-folder-with-multiple-files-power-query
                       （official_primary）；support.microsoft.com/.../vstack-函数（VSTACK 仅 M365/Excel 2024，
                       无网页/手机，跨工作簿不打开源文件会 #VALUE!）；kimi.com/zh-cn/resources/combine-multiple-excel-files-into-one-workbook
                       （official_primary）；本轮本地 fixture 实跑（见 §3）
真实技术门槛           ①入口要摸（数据→获取数据→从文件夹→合并并转换→关闭并上载）；②表头/起始行不一致→架构不匹配；
                       ③Excel 网页版 Power Query 连接器清单里没有"从文件夹"且要订阅→免费浏览器路径不成立；
                       ④手机 Office 无 PQ；⑤下周新文件要会点"全部刷新"；
                       ⑥开源侧 pandas 3.0.6（2026-09-17 发布，49.7k★）仍在维护但要 Python+终端；
                       GitHub 上"merge excel"前 15 个仓库最高 25★、多数 2016–2022 停更——没有双击可用的小工具
Supply-side judgement  HUMAN_TEST_CANDIDATE
Human evidence         NONE
```

**为什么不是 EXIT**：自带合并是确定且可复用的，但"这个人手上到底是 WPS 还是正版 Excel、
会不会点那几步、结果对不对"零真人证据。**现在判 EXIT 就是猜。**

**怀疑的 barrier**：`VERIFICATION` 为主，`TRANSLATION` 为辅。
**能证伪它的真人观察**：不懂技术的真人用手机、不装插件，在通用 AI App 里从微信一次选中本周那几个 .xlsx，
只输入他原话，判据四项全中即转 EXIT：≤5 分钟拿到可下载 .xlsx；行数=各文件数据行之和；表头只出现一次；
抽 3 列合计与原表逐列相加一致。**换另一批文件再测一次**，两次全过才算。

---

---

### S2 · 微信截图里的数字要一个个抄出来

```text
Capability            图片→结构化数据（可粘贴进表格）
现有最佳供应方式        把截图交给手机里已装的免费 AI 助手，说一句"转成表格并导出 Excel"
官方 / 实测证据        Apple 官方：iPhone 实况文本支持中文、iPhone XS/iOS 15+，但只"复制文本"不保留表格结构
                       （support.apple.com/zh-cn/120004，official_primary）；Kimi 官方写明图片可转 Excel、
                       免费试用、手机可用、认手写但精度受图片质量影响（official_primary）；
                       Excel 自带"从图片插入数据"需 Microsoft 365 且官方语言列表不含中文→中文截图基本无效
                       （support.microsoft.com/zh-cn/office/插入图片中的数据，official_primary）；
                       腾讯云通用表格识别免费 1000 次/月但属开发者 API（official_primary）；
                       白描会员 30/50 元档（official_primary）
真实技术门槛           多一跳：离开微信→开另一个 App→上传→下载→再导入表格软件；
                       合并单元格/嵌套表头/糊图/手写体最易错；多张截图汇总成一张表无一键方案
Supply-side judgement  EXIT_CANDIDATE（但留下一条硬缺口，见下）
Human evidence         NONE
```

**判定**：图片→结构化表格这一动作已被多款免费、手机可用、彼此独立的产品覆盖，**世界已经解决**，
World Space 不该再造一层。

**但这次审判暴露的缺口不属于 S2，属于所有涉及数字的场景**：
四层供应**没有任何一层**给出"这一格我没把握"的置信提示，错误数字被直接抄进报表会造成真实损失。
→ 这条并入 §2 的跨场景发现 V。

---

---

### S3 · 很多会议录音从来没整理

```text
Capability            长音频→转写+纪要+待办+可检索
现有最佳供应方式        手机上元宝「录音笔」导入旧录音（商店自述"转写翻译不限时"，v2.85.1，2026-09-17）；
                       千问自述"离线或实时语音转文字+会议总结与待办"（v7.3.5）；已在飞书/钉钉组织内的走妙记/闪记
官方 / 实测证据        apps.apple.com/cn/app/id6480446430（official_app_listing）；
                       apps.apple.com/cn/app/id6466733523（official_app_listing）；
                       阿里云听悟计费页：上传文件每天免费 2 小时、ASR 0.6 元/小时+大模型 0.064 元/小时叠加
                       （help.aliyun.com/zh/tingwu/pricing-and-billing-rules，official_docs）；
                       听悟功能页自设规格：单文件 ≤6GB/6 小时、待办最多 6 条、摘要最佳 ≤4 小时
                       （help.aliyun.com/zh/tingwu/features，official_docs）；
                       腾讯会议：免费版无转写额度、专业/商业版不限时（meeting.tencent.com/support/topic/1857）；
                       讯飞听见包月 18/88 元；剪映字幕已转会员（官方页未核到原文→unverified）
真实技术门槛           开源侧 whisper large 约需 10GB 显存；faster-whisper 末次提交 2025-11-19（约 10 个月未更）；
                       FunASR 最活跃（v1.4.16 / 2026-09-18）仍需 Python+CUDA → 普通人不可达
Supply-side judgement  HUMAN_TEST_CANDIDATE
Human evidence         NONE
```

**关键矛盾（官方声称 vs 可核实）**：商店文案写"不限时"，同一家的功能文档自设 6 小时/单文件、待办最多 6 条；
听悟个人端只写"每月有限转录时长"而不给数字。
**所有产品的录音留存期限与是否用于训练，均未核到可核官方条款**（元宝 2025-03 曾因协议条款致歉并三改）。

**怀疑的 barrier**：`ACCESS`（存量几十条要逐个导入排队）+ `TRUST`（录音含他人声音与公司信息）。
**能证伪的真人观察**：真人拿约 10 条、合计约 8 小时的旧录音，30 分钟内零付费跑完"导入→纪要→待办→导出并检索命中"，
则改判 EXIT；若卡在额度/格式/排队，本判断作废。

---

---

### S4 · 父辈留下的手写笔记不知道怎么办

```text
Capability            手写纸稿→可检索/可编辑/可保存
现有最佳供应方式        逐页拍照 + 按"主题-页码"命名存云相册（先保住原件、先可搜），
                       再用免费多模态 App 分批出初稿；潦草页与关键页按千字几十元交人工录入
官方 / 实测证据        百度 OCR 手写：自述"20+ 语言、准确率可达 90% 以上"，公有云 API 最高 1000 次/月免费
                       （ai.baidu.com/tech/ocr_others/handwriting，official）；WPS 官方页"连笔手写体识别率突破 92%、
                       标准 A4 约 98%"（wps.cn/article/uTKe6TSP.html，official）；腾讯云文档自认手写接口是旧版本、
                       建议改用通用印刷体高精度（cloud.tencent.com/document/product/866/36212，official）；
                       阿里云 Qwen-VL 官方示例提示词自带"不要遗漏和捏造虚假信息，模糊可用?代替"
                       （help.aliyun.com/zh/model-studio/user-guide/qwen-vl-ocr，official）；
                       人工录入官方成交单价：手写体近现代档案 40 元/千字、徽州民间手写文献 68 元/千字、
                       印刷体 15 元/千字、扫描 0.49 元/页（ccgp.gov.cn 中标公告，official-gov）
                       → 手写≈印刷 2.7 倍，市场自己承认手写仍需人工兜底
真实技术门槛           PP-OCRv5 官方称支持中英混合手写并返回置信度、文档建议 GPU；TrOCR 手写权重只有英文 IAM；
                       EasyOCR 无官方手写主张 → 要装 Python+Paddle，普通人不可达
Supply-side judgement  HUMAN_TEST_CANDIDATE
Human evidence         NONE
```

**这一条最诚实的结论**：转录本身已被 A/B/D 覆盖，那一半**应该直接跳出去**（甚至可以建议花钱找人录）。
真正没人供应的是**"结果对不对由谁判"**——逝者笔迹没有 ground truth，模型会把缺笔补成通顺的假句；
而"哪几页值得留、这句话到底什么意思"没有任何工具回答。老人潦草笔迹的真实水平：`UNKNOWN`。

**怀疑的 barrier**：`VERIFICATION`（家属辨认＋人工校对，无产品承接）+ `TRUST`（遗物照片传进商业服务后的留存/训练用途，
多数 App 无中文可核条款，家属因此不敢开工）。
**能证伪的真人观察**：真人把父亲 10 页手稿喂给免费 App、请另一位家属逐字校对——若家属看后直接接受、
不需要逐字核对，且隐私顾虑被"本地拍照＋找人录"一句话化解，即判 EXIT（本场景只剩拍照归档＋花钱录入）。

---

---

### S5 · 手机里几千张照片一直没整理

```text
Capability            去重 / 人物归类 / 备份 / 找旧图 / 做成实体相册
现有最佳供应方式        先用手机自带：iPhone 相册→重复项目→合并 ＋ 人物相簿；华为图库→相册→清理照片；
                       vivo 随手清；找旧图可加国区 ¥1 的离线 App。5GB 之外的备份必须付费。
官方 / 实测证据        iPhone 合并重复照片为现行官方功能（support.apple.com/zh-cn/guide/iphone/iph1978d9c23/ios，
                       official）；华为官方写明清理需 HarmonyOS 6.1+ 且**熄屏充电时才分析**
                       （consumer.huawei.com/cn/support/content/zh-cn16094960/，official）；
                       iCloud 免费仍 5GB、50GB 起 6 元/月（apple.com.cn/icloud，official）；
                       国行设备 Apple Intelligence "目前不可用"（官方地区页，页面日期 2026-09-14，official）
                       → "问照片/自然语言搜图"在国行走不通；
                       一刻相册 v6.37.6（2026-09-05）自述"无限存储空间"、同页在卖 16 元/月会员
                       （apps.apple.com/cn lookup，开发者自述＝semi-official，"无限"未核到书面条款）；
                       Immich v3.2.2（2026-09-15，114.5k★）官方要求 Docker + 6GB RAM + 常开服务器（official）；
                       停运前科：网易相册 2019-05-08 关服、字节时光相册 2023-12-06 停运
真实技术门槛           Google 相册与 ChatGPT 经 Apple 国区 lookup API 实测 resultCount=0（国区搜不到）；
                       PhotoPrism 社区版免费但人脸等能力按 €2/月起档位区分、手机端只给 PWA；
                       小米/OPPO/荣耀自带清理未核到官方页（unverified）
Supply-side judgement  HUMAN_TEST_CANDIDATE
Human evidence         NONE
```

**这一条的缺口和别处不一样**：单点能力全部免费或低价可用，"找不到工具"不成立；
缺的是**没人把"第一次整理完 → 以后还干净 → 变成成品"连成一条有人负责的链**。
去重只列候选不判"留哪张"；人物与事件归类只活在云端相册里，导出即丢；清理与合并全是一次性动作。

**怀疑的 barrier**：`INTEGRATION`（唯一一条以它为主的）+ `TRUST`
（全家面孔 + 停服前科 + "无限"查不到条款 → 多数人只肯放副本，不敢交唯一副本）。
**能证伪的真人观察**：给一个有几千张照片的真人**只一句入口指引**，观察他能否 30 分钟内完成
去重＋建人物相册＋把重要照片落到第二份副本，**并在 4 周后仍保持整洁、且自己做出过一次相册书**。
若一句指引就走完全程并维持住 → 缺口只是"不知道入口"，本 seed 判 EXIT；
若能删重复但 4 周后回到原样、始终没做出成品 → `INTEGRATION` ＋成品缺口成立。



---

---

### S6 · 每个月都做差不多的报告

```text
Capability            重复月报：取数→图表→叙述→对齐公司模板→发出
现有最佳供应方式        把模板固化一次：Excel 模板＋数据透视表（微软文档：新版连本地数据默认自动刷新），
                       每月约 20 分钟可交付；要"配一次长期自动"则飞书多维表格定时自动化（免费版 200 次/月，
                       专业版 35 元/人/月，无需代码）
官方 / 实测证据        Microsoft Copilot 支持区域页：中国大陆属"不可用/不受支持"例外区（世纪互联版亦无 Copilot）
                       （support.microsoft.com/zh-cn/topic/...copilot支持的区域和语言，official_primary）
                       → 个人拿不到世界最出名那套；
                       飞书多维表格版本权益页（base.feishu.cn/helpcenter/ai8y3d44/hlh442ej，official_primary）；
                       Kimi Sheets 官方功能页标价 0（kimi.ai/zh-hans/features/sheets，official_primary）；
                       微软"刷新数据透视表的数据"（support.microsoft.com/zh-cn/excel/refresh-pivottable-data，
                       official_primary）；FineReport 定时调度支持日报/月报并邮件推送，需企业部署（official）；
                       DeepSeek 隐私政策：输入可用于模型训练，需手动关闭"数据用于优化体验"
                       （cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html，official_primary）
真实技术门槛           n8n 205.2k★ 但 Sustainable Use License（fair-code 非 OSI）且要服务器+Docker；
                       Metabase 49.3k★ AGPL 自托管；python-docx 1.2.0（2025-06）仍在维护 → 不会写代码/没有 IT 即不可达
Supply-side judgement  EXIT_CANDIDATE
Human evidence         NONE
```

**判定**：四条独立路径都能自助到"可交付"，剩余摩擦是**公司权限与合规模板**问题，不是能力可达性缺口。
**"复制上月改数字"在很多公司仍然是正确做法，不必偏爱 AI。**

注意这里暴露的 `TRUST` 是真实且硬的：**公司普遍禁止把经营数据交给公网 AI**，
而部分通用 AI 的官方政策确实写明输入可用于训练（要手动关）。这一条不属于 S6，属于 §2 的 V/T 发现。

**能证伪的真人观察**：真实上班族按最低阻力路径做本月月报，若 30 分钟内仍拿不出可直接发给领导的成稿，
放弃点在导数、脱敏审批或格式对齐 → 本判定被推翻，改判 HUMAN_TEST_CANDIDATE。

---

---

### S7 · 不会编程但想有个地方介绍自己

```text
Capability            一个别人手机上真能打开的公开个人页面
现有最佳供应方式        不建站——先用微信里天然打得开的公开页（订阅号/视频号主页、名片类小程序）；
                       要"像网站"再用国内免费建站的平台二级域名（凡科、上线了：0 元、0 域名、0 备案、手机可编辑）
官方 / 实测证据        阿里云《网站搭建全流程指引》：未备案"网站无法开通访问"；备案需包年包月 >3 个月的主机
                       （help.aliyun.com/zh/dws/getting-started/the-whole-process-of-website-building-1/，official）；
                       阿里云《管局审核》：一般 1~20 个工作日、不可催审、域名实名且持有者须与备案主体一致，
                       开通后 30 日内再办公安联网备案（.../administration-review，official）；
                       微信开放平台：合法域名必须经 ICP 备案且仅支持 https/wss
                       （developers.weixin.qq.com/miniprogram/dev/framework/ability/network.html，official）；
                       GitHub Pages 限制 1GB/100GB 月流量（docs.github.com，official）；Gitee Pages 官方页标题即"功能已下线"
                       （gitee.com/help/articles/4228，official）；秒悟/万小智/v0/Lovable/Bolt 定价见 §6 证据清单
真实技术门槛           走自有域名＝必须备案（实名＋主机包年＋管局 1~20 工作日＋公安备案）；不备案只能用随机二级域名；
                       海外建站工具发布地址是境外默认域名 → 大陆/微信内能否打开本轮无大陆侧实测（unverified）
Supply-side judgement  EXIT_CANDIDATE
Human evidence         NONE
```

**判定**：成功判据"别人手机上真的打开了他的页面"已被微信生态公开页 + 国内免费建站二级域名完整覆盖，
0 元 0 备案即可达成。剩余摩擦是**监管与网络环境**，不是供给缺口，新产品补不掉。
→ 按 `AGENTS.md` 第 4 条（可以直接跳出去），**这一条应该带用户走出去，不是给他摆工具**。

**最典型的失败形态值得记下来**：页面做完了，朋友点开是白屏。
"上线"≠"别人打得开"——这是本条唯一真正难的地方，而它不是 AI 能力问题。

**能证伪的真人观察**：让真人用手机各做一次并计时——A 用公众号主页或免费建站二级域名页把链接发给 3 位微信好友；
B 把海外 AI 生成站点链接同样发出。若 A 在微信内也被拦/白屏，或 B 的朋友全部正常打开，
则"平台二级域名可靠、境外默认域名不可靠"的排序被推翻；若有人 1 天内 0 备案用自有域名在微信稳定打开，
`BEST_CURRENT_SUPPLY` 需改写。

---

---

### S8 · 每天要回复很多差不多的问题

```text
Capability            高频重复提问→一套可复用话术 / 自动回复
现有最佳供应方式        手机上用免费版通用 AI 把常见问题生成一套话术，存进企业微信
                       「工作台-客户联系-快捷回复」或手机输入法常用语；有公众号/店铺就开平台自带自动回复
官方 / 实测证据        企业微信官方《快捷回复》：自带、免费、手机端可设
                       （work.weixin.qq.com/nl/act/p/09ec1c3758424ce4，official）；
                       企业微信官方帮助《如何使用微信客服机器人》：知识库/相似问/AI 无效问识别，免费、认证非强制
                       （open.work.weixin.qq.com/help2/pc/19627，official）；
                       企业微信注册与认证页：注册免费、个人可注册 Individual team、审核费 300 元、
                       未认证外部联系人上限 200（.../15422 与 .../14641，official；两处口径与"客户超 100 需认证"不一致 → 记 unverified）；
                       扣子官方《发布到微信客服》：前置＝已开微信客服 + 完成企业认证（docs.coze.cn/guides_wecom，official）；
                       腾讯元器官方指南：公众号智能体免费、支持订阅号/服务号，未认证号长回复需回"继续"
                       （yuanqi.tencent.com/guide/agent-build-wechat-agent，official）；
                       阿里 AI 店小蜜 0.2 元/通、日 UV<50 免单（媒体口径，未找到官方价目页 → unverified）
真实技术门槛           个人微信挂机器人**不可推荐**：《微信软件许可及服务协议》8.2.1.6 禁第三方工具自动化、
                       8.5.1 可封号；wechaty 网页协议对 2017 后注册号基本不可用；
                       LangBot 接公众号需服务器 + 公网 HTTPS
Supply-side judgement  EXIT_CANDIDATE
Human evidence         NONE
Reach state            供应侧候选：likely ordinary-accessible；Final Reach state：**UNCONFIRMED**
                       （缺真人证据，不得写 ORDINARY_REACHABLE —— 见 Lab §13 与 Mission 9）
```

**判定**：A 层自带、免费、手机端就能完成；C 层阻力≈0（只剩"列 10 个问题 + 粘贴进快捷回复"两步手工）；
B/D 层比 A 更贵更重还要资质。**企业微信自带快捷回复已经够了 → World Space 应退出。**

**能证伪的真人观察**：一位真·家长群群主或无执照小店主，照上面在手机上做——
若 20 分钟内仍搭不出一套可复用话术，或明确卡在"企业微信注册 / 输入法常用语设置"并放弃，则退出判断被证伪。

---

## 2. 跨场景发现：供应不缺的那一格，缺在哪里

这不是结论，是**从 8 条已完成审判里浮出来的重复结构**，供真人实验优先去验。

```text
已完成 8 条：4 条判 EXIT（S2 截图 / S6 月报 / S7 个人页面 / S8 重复回复）
             4 条判 HUMAN_TEST（S1 Excel / S3 录音 / S4 手写 / S5 照片）
DISCOVERY / SELECTION 型摩擦：8 条里 0 条成为主要障碍
                              —— "不知道有这种能力"和"不知道选哪个"在 2026-09 的供应侧已基本不成问题
两条独立研究在同一晚各自查到：ChatGPT 与 Google 相册在国区 App Store lookup 均 resultCount=0
                              —— 互为佐证，但这只说明"境外产品在国内入口不可及"，不说明国内没有替代品
```

浮出来的三个真正重复的障碍：

### V · VERIFICATION（结果对不对，没人背书）

- S1：本地 fixture 实测——列顺序不同就能让"叠在一起"的结果少 24.00 元且**不报一行错**，
  还凭空造出一个假品名；按表头对齐修好总额之后，一行"数量单价填反"让明细数量从 7 变 9.1，
  **而总金额恰好不变**（乘法交换），所以"我看下总数没问题"这种核对抓不到它（见 §3）。
- S2：四层供应无一提供逐格置信提示；错的数字进报表是真实损失。
- S4：手写转录没有 ground truth，模型会把缺笔补成通顺的假句；厂商自己的示例提示词写着"不要捏造"。

### T · TRUST（数据出去之后归谁、被拿去干什么）

- S3：所有转写产品的录音留存期限与训练用途，均**未核到**可核官方条款。
- S4：遗物照片传进商业服务，家属因此不敢开工。
- S6：公司普遍禁止经营数据出公网；且某家通用 AI 的官方隐私政策确实写明输入可用于训练（需手动关）。

### I · INTEGRATION（一次成功了，但留不下来）

- S5：8 条里**唯一**一条以它为主障碍的。去重、归类、备份、冲印每个单点都已免费或低价可用，
  但清理与合并全是**一次性动作**（华为官方还写明要熄屏充电才跑分析），
  人物与事件归类只活在云端相册里、导出即丢，**没有任何供给保证"三个月后还干净"**，
  也没有人把"整理完 → 还整洁 → 变成一本相册"连成一条链。

一句只作为**假设**写下的话（不得当作已证）：

> World Space 的剩余机会可能不在"找到能力"，而在"让人敢把自己拿到的结果交出去"（§V/§T），
> 以及"做成一次之后能不能真的留在他的生活里"（§I）。
> 而 §V、§T 这两格按 `CONSTITUTION.md` §07 的纪律**不能靠更多自动化来填**。

---

## 3. Fixture 实测（Mission 8：能跑的就真跑）

`research/capability-reach/fixtures/`：4 份**自生成虚构**周报表 + 合并脚本 + 结果文件，可本地重跑复核。

```text
按列位置合并  金额合计 162.90（真值 186.90，差 −24.00）＋ 凭空多出一个假品名，全程 0 报错
按表头合并    金额合计 186.90（对）；但"数量单价填反"那行让 香蕉 数量 7 → 9.1，
              其金额仍为 29.40（对）—— 总数核对无法发现明细已错
结论         仅支撑 TECHNICAL / OPERATOR FEASIBILITY。REAL HUMAN CASES = 0
```

未跑的 fixture 及原因：假数字截图 OCR、公开音频转写、虚构手写页识别——**都需要真调外部视觉/语音服务**，
本轮按"不擅自消耗预算、不碰生产配置"的边界未执行（预算现状：公网账本月 `1.494026` / `20`，本轮 0 次消耗）。
这三项是**下一轮最该跑的**，因为它们直接检验 §V。

---

## 4. 竞争层地图（Mission 14：不给品牌排总榜）

```text
基础模型        已把"看懂图/听懂话/写通顺"变成水电气；没有把"这件事跟我有关"变成能力
Agent / Work    正在吃掉"多步骤执行"（Cowork / 秒悟 / 千问定时任务 / 飞书自动化）
                —— 但入口语言仍是 Agent/积分/席位，中国大陆在多项上直接不可得（Copilot 例外区）
开源执行框架    能力真实存在且活跃（pandas 3.0.6 / FunASR 1.4.16 / PP-OCRv5 / whisper），
                门槛是终端、GPU、Python、服务器 → EXPERT_REACHABLE，不是普通人可达
中国通用 AI     免费、手机、中文、不翻墙、不用信用卡 —— 这一层是 2026-09 中国普通人的主入口
成熟普通软件    Excel 透视表、手机相册、微信自带能力、企业微信快捷回复：多次在本轮直接赢过 AI 方案
World Space     机会只存在于上面五层用完之后仍然留给普通人的那段断层
```

**已判定退出候选**（详见 §1 各条与 §7）：S2 图片转表格、S6 重复月报、S7 个人页面、S8 重复回复。

---

## 5. 顺带审了我们自己：产品清单里的主张已经出现"误指路"级过期

供应侧审判的过程中，同时把 `catalog/resources.json` 与用户可见文案里的事实主张
（免费额度、水印、会员门槛、按钮名、系统要求）对官方现状重核了一遍。**结果不体面，如实记。**

| 严重度 | 我们文件里的原话（位置） | 我们声称 | 现在实际是什么 | 证据（official，2026-09-19） |
|---|---|---|---|---|
| **高** | `catalog/resources.json:136,147` | `"cost_category": "可以免费开始"`；`why_selected` 原文："如实标注：**免费模板够用**，但部分模板导出带水印、商用要看授权" | 官方价目页：可免费下载标注"**仅公益免费模板**"；无水印下载与**个人商用授权**在模板会员 ¥159/年（AI ¥319、大会员 ¥469，自动续费）之后。我们确实提醒了"商用要看授权"，但**"免费模板够用"这一句偏乐观**：用户按我们的话去下载，会在导出这一步才撞上会员墙 | gaoding.com/buy-svip |
| **高** | `resources.json:19,34`、`paths/step-1-first-small-task.md:11` | 豆包"免费"（无保留） | 2026-07 起有收费专业版 ¥68/200/500 每月，"部分原免费功能现弹付费"；基础对话仍免费；官网无可核价目页（/pricing /vip 为空壳）→ 该主张目前只有媒体支撑 | 163.com/dy/article/L5V935E60556BZTG.html（media，2026-09-04） |
| 中 | `resources.json:181,191,202` | `one_line`："字节出品的**免费**修图 App，滤镜、调色、消除路人都能做"；`cost_category`: 免费 | 官方在架页明列【自动续费会员】，专属妆容/精致滤镜特效在会员内；媒体称 AI 消除为 SVIP 权益 → "免费"与"消除路人都能做"两句都会让人在应用内撞墙 | itunes.apple.com/cn/lookup?id=1500526240 |
| 中 | `paths/step-3-find-answers.md:11` | "打开输入框下方的「深度思考」和「联网搜索」" | 2026-09 报道：模式已合并，搜索改称「智能搜索」，旧按钮名不再 → 用户找不到开关（文案有"找不到就直接发"兜底） | i.ifeng.com/c/8wIzoVxyeZH（media） |
| 低 | `resources.json:174` | 一刻相册因 yike.com SSL 异常而以 App Store 为来源 | yike.com 今日仍 TLS 失败，但官方可达站是 **yike.baidu.com**(200)，我们没引用 | yike.baidu.com |
| 低 | `resources.json:3` | `last_reviewed_at: 2026-09-07/11` | 距本轮已 8–12 天，且上面几条已变 | — |

**关键上下文**：`resources.json:4` 的 `reviewer_note` 写着 2026-09-07"doubao/deepseek/gaoding/xingtu/yike_album
**free tiers confirmed**"——也就是说这一批"免费"主张是被**当作已核实**登记进仓库的，而本轮复查里
其中至少两条（稿定、豆包）与现状不符。这说明问题不是某句话写错，而是**这套核对的保质期比想象的短**：
8–12 天就足以让一条推荐变成误指路。

**另外两处"被当成已核证事实"的主张，本轮核不实**：

- `docs/v2/NORTH_STAR.md:146` 把"通义听悟免费额度"列为 PR #25 已核证素材——官方站只有"免费体验"，
  **没有额度数字**，媒体口径互相矛盾（每月 10 小时 vs 每天 10 小时）。这条与 §1-S3 的独立发现是同一件事。
- `docs/goal-coverage.md:27` 剪映字幕转会员：仅媒体佐证，无官方原文。

**可达性核对（决定这是"潜在"还是"正在"误导）**：本轮实测 `https://www.ymai.fun/` 与
`https://yueminghub.github.io/World-Space/` 均经 2 次重定向落到 `https://ymai.fun/login`；
深层路径 `web/index.html` 为 404。**所以带这些旧文案的面板版目前公网打不开，风险是潜在的，不是正在发生的。**
但只要 V1 重新被发布，上面"高"两条就会变成误指路。

**本轮没有修改 `catalog/resources.json`、`paths/` 或任何前端文案**（Lab §16 禁止施工 + 不部署）。
修复动作与判据已写进 `research/capability-reach/NEXT_CANDIDATES.md` NC-08。

---

## 6. 补充证据（§1 未展开的定价与"活着吗"）

```text
v0.app/pricing            Free $0/mo、含 $5 credits、7 msg/day；Plus $30        official  2026-09-19
stirling.com/pricing      桌面版免费，含 Web/桌面/自部署；v2.14.3（2026-08-06）  official  2026-09-19
                          Win .msi / mac .dmg / Linux .deb，活跃维护
itunes.apple.com/cn/lookup?id=1467852587  一刻相册 V6.37.6（2026-09-05）在架，
                          商店文案仍写"无限存储空间…无限量原画质备份"（宣传语，非书面条款）
support.apple.com/zh-cn/HT201238          iCloud 照片免费 5GB                   official
support.apple.com/en-us/guide/iphone/iph1978d9c23/ios  iPhone 合并重复项目为官方功能
定价（S7）                 秒悟 Meoo 注册送 1 万积分、免费版即自动生成可访问链接；
                          万小智体验版 9.9 元起但"必须购买对应版本才可以发布上线"；
                          v0 免费 $5/月额度、Lovable 每日 5 点、Bolt.new 每日 30 万 token 不要信用卡
                          —— 后三者的发布地址均为境外默认域名（大陆可达性 unverified）
已下线                    Gitee Pages 官方帮助页标题即"功能已下线"
```

---

## 7. EXIT CANDIDATES —— World Space 不该做的事

这部分是本轮最重要的产出。**下面每一条都意味着：不要再为它设计 World Space 功能。**

| # | 场景 | 已经被谁吃掉 | 我们该做的（按 AGENTS.md §4「可以直接跳出去」） |
|---|---|---|---|
| E1 | 图片/截图 → 结构化表格 | 手机端多款免费通用 AI；iOS 实况文本可取纯文本 | **退出**。最多留一句"结果要逐格核对" |
| E2 | 每月重复报告 | Excel 模板＋透视表（自动刷新）、飞书多维表格定时自动化；Copilot 在中国个人不可得 | **退出**。"复制上月改数字"在很多公司仍是正解 |
| E3 | 不会编程做公开个人页面 | 微信生态公开页 + 国内免费建站二级域名，0 元 0 备案 | **退出**，直接带用户过去；只保留"让别人真能打开"这一句风险提示 |
| E4 | 大量重复回复 | 企业微信自带快捷回复与免费客服机器人、公众号自带自动回复 | **退出**。个人微信挂机器人有封号条款，**不得推荐** |

**这 4 条不是研究失败。** 按 Lab §11，它们是 `WORLD_SPACE_REMAINDER = NONE` 的场景。

⚠️ 但这 4 个 EXIT 判定全部只基于供应侧证据。**在真人身上判 EXIT 才是终判**——
每条都附了可证伪观察（见 §1 各条末尾）。

---

## 8. HUMAN TEST CANDIDATES —— 只剩这四条值得拿真人去验

按 Lab §12 的五件套逐条检查后才留下。**今晚只能写"候选"，不能写"已证实 Reach Gap"。**

### H1｜S1 每周合多个 Excel

```text
Capability Exists        确定存在：Power Query 从文件夹合并（微软官方，Excel 2016–365）、
                         多家免费通用 AI 支持上传多 xlsx 出表
Suspected Reach Gap      他能起跑，但拿到的表可能悄悄是错的，而他没有发现错误的手段
Suspected Barrier        VERIFICATION（主）+ TRANSLATION（次）
Why Direct AI may not    原话直问能拿到"一个看起来完成的文件"；本轮 fixture 已证：错的方式是
                         "总额对、明细错"（数量 7→9.1，金额不变），这种错任何一句话回答都不会提示
够不够真人观察什么        真人拿到合并结果后，自己会不会去核、会不会核、核不核得出来
```

### H2｜S3 大量会议录音整理

```text
Capability Exists        确定存在：手机端免费转写 + 纪要 + 待办（多家在架产品自述）
Suspected Reach Gap      存量批量导入、跨录音检索、以及"敢不敢把录音交出去"
Suspected Barrier        ACCESS（逐个导入排队）+ TRUST（留存与训练条款核不到）
Why Direct AI may not    单条录音能过；几十条旧文件与"以后还能找回来"没有产品承接；
                         额度与规格自相矛盾（商店"不限时" vs 文档"单文件 ≤6 小时、待办最多 6 条"）
够不够真人观察什么        真人拿 10 条约 8 小时旧录音，30 分钟内零付费能否跑完导入→纪要→待办→导出并检索命中
```

### H3｜S4 手写资料数字化

```text
Capability Exists        部分存在：厂商自述手写识别 90%~92%（官方口径），
                         且市场用价格承认了人手兜底：手写录入 40–68 元/千字 vs 印刷体 15 元/千字
Suspected Reach Gap      转录本身能跳出去；缺的是"这句话到底什么意思、哪几页值得留"
Suspected Barrier        VERIFICATION（无 ground truth，模型把缺笔补成通顺假句）
                         + TRUST（遗物照片进商业服务，无中文可核条款 → 家属不敢开工）
Why Direct AI may not    它会给你一份读得通、但可能全是编的转写；错误在"通顺"里被藏起来
够不够真人观察什么        真人的父亲手稿喂给免费 App 后，另一位家属是否必须逐字校对；
                         若必须，且家属因隐私不敢开工 → Gap 存活
```

### H4｜S5 手机里几千张照片一直没整理

```text
Capability Exists        确定存在：iPhone 合并重复项目、华为清理、iCloud/一刻相册/腾讯相册管家、
                         ¥1 离线搜索 App、世纪开元冲印（均有官方页）
Suspected Reach Gap      第一次能整理完，但维持不住，也没有变成任何成品
Suspected Barrier        INTEGRATION（主）+ TRUST（全家面孔 + 两次真实停运前科 + "无限空间"查不到书面条款）
Why Direct AI may not    这不是模型能答一次的问题：它需要一次性动作变成长期习惯，
                         而今天所有供给都是"跑一次"的（华为甚至要熄屏充电才分析）
够不够真人观察什么        只给一句入口指引，30 分钟内能否完成去重＋人物相册＋第二份副本；
                         **4 周后是否还干净**；他自己有没有做出过一次相册/合集
```

**四条的共同点**：都**不是**"找不到工具"，而是
"拿到了结果，但不敢信、不知道怎么核、不敢把数据交出去"（H1/H2/H3），
或"做成了一次，但没留在生活里"（H4）。
→ 这是本轮唯一值得带到明天真人实验去的结构性假设。它仍然是**假设**。

---

## 9. Path A 基线提案（Mission 12 · 状态：PROPOSED，未批准）

**推荐 China 基线：豆包 · 免费版 · 手机 App 默认「对话」模式**（doubao.com 网页为备用入口）。

按 Lab/任务的五条排序标准逐条：

```text
1 目标人群现实可访问  5/5  中国区商店在架、免费、v15.1.0（2026-09-15 更新），
                         商店评分数 4,377,294（约为同类 14 倍）；手机号/抖音/Apple 登录
2 通用能力足够强      4/5  官方自述含联网搜索、语音输入输出、拍照识图、表格/PPT/文档；扣分：高级模型属付费项
3 中文自然            5/5
4 无需技术设置        5/5  不翻墙、不用信用卡、不装东西
5 稳定公开产品        5/5  三份官方协议 2026-09-17 生效，非内测、无下线公告
```

为什么不选别的：**DeepSeek** 免费无分层，但官方入口自述止于"问答"，12 条 case 里至少 5 条会因传不上图/音失败，
那会混淆"能力不存在"与"入口不可及"；**元宝** 免费、微信登录、录音转写不限时，只差装机量（列为第 2 顺位）；
**千问/夸克** 首页即智能体广场，入口噪音对 50+ 不友好；**Kimi** 是评测里最强的一档，但产品语言是 Agent 集群/Code/Claw，
**正是 §7 要排除的人看不懂的那层**；**星火** 有连续订阅、心智低于豆包；**ChatGPT / Gemini** 经 Apple 目录实测
**中国区 NOT LISTED**（只有同名山寨 App），需境外号码＋网络，违反第 1、4 条；**Claude** 上架状态未核到官方条目，标 unverified。

**必须拆两条基线**：China＝上面那个，12 条 case 全跑、由真人自己操作；
Global＝境外免费版同类产品，只在 A 判"没做到"的 case 上由研究者在境外环境代跑同一句原话，
用来回答"这能力今天到底存不存在"。**两条分母不同，禁止合并比较。**

**替换触发条件**：豆包免费额度或分时段限制收紧→换元宝；元宝上传文件需付费→换 DeepSeek，
并把"传不上"本身记为发现；豆包默认强推 Agent 且无法退回普通对话→**停跑上报**，不擅自继续。

**冻结协议（要固定下来的动作）**：用参与者自己的手机 App；只用默认对话，禁用「工作任务」/智能体/自定义提示；
原话逐字输入含错别字，研究者不补话术；允许追问但上限 3 轮、问什么由参与者决定；
跑前截首页（UI 上显示的模型名与额度提示），每轮全屏截图；记录是否会员、剩余额度、时段；
研究者另用一个免费账号跑同一句作对照；本轮不主动升级，被迫升级记日期；每次调用计入成本。

> ⚠️ 与 §5 的交叉冲突必须让批准人看见：**我们对外承诺豆包"免费"，而媒体口径是 2026-07 起有 ¥68/200/500 专业版、
> 部分原免费功能弹付费，官方无可核价目页。** 拿它当 Path A 基线在"现实可访问"上是对的，
> 在"我们的产品文案"上会自相矛盾——两件事都要修，且不能互相掩盖。

**STATUS: 已批准（2026-09-19）** —— 冻结位置是 Lab **§21**（不是 §19；§19 是未决项清单）。
状态：`PATH_A_PROTOCOL = APPROVED_FOR_WAVE1`，只授权到 Wave 1。
上面那段"与自家文案自相矛盾"的问题**仍未修**（NC-08，需 Founder 批准才动对外数据）。

---

## 10. 本轮的现实边界（重申，不许以后被省略）

```text
REAL HUMAN CASES        = 0
本文证据等级             = Machine / Operator Evidence
ORDINARY_REACHABLE 宣布  = 0 次（本轮没有资格宣布任何一个能力进入此状态）
大陆网络侧可达性实测      = 未做（本轮出口在境外）
真人实验消耗            = 0 次调用；公网账本 month_cost_rmb=1.494026 / 上限 20（healthz 实读）
H1（Reach Gap 是否真实） = UNRESOLVED
H2（方法是否有剩余价值） = UNRESOLVED
H3（是否需要独立产品）   = NOT YET TESTED
V0.2 开发               = NOT AUTHORIZED
```

