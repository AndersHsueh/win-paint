# outputs/

> **LLM 写目录。本目录下是 LLM 生成的对外/对内交付物。**

本目录存放**从 raw + wiki 派生**的所有产出,包括但不限于:

- 售前方案(.html / .pdf):技术方案、人力方案、报价方案
- 需求澄清材料(.docx / .xlsx):会前材料、会议纪要
- 系统设计文档(.docx):系统设计概要、数据库设计、接口设计、需求文档
- 报价表(.xlsx)
- 配套图表(.png / .svg,放在子目录 `diagrams/`)
- 截图证据(.png,放在子目录 `screenshots/`)
- 培训课件(.html):面向客户方的 4 课 / N 课培训材料
- 生成脚本(.js / .ts):用于程序化生成 docx / xlsx / html 的脚本

## 命名约定

- 方案类:`<类型>_<版本>.html`(如 `技术选型与实施方案.html` / `报价表_V2.xlsx`)
- 设计文档:`<类型>.docx`(如 `系统设计概要.docx`)
- 子目录:
  - `diagrams/` — 配套图(架构图 / 业务流图 / 时序图 / ER 图)
  - `screenshots/` — 截图证据(原型截图 / 部署截图)
  - `scripts/` — 生成脚本(如 `generate_docx.js`)

## LLM 行为约束

1. **可写** — 用 Write / Edit 生成 outputs 下文件
2. **生成时必登 log.md** — 详见 [[../wiki/工作流-ingest-query-lint#维护纪律]]
3. **可被 wiki 反向引用** — 在对应 wiki 主题页里说明"详见 outputs/X"的派生关系
4. **不可作为 wiki 互链的目标** — `[[outputs/X]]` 不算合规 wiki 链接;若要引用,用文字描述"详见 outputs/X" 或在 wiki 主题里加"## 关联输出"段列出
5. **派生关系要可追溯** — 任何 outputs 文件应在生成脚本里有对应入口,或 wiki 主题里有"生成来源"说明