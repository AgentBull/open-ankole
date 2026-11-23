import { describe, expect, it } from 'bun:test'
import { create } from '@bufbuild/protobuf'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { basename, join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { BRAIN_OPERATIONS } from '../src/core/llm'
import { scheduledReplyReminder } from '../src/core/turns/scheduled_reply'
import {
  buildTextTurnSystemPrompt,
  buildTextTurnUserPrompt,
  textTurnHostedTools,
  textTurnStatefulContext
} from '../src/core/turns/text_turn_prompt'
import { AgentConversationContextResponseSchema } from '../src/fabric/generated/ankole/runtime_fabric/v1/rpc_pb'
import type { TurnStart } from '../src/lanes/actor_lane'
import {
  buildAmbientRecognizerSystemPrompt,
  buildAmbientRecognizerUserPrompt,
  type AmbientTextTurnRoute
} from '../src/prompts/ambient_prompt'
import { ambientRouteSection, buildAgentSystemPrompt } from '../src/prompts/system_prompt'
import { turnStartForTest } from './support/llm'

const ARCHITECTURE_TERM_LEAK_RE =
  /\b(?:Ecto|Rustler|Oban|Ankole\.Repo|PostgreSQL|RuntimeFabric|AIGateway|SignalsGateway)\b/g

const repoRoot = resolve(import.meta.dir, '..', '..', '..')
const cliRoot = resolve(import.meta.dir, '..', 'src', 'cli')
const libraryRoot = join(repoRoot, 'app', 'library')
const codexBaseInstructionsPath = join(repoRoot, 'app', 'control_plane', 'priv', 'codex', 'base_instructions.md')

function findArchitectureLeaks(text: string): string[] {
  return [...new Set(text.match(ARCHITECTURE_TERM_LEAK_RE) ?? [])]
}

function collectFiles(root: string, predicate: (filePath: string) => boolean): string[] {
  const results: string[] = []
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const fullPath = join(root, entry.name)
    if (entry.isDirectory()) {
      results.push(...collectFiles(fullPath, predicate))
    } else if (entry.isFile() && predicate(fullPath)) {
      results.push(fullPath)
    }
  }
  return results.toSorted()
}

function buildConversationContext(overrides?: { adapter?: string; mission?: string; soul?: string }) {
  return create(AgentConversationContextResponseSchema, {
    agent: { displayName: 'Atlas', role: 'Research Analyst' },
    conversation: {
      id: 'conv-fixture-1',
      timezone: 'Asia/Singapore',
      startedAt: '2026-07-18T10:00:00Z',
      originChannel: {
        adapter: overrides?.adapter ?? 'lark',
        kind: 'im_group',
        label: 'Ops Room'
      }
    },
    soul: overrides?.soul ?? 'Be accurate, direct, and transparent about gaps.',
    mission: overrides?.mission ?? 'Support team research and delivery.',
    skills: [
      {
        skillName: 'pdf',
        description: 'Generate formatted PDF deliverables.',
        category: 'documents'
      }
    ]
  })
}

function fullTextTurnStart(overrides?: Partial<TurnStart>): TurnStart {
  const base = turnStartForTest()
  return {
    ...base,
    hosted_tools: [{ type: 'web_search' }, { type: 'image_generation' }, { type: 'brain' }],
    actor_event: {
      ...base.actor_event,
      payload_json: {
        time: '2026-07-18T12:00:00Z',
        data: {
          channel: { id: 'lark:chat:ops', kind: 'im_group', name: 'Ops Room' },
          entry: {
            text: 'Summarize the latest rollout notes.',
            signal_channel_id: 'lark:chat:ops',
            provider_time: '2026-07-18T12:00:00Z',
            author: { display_name: 'Alice', principal_uid: 'alice-1', metadata: { sender_type: 'user' } }
          }
        }
      }
    },
    ...overrides
  } as TurnStart
}

