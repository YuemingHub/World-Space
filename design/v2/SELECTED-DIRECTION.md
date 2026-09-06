# SELECTED-DIRECTION（v2 重构轮）

## 决定
延续 v1 已批准的 Storytelling · 叙事极简模板方向（templateRef: https://baizhi.cloud/landing/design-prompt/detail/storytelling）。

## 依据
1. 该模板由用户在 v1 轮选卡中**明确选中**（v1/SELECTED-DIRECTION.md 在案）。
2. 该视觉系统已通过 v1 全部验证：design-jury R2 复合 8.0（passed）、渲染质量门 89/100（passed）。
3. 本轮需求是内容结构重构（看见→学会→陪跑）而非视觉方向更换；design-refinement 技能要求 bounded refinement 保留既定方向。

## 程序记录
- 图像生成 MCP 因钱包余额不足（-32010）无法产出方向图，按流程回退模板推荐。
- 模板卡唤起后 10 分钟超时无用户响应（no template selection after 10m0s）。
- 依据 design-flow"无交互工具时自动选最强推荐"规则落定推荐项，非用户现场选择；用户此后仍可要求换向。
