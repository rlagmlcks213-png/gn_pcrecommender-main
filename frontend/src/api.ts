const API_BASE = "http://127.0.0.1:5000/api";

export interface Part {
  product_id: number;
  name: string;
  price_krw: number;
  image_url?: string | null;
  product_url?: string | null;
  quantity?: number;
  unit_price_krw?: number;
  [key: string]: unknown;
}

export interface BuildResponse {
  status: "ok" | "no_matching_product" | "budget_insufficient" | "error";
  message: string;
  parts?: Record<string, Part>;
  total_price_krw?: number;
  review_notes?: string[];
  _requirements?: Record<string, unknown>;
  _options?: Record<string, unknown>;
}

export interface GameOption {
  id: number;
  title: string;
}

export interface UsageProfileOption {
  id: number;
  code: string;
  display_name: string;
}

export async function fetchGames(): Promise<GameOption[]> {
  const res = await fetch(`${API_BASE}/games`);
  return res.json();
}

export async function fetchUsageProfiles(): Promise<UsageProfileOption[]> {
  const res = await fetch(`${API_BASE}/usage-profiles`);
  return res.json();
}

export interface CreateBuildParams {
  game_ids: number[];
  usage_profile_ids: number[];
  budget_krw: number;
  placement: string;
  rgb: string;
  mode: "cost" | "perf";
}

export async function createBuild(params: CreateBuildParams): Promise<BuildResponse> {
  const res = await fetch(`${API_BASE}/builds`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
  return res.json();
}

export async function upgradeCpuGpu(current: BuildResponse): Promise<BuildResponse> {
  const res = await fetch(`${API_BASE}/builds/upgrade-cpu-gpu`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(current),
  });
  return res.json();
}

export async function upgradeRam(current: BuildResponse, targetGb?: number): Promise<BuildResponse> {
  const res = await fetch(`${API_BASE}/builds/upgrade-ram`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...current, target_gb: targetGb }),
  });
  return res.json();
}