describe('prompt surface and prefix stability', () => {
  it('keeps buildAgentSystemPrompt session-stable in exact block order and free of per-turn directives', () => {
    const turnStart = fullTextTurnStart()
    const hostedTools = textTurnHostedTools(turnStart)
    const prompt = buildAgentSystemPrompt({
      userFilesRoot: '/agents/agent-1/user-files',
      workspaceRoot: '/agents/agent-1/workspaces/session-1',
      turnStart: { ...turnStart, hosted_tools: hostedTools },
      agentConversationContext: buildConversationContext(),
      availableToolNames: [
        'read_file',
        'create_background_job',
        'respawn_background_job',
        'workflow',
        'skill_view',
        ...BRAIN_OPERATIONS
      ]
    })

    expect(prompt).not.toContain('<ambient_route>')
    expect(prompt).not.toContain('End this scheduled turn with one JSON object')

    const orderedMarkers = [
      'You are Atlas, an AI colleague Agent powered by Ankole.',
      'Be accurate, direct, and transparent about gaps.',
      '<mission>',
      '<completion_contract>',
      '<background_agent_job_policy>',
      '<workflow_policy>',
      '<long_term_memory>',
      '<agent_environment_info_policy>',
      '<tools>',
      '## Skills',
      '<runtime_context>'
    ]
    let lastIndex = -1
    for (const marker of orderedMarkers) {
      const nextIndex = prompt.indexOf(marker)
      expect(nextIndex).toBeGreaterThan(lastIndex)
      lastIndex = nextIndex
    }
  })

  it('produces byte-identical system prompts and tool declarations across main, ambient, and scheduled turns', () => {
    const baseTurnStart = fullTextTurnStart()
    const context = buildConversationContext()
    const localTools = [
      { name: 'read_file' },
      { name: 'apply_patch' },
      { name: 'create_background_job' },
      { name: 'respawn_background_job' },
      { name: 'workflow' },
      { name: 'skill_view' },
      { name: 'cron' }
    ]

    const scheduledTurnStart = fullTextTurnStart({
      actor_event: { ...baseTurnStart.actor_event, type: 'cron.fire' },
      request_context: {
        silent_success_allowed: true,
        schedule_origin: {
          schedule_kind: 'cron_fire',
          due_at: '2026-07-18T12:00:00Z',
          fired_at: '2026-07-18T12:00:01Z',
          timezone: 'Asia/Singapore',
          cron_schedule_name: 'ops-check',
          payload: {}
        }
      }
    })

    const variants = [baseTurnStart, baseTurnStart, baseTurnStart, scheduledTurnStart].map(turnStart => ({
      hostedTools: textTurnHostedTools(turnStart),
      systemPrompt: buildTextTurnSystemPrompt({
        userFilesRoot: '/agents/agent-1/user-files',
        workspaceRoot: '/agents/agent-1/workspaces/session-1',
        turnStart,
        agentConversationContext: context,
        tools: localTools,
        hostedTools: textTurnHostedTools(turnStart)
      })
    }))

    for (const variant of variants) {
      expect(variant.systemPrompt).toBe(variants[0]!.systemPrompt)
      expect(variant.hostedTools).toEqual(variants[0]!.hostedTools)
      expect(variant.systemPrompt).not.toContain('<ambient_route>')
      expect(variant.systemPrompt).not.toContain('End this scheduled turn with one JSON object')
    }

    const foregroundRoute: AmbientTextTurnRoute = { action: 'FOREGROUND_REPLY', authority: 'NONE' }
    const confirmationRoute: AmbientTextTurnRoute = { action: 'NEW_WORK', authority: 'NONE' }

    const foregroundUser = buildTextTurnUserPrompt(
      baseTurnStart,
      { role: 'user', content: 'Status?' },
      { timezone: 'Asia/Singapore', ambientRoute: foregroundRoute }
    )
    const confirmationUser = buildTextTurnUserPrompt(
      baseTurnStart,
      { role: 'user', content: 'Please audit everything.' },
      { timezone: 'Asia/Singapore', ambientRoute: confirmationRoute }
    )
    const scheduledUser = buildTextTurnUserPrompt(
      scheduledTurnStart,
      { role: 'user', content: 'Run ops-check.' },
      { timezone: 'Asia/Singapore' }
    )

    expect(Array.isArray(foregroundUser.content)).toBe(true)
    const foregroundParts = foregroundUser.content as Array<{ type: string; text?: string }>
    expect(foregroundParts[0]!.text).toStartWith('<agent_environment_info>\n')
    expect(foregroundParts[0]!.text).not.toContain('<ambient_route>')
    expect(foregroundParts[1]!.text).toContain('<ambient_route>')
    expect(foregroundParts[1]!.text).toContain('FOREGROUND_REPLY')
    expect(foregroundParts[2]!.text).toBe('Status?')

    const confirmationParts = confirmationUser.content as Array<{ type: string; text?: string }>
    expect(confirmationParts[0]!.text).toStartWith('<agent_environment_info>\n')
    expect(confirmationParts[0]!.text).not.toContain('<ambient_route>')
    expect(confirmationParts[1]!.text).toContain('<ambient_route>')
    expect(confirmationParts[1]!.text).toContain('NEW_WORK, but no human request or standing order authorizes it')

    const scheduledParts = scheduledUser.content as Array<{ type: string; text?: string }>
    expect(scheduledParts[0]!.text).toStartWith('<agent_environment_info>\n')
    expect(scheduledParts[0]!.text).toContain('schedule_turn_mode: cron')
    expect(scheduledParts[0]!.text).not.toContain('End this scheduled turn with one JSON object')
    expect(scheduledParts[1]!.text).toContain('End this scheduled turn with one JSON object')
    expect(scheduledParts[2]!.text).toBe('Run ops-check.')

    expect(textTurnStatefulContext(baseTurnStart, 'conv-fixture-1')).not.toHaveProperty('metadata')
    expect(textTurnStatefulContext(baseTurnStart, 'conv-fixture-1', confirmationRoute)).toMatchObject({
      metadata: {
        ambient_route_action: 'NEW_WORK',
        ambient_route_authority: 'NONE'
      }
    })
  })

  it('orders ambient recognizer system policy before identity and puts current_time at the end of user prompt', () => {
    const recognizerSystem = buildAmbientRecognizerSystemPrompt({
      displayName: 'Atlas',
      mission: 'Support the team.',
      soul: 'Stay concise.'
    })

    const policyIdx = recognizerSystem.indexOf('You are the ambient intent router for this Agent in a shared room.')
    const aboutIdx = recognizerSystem.indexOf('<about>')
    const displayNameIdx = recognizerSystem.indexOf('<display_name>Atlas</display_name>')
    expect(policyIdx).toBe(0)
    expect(aboutIdx).toBeGreaterThan(policyIdx)
    expect(displayNameIdx).toBeGreaterThan(aboutIdx)

    const recognizerUser = buildAmbientRecognizerUserPrompt({
      standingOrders: 'Speak when CI breaks.',
      backdrop: ['- 10:00 [human] Alice: Deploy started.'],
      newMessages: ['- [id:msg-2] 10:05 [human] Bob: Is CI passing?'],
      workCandidates: { complete: true, jobs: [] },
      currentTime: '2026-07-18 10:06',
      groupName: 'Ops Room',
      adapter: 'lark',
      timezone: 'Asia/Singapore'
    })

    const runtimeStart = recognizerUser.indexOf('<runtime_context>')
    const runtimeEnd = recognizerUser.indexOf('</runtime_context>')
    const newMessagesIdx = recognizerUser.indexOf('New Messages (not yet judged; classify only these):')
    const currentTimeIdx = recognizerUser.indexOf('current_time: 2026-07-18 10:06')

    expect(runtimeStart).toBe(0)
    expect(recognizerUser.slice(runtimeStart, runtimeEnd)).not.toContain('current_time:')
    expect(currentTimeIdx).toBeGreaterThan(newMessagesIdx)
    expect(recognizerUser.trimEnd().endsWith('current_time: 2026-07-18 10:06')).toBe(true)
  })
})

