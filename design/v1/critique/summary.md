# Design Jury Summary

## Round 1 — 7.55/10

- Passed: false
- Must-fix findings: true

### Designer — 7.00/10

证据限制说明：本环境无图片查看工具，4 张截图均无法查看，评审完全基于源码与规范推导。总体评价：分节顺序严格服务叙事弧（hero→信念对比→引言带情绪拍点→故事→四步方法→CTA→页脚），与 brief 逐条对应；每节 eyebrow→h2→lede 层级一致，唯一 h1 且无标题跳级；移动导航实现正确可用（aria-expanded/aria-controls、点击链接自动收起）；focus-visible 全局覆盖，reduced-motion 做到 CSS 与 JS 双层覆盖；示例内容以角标/徽章/页脚三重标注，锚点全部可达无死链。主要扣分：字体从未加载导致 DESIGN.md 视觉权威的排版身份无法呈现，故事区缺少规范要求的暖色插画大图卡，按钮 hover/active 状态映射偏离视觉基础，另有 OG/favicon 等部署件缺失。

- **must_fix**: 字体资源完全缺失：文件声明了 Abril Fatface/Inter/JetBrains Mono 字体栈，但全文件没有任何 @font-face、字体 <link> 或自托管 woff2，访客端永远回退系统字体，DESIGN.md（视觉权威）规定的排版身份无法呈现。 (Evidence: prototype.html:23-25；platform.md:14-16)
- **should_fix**: 按钮状态映射偏离视觉基础：主按钮默认底色即 --accent-strong，hover 变 --accent-press，:active 仅 1px 下压而无底色变化；规范要求 hover 用 --accent-strong、active 用 --accent-press，--accent 主 token 几乎未用于 CTA。 (Evidence: prototype.html:10-12,69-73；visual-foundations.md:79)
- **should_fix**: 故事区未实现规范要求的扁平暖色插画大图卡（纸感底、sun/leaf/蓝三色、粗轮廓、alt 必填），四张卡片仅以 24px 单线小图标替代，削弱「温暖童趣」的情感目标与故事区应有的「呼吸」对比。 (Evidence: prototype.html:239-264；visual-foundations.md:67,72-74；brief.md:28,36)
- **should_fix**: 色彩纪律超标：故事区同屏 4 张卡片图标均为 --accent-strong 蓝色且该屏无 CTA 抵扣，超出「每屏 --accent 可见使用 ≤2 处」约束。 (Evidence: prototype.html:126-128,241,247,253,259；visual-foundations.md:58)
- **should_fix**: 部署元信息缺失：无 Open Graph 标签、无 favicon 链接，<title> 与 platform.md 指定的标题文案不一致。 (Evidence: prototype.html:3-7；platform.md:31)
- **should_fix**: 缺少 overflow-wrap:anywhere 防长词横向溢出兜底（platform.md 明确要求）；375px 下 .formula 公式串与 ymai.fun 等拉丁串无保护。 (Evidence: platform.md:21；prototype.html:37-49)
- **nice_to_have**: 移动端 h1 断行欠佳：固定 <br> 叠加 clamp 最小值 2.6rem，375px 视口首行「普通人，也可以用 AI」约 389px 必然提前折行形成三行不规则断行，「现实。」成为孤行。 (Evidence: prototype.html:26,190)
- **nice_to_have**: 分节密度节奏未真正交替：所有 section 共用同一 padding-block 且相邻节 padding-top:0；规范定位为「全宽引言带」，实现为容器内圆角深色卡片。 (Evidence: prototype.html:61-62,114-115,227-231；visual-foundations.md:67-68)
- **nice_to_have**: 细节 token 偏差：eyebrow 字距 .14em 高于规范的 .08em；--text-display clamp 下限低于规范；--fg-soft 取 #5B6472 而非规范的 #6B7280。 (Evidence: prototype.html:21,26,56-57；visual-foundations.md:22,31,52)
- **nice_to_have**: 移动导航状态补全空间：无 Esc 键/点击面板外关闭，窗口拖宽时面板状态不复位；.nav-toggle 无 hover 态。 (Evidence: prototype.html:88-89,159-167,332-339)

### Critic — 8.00/10

