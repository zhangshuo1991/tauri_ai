export interface AiSite {
  id: string;
  name: string;
  url: string;
  icon: string;
  builtin: boolean;
  summary_prompt_override?: string;
}

export interface AppConfig {
  sites: AiSite[];
  site_order: string[];
  pinned_site_ids: string[];
  recent_site_ids: string[];
  theme: string;
  sidebar_width: number;
  sidebar_expanded_width: number;
  language: string;
  summary_prompt_template: string;
  ai_api_base_url: string;
  ai_api_model: string;
  ai_api_key: string;
  active_project_id: string;
}

export interface ProjectSummary {
  id: string;
  title: string;
  updated_at: number;
}

export interface ProjectContext {
  id: string;
  title: string;
  notes: string;
  summary: string;
  created_at: number;
  updated_at: number;
}
