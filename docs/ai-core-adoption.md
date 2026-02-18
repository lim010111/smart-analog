# AI Core Adoption Guide

This branch introduces shared OpenAI primitives in `src/services/ai/core`.

## Shared Modules

- `config.py`
  - `load_openai_config(...)`
  - `read_bool_env(...)`
  - `read_int_env(...)`
  - `read_float_env(...)`
- `client.py`
  - `OpenAIJSONClient.request_json(...)`
- `workflow.py`
  - `request_json_or_empty(...)`
- `json_utils.py`
  - `parse_json_object(...)`
- `context.py`
  - `build_event_context(...)`
  - `event_context_to_dicts(...)`

## Adoption by Feature Branch

### feature/ai-coloring

1. Keep `ColorRule` and `CustomColorSchema` in the feature layer.
2. Replace inline OpenAI SDK import/client setup with:

```python
from src.services.ai.core import OpenAIJSONClient, load_openai_config, request_json_or_empty

config = load_openai_config(model_env="OPENAI_COLOR_MODEL", timeout_env="OPENAI_COLOR_TIMEOUT")
client = OpenAIJSONClient(config)
```

3. Replace custom JSON slicing parser with `request_json_or_empty(...)`.

### feature/ai-briefing

1. Build briefing prompt payload from `event_context_to_dicts(events)`.
2. Use `OpenAIJSONClient.request_json(...)` for strict JSON outputs.
3. Keep briefing-specific output schema validation in branch-local module.

### feature/ai-natural-input

1. Keep natural-language parser schema in branch-local module.
2. Use shared config/client helpers from `src/services/ai/core`.
3. Reuse `parse_json_object(...)` for fallback parsing of model output.

## Environment Variables

Shared defaults in `.env.template`:

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `OPENAI_TIMEOUT`

Feature branches can override model/timeout env names by passing `model_env` and `timeout_env` to `load_openai_config(...)`.