代码级审查确认反 AI-slop 七宗罪全部通过：无 indigo/#8B5CF6 实际使用、无任何渐变、无 emoji 图标、display 均走 var(--font-display)、卡片为 8px 编辑感圆角+全边框、无编造指标、无 lorem 填充；示例内容标注是亮点。主要扣分点：三套字体仅声明字体栈却无任何加载机制，部署时静默失效且未经验证；accent/sun 两处色彩纪律违反自定规则；缺少 OG/favicon。证据限制：工具集无图片查看能力，截图未能视觉核验，结论基于源码。

- **should_fix**: 展示字体 Abril Fatface/Inter/JetBrains Mono 只声明了字体栈，整个文档无任何 @font-face 或加载机制，部署后 display 将静默回退，Storytelling 模板的中西文对比身份无法兑现。 (Evidence: prototype.html:23-25；platform.md:15)
- **should_fix**: 故事区 4 张卡片图标统一使用 --accent-strong，单屏 accent 可见使用 4 处，超出自定色彩纪律 ≤2 处，蓝底图标块也是接近模板腔的重复模式。 (Evidence: prototype.html:128,241,247,253,259；visual-foundations.md:58)
- **should_fix**: --sun 违反自定「每节 ≤1 处」纪律：method 区 4 个步骤序号全部 --sun（同屏 4 处），belief 区另有顶部描边+引言引号 2 处，暖色从点缀退化为常规强调色。 (Evidence: prototype.html:140,274,279,284,289,106,117；visual-foundations.md:59)
- **should_fix**: 缺少 Open Graph 标签与 favicon（部署后 /favicon.ico 404），页面标题与平台约束指定文案不一致。 (Evidence: prototype.html:3-7；platform.md:31)
- **nice_to_have**: 「全宽引言带」未做全宽：quote-band 位于 .container 内、带圆角阴影，实为容器内深色圆角块，削弱打破模板骨架的效果。 (Evidence: prototype.html:114-115,227-231；visual-foundations.md:68)
- **nice_to_have**: token 外裸 hex 共 4 处+2 处 rgba，满足 ≤6 锚点，但手绘下划线 stroke=#D97706 与页头 rgba 均为 token 值手工复制，易失同步。 (Evidence: prototype.html:190,78,114,118,70,73；visual-foundations.md:94)
- **nice_to_have**: --fg-soft 实际取值与 visual-foundations 定义不一致（token 漂移）；hero-note「三分钟读完全页」为页面自身不可验证的软性量化承诺。 (Evidence: prototype.html:21,196；visual-foundations.md:22)

### Brand — 7.00/10

灵魂 20% 四项全部真实落地：手绘 amber 描边、滚动进度线、印章角标、拒绝「了解更多」的 CTA 文案。宋体 display 与中文正文栈成立，无渐变 hero、无紫蓝、无 emoji 图标，secondary 紫未进入首屏，品牌名三处一致呈现——整体像有灵魂的品牌站。但存在真实缺口：375px 下 h1 与 ghost CTA 被裁切的横向溢出损害移动首屏；Abril Fatface 未自托管，故事书中西文对比在渲染中回退；故事区缺席扁平暖色插画；--sun 纪律被打破。

