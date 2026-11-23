# 上传审批附件或图片

只有用户在 `clarify` 卡片中点击 `同意并提交` 后，才能上传审批附件。接口返回 file code；创建实例时把 code 数组写入 `attachmentV2`、`image` 或 `imageV2` 控件的 `value`。

## 请求契约

- 方法和路径：`POST /open-apis/approval/v4/files/upload`
- 应用权限：`approval:approval` 和 `approval:instance.file`。这两个权限属于当前用户的 PersonalAgent app，不属于用户 OAuth scope；首次上传前，用户必须在飞书开发者后台同意并发布。
- Content-Type：`multipart/form-data`
- 身份：wrapper 使用当前 Turn 发起人的 profile，并以该 profile 所属 PersonalAgent app 的应用身份上传。它不使用继承的 Agent bot 凭据。不要手写 `Authorization`，不要传 `--as` 或 `--profile`。
- 一次请求只能上传一个文件；多个文件必须分别上传。
- `attachment` 最大 50 MB；`image` 最大 10 MB。
- 不要把旧示例中的 `/approval/openapi/v2/file/upload` 替换进本 Skill；Ankole wrapper 固定调用上面的 v4 路径。

如果接口返回 `99991672` 或 `app_scope_not_applied`，停止上传和提交，把错误中的开发者后台权限链接交给用户。用户确认权限已发布后，只重试这一个失败文件；不要重新上传已经成功的文件，也不要重试状态不明的提交。

multipart 请求体字段：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `name` | string | 是 | 文件名，必须包含扩展名，例如 `invoice.pdf` |
| `type` | string | 是 | `attachment` 或 `image`；必须与审批定义中的控件类型一致 |
| `content` | file | 是 | 文件内容；在 CLI 中必须显式写成 `--file content=<path>`，不能使用默认字段名 `file` |

`attachmentV2` 使用 `type=attachment`；`image` 和 `imageV2` 使用 `type=image`。

```bash
/repo/app/library/agent-plugins/lark/skills/lark-approvals/scripts/lark-approvals files upload --file content=./receipts/invoice.pdf --data '{"name":"invoice.pdf","type":"attachment"}' --format json
```

## 响应契约

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | int | `0` 表示成功；非 `0` 表示失败 |
| `msg` | string | 返回码说明 |
| `data.code` | string | 文件标识码；写入创建实例的图片或附件控件 `value` |
| `data.url` | string | 文件 URL，有效期 12 小时 |

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "code": "D93653C3-2609-4EE0-8041-61DC1D84F0B5",
    "url": "https://example.com/lark-approval-attachment/file"
  }
}
```

发起审批后，每次读取审批详情都会得到新的文件 URL。如果 URL 参数包含字面量 `\\u0026`，将它替换为 `&` 后再打开。提单依赖 `data.code`，不要依赖短期 URL。

控件值示例：

```json
{
  "id": "widget1",
  "type": "attachmentV2",
  "value": ["D93653C3-2609-4EE0-8041-61DC1D84F0B5"]
}
```
