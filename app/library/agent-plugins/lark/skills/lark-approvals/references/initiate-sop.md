# 发起审批 SOP

用户要求发起任何新审批时，必须按以下顺序执行，包括请假、报销、出差、通用审批和带附件审批。普通审批只整理实际提供的字段和附件；报销审批还要分析发票或收据。

## 1）整理原始材料

- 保留原始上传文件，不覆盖或改名。
- 压缩包先列出目录，再解压到新建的 workspace 相对目录。可使用 `unzip`、`7z`、`unrar`、`tar` 等已安装工具。
- 发现绝对路径、通过 `..` 越界的路径或符号链接时，停止解压。
- 忽略 `__MACOSX`、`.DS_Store` 等归档元数据，但不得漏掉真实业务文件。
- 加密、损坏、格式不支持或解压后体积异常时，告诉用户具体问题，不猜密码，不继续提单。

## 2）逐文件分析

普通审批至少记录每个真实文件的原文件名、文件类型、用途和无法识别的问题。发票或收据还要记录：

- 原文件名
- 商户或开票方
- 日期
- 发票号或收据号
- 币种
- 含税总额
- 税额（文件中存在时）
- 建议费用类别
- 费用用途
- 无法识别的字段
- 疑似重复项

草稿必须提到每个真实业务文件。准备提交的文件列在“待上传附件”中；不能提交或仍有问题的文件列在“未解决项目”中。不得编造值。报销审批还要逐项复算总额，并确认总额等于明细金额之和。

## 3）读取真实审批定义

- 未给 `approval_code` 时，用 `approvals search` 搜索。多个定义都合理时，让当前用户选择。
- 用 `approvals get` 读取目标定义。`is_external=true` 时返回 `create_link`，不调用 `instances create`。
- 准备草稿前读取 [`lark-approval-instance-form-control-parameters.md`](./lark-approval-instance-form-control-parameters.md) 和 [`lark-approval-instance-value-sourcing.md`](./lark-approval-instance-value-sourcing.md)。用户点击 `同意并提交` 后，再读取 [`lark-approval-initiate.md`](./lark-approval-initiate.md)。
- 按真实控件 `id`、`type`、选项值和节点规则映射材料。文件和对话无法提供的必填值必须向用户询问。
- 人员姓名唯一匹配当前 `auth status --verify` 返回的用户时，可使用该用户的 `open_id`。其他人员或部门无法从稳定 ID 唯一确定时，要求用户提供 `open_id` 或 `open_department_id`；不要把姓名、邮箱或另一个用户的上下文当成 ID。

## 4）用 `clarify` 展示草稿

使用当前用户的语言。把草稿写入 `clarify.question`。普通审批使用下面的格式：

```markdown
## 审批申请草稿

- 审批定义：<approval name>

### 表单值

- <field label>: <value>

### 审批人

- <approver>

### 抄送人

- 无

### 待上传附件

- <file>

### 未解决项目

- 无
```

报销审批使用下面的格式：

```markdown
## 报销申请草稿

- 审批定义：<approval name>
- 费用用途：<purpose>
- 币种：<currency>
- 合计：<total>

| # | 原文件 | 商户 | 日期 | 发票或收据号 | 金额 | 类别 | 备注 |
|---|---|---|---|---|---:|---|---|
| 1 | <file> | <merchant> | <date> | <number> | <amount> | <category> | <notes> |

### 表单值

- <field label>: <value>

### 待上传附件

- <file>

### 未解决项目

- 无
```

草稿末尾加上问题：“是否提交以上审批？如需修改，请在自定义输入框中填写修改意见。”

调用 `clarify` 时只提供两个选项：

```json
[
  {"label": "同意并提交", "description": "按以上内容正式发起审批。"},
  {"label": "取消申请", "description": "停止处理，不发起审批。"}
]
```

`clarify` 会自动显示自定义输入框，并在调用后结束当前回复。调用前和调用后都不得上传附件或创建审批实例。

用户选择 `取消申请` 时停止。用户填写修改意见时，按意见修改草稿，再次调用 `clarify`。定义、表单值、审批人、抄送人或附件发生变化时，也必须更新草稿并再次调用 `clarify`。

用户首次提出创建或提交审批，不表示用户已经同意草稿。用户选择审批定义、补充字段或替换附件，也不表示同意提交。只有 `同意并提交` 这一次点击才是同意。

## 5）用户同意后提交

- 只把草稿中列出的文件作为附件。报销时上传每个已分析的发票或收据，不要只上传外层压缩包。只有草稿明确列出压缩包本身时，才上传压缩包。
- 每个文件只调用一次 `files upload`，并按 [`files-upload.md`](./files-upload.md) 中的请求契约传 `name`、`type` 和 `content`。除非用户修复并确认应用权限问题，否则上传失败或响应不明时不得重试。
- 保存每次成功响应的 `data.code`，并映射到对应控件。任一上传失败或响应不明时立即停止，不得静默省略附件，不得创建审批实例。
- 根据真实定义组装 `form`，把上传得到的 file code 放进对应控件。只在定义要求时添加节点审批人或抄送人。
- 调用一次 `instances create --yes`。
- 成功后返回 `approval_name`、`instance_code`、`instance_link`、初始状态和附件数量。报销审批还要返回提交总额。响应不明时先用只读查询确认结果，不得重复提交。