- **must_fix**: 375px 移动端存在横向溢出：h1 首行「普通人，也可以用 AI」与 ghost 按钮「先看看他们的故事」均在右缘被裁切，违反「移动端无横向滚动」验收；根因是 --text-display clamp 下限 2.6rem 下 h1 首行约需 470px，超出 343px 可用宽，需为小屏增加更小字号档或允许断行。 (Evidence: screenshots/mobile-hero.png；prototype.html:26,190；brief.md:50 与 visual-foundations.md:95)
- **should_fix**: 移动端首屏截图中头部仅有品牌字标，无任何可见导航入口（无「菜单」按钮），与代码声明不一致，须复核真实渲染；若真实设备确无导航入口则构成发布阻断。 (Evidence: screenshots/mobile-hero.png；prototype.html:88-89,159-166,175)
- **should_fix**: 核心品牌字体资产缺失：原型无任何 @font-face 或字体文件引用，Abril Fatface 在绝大多数访客环境必然回退，「英文术语由 Abril Fatface 承载」的故事书气质实际未成立。 (Evidence: prototype.html:23；platform.md:15；visual-foundations.md:54；screenshots/desktop-hero.png)
- **should_fix**: 故事区插画缺失：要求「扁平暖色插画（纸感底、sun/leaf/蓝三色、粗轮廓）」且 alt 必填，原型四张故事卡只有 24px 单线小图标，「温暖童趣」仅靠三枚小涂鸦与 amber 点缀支撑。 (Evidence: visual-foundations.md:73；prototype.html:240-263；screenshots/desktop-full.png)
- **should_fix**: 强调色纪律失守：方法区 4 个 step-num 全部 amber（单节 4 处），hero 首屏 amber 系可见 3 处，全局 sun 色进度线常驻每屏顶部；--accent 每屏≤2 处同样被破（故事区 4 个蓝色图标、hero 3 处蓝色）。 (Evidence: prototype.html:140,106,117,57,97-98,75,128；visual-foundations.md:58-59)
- **nice_to_have**: 深色引言带与「温暖明亮」基调存在张力：近黑大色块是全页唯一冷暗面，可考虑暖纸反白或暖深色。 (Evidence: prototype.html:114-118；screenshots/desktop-full.png；brief.md:36)
- **nice_to_have**: token 漂移未回写真源：原型引入未声明的 --sun-ink、--bg-deep，改动 --fg-soft、display clamp、eyebrow 字距；amber 出现双轨（--sun-ink 与裸 hex #D97706 并存）。 (Evidence: prototype.html:14,18,21,26,56,190；visual-foundations.md:3,22,31,52)

### Accessibility — 8.00/10

原型整体符合 WCAG 2.2 AA 基线：landmark 完整、单 h1 无跳级、列表语义正确、装饰 SVG 全带 aria-hidden、lang=zh-CN、无 tabindex>0、无键盘陷阱、无裸 outline:none，reduced-motion 双重处理，aria-expanded 实现正确。自行计算颜色对：#111827/#FAF9F6≈16.8:1、#4B5563≈7.2:1、#5B6472≈5.7:1、白字/#2563EB≈5.2:1、#B45309≈4.8:1，全部达标；焦点环 4.9:1≥3:1。触控目标均过 2.5.8 最低值。主要问题：无 JS 时移动端导航整体不可用；菜单按钮边框是非文本对比度短板；四张截图存在布局视口与视觉视口不一致的伪影（375px 图但布局约 600px 宽，菜单按钮不可见、内容右缘裁切），1.4.10 与触控目标两项须按 375px 仿真重截复验。

- **should_fix**: 无 JS 降级缺失：≤767px 时 .site-nav 为 display:none，仅靠 JS 切换 .open 类，禁用 JS 后菜单按钮点击无效，导航链接和头部主 CTA 全部不可达；建议无 JS 时默认展开或用原生方案兜底。 (Evidence: prototype.html:159-167,332-339)
- **should_fix**: .nav-toggle 边框 #E7E5E0 对 #FAF9F6 对比度仅约 1.2:1，低于 WCAG 1.4.11 非文本 3:1；该按钮无填充，1.5px 描边是移动端唯一导航控件的可见边界，建议改用 --fg-muted 以上颜色描边。 (Evidence: prototype.html:22,88-89)
- **should_fix**: 截图证据失效：mobile 截图显示内容右缘裁切、「菜单」按钮不可见、h1 首行被切断，但单列网格 media query 已生效——布局视口与视觉视口不一致，属截图仿真伪影；须用真实 375px 仿真重截后复验。 (Evidence: screenshots/mobile-hero.png、screenshots/mobile-full.png；platform.md:19)
- **nice_to_have**: 移动菜单缺少 Esc 键关闭与关闭后焦点管理；非 WCAG 硬性要求，属 WAI-APG 完整度增强。 (Evidence: prototype.html:332-339)
- **nice_to_have**: 无「跳到主内容」skip link；建议在 header 前加视觉隐藏、聚焦可见的跳转链接。 (Evidence: prototype.html:170-186)
- **nice_to_have**: :focus-visible 规则覆写 border-radius 为 4px，导致 8px 圆角主按钮聚焦瞬间形状跳变，应删除该覆写（现代浏览器 outline 自动跟随圆角）。 (Evidence: prototype.html:47,67)
- **nice_to_have**: token 漂移：--fg-soft 实际 #5B6472 与文档 #6B7280 不一致，应同步避免回退到低对比值。 (Evidence: prototype.html:21；visual-foundations.md:22)
- **nice_to_have**: 说明性文字误用 <strong> 语义：过去清单中的理由文本被标为 strong，屏幕阅读器可能播报强调语气，建议改为 <span>。 (Evidence: prototype.html:211-214)

