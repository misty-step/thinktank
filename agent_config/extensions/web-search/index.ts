import path from "node:path";
import { homedir } from "node:os";

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { StringEnum } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";

import { QueryCache } from "../../skills/web-search/cache";
import { assessConfidence } from "../../skills/web-search/confidence";
import { WebSearchOrchestrator } from "../../skills/web-search/orchestrator";
import type {
  ProviderAdapter,
  SearchRequest,
  SearchResponse,
  WebCommand,
} from "../../skills/web-search/provider-adapter";
import {
  Context7Provider,
  BraveProvider,
  ExaProvider,
  PerplexitySynthesisProvider,
} from "../../skills/web-search/providers";
import {
  inferRecencyDays,
  isDocsLookup,
  isTimeSensitiveQuery,
  normalizeQuery,
} from "../../skills/web-search/query-utils";
import { currentOrchestrationDepth, isTopLevelTelemetryEnabled } from "../shared/depth-telemetry";
import {
  ENABLE_NESTED_WEB_SEARCH_WARN_ENV,
  resolveWebSearchLogPath,
} from "./telemetry";

const MODE = StringEnum(["web", "web-deep", "web-news", "web-docs"] as const);
const MAX_LIMIT = 10;
const DEFAULT_LIMIT = 5;

export default function webSearchExtension(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Retrieve web/documentation sources with citation URLs, recency bias, and provider fallback.",
    parameters: Type.Object({
      query: Type.String({ description: "Search query to run" }),
      mode: Type.Optional(MODE),
      limit: Type.Optional(Type.Integer({ minimum: 1, maximum: MAX_LIMIT })),
      recencyDays: Type.Optional(Type.Integer({ minimum: 1, maximum: 3650 })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const mode = (params.mode ?? "web") as WebCommand;
      const limit = clampLimit(params.limit ?? DEFAULT_LIMIT);
      const request: SearchRequest = {
        query: params.query,
        command: mode,
        limit,
        recencyDays:
          typeof params.recencyDays === "number"
            ? params.recencyDays
            : inferRecencyDays({ query: params.query, command: mode, limit }),
      };

      const response = await runSearchPipeline(request);
      return {
        content: [{ type: "text", text: JSON.stringify(response, null, 2) }],
        details: response,
      };
    },
  });

  registerSearchCommand(pi, "web", "Run fast web retrieval");
  registerSearchCommand(pi, "web-deep", "Run web retrieval plus optional synthesis");
  registerSearchCommand(pi, "web-news", "Run recency-biased web retrieval");
  registerSearchCommand(pi, "web-docs", "Run docs/library-biased retrieval");

  pi.on("session_start", async (_event, ctx) => {
    const depth = currentOrchestrationDepth(process.env);
    const allowNestedWarn = isTopLevelTelemetryEnabled(ENABLE_NESTED_WEB_SEARCH_WARN_ENV, process.env);
    if (depth > 0 && !allowNestedWarn) {
      return;
    }

    const hasProvider = Boolean(
      process.env.CONTEXT7_API_KEY || process.env.EXA_API_KEY || process.env.BRAVE_API_KEY
    );
    if (!hasProvider) {
      ctx.ui.notify(
        "web_search: no providers configured. Set CONTEXT7_API_KEY, EXA_API_KEY, or BRAVE_API_KEY.",
        "warning"
      );
    }
  });
}

async function runSearchPipeline(request: SearchRequest): Promise<SearchResponse> {
  const configDir = getConfigDir();
  const cache = new QueryCache({
    filePath: path.join(configDir, "cache", "web-search-cache.json"),
    ttlMs: Number(process.env.WEB_SEARCH_TTL_MS ?? 30 * 60 * 1000),
  });

  const providers = buildProviderChain(request);
  const depth = currentOrchestrationDepth(process.env);
  const logPath = resolveWebSearchLogPath(configDir, depth, process.env);

  const orchestrator = new WebSearchOrchestrator(providers, {
    cache,
    logPath,
  });

  const { results, meta } = await orchestrator.searchWithMeta(request);
  const confidence = assessConfidence(request, results);

  let synthesis: SearchResponse["synthesis"] = null;
  if (request.command === "web-deep" && process.env.PERPLEXITY_API_KEY && results.length > 0) {
    const perplexity = new PerplexitySynthesisProvider(process.env.PERPLEXITY_API_KEY);
    const generated = await perplexity.synthesize(request.query, results);
    synthesis = generated.citations.length > 0 ? generated : null;
  }

  return {
    results,
    meta: {
      query: request.query,
      normalized_query: normalizeQuery(request.query),
      command: request.command,
      provider_chain: meta.providerChain,
      provider_used: meta.providerUsed,
      cache_hit: meta.cacheHit,
      time_sensitive: isTimeSensitiveQuery(request.query, request.command),
      recency_days: request.recencyDays ?? null,
      confidence: confidence.confidence,
      uncertainty: confidence.uncertainty,
    },
    synthesis,
  };
}

function buildProviderChain(request: SearchRequest): ProviderAdapter[] {
  const providers: ProviderAdapter[] = [];
  const docsLookup = isDocsLookup(request.query, request.command);

  if (docsLookup && process.env.CONTEXT7_API_KEY) {
    providers.push(new Context7Provider(process.env.CONTEXT7_API_KEY));
  }
  if (process.env.EXA_API_KEY) {
    providers.push(new ExaProvider(process.env.EXA_API_KEY));
  }
  if (process.env.BRAVE_API_KEY) {
    providers.push(new BraveProvider(process.env.BRAVE_API_KEY));
  }

  if (providers.length === 0) {
    throw new Error(
      "web_search: no retrieval providers configured (need CONTEXT7_API_KEY, EXA_API_KEY, or BRAVE_API_KEY)"
    );
  }

  return providers;
}

function registerSearchCommand(pi: ExtensionAPI, command: WebCommand, description: string): void {
  pi.registerCommand(command, {
    description,
    handler: async (args, ctx) => {
      const query = args.trim();
      if (!query) {
        ctx.ui.notify(`Usage: /${command} <query>`, "warning");
        return;
      }

      const message = [
        `Use the web_search tool now with mode "${command}" and query "${query}".`,
        "Return concise output and cite source URLs for each factual claim.",
        "If tool meta.confidence is low or meta.uncertainty is non-null, state uncertainty explicitly.",
      ].join(" ");

      if (ctx.isIdle()) {
        pi.sendUserMessage(message);
        return;
      }

      pi.sendUserMessage(message, { deliverAs: "followUp" });
    },
  });
}

function clampLimit(limit: number): number {
  return Math.max(1, Math.min(MAX_LIMIT, Math.floor(limit)));
}

function getConfigDir(): string {
  return (
    process.env.PI_CONFIG_DIR ??
    process.env.PI_CODING_AGENT_DIR ??
    path.join(homedir(), ".pi", "agent")
  );
}
