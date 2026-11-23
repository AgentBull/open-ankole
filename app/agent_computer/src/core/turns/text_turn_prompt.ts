import type { TurnStart } from '../../lanes/actor_lane'
import type { AgentConversationContextResponse } from '../../lanes/rpc_lane'
import type { AmbientTextTurnRoute } from '../../prompts/ambient_prompt'
import { ambientRouteSection, buildAgentSystemPrompt } from '../../prompts/system_prompt'
import { BRAIN_OPERATIONS, type HostedTool, type StatefulResponseContext, type UserMessage } from '../llm'
import {
  actorEventEnvironmentInfoLines,
  insertTrustedContextPartsAfterEnvironmentInfo,
  prependEnvironmentInfoLinesToUserMessage,
  turnRequestEnvironmentInfoLines
} from './message_context'
import { scheduleTurnContextFromTurnStart } from './schedule_turn_context'
import { scheduledReplyReminder } from './scheduled_reply'
import { statefulTruncationFromActorEventPayload } from './turn_runtime_policy'

/**
 * Resolves the hosted tool declarations passed to AIGateway for a text turn.
 * Brain keeps `inject: true` across routes so tool declarations stay identical.
 */
export function textTurnHostedTools(turnStart: TurnStart): HostedTool[] {
  return (turnStart.hosted_tools ?? []).map((tool): HostedTool =>
    tool.type === 'brain' ? { type: 'brain', inject: true } : tool
  )
}

/**
 * The model-facing names of the hosted Brain operations, so prompt guidance
 * about memory follows what AIGateway actually declares this turn.
 */
export function hostedBrainOperationNames(hostedTools: HostedTool[]): string[] {
  const brain = hostedTools.find(tool => tool.type === 'brain')
  if (!brain || brain.type !== 'brain') return []
  return [...(brain.operations ?? BRAIN_OPERATIONS)]
}

/**
 * Builds the session-stable system prompt for a text turn.
 */
export function buildTextTurnSystemPrompt(opts: {
  userFilesRoot: string
  workspaceRoot: string
  turnStart: TurnStart
  agentConversationContext: AgentConversationContextResponse
  tools: Array<{ name: string }>
  hostedTools: HostedTool[]
}): string {
  return buildAgentSystemPrompt({
    userFilesRoot: opts.userFilesRoot,
    workspaceRoot: opts.workspaceRoot,
    turnStart: { ...opts.turnStart, hosted_tools: opts.hostedTools },
    agentConversationContext: opts.agentConversationContext,
    availableToolNames: [...opts.tools.map(tool => tool.name), ...hostedBrainOperationNames(opts.hostedTools)]
  })
}

/**
 * Builds the current turn's user message with `<agent_environment_info>` followed
 * by trusted per-turn context (`<ambient_route>`, scheduled-reply contract).
 */
export function buildTextTurnUserPrompt(
  turnStart: TurnStart,
  userPrompt: UserMessage,
  opts: { timezone: string; ambientRoute?: AmbientTextTurnRoute }
): UserMessage {
  const scheduleContext = scheduleTurnContextFromTurnStart(turnStart)
  const withEnv = prependEnvironmentInfoLinesToUserMessage(userPrompt, [
    ...actorEventEnvironmentInfoLines(turnStart.actor_event.payload_json, {
      timezone: opts.timezone
    }),
    ...turnRequestEnvironmentInfoLines(turnStart)
  ])
  return insertTrustedContextPartsAfterEnvironmentInfo(withEnv, [
    opts.ambientRoute ? ambientRouteSection(opts.ambientRoute) : '',
    scheduleContext ? scheduledReplyReminder(scheduleContext.silentSuccessAllowed) : ''
  ])
}

/**
 * Builds the AIGateway stateful request context, attaching host-committed
 * ambient route metadata when present.
 */
export function textTurnStatefulContext(
  turnStart: TurnStart,
  conversationID: string,
  ambientRoute?: AmbientTextTurnRoute
): StatefulResponseContext {
  const truncation = statefulTruncationFromActorEventPayload(turnStart.actor_event.payload_json)
  return {
    actorEventID: turnStart.actor_event.actor_event_id,
    conversationID,
    ...(truncation ? { truncation } : {}),
    ...(ambientRoute
      ? {
          metadata: {
            ambient_route_action: ambientRoute.action,
            ambient_route_authority: ambientRoute.authority
          }
        }
      : {})
  }
}