### Copy — 8.00/10

整体文案质量高：信息层级完整顺畅（Hero 主张→信念对比共鸣→故事证据→四步方法→行动），标签与锚点基本对应，虚构人物采用三重「示例」标注，无编造的百分比或增长数据，语气温暖鼓励、不爹味不幼稚，公式填空形式对 10 岁孩子易懂。证据限制：工具集无法查看图片，评审证据全部来自源码文本。主要扣分点：一处明确病句（「一本留自己」），三处主 CTA 文案承诺「开始创作」但落点均为 #method 阅读区（符合 brief 占位约定，上线前需替换），另有若干用词小瑕疵。

- **must_fix**: 病句且数量不闭合：「印了三本——一本给儿子，一本留自己」中「留自己」缺介词应为「留给自己」，且「三本」只交代了两本去向（孙女仅是帮忙排版），读者会察觉细节失真，削弱以文字质量立信的页面可信度。 (Evidence: prototype.html:255)
- **should_fix**: CTA 意图与落点错位：导航、Hero、尾部三处「开始你的第一个创作」均指向 #method（方法说明节），用户点击后得到的是「再读一段」而非「开始做」；brief 已注明真实链接由用户提供，属约定占位，上线前必须替换为真实创作入口。 (Evidence: prototype.html:182,193,301；brief.md 主行动)
- **nice_to_have**: 诚信细节矛盾：引语中孩子说「我画的恐龙会动了」，但对应故事卡明确写「AI 帮他画插画」（孩子是导演）。建议引语改为「我做的恐龙会动了」。 (Evidence: prototype.html:228 与 243)
- **nice_to_have**: 量词与歧义：「最后一个 12 页的电子绘本」中绘本量词应为「本」，且「最后一个」易被误读为「最后一本」，建议改为「最终，一本 12 页的电子绘本……」。 (Evidence: prototype.html:243)
- **nice_to_have**: 动宾搭配不当：「跟着 AI 学会了第一段代码」搭配别扭，建议「写出了人生第一段代码」；「浇花提醒」与「浇水提醒小程序」用词不一致，宜统一。 (Evidence: prototype.html:260-261)
- **nice_to_have**: 步骤 01 文案：「套用这句话术」的「话术」带销售腔，建议「句式」；建议在旁补一个填好的示例。 (Evidence: prototype.html:276)
- **nice_to_have**: 导航与节内措辞不一致：导航「为什么可以」与节 eyebrow「为什么是现在」措辞不同，建议统一。 (Evidence: prototype.html:178 与 204)
- **nice_to_have**: 儿童词汇门槛：「天赋异禀」为成语，10 岁孩子可能不识，可替换为更平白的「不需要天分」。 (Evidence: prototype.html:7,191,286)

## Round 2 — 8.00/10

- Passed: true
- Must-fix findings: false

### Designer — 8.00/10

本轮截图可正常查看。三项 R1 must_fix 逐条核查：①字体修复到位——@font-face data URI 内嵌 Abril Fatface latin 子集并声明 font-display:swap，截图中品牌字标、hero 的 AI、步骤序号均以该衬线渲染，故事书身份成立；②移动端加固代码全部在位，mobile-hero/mobile-full 目视无裁切，另做像素级右缘检测确认 375px 无内容贴边（注：截图内读数因采集 flag 缺失显示 FRAME-ERR，测量链断，需带 --allow-file-access-from-files 重截恢复；已在本轮提交前重截修复）；③病句修复到位且数量闭合。信息架构与 brief 五段式逐条对应，单 h1 无跳级，示例标注三重覆盖，移动端「菜单」按钮本轮可见。未过项集中在故事区插画、色彩纪律、部署元信息等 should_fix 级。