describe('architecture-term leak scan', () => {
  it('finds no internal architecture terms in rendered prompt outputs or exported CLI help', async () => {
    const samples: Array<{ name: string; text: string }> = []

    for (const adapter of ['lark', 'telegram', 'slack']) {
      const turnStart = fullTextTurnStart()
      samples.push({
        name: `buildAgentSystemPrompt(full,${adapter})`,
        text: buildAgentSystemPrompt({
          userFilesRoot: '/agents/agent-1/user-files',
          workspaceRoot: '/agents/agent-1/workspaces/session-1',
          turnStart: { ...turnStart, hosted_tools: textTurnHostedTools(turnStart) },
          agentConversationContext: buildConversationContext({ adapter }),
          availableToolNames: [
            'read_file',
            'create_background_job',
            'respawn_background_job',
            'workflow',
            'skill_view',
            ...BRAIN_OPERATIONS
          ]
        })
      })
    }

    const readOnlyTurnStart = fullTextTurnStart({ hosted_tools: [{ type: 'brain' }] })
    samples.push({
      name: 'buildAgentSystemPrompt(read-only-brain,no-mission)',
      text: buildAgentSystemPrompt({
        userFilesRoot: '/agents/agent-1/user-files',
        workspaceRoot: '/agents/agent-1/workspaces/session-1',
        turnStart: readOnlyTurnStart,
        agentConversationContext: buildConversationContext({ mission: '', soul: '' }),
        availableToolNames: ['recall', 'get_page']
      })
    })

    for (const route of [
      { action: 'FOREGROUND_REPLY', authority: 'NONE' },
      { action: 'NEW_WORK', authority: 'NONE' },
      { action: 'NEW_WORK', authority: 'EXPLICIT_REQUEST' },
      { action: 'NEW_WORK', authority: 'STANDING_ORDER' }
    ] as const) {
      samples.push({
        name: `ambientRouteSection(${route.action}:${route.authority})`,
        text: ambientRouteSection(route)
      })
    }

    samples.push(
      { name: 'scheduledReplyReminder(true)', text: scheduledReplyReminder(true) },
      { name: 'scheduledReplyReminder(false)', text: scheduledReplyReminder(false) },
      {
        name: 'buildAmbientRecognizerSystemPrompt',
        text: buildAmbientRecognizerSystemPrompt({
          displayName: 'Atlas',
          mission: 'Support the team.',
          soul: 'Stay concise.'
        })
      },
      {
        name: 'buildAmbientRecognizerUserPrompt',
        text: buildAmbientRecognizerUserPrompt({
          standingOrders: 'Speak when CI breaks.',
          backdrop: ['- 10:00 [human] Alice: Deploy started.'],
          newMessages: ['- [id:msg-2] 10:05 [human] Bob: Is CI passing?'],
          workCandidates: {
            complete: true,
            jobs: [{ jobID: '101', title: 'Check CI', status: 'running', taskExcerpt: 'Inspect CI logs.' }]
          },
          currentTime: '2026-07-18 10:06',
          groupName: 'Ops Room',
          adapter: 'lark',
          timezone: 'Asia/Singapore'
        })
      }
    )

    const cliHelpModules = collectFiles(
      cliRoot,
      filePath => filePath.endsWith('.ts') && /export\s+const\s+\w*CLI_HELP\b/.test(readFileSync(filePath, 'utf8'))
    )
    expect(cliHelpModules.length).toBeGreaterThanOrEqual(2)

    for (const modulePath of cliHelpModules) {
      const exportsObj = (await import(pathToFileURL(modulePath).href)) as Record<string, unknown>
      for (const [exportName, value] of Object.entries(exportsObj)) {
        if (exportName.endsWith('CLI_HELP') && typeof value === 'string') {
          samples.push({ name: `${basename(modulePath)}:${exportName}`, text: value })
        }
      }
    }

    const leaks = samples.flatMap(sample => {
      const matched = findArchitectureLeaks(sample.text)
      return matched.length > 0 ? [`${sample.name}: ${matched.join(', ')}`] : []
    })
    expect(leaks).toEqual([])
  })

  it('finds no internal architecture terms in app/library markdown files or Codex base instructions', () => {
    expect(existsSync(libraryRoot)).toBe(true)
    const markdownFiles = collectFiles(
      libraryRoot,
      filePath => filePath.endsWith('.md') && !/^README.*\.md$/i.test(basename(filePath))
    )
    expect(markdownFiles.length).toBeGreaterThan(0)

    const filesToScan = [...markdownFiles]
    if (existsSync(codexBaseInstructionsPath)) {
      filesToScan.push(codexBaseInstructionsPath)
    } else if (!existsSync('/etc/ankole-agent-computer-container')) {
      throw new Error(`Expected Codex base instructions at ${codexBaseInstructionsPath}`)
    }

    const leaks = filesToScan.flatMap(filePath => {
      const matched = findArchitectureLeaks(readFileSync(filePath, 'utf8'))
      return matched.length > 0 ? [`${filePath}: ${matched.join(', ')}`] : []
    })
    expect(leaks).toEqual([])
  })
})
