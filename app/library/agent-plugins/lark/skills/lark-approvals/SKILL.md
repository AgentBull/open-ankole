---
name: lark-approvals
version: 1.2.1
description: "Feishu approvals: query and act on pending/done approval tasks and instances; search/initiate native approvals; archive invoices/receipts and submit confirmed reimbursements. Non-approval to-dos go to lark-oa."
default_enabled: true
ankole-runtime: main
category: productivity
tags: [lark, feishu, approval, workflow]
metadata:
  requires:
    bins: ["lark-cli"]
  cliHelp: "/repo/app/library/agent-plugins/lark/skills/lark-approvals/scripts/lark-approvals"
  upstream: https://github.com/larksuite/cli/tree/a7865cd0a7416655535517a2a630848fde318761/skills/lark-approval
  upstream_commit: a7865cd0a7416655535517a2a630848fde318761
  modified_for: Ankole one-to-many digital coworker runtime
---

# 飞书审批

**CRITICAL — 开始前 MUST 先读取 [`references/user-runtime.md`](references/user-runtime.md)。**

Ankole 服务多名用户，每次操作只使用当前 Turn 发起人的独立 user profile，不得复用他人 profile、审批列表、人员 ID 或上下文。本 Skill **仅供主会话使用**（票据解压、识别、汇率换算和明细整理可交后台任务，再由主会话继续；不得让后台任务加载本 Skill 或调用审批 wrapper）。

所有命令必须调用 wrapper：

```text
/repo/app/library/agent-plugins/lark/skills/lark-approvals/scripts/lark-approvals
```

**隔离硬规则（由规则维持，非沙箱强制）：** 严禁直接调用 `lark-cli`，严禁传 `--as` 或 `--profile`，严禁读取/列出/复制共享 CLI 配置或自行设置 `ANKOLE_RUNTIME_*`。wrapper 按当前 Turn 发起人选 profile 并移除 Agent bot 凭据（审批读写用 user 身份，附件上传用同 profile 下 PersonalAgent app 身份；仅账号配置操作加锁，正常读写可跨用户并行）。若 wrapper 报错无有效人类 Principal 或 profile，立即停止并告知用户。

调用前按需读 references 查参数（未覆盖字段仅用 wrapper `schema <resource> <method>` 确认）。**发起新审批硬规则：** 先用 `clarify` 展示 Markdown 草稿；用户点击 `同意并提交` 前，严禁调用 `files upload` 或 `instances create`（完整流程与模板见 [`references/initiate-sop.md`](references/initiate-sop.md)）。

## 路由优先级

审批待办不是飞书任务。核心对象为审批单据、待办、实例、意见或定义（同意、拒绝、转交、退回、撤回、催办、加签、抄送、查待办/已办/已发起/详情、发起请假/报销/出差/通用审批、上传审批附件）时，优先走 `lark-approvals`；仅非审批任务、OKR 或考勤走 `lark-oa`。

## 选哪个命令

| 想做什么 | wrapper 命令 | 按需读取 reference |
|---|---|---|
| 搜可发起定义 | `approvals search` | [`lark-approval-approvals-search.md`](references/lark-approval-approvals-search.md) |
| 看审批定义详情或确认表单流程 | `approvals get` | [`lark-approval-approvals-get.md`](references/lark-approval-approvals-get.md) |
| 提交已同意原生审批 | `instances create` | [`lark-approval-initiate.md`](references/lark-approval-initiate.md) |
| 查待办或已办 | `tasks query`（`topic`：1 待办、2 已办、17 未读、18 已读） | [`lark-approval-tasks-query.md`](references/lark-approval-tasks-query.md) |
| 看表单、进度或当前节点 | `instances get` | [`lark-approval-instances-get.md`](references/lark-approval-instances-get.md) |
| 同意审批 | `tasks approve` | [`lark-approval-tasks-approve.md`](references/lark-approval-tasks-approve.md) |
| 拒绝审批 | `tasks reject` | [`lark-approval-tasks-reject.md`](references/lark-approval-tasks-reject.md) |
| 转交审批 | `tasks transfer` | [`lark-approval-tasks-transfer.md`](references/lark-approval-tasks-transfer.md) |
| 加签审批 | `tasks add_sign` | [`lark-approval-tasks-add-sign.md`](references/lark-approval-tasks-add-sign.md) |
| 退回审批 | `tasks rollback` | [`lark-approval-tasks-rollback.md`](references/lark-approval-tasks-rollback.md) |
| 催办审批 | `tasks remind` | [`lark-approval-tasks-remind.md`](references/lark-approval-tasks-remind.md) |
| 撤回已发起审批 | `instances cancel` | [`lark-approval-instances-cancel.md`](references/lark-approval-instances-cancel.md) |
| 追加抄送 | `instances cc` | [`lark-approval-instances-cc.md`](references/lark-approval-instances-cc.md) |
| 按定义查已发起审批 | `instances initiated` | [`lark-approval-instances-initiated.md`](references/lark-approval-instances-initiated.md) |
| 上传审批图片或附件 | `files upload` | [`files-upload.md`](references/files-upload.md) |

- 发起链：整理材料 -> 无 `approval_code` 时 `approvals search` -> `approvals get`（按 [`lark-approval-instance-form-control-parameters.md`](references/lark-approval-instance-form-control-parameters.md) 与 [`lark-approval-instance-value-sourcing.md`](references/lark-approval-instance-value-sourcing.md) 映射控件）-> `clarify` 展示草稿 -> 用户点 `同意并提交` -> `files upload` -> `instances create --yes`
- 处理链：`tasks query` 取 `instance_code` + `task_id`（必须成对传）-> 仅在用户明确要看详情/节点/表单/进度时 `instances get` -> 执行动作

## 执行原则与 1395001 处理

- 已知 `instance_code` + `task_id` 直接执行 `tasks approve/reject/transfer/add_sign/rollback/remind`，不先查列表再过滤，不重复查当前 Turn 已有结果。
- 写操作失败或响应不明时严禁盲目重试；仅当 reference 明确给出恢复条件且用户已完成前置操作后才按说明重试。
- 返回 `1395001` 时：禁止重复写操作；核查是否已被处理、状态是否已变、当前发起人是否仍有资格、节点是否支持；如需确认仅补一次 `tasks query` 或 `instances get` 后向用户报告。

```bash
WRAPPER=/repo/app/library/agent-plugins/lark/skills/lark-approvals/scripts/lark-approvals
"$WRAPPER" approvals search --data '{"keyword":"请假"}'
"$WRAPPER" approvals get --params '{"approval_code":"<code>"}'
"$WRAPPER" tasks query --params '{"topic":"1"}'
"$WRAPPER" tasks approve --data '{"instance_code":"<ic>","task_id":"<tid>","comment":"同意"}' --dry-run
```

## 发起审批 SOP 与附件契约

- 五步发起流程（压缩包路径安全与符号链接拒绝、发票明细复算、`clarify` 草稿模板与双选项提交）见 [`references/initiate-sop.md`](references/initiate-sop.md)。
- 附件上传（`--file content=<path>`、`attachmentV2` 用 `type=attachment`、`image`/`imageV2` 用 `type=image`、`99991672`/`app_scope_not_applied` 权限处理）见 [`references/files-upload.md`](references/files-upload.md)。

## 不在本 Skill 范围

不创建审批定义（走飞书客户端或管理后台）；三方定义只返回 `create_link`；非审批任务走 `lark-oa`；每次均以当前 Turn 发起人为边界。