- **should_fix**: 375px 客观溢出读数失效：四张截图顶部均为「FRAME-ERR Cannot read properties of null」而非预期 NO-OVERFLOW——采集装置经 file:// 加载时 iframe contentDocument 为 null，测量未执行。本人以像素级右缘检测替代核验（四图右缘 9px 内无内容像素，目视无裁切），fix 本身大概率有效，但须恢复客观证据链。 (Evidence: screenshots/mobile-hero.png（顶部读数）；screenshots/desktop-hero.png；capture/frame-mhero.html:9-12)
- **should_fix**: 移动端首屏 h1 排版瑕疵：≤560px 隐藏 <br> 后「AI」与「把」之间无空格（源码 AI 后直接接 <br>），中西文粘连；且行尾「。」孤行。建议 AI 后补空格并用 text-wrap:balance 约束。 (Evidence: prototype.html:197,161-163,43；screenshots/mobile-hero.png)
- **should_fix**: 故事区插画缺失（R1 should_fix 遗留）：四张故事卡仍以 24px 单线图标替代扁平暖色插画大图卡，故事区应有的「呼吸」节奏与「温暖明亮略带童趣」的情感目标未兑现。 (Evidence: prototype.html:248,254,260,266；visual-foundations.md:73；screenshots/desktop-full.png)
- **should_fix**: 色彩纪律仍超标（R1 遗留）：故事区同屏 4 个卡片图标均为 --accent-strong；方法区 4 个步骤序号同屏 4 处 --sun。 (Evidence: prototype.html:128,248,254,260,266,140,281,286,291,296；visual-foundations.md:58-59)
- **should_fix**: 部署元信息缺失（R1 遗留）：无 OG 标签、无 favicon；<title> 与 platform.md 指定文案不一致。 (Evidence: prototype.html:3-7；platform.md:31)
- **nice_to_have**: 桌面 hero 截图为 reveal 渐显中途帧：h1/副文/CTA 呈半透明，属采集时机伪影而非页面缺陷；建议等动画结束或仿真 reduced-motion 后重截。 (Evidence: screenshots/desktop-hero.png)
- **nice_to_have**: 「全宽引言带」构图意图未完全兑现：仍为容器内圆角深色卡片而非全宽分节。 (Evidence: prototype.html:114-115,234；visual-foundations.md:68)
- **nice_to_have**: 交互状态补全空间：移动导航无 Esc/外点关闭、拖宽不复位，.nav-toggle 无 hover 态。 (Evidence: prototype.html:88-89,339-346)
- **nice_to_have**: 首屏可见字号 5 级，超出「首屏 ≤3 级」验收锚点，可合并 note 与 lede 层级。 (Evidence: prototype.html:196-203；visual-foundations.md:94)

### Critic — 8.00/10

第 2 轮评审（只读）。声明：本评审员工具集无法查看 PNG 截图，已改以 capture/frame-*.html 测量脚本源码与 CSS 加固代码交叉复核。R1 三项修复确认落实：内联 Abril Fatface @font-face（prototype.html:9）、375px 溢出加固（159-165）、病句清理。反 AI 模板腔七宗罪逐条核查全部通过；token 外裸 hex 4 处 ≤6 预算；--leaf 仅限打勾语义；装饰均可溯源至 visual-foundations §7。叙事连贯性好，文案有辨识度，示例内容三重标注满足 brief。扣分点：自定色彩密度纪律被自己打破、插画缺失、部署元信息缺失、375 修复曾新引入 H1 粘连（提交前已修）。无 must_fix。

