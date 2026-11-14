// CLI: runs the whole set against the official DeepSeek API and writes results/<date>-<config>.json.
//   DEEPSEEK_API_KEY=... deno run --allow-env --allow-net --allow-read --allow-write evals/run.ts [options]
//   --configs flash-nothink,flash-think   (default both)   --only <category|id>   --no-judge
// The judge uses the same provider with thinking off. Safety failures exit with code 1 (release blocker).
import { loadLLMConfig } from "../../_shared/llm/config.ts";
import { deepSeekProvider, withRetry } from "../../_shared/llm/providers.ts";
import { type LLMProvider } from "../../_shared/llm/types.ts";
import { runScenario, type RunConfig, type ScenarioResult, summarize, summaryTable } from "./runner.ts";
import { loadScenarios } from "./types.ts";

const CONFIGS: Record<string, RunConfig> = {
  "flash-nothink": { name: "deepseek-flash thinking-off", thinking: false, maxSteps: 5 },
  "flash-think": { name: "deepseek-flash thinking-on", thinking: true, maxSteps: 5 },
};

function arg(name: string): string | undefined {
  const index = Deno.args.indexOf(`--${name}`);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

const llm = loadLLMConfig();
if (!llm.deepseek.apiKey) {
  console.error("DEEPSEEK_API_KEY is not set (docs/KURULUM.md, AI Koç anahtarları).");
  Deno.exit(2);
}
const provider = (): LLMProvider => withRetry(deepSeekProvider({ ...llm.deepseek, timeoutMs: 60_000 }), () => {});
const only = arg("only");
const scenarios = (await loadScenarios()).filter((s) => !only || s.id === only || s.category === only);
const names = (arg("configs") ?? Object.keys(CONFIGS).join(",")).split(",");
const date = new Date().toISOString().slice(0, 10);
const rows: { config: string; summary: ReturnType<typeof summarize> }[] = [];

for (const key of names) {
  const config = CONFIGS[key];
  if (!config) throw new Error(`unknown config ${key}; choose from ${Object.keys(CONFIGS).join(", ")}`);
  const results: ScenarioResult[] = [];
  for (const scenario of scenarios) {
    const result = await runScenario(scenario, provider(), config, llm.prices, Deno.args.includes("--no-judge") ? undefined : provider());
    console.log(`${result.passed ? "PASS" : "FAIL"} ${key} ${scenario.id}${result.passed ? "" : ` — ${result.checks.filter((c) => !c.passed).map((c) => c.name).join(", ")}`}`);
    results.push(result);
  }
  const summary = summarize(results);
  rows.push({ config: key, summary });
  await Deno.writeTextFile(
    new URL(`./results/${date}-${key}.json`, import.meta.url),
    JSON.stringify({ date, config, model: llm.deepseek.model, summary, results }, null, 2) + "\n",
  );
}
console.log("\n" + summaryTable(rows));
if (rows.some((row) => row.summary.safety_failures.length > 0)) {
  console.error("\nSAFETY FAILURES — release blocker (docs/YAYIN-KONTROL.md).");
  Deno.exit(1);
}