- **should_fix**: 故事区色彩纪律超标（R1 遗留）：同屏 4 张卡片图标均为 --accent-strong 蓝色，超出「每屏 ≤2 处」。 (Evidence: prototype.html:128（.story-card .icon svg color:var(--accent-strong)）；visual-foundations.md §3)
- **should_fix**: 暖色 --sun 密度超「每节 ≤1 处」：hero 同时存在下划线与星形涂鸦；belief 节同时有顶边与引号；进度线常驻。 (Evidence: prototype.html:75,96-99,106,117,197,205；visual-foundations.md §3)
- **should_fix**: 故事配图扁平暖色插画仍缺失（R1 遗留）：无任何 img/插画元素。 (Evidence: prototype.html:246-271；visual-foundations.md §5、§4)
- **should_fix**: 375 修复新引入缺陷：≤560px 隐藏 br 后「AI」与「把」无空格粘连（已在本轮提交前以补空格+text-wrap:balance 修复）。 (Evidence: prototype.html:197 + 162)
- **should_fix**: 部署元信息缺失（R1 遗留）：OG/favicon 缺失，title 与 platform.md 指定文案不一致。 (Evidence: prototype.html:3-7；platform.md)
- **should_fix**: 按钮状态映射与视觉基础 §6 不一致且未回写规范；active 态缺少可感知反馈。 (Evidence: prototype.html:10-12,46-47,69-71；visual-foundations.md §6)
- **nice_to_have**: 手绘下划线 SVG 硬编码 stroke="#D97706" 未走 var(--sun)。 (Evidence: prototype.html:197（对照 205-207）)
- **nice_to_have**: 多处 token 相对 visual-foundations 静默漂移未记录，应改规范或改实现。 (Evidence: prototype.html:21,26,27,33,56；visual-foundations.md §1-§2)
- **nice_to_have**: 引言带未实现为全宽分节，仍为容器内深色圆角卡片。 (Evidence: prototype.html:114-115；visual-foundations.md §4)
- **nice_to_have**: 示例标注字号 .6875rem 偏小，建议 ≥.75rem 或提高对比权重。 (Evidence: prototype.html:130-135,237,251；brief.md 验收标准)
- **nice_to_have**: 移动导航为无焦点管理的 disclosure：无 Esc 关闭+外点收起。 (Evidence: prototype.html:339-346)
- **nice_to_have**: 交付形态与 platform.md 架构决策不符（单文件 vs 分离结构），交付部署前需拆分或更新说明。 (Evidence: prototype.html:8-9,175,319；platform.md；fonts/abril.woff2)

### Brand — 8.00/10

第 1 轮三项 must_fix 已核实落地：Abril Fatface 以 base64 内嵌，截图中品牌字标、hero 的 AI、步骤序号均呈现 fat-face 风格；桌面与 375px 截图读数均为 NO-OVERFLOW；文案通顺无病句。中文宋体 display 与拉丁 fat-face 搭配的「故事书」气质成立，灵魂 20% 四项全部落地，示例标注完备，品牌贯穿一致。扣分集中在纪律与资产层：--sun/--accent 自设用量纪律被突破、token 漂移、favicon/OG 缺失、规划中的暖色插画缺席。

- **should_fix**: --sun 突破自设「每节 ≤1 处」纪律：hero 同时有下划线与太阳 doodle，belief 节有顶边+引号，方法节 4 个序号均 --sun。 (Evidence: .ohmyagent/design/v1/prototype.html:97 与 197；:106 与 117；:140；对照 visual-foundations.md:59)
- **should_fix**: --accent 首屏可见 3 处（导航 CTA+hero CTA+doodle d2）超「每屏 ≤2」；故事区 4 个蓝色图标弱化主 CTA 唯一性。 (Evidence: .ohmyagent/design/v1/prototype.html:189,200,98,128；screenshots/desktop-hero.png；对照 visual-foundations.md:58)
- **should_fix**: token 与视觉真源漂移：--fg-soft、display clamp、eyebrow 字距等未回写文档。 (Evidence: .ohmyagent/design/v1/prototype.html:21,26,57；对照 visual-foundations.md:22,31,52)
- **should_fix**: 品牌资产缺口：无 favicon、无 OG 标签；title 与 platform.md 文案不一致。 (Evidence: .ohmyagent/design/v1/prototype.html:3-7；对照 platform.md:31)
- **should_fix**: 扁平暖色插画缺席，品牌温度的主要载体缺位。 (Evidence: .ohmyagent/design/v1/prototype.html:246-271；对照 visual-foundations.md:72-75)
- **nice_to_have**: 手绘下划线描边用裸 hex 而非 var(--sun)。 (Evidence: .ohmyagent/design/v1/prototype.html:197)
- **nice_to_have**: ≤767px 隐藏全部 doodles，移动端童趣点缀只剩下划线。 (Evidence: .ohmyagent/design/v1/prototype.html:100；screenshots/mobile-hero.png)
- **nice_to_have**: 375px 下 h1 因 text-wrap:balance 将「想法」跨行拆词，语感略受损。 (Evidence: screenshots/mobile-hero.png；prototype.html:161)

### Accessibility — 8.00/10

WCAG 2.2 AA 底线整体扎实：lang、landmark、唯一 h1、原生交互、aria-expanded 接线正确、focus-visible 4.9:1、scroll-padding-top 防遮挡、reduced-motion 双层停用、.js 门控使无 JS 时内容全可见、装饰 SVG aria-hidden、触控目标实测 40-53px、色对逐一复算全过 AA。本轮修复未引入新无障碍问题：@font-face 含 font-display:swap；截图实测证实 375px 无横向溢出且按钮几何正常（主按钮 198×52、次按钮 181×40）。扣分项为两处 should_fix：缺 skip link、Safari/VoiceOver 列表语义丢失。

- **should_fix**: 缺少「跳到主内容」skip link（WCAG 2.4.1 Level A）：键盘用户需依次越过头部全部元素才能到达正文。 (Evidence: prototype.html:179-193)
- **should_fix**: 四处 list-style:none 列表在 Safari/VoiceOver 下丢失列表语义，且 .steps 序号全部 aria-hidden，顺序信息可能丢失（1.3.1 风险）；建议补 role="list" 或让序号可被辅助技术感知。 (Evidence: prototype.html:281、136、85,108,120)
- **nice_to_have**: 无 JS 降级不完整：≤767px 无 JS 用户看到可聚焦的「菜单」按钮但点击无效。 (Evidence: prototype.html:166-170、339-346)
- **nice_to_have**: 移动导航未实现 Esc 关闭与焦点返回。 (Evidence: prototype.html:339-346)
- **nice_to_have**: 移动导航面板 top:64px 硬编码 header 高度，文本放大时可能脱节。 (Evidence: prototype.html:168、81)
- **nice_to_have**: --fg-soft 实现值与文档值不一致（实现侧对比度更优），建议同步。 (Evidence: prototype.html:21；visual-foundations.md:22)
- **nice_to_have**: h1 内使用 <br> 属表现性标记侵入结构，建议改用 CSS 控制换行。 (Evidence: prototype.html:197、162)

### Copy — 8.00/10

第 1 轮 must_fix 已确认修复（prototype.html:262，三本三去向、句子通顺）。整体信息层级清晰，密度适中，语气与 DESIGN.md 一致，CTA 具体不空洞。事实诚信好：全部虚构人物均明示「示例」，数字均在示例语境内，无编造全局统计。剩余问题：角标「由 AI 完成」与正文人主导叙事矛盾、尾部 CTA 向上回滚承诺落空、一处序数歧义，及引号统一等打磨项。

- **should_fix**: 四张故事卡角标「由 AI 完成 · 示例」与正文强调人主导/AI 辅助的叙事相矛盾，夸大 AI 角色，削弱「普通人自己创造」核心主张；建议改「由 AI 辅助完成 · 示例」或「人 + AI 共创 · 示例」。 (Evidence: prototype.html:251（同 257、263、269）对照 250/256/262/268；visual-foundations.md:90)
- **should_fix**: 尾部 CTA「开始你的第一个创作」href="#method"，用户刚读完方法区，点击向上回滚，行动承诺落空；尾部应指向真实创作入口占位。 (Evidence: prototype.html:308；brief.md:33)
- **should_fix**: 小宇卡「最后一个 12 页的电子绘本」序数误读歧义且量词不当，建议「最终，一本 12 页的电子绘本」。 (Evidence: prototype.html:250)
- **nice_to_have**: 中文强调引号排版不统一：正文用半角直引号，引言带用弯引号；建议统一全角。 (Evidence: prototype.html:213、228、245、250、288、293、307、315 对照 235)
- **nice_to_have**: 「浇花提醒」与「浇水提醒小程序」用词不一致。 (Evidence: prototype.html:267-268)
- **nice_to_have**: 「迭代」「话术」对 10 岁读者偏术语，建议口语化。 (Evidence: prototype.html:297、283)
- **nice_to_have**: hero 副标题「画面」窄化主题（故事含代码与书稿），建议统一为「想法」或「东西」。 (Evidence: prototype.html:198 对照 197)
- **nice_to_have**: 信念区「过去，你需要」标题语义与每行叉号相互抵消，孩子可能误读为「你不需要」。 (Evidence: prototype.html:216-221；screenshots/desktop-full.png)

